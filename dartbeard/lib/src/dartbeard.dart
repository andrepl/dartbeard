library dartbeard;

import 'dart:async';
import 'dart:io';
import 'dart:convert';

import 'package:http_parser/http_parser.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as path;
import 'package:postgresql/postgresql.dart';
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf_static/shelf_static.dart';
import 'package:shelf_route/shelf_route.dart' as route;
import 'package:shelf_web_socket/shelf_web_socket.dart' as sWs;

import 'package:models/models.dart';

import 'package:dartbeard/src/conf.dart';
import 'package:dartbeard/src/tvdb.dart';
import 'package:dartbeard/src/btn.dart';
import 'package:dartbeard/src/transmission.dart';
import 'package:dartbeard/src/database.dart';
import 'package:dartbeard/src/watch.dart';
import 'package:dartbeard/src/plex.dart';
import 'package:dartbeard/src/postprocessing.dart';
import 'package:dartbeard/src/util.dart';


class AppServer {
  final logger = new Logger("dartbeard");

  final Conf conf = new Conf();

  // Components
  final Database db = new Database();
  final Transmission transmission = new Transmission();
  final TVDB tvdb = new TVDB();
  final BTN btn = new BTN();
  final Watcher watcher = new Watcher();
  final Plex plex = new Plex();

  PostProcessor postProcessor;

  Timer watcherTimer;
  // webserver routing / websocket handling things
  route.Router router;
  shelf.Handler handler;
  Map<String, Function> rpcHandlers;

  final List<CompatibleWebSocket> connectedSockets = [];

  // Map of 'channels' to Set's of WebSockets.
  final Map<String, Set> dataSubscriptions = {};

  // Lets us display the name of a series that is about to be
  // added when we only have the id, as long as we've seen it
  // in search results in the past.
  final Map<int, String> seriesNameCache = {};

  // Timers for scheduling things.
  Timer autoScanTimer;
  Timer postProcessTimer;
  Timer autoSearchTimer;
  Timer autoUpdateTimer;

  String get serverBinDirectory => path.dirname(Platform.script.toString()).substring(7);

  AppServer() {
    // One time initialization of components.
    db.changes.listen(onChangeEvent);
    transmission.db = db;
    transmission.start();
    postProcessor = new PostProcessor(conf, db, tvdb, btn, transmission, plex);

    reloadConfig();

    router = (route.router()
      ..get('/ws', sWs.webSocketHandler(handleWebSocketConnect)))
      ..add('', ['GET'], createStaticHandler(path.normalize(path.join(serverBinDirectory, '../static')),  defaultDocument: 'index.html'), exactMatch: false);

    handler = const shelf.Pipeline()
    .addMiddleware(shelf.logRequests(logger: logRequest))
    .addHandler(router.handler);

    // i wish dart made this less clumsy
    rpcHandlers = {
      "set_episode_status": this.rpc_setEpisodeStatus,
      "save_series_settings": this.rpc_saveSeriesSettings,
      "get_config": this.rpc_getConfig,
      "save_config": this.rpc_saveConfig,
      "unlock_series": this.rpc_unlockSeries,
      "add_torrent": this.rpc_addTorrent,
      "search_torrent": this.rpc_searchTorrent,
      "validate_setting": this.rpc_validateSetting,
      "get_all_series": this.rpc_getAllSeries,
      "delete_series": this.rpc_deleteSeries,
      "get_series": this.rpc_getSeries,
      "get_all_torrents": this.rpc_getAllTorrents,
      "update_series": this.rpc_updateSeries,
      "subscribe": this.rpc_subscribe,
      "unsubscribe": this.rpc_unsubscribe,
      "get_unused_series_directories": this.rpc_getUnusedSeriesDirectories,
      "new_series_search": this.rpc_newSeriesSearch,
      "get_upcoming_episodes": this.rpc_getUpcomingEpisodes,
      "scan_series": this.rpc_scanSeries,
      "backfill_series": this.rpc_backfillSeries
    };
  }

  logRequest(String message, bool isError) {
    List<String> parts = message.split("\t");
    parts.removeAt(0);
    String msg = parts.join("\t");
    if (isError) {
      logger.severe(msg);
    } else {
      logger.info(msg);
    }
  }

