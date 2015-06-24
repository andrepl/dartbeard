library dartbeard.transmission;

import "dart:async";
import "dart:convert";
import "dart:core";
import "dart:io";

import "package:crypto/crypto.dart";
import "package:path/path.dart" as path;
import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';
import 'package:models/models.dart';

import 'package:dartbeard/src/conf.dart';
import 'package:dartbeard/src/util.dart';
import 'package:dartbeard/src/btn.dart';


class Transmission {
  Logger logger = new Logger("dartbeard");
  static List<String> TORRENT_FIELDS = ["name", "hashString", "leftUntilDone", "totalSize", "status",
    "peers", "peersConnected", "activityDate", "downloadDir", "trackers"
    "doneDate", "startDate", "addedDate", "rateDownload", "rateUpload"];

  Future updater = null;
  Map<String, Torrent> torrents = {};

  String sessionId = "x";
  int _seq = 0;
  bool running = false;
  bool connected = false;
  String host;
  int port;
  String connectionError;
  var db;
  bool adding = false;

  Transmission();

  void stop() {
    running = false;

  }

  String _getTag() {
    if (_seq == 999999999) { _seq = 0; }
    return (_seq++).toString();
  }

  Future request(String method, [Map args]) async {
    Map payload = {"method": method, "tag": _getTag()};
    if (args != null) {
      payload["arguments"] = args;
    }
    String url = "http://${host}:${port}/transmission/rpc";
    Map headers = {"x-transmission-session-id": sessionId, "content-type": "application/json"};
    var response;
    try {
      response = await http.post(url, headers: headers, body: JSON.encode(payload));
    } on SocketException catch (e) {
      var connectionError = e.toString();
      connected = false;
      return null;
    }

    if (response.statusCode == 409) {
      sessionId = response.headers["x-transmission-session-id"];
      headers["x-transmission-session-id"] = sessionId;
      response = await http.post(url, headers: headers, body: JSON.encode(payload));
    }

    return response;
  }

  Future start() async {
    if (!running) {
      running = true;
      updater = new Future.delayed(new Duration(seconds: 1), updateTorrents);
    }
  }

  addTorrent(url, relatedContent) async {
    adding = true;
    String data = null;
    if (!url.startsWith("data:")) {
      http.Response response = await http.get(url);
      data = CryptoUtils.bytesToBase64(response.bodyBytes);
    } else {
      int pos = url.indexOf(',');
      data = url.substring(pos + 1);
    }
    
    var resp = await request("torrent-add", {'metainfo': data});
    Map respMap = JSON.decode(resp.body);

    Map args = respMap['arguments'];
    if (args.containsKey("torrent-added")) {
      Torrent t = new Torrent();
      t.relatedContent = relatedContent;
      t.hash = args['torrent-added']['hashString'];
      t.name = args['torrent-added']['name'];
      torrents[args['torrent-added']['hashString']] = t;
      var data = {
        'hash': args['torrent-added']['hashString'],
        'name': args['torrent-added']['name'],
        'relatedContent': relatedContent
      };
      logger.fine("Inserting/Updating torrent: ${data['hash']}, ${data['name']}, ${data['relatedContent']}");
      await db.insertOrUpdateTorrent(args['torrent-added']['hashString'], data);
    } else {
      logger.warning("Add Torrent Failed with: ${respMap}");
    }
    adding = false;
    return args;
  }

  updateTorrents() async {
    if (adding) {
      return;
    }
    var resp = await request("torrent-get", {"fields": TORRENT_FIELDS});
    if (resp != null) {
      Map rawList = JSON.decode(resp.body);
      List<String> seenKeys = [];
      for (var torrent in rawList["arguments"]["torrents"]) {
        Torrent tor;
        seenKeys.add(torrent['hashString']);
        if (torrents.containsKey(torrent["hashString"])) {
          tor = torrents[torrent["hashString"]];
          tor.updateFromMap(torrent);
        } else {
          tor = new Torrent.fromMap(torrent);
          torrents[tor.hash] = tor;
        }
        if (db != null) {
          Map map = tor.toDBMap();
          await db.insertOrUpdateTorrent(tor.hash, map);
        }
      }
      List<String> toRemove = torrents.keys.where((k) => !seenKeys.contains(k)).toList();
      if (toRemove.length > 0) {
        await db.deleteTorrents(toRemove);
        toRemove.forEach((k) => torrents.remove(k));
      }
    } else {
      //print("Not Connected");
    }
    if (running) {
      updater = new Future.delayed(new Duration(seconds: 1), updateTorrents);
    }
  }

  getRawTorrent(String hash) async {
    var resp = await request("torrent-get", {'ids': [hash], 'fields': TORRENT_FIELDS});
    Map respMap = JSON.decode(resp.body);
    return respMap['arguments']['torrents'][0];
  }

  getTorrentFiles(String hash) async {
    var resp = await request("torrent-get", {'ids': [hash], 'fields': ['id', 'files', 'downloadDir']});
    Map respMap = JSON.decode(resp.body);
    return respMap['arguments']['torrents'][0]['files'];
  }


}

//
//main() async {
//  var t = new Transmission("scruffy", 9091);
//  await t.start();
//}