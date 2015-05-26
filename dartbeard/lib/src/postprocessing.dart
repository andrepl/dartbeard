library dartbeard.postprocessing;

import 'dart:io';

import 'package:path/path.dart' as path;

import 'package:models/models.dart';

import "package:dartbeard/src/database.dart";
import "package:dartbeard/src/tvdb.dart";
import "package:dartbeard/src/conf.dart";
import "package:dartbeard/src/transmission.dart";
import "package:dartbeard/src/btn.dart";
import 'package:dartbeard/src/util.dart';
import 'package:dartbeard/src/plex.dart';


class PostProcessor {

  Conf conf;
  Database db;
  TVDB tvdb;
  Transmission transmission;
  BTN btn;
  Plex plex;
  PostProcessor(this.conf, this.db, this.tvdb, this.btn, this.transmission, this.plex);

  getRelatedContent(String relatedContent) async {
    List<String> parts = relatedContent.split(':');
    int pk = int.parse(parts[1]);
    if (parts[0] == 'episode') {
      return db.getEpisode(pk);
    } else if (parts[0] == 'series') {
      return db.getSeries(pk);
    } else {
      return relatedContent;
    }
  }

  processEpisode(Episode episode, Torrent torrent) async {
    await db.setTorrentProcessing(torrent.hash);
    Series s = await db.getSeries(episode.seriesId);
    String dir = path.join(conf.library_root, s.libraryLocation);
    String renamePattern = s.renamePattern;
    if (renamePattern == null) {
      renamePattern = conf.default_rename_pattern;
    }
    List<Map> files = await transmission.getTorrentFiles(torrent.hash);
    files = files.where((f) => isVideoFile(f['name'])).toList();
    files.sort((a,b) => a['length'].compareTo(b['length']));
    Map file = files.last;
    File srcFile = new File(path.join(torrent.downloadDir.path, file['name']));
    Map patternData = episode.toMap();
    patternData['series'] = s.name;
    patternData['extension'] = file['name'].split('.').last;
    String renamed = renderRename(renamePattern, patternData);
    File destFile = new File(path.join(dir, renamed));
    episode.libraryLocation = renamed;
    try {
      await mkdirs(destFile.parent);
      await linkFile(srcFile, destFile);
    } catch (exception) {
      print(exception);
    }
    await db.setTorrentProcessed(torrent.hash);
    await db.updateEpisode(episode.id, {'libraryLocation': renamed, 'status': 'Downloaded'});
    await plex.refresh();
  }

  processSeries(Series series, Torrent torrent) {

  }

  String findEpisodeFile(Episode ep, List<String> files) {
    for (String file in files) {
      Match m = seasonEpPattern.firstMatch(file);
      if (m != null) {
        List<int> epNums = episodeRepeatPattern.allMatches(m.group(2)).map((e) => int.parse(e.group(1))).toList();
        if (epNums.contains(ep.number)) {
          return file;
        }
      } else {
        m = airDatePattern.firstMatch(file);
        if (m != null) {
          if (ep.formatFirstAired('yyyy.MM.dd') == '${m.group(1)}.${m.group(2)}.${m.group(3)}') {
            return file;
          }
        }
      }
    }
    return null;
  }

  processSeason(Series series, int seasonNumber, Torrent torrent) async {
    await db.setTorrentProcessing(torrent.hash);
    String dir = path.join(conf.library_root, series.libraryLocation);
    String renamePattern = series.renamePattern;
    if (renamePattern == null) {
    renamePattern = conf.default_rename_pattern;
    }
    List<Map> files = await transmission.getTorrentFiles(torrent.hash);
    files = files.where((f) => isVideoFile(f['name'])).toList();
    String renamed = null;
    List<Episode> seasonEps = await db.getEpisodes(series.id, seasonNumber);
    Map patternData;
    for (Episode ep in seasonEps) {
      var file = findEpisodeFile(ep, files.map((f) => f['name']).toList());
      if (file != null) {
        patternData = ep.toMap();
        patternData['series'] = series.name;
        patternData['extension'] = file.split('.').last;
        renamed = renderRename(renamePattern, patternData);
        File srcFile = new File(path.join(torrent.downloadDir.path, file));
        File destFile = new File(path.join(dir, renamed));
        await mkdirs(destFile.parent);
        await linkFile(srcFile, destFile);
        ep.libraryLocation = renamed;
        ep.status = 'Downloaded';
        await db.updateEpisode(ep.id, {'libraryLocation': ep.libraryLocation, 'status': ep.status});
      }
    }
    await db.setTorrentProcessed(torrent.hash);
    await plex.refresh();
  }

  processUnknown(Torrent t) async {
    await db.setTorrentProcessing(t.hash);
    Map raw = await transmission.getRawTorrent(t.hash);
    bool hasBtnTracker = false;
    for (Map tracker in raw['trackers']) {
      if (tracker['announce'].contains("tracker.broadcasthe.net")) {
        hasBtnTracker = true;
        break;
      }
    }
    if (hasBtnTracker) {
      String name = raw['name'];
      if (isVideoFile(name)) {
        var parts = name.split(".");
        parts.removeLast();
        name = parts.join(".");
      }
      var matches = await btn.search({'release': name});
      if (matches.length > 0) {
        int seriesId = matches[0]['TvdbID'];
        Series s = await db.getSeries(seriesId);
        if (s == null) {
          //TODO
        }
      }
    }
    await db.setTorrentProcessed(t.hash);
    await plex.refresh();
  }

  processComplete() async {
    List<Torrent> unprocessed = await db.getUnprocessedTorrents();
    for (Torrent t in unprocessed) {
      if (t.relatedContent != null) {
        // Known Torrent (added by us)
        var related = await getRelatedContent(t.relatedContent);
        if (related is Episode) {
          processEpisode(related, t);
        } else if (related is Series) {
          processSeries(related, t);
        } else if (related is String) {
          if (related.startsWith("season:")) {
            var parts = related.split(':');
            Series s = await db.getSeries(int.parse(parts[1]));
            if (s != null) {
              processSeason(s, int.parse(parts[2]), t);
            }
          }
        }
      } else {
        // Unknown Torrent
        processUnknown(t);
      }
    }
  }
}