  reloadConfig() async {
    logger.info("Reloading config.");

    conf.reload();

    await db.start(conf.database_uri);

    watcher.setRootDirectory(conf.library_root);

    // Transmission just polls, there is no persistent
    // connection so it's this easy.
    transmission.host = conf.transmission_host;
    transmission.port = conf.transmission_port;

    plex.host = conf.plex_host;
    plex.port = conf.plex_port;
    plex.libraryRoot = conf.library_root;

    btn.apiKey = conf.btn_api_key;
    tvdb.apiKey = conf.tvdb_api_key;

    // Reschedule the timers.
    if (autoScanTimer != null) {
      autoScanTimer.cancel();
    }
    autoScanTimer = new Timer.periodic(new Duration(milliseconds: 500), autoScan);

    if (postProcessTimer != null) {
      postProcessTimer.cancel();
    }
    postProcessTimer = new Timer.periodic(new Duration(milliseconds: 2000), postProcess);

    if (autoSearchTimer != null) {
      autoSearchTimer.cancel();
    }
    autoSearchTimer = new Timer.periodic(new Duration(seconds: 300), autoTorrentSearch);

    if (autoUpdateTimer != null) {
      autoUpdateTimer.cancel();
    }
    autoUpdateTimer = new Timer.periodic(new Duration(seconds: 60), autoUpdateSeries);

    logger.info("Reloaded config.");
  }

  shelf.Response handleHttpRequest(request) {
    return new shelf.Response.ok("Hello!");
  }

  handleWebSocketConnect(CompatibleWebSocket websocket) {
    logger.info("New websocket connection established.");
    this.connectedSockets.add(websocket);
    websocket.listen((String msg) {
      Map req = JSON.decode(msg);
      var displayArgs = req['args'].toString();
      if (displayArgs == 'null') {
        displayArgs = '';
      }
      if (displayArgs.length > 76) {
        displayArgs = displayArgs.substring(0, 76) + '...' + displayArgs.substring(displayArgs.length-1);
      }
      Function handler = rpcHandlers[req["method"]];
      if (handler == null) {
        logger.warning("Unknown rpc method ${req['method']}($displayArgs)");
        websocket.add(JSON.encode({"tag": req["tag"], "error": "Unknown method: ${req['method']}"}));
      } else {
        logger.info("RPC ${req['method']}($displayArgs)");
        rpcHandlers[req["method"]](websocket, req["args"])
        .then((result) {
          websocket.add(JSON.encode({"tag": req["tag"], "result": result}));
        }).catchError((error, stacktrace) {
          logger.severe("RPC Error ", error, stacktrace);
          print(error);
          print(stacktrace);
          websocket.add(JSON.encode({"tag": req["tag"], "error": error.toString()}));
        });
      }
    }, onDone: () {
      logger.info("Websocket disconnected. [${websocket.closeCode}: '${websocket.closeReason}']");
      this.connectedSockets.remove(websocket);
      dataSubscriptions.forEach((eventType, subscriberList) {
        subscriberList.remove(websocket);
      });
    });
  }

  sendToSubscribers(WebSocketEvent event) {
    Set subscribers = dataSubscriptions[event.type];
    if (subscribers != null && subscribers.length > 0) {
      if (event.type.startsWith("torrent::")) {
        var torrent = transmission.torrents[event.data['hash']];
        event.data['torrent'] = torrent.toMap();
      }
      var msg = JSON.encode({'event': {'type': event.type, 'data': event.data}});
      subscribers.forEach((s) => s.add(msg));
    }
  }

  broadcastNotification(Map map) {
    sendToSubscribers(new WebSocketEvent('notify', map));
  }

  bool isAutoScanning = false;
  autoScan(Timer t) async {
    if (!isAutoScanning) {
      isAutoScanning = true;
      String dir = watcher.getScanDirectory();
      if (dir != null) {
        Series s = await db.getSeriesByLibraryLocation(dir);
        if (s != null) {
          if (s.updating) {
            watcher.scanRequired.add(dir);
          } else {
            scanSeries(s.id);
          }
        }
      }
      isAutoScanning = false;
    }
  }

  autoUpdateSeries(Timer t) async {
    Series needsUpdate = await db.getSeriesNeedingUpdate();
    if (needsUpdate != null) {
      logger.info("${needsUpdate.name} Metadata has not been updated since ${needsUpdate.lastUpdated}, Updating.");
      await updateSeries(needsUpdate.id);
    }
  }

  bool isPostProcessing = false;
  postProcess(Timer t) async {
    if (!isPostProcessing) {
      isPostProcessing = true;
      await postProcessor.processComplete();
      isPostProcessing = false;
    }
  }

  onChangeEvent(evt) async {
    List<String> parts = evt.payload.split(' ');
    String action = parts[0];
    String model = parts[1];
    WebSocketEvent event;
    //logger.fine("db ChangeEvent received: ${evt.channel} => ${evt.payload}");
    if (model == 'torrent') {
      String hash = parts[2];
      Map data = {'hash': hash};
      var eventName = '${model}::${action}';
      event = new WebSocketEvent(eventName, data);
      //print("torrent $action $data");
    } else if (model == 'series') {
      int pk = int.parse(parts[2]);
      Map data = {'id': pk};
      if (action == 'update') {
        List<String> fields = parts[3].split(',');
        Series s = await db.getSeries(pk);
        Map updatedValues = {};
        s.toMap().forEach((k,v) {
          if (fields.contains(k) || k == 'knownEpisodes' || k == 'downloadedEpisodes') {
            updatedValues[k] = v;
          }
        });
        data['fields'] = updatedValues;
      }
      var eventName = '${model}::${action}';
      event = new WebSocketEvent(eventName, data);

    } else if (model == 'episode') {
      int pk = int.parse(parts[2]);
      int seriesId = int.parse(parts[3]);
      Map data = {'id': pk, 'seriesId': seriesId};
      if (action == 'update') {
        List<String> fields = parts[4].split(',');
        Episode e = await db.getEpisode(pk);
        Map updatedValues = {};
        e.toMap().forEach((k,v) {
          if (fields.contains(k)) {
            updatedValues[k] = v;
          }
        });
        data['fields'] = updatedValues;
      }
      var eventName = '${model}::${action}';
      event = new WebSocketEvent(eventName, data);
    } else {
      // TODO: Log something
    }
    this.sendToSubscribers(event);
  }

  scanSeries(seriesId) async {
    Series series = await db.getSeries(seriesId);
    logger.info("Scanning ${series.name}...");
    await db.setSeriesUpdating(seriesId, true);
    List<Episode> episodes = await db.getEpisodes(seriesId);
    List<String> files = (await getFilesRecursively(path.join(conf.library_root, series.libraryLocation))).map((f) => f.path).toList();
    List<FileInfo> matchInfo = files.map((f) => getFileInfo(f)).toList();

    int newFiles = 0;
    int lostFiles = 0;
    int movedFiles = 0;

    bool lost;

    for (Episode ep in episodes) {
      lost = false;
      // If the db record has a libraryLocation, make sure it still exists.
      if (ep.libraryLocation != null) {
        if (!files.contains(ep.libraryLocation)) {
          lost = true;
          logger.info("${ep.libraryLocation} no longer exists, marking ${ep.seasonEpisode} as ignored.");
          ep.libraryLocation = null;
          await db.updateEpisode(ep.id, {'libraryLocation': null, 'status': 'Ignored'});
        } else {
          // The file still exists.
          continue;
        }
      }

      // if we get here, the episode has no associated file in the db
      // we have to find one.
      List<FileInfo> matches = matchInfo.where((fi) => fi.season == ep.seasonNumber && fi.episodes.contains(ep.number)).toList();
      if (matches.length > 0) {
        if (lost) {
          movedFiles += 1;
        } else {
          newFiles += 1;
        }
        ep.libraryLocation = matches[0].path;
        logger.fine("matched ${ep.libraryLocation} to ${ep.seasonEpisode}");
        await db.updateEpisode(ep.id, {'libraryLocation': ep.libraryLocation, 'status': 'Downloaded'});
      } else {
        // Check for date-based
        matches = matchInfo.where((fi) => fi.isDateNamed && ep.firstAired != null && fi.airDate == "${ep.firstAired.year}-${ep.firstAired.month}-${ep.firstAired.day}").toList();
        if (matches.length > 0) {
          if (lost) {
            movedFiles += 1;
          } else {
            newFiles += 1;
          }
          ep.libraryLocation = matches[0].path;
          logger.fine("matched ${ep.libraryLocation} to ${ep.seasonEpisode} (by airdate)");
          await db.updateEpisode(ep.id, {'libraryLocation': ep.libraryLocation, 'status': 'Downloaded'});
        } else {
          if (lost) {
            lostFiles += 1;
          }
        }
      }
    }
    if (lostFiles > 0 || newFiles > 0 || movedFiles > 0) {
      plex.refresh();
    }
    logger.info("Scan of ${series.name} complete. [${newFiles} new, ${movedFiles} moved, ${lostFiles} lost]");
    await db.setSeriesUpdating(seriesId, false);
  }

  Future updateSeries(seriesId, {String libraryLocation: null, bool scan: false}) async {

    TVDB tvdb = new TVDB();
    tvdb.apiKey = conf.tvdb_api_key;
    Series existing = await db.getSeries(seriesId);
    String cachedName = seriesNameCache[seriesId];

    if (cachedName == null) {
      cachedName = "Unknown Series";
    }

    String action = existing == null ? "Adding new Series ${cachedName}" : "Updating series ${existing.name}";
    logger.info(action);
    Map seriesData = await tvdb.getSeries(seriesId, includeEpisodes: true);
    broadcastNotification({"message": action});
    if (libraryLocation != null) {
      seriesData["libraryLocation"] = libraryLocation;
    } else if (existing == null) {
      String dirname = cleanSeriesName(seriesData['name']);
      Directory dir = new Directory(path.join(conf.library_root, dirname));
      try {
        await dir.create();
        seriesData['libraryLocation'] = dirname;
      } catch (exception, stacktrace) {
        logger.severe("Failed to create directory ${dir}", exception, stacktrace);
      }
    }

    bool success = await db.insertOrUpdateSeries(seriesId, seriesData);
    if (success) {
      if (existing == null) {
        Series newSeries = await db.getSeries(seriesId);
        broadcastNotification({"message": "${newSeries.name} Successfully Added!"});
        logger.info("Successfully added new series ${newSeries.name}.");
      } else {
        broadcastNotification({"message": "${existing.name} Successfully Updated!"});
        logger.info("Successfully updated metadata for ${existing.name}.");
      }
      if (scan) {
        scanSeries(seriesId);
      }
    } else {
      logger.warning("Failed to update metadata for ${existing.name}, is it locked?");
      broadcastNotification({"message": "Failed to update ${existing.name}, is it Locked?"});
    }

  }

  _chooseAndDownloadTorrents(List<Episode> wantedEpisodes, List<Map> torrents) async {

    Map potentialMatches = {};
    Map<Episode, Map> downloaded = {};

    // Collect all matching torrents for each wanted episode.
    // so that we can choose the appropriate one if there are multiple.
    for (Episode e in wantedEpisodes) {
      var matches = torrents.where((t) => torrentMatchesEpisode(t, e)).toList();
      if (matches.length > 0) {
        potentialMatches[e] = matches;
      }
    }

    for (Episode e in potentialMatches.keys) {
      Series s = await db.getSeries(e.seriesId);
      String preferredRes = s.preferredResolution;
      if (preferredRes == null) {
        preferredRes = conf.default_preferred_resolution;
      }

      List<Map> potential = potentialMatches[e];
      logger.fine("Looking for ${s.name} ${e.seasonEpisode} in ${potential.length} potential torrents.");

      List<Map> resMatch = potential.where((t) => t['Resolution'] == preferredRes).toList();

      if (resMatch.length == 0) {
        continue;
      }

      if (resMatch.length > 1) {
        List<Map> scene =resMatch.where((t) => t['Origin'] == 'Scene').toList();
        if (scene.length > 0) {
          resMatch = scene;
        }
      }

      Map choice = null;
      if (resMatch.length > 1) {
        resMatch.sort((a,b) {
          return int.parse(a['Seeders']).compareTo(int.parse(b['Seeders']));
        });
        choice = resMatch.last; // Most seeders
      } else {
        choice = resMatch[0];
      }

      var resp = await transmission.addTorrent(choice['DownloadURL'], 'episode:${e.id}');
      if (resp.containsKey('torrent-added')) {
        await db.updateEpisode(e.id, {'status': 'Downloading'});
        downloaded[e] = choice;
      }
    }
    return downloaded;
  }

  autoTorrentSearch(Timer timer) async {

    Map meta = await db.getBTNMeta();
    List<int> lastTorrentIds = [];
    if (meta['lastTorrentIds'] != null && meta['lastTorrentIds'] != '') {
      lastTorrentIds = meta['lastTorrentIds'].split(',').map((id) {
        return int.parse(id);
      }).toList();
    }
    List<Episode> wantedEps = await db.getWantedEpisodes();

    List seriesIds = new Set.from(wantedEps.map((e) => e.seriesId)).toList();
    logger.info("Torrent search for ${seriesIds.length} series.");
    Map query = {'tvdb': seriesIds, 'time': '>=${meta["lastTorrentTime"]}', 'category': 'Episode'};
    List<Map> torrents = await btn.search(query);
    logger.info("Processing ${torrents.length} new Torrents.");
    if (torrents.length == 0) {
      return;
    }

    String newLastIds = torrents.map((t) => t['TorrentID']).join(',');
    int newLastTime = int.parse(torrents[0]['Time']);

    // process the new Torrents
    torrents = torrents.where((t) => !lastTorrentIds.contains(int.parse(t['TorrentID']))).toList();

    var downloaded = await _chooseAndDownloadTorrents(wantedEps, torrents);
    if (downloaded.length > 0) {
      broadcastNotification({'message': 'Auto-Download snatched torrents: ${downloaded.values.map((d) => d['ReleaseName']).toList()}'});
    }
    await db.setBTNMeta({'lastTorrentTime': newLastTime, 'lastTorrentIds': newLastIds});
    logger.fine("Auto-search complete.");
  }

  backfillSeries(Series s) async {

    var torrents = btn.search({'tvdb': s.id});
    List<Episode> wantedEpisodes = await db.getWantedEpisodes();
    wantedEpisodes = wantedEpisodes.where((e) => e.seriesId == s.id).toList();
    _chooseAndDownloadTorrents(wantedEpisodes, torrents).then((Map<Episode, Map> downloaded) {
      broadcastNotification({'message': 'Backfill downloaded torrents: ${downloaded.values.map((d) => d['ReleaseName']).toList()}'});
    });

  }

  /**
 * RPC Handlers
 */

  Future rpc_setEpisodeStatus(CompatibleWebSocket socket, Map args) async {
    for (int epId in args['episodes']) {
      await db.updateEpisode(epId, {'status': args['status']});
    }
    return new Future.value("ok");
  }

  Future rpc_saveSeriesSettings(CompatibleWebSocket socket, Map args) async {

    await db.insertOrUpdateSeries(args['id'], args);
    return new Future.value("ok");
  }

  Future<Map> rpc_getConfig(CompatibleWebSocket socket, Map args) {
    return new Future.value(conf.toMap());
  }

  Future rpc_saveConfig(CompatibleWebSocket socket, Map args) {
    conf.updateFromMap(args);
    conf.save();
    broadcastNotification({'message': 'Config Updated'});
  }

  Future rpc_unlockSeries(CompatibleWebSocket socket, Map args) async {
    await db.setSeriesUpdating(args['id'], false);
  }

  Future<Map> rpc_validateSetting(CompatibleWebSocket socket,  Map args) async {
    var val = await conf.validate(args['setting'], args['value']);
    return val;
  }

  Future<List<Series>> rpc_getAllSeries(CompatibleWebSocket socket, Map args) async {
    List<Series> results = (await db.getAllSeries()).map(
            (series) => series.toMap()
    ).toList();
    return new Future.value(results);
  }

  Future<List<Map>> rpc_getSeries(CompatibleWebSocket socket, Map args) async {
    Series s = await db.getSeries(args["id"]);
    if (args.containsKey('includeEpisodes') && args['includeEpisodes'] != false) {
      s.episodes = await db.getEpisodes(s.id);
    }
    return new Future.value(s.toMap());
  }

  Future<List<Episode>> rpc_getUpcomingEpisodes(CompatibleWebSocket socket, Map args) async {
    List<Episode> upcoming = await db.getUpcomingEpisodes();
    return upcoming.map((e) => e.toMap()).toList();
  }

  Future<List<Map>> rpc_getAllTorrents(CompatibleWebSocket socket, Map args) async {
    List results = transmission.torrents.values.map((t) => t.toMap()).toList();
    return results;
  }

  Future rpc_scanSeries(CompatibleWebSocket socket, Map args) async {
    return await scanSeries(args['id']);
  }

  Future rpc_searchTorrent(CompatibleWebSocket socket, Map args) async {
    Series series;
    Episode episode;
    Map query = {};
    if (args.containsKey('episodeId')) {
      episode = await db.getEpisode(args['episodeId']);
      series = await db.getSeries(episode.seriesId);
      query['category'] = 'Episode';
    } else if (args.containsKey('seriesId')) {
      series = await db.getSeries(args['seriesId']);
      query['category'] = 'Season';
    }

    query['tvdb'] = series.id;

    List<Map> results = await btn.search(query);
    logger.finer("${results.length} unfiltered");
    if (episode != null) {
      results = results.where((t) => torrentMatchesEpisode(t, episode)).toList();
    } else if (args['seasonNumber'] != null) {
      results = results.where((t) => t['GroupName'] == 'Season ${args['seasonNumber']}').toList();
    }
    String preferredRes = series.preferredResolution == null ? conf.default_preferred_resolution : series.preferredResolution;
    results.sort((a, b) {
      int aRes = a['Resolution'] == preferredRes ? 0 : 1;
      int bRes = b['Resolution'] == preferredRes ? 0 : 1;
      int res = aRes.compareTo(bRes);
      if (res == 0) {
        return int.parse(b['Seeders']).compareTo(int.parse(a['Seeders']));
      }
      return res;
    });
    logger.finer("${results.length} filtered");
    return results;
  }

  bool torrentMatchesEpisode(Map t, Episode ep) {
    if (t['Category'] == 'Season') return false;
    if (t['TvdbID'].toString() != ep.seriesId.toString()) return false;

    String grpName = t['GroupName'];
    Match match = seasonEpPattern.firstMatch(grpName);
    if (match != null) {
      int season = int.parse(match.group(1));
      List<int> epnums = episodeRepeatPattern.allMatches(match.group(2)).map((m) => int.parse(m.group(1))).toList();
      return (season == ep.seasonNumber && epnums.contains(ep.number));
    } else {
      match = airDatePattern.firstMatch(grpName);
      if (match != null) {
        return (ep.formatFirstAired('yyyy.MM.dd') == '${match.group(1)}.${match.group(2)}.${match.group(3)}');
      } else {
        return false;
      }
    }
  }

  Future rpc_subscribe(CompatibleWebSocket socket, Map  args) {
    List events;
    if (args["events"] is String) {
      events = [args["events"]];
    } else {
      events = args["events"];
    }

    for (String event in events) {
      if (!dataSubscriptions.containsKey(event)) {
        dataSubscriptions[event] = new Set();
      }
      dataSubscriptions[event].add(socket);
    }
    return new Future.value("ok");
  }

  Future rpc_unsubscribe(CompatibleWebSocket socket, Map args) {
    List events;
    if (args["events"] is String) {
      events = [args["events"]];
    } else {
      events = args["events"];
    }
    for (String event in events) {
      if (dataSubscriptions.containsKey(event)) {
        dataSubscriptions[event].remove(socket);
      }
    }
    return new Future.value("ok");
  }

  Future rpc_addTorrent(CompatibleWebSocket socket, Map args) async {
    var relatedContent = null;
    if (args.containsKey('episodeId')) {
      relatedContent = 'episode:${args['episodeId']}';
    } else if (args.containsKey('seasonNumber') && args.containsKey('seriesId')) {
      relatedContent = 'season:${args['seriesId']}:${args['seasonNumber']}';
    }
    var resp = await transmission.addTorrent(args['url'], relatedContent);

    if (resp.containsKey("torrent-added")) {
      if (relatedContent != null) {
        if (args.containsKey('episodeId')) {
          await db.updateEpisode(args['episodeId'], {'status': 'Downloading'});
        }
      }
    }
    return resp;
  }

  Future rpc_updateSeries(CompatibleWebSocket socket, Map args) {
    updateSeries(args["id"], libraryLocation: args["libraryLocation"], scan: args["scan"] == true || args.containsKey("libraryLocation"));
    return new Future.value('ok');
  }

  Future rpc_getUnusedSeriesDirectories(CompatibleWebSocket socket, Map args) async {
    Directory dir = new Directory(conf.library_root);
    List results = await dir.list(recursive: false).toList();
    List<String> response = [];
    List<String> used = await db.getAllSeriesDirectories();
    String d;
    for (var res in results) {
      if (res is Directory) {
        d = path.basename(res.path);
        if (!used.contains(d)) {
          response.add(d);
        }
      }
    }
    return response;
  }

  Future rpc_deleteSeries(CompatibleWebSocket socket, Map args) async {
    Series s = await db.getSeries(args['id']);
    await db.deleteSeries(args['id']);
    broadcastNotification({"message": "Deleted ${s.name}"});
  }

  Future rpc_newSeriesSearch(CompatibleWebSocket socket, Map args) async {
    List results = await tvdb.search(args["seriesName"], "en");
    List<Map> returnVal = [];
    for (Series e in results) {
      Map map = e.toMap();
      seriesNameCache[e.id] = e.name;
      map["inLibrary"] = await db.seriesExists(map['id']);
      returnVal.add(map);
    }
    return returnVal;
  }

  Future rpc_backfillSeries(CompatibleWebSocket socket, Map args) async {
    Series s = await db.getSeries(args['id']);
    if (s != null) {
      backfillSeries(s);
    }
  }
}

class WebSocketEvent {
  String type;
  Map data;
  WebSocketEvent(this.type, this.data);
}
