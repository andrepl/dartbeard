// Copyright (c) 2015, <your name>. All rights reserved. Use of this source code
// is governed by a BSD-style license that can be found in the LICENSE file.

/// The models library.
library models;

import 'package:intl/intl.dart';
import 'dart:io';
DateFormat dateFormat = new DateFormat('yyyy-MM-dd');

int _dtToMillis(datetime) {
  if (datetime == null) {
    return null;
  }
  return datetime.millisecondsSinceEpoch;
}

DateTime _toDt(val) {
  if (val == null) {
    return null;
  } else if (val is DateTime) {
    return val;
  }
  if (val is String) {
    try {
      val = num.parse(val);
    } catch(exception) {
      try {
        return DateTime.parse(val);
      } catch (exception) {
        return null;
      }
    }
  }
  if  (val.toString().length <= 10) {
    val = val * 1000;
  }
  return new DateTime.fromMillisecondsSinceEpoch(val);
}

int _toNum(val) {
  if (val == null) {
    return null;
  }

  if (!(val is num)) {
    val = num.parse(val);
  }
  return val;
}


class Series {
  int id;
  String name;
  DateTime firstAired;
  String airsTime;
  String airsDOW;
  String overview;
  String contentRating;
  String network;
  int runTime;
  String banner;
  String poster;
  String fanart;
  String language;
  String status;
  String libraryLocation;
  DateTime lastUpdated;

  bool inLibrary = false;

  List<Episode> episodes = [];
  int knownEpisodes;
  int downloadedEpisodes;
  bool updating = false;
  bool ignore = false;

  String renamePattern;
  String preferredResolution;
  bool selected;
  int index;

  String get firstAiredDate => firstAired == null ? null : dateFormat.format(firstAired);

  String get sortableName {
    String ln = name.toLowerCase();
    if (ln.startsWith("the ")) {
      return name.substring(4);
    } else if (ln.startsWith("a ")) {
      return name.substring(2);
    } else if (ln.startsWith("an ")) {
      return name.substring(3);
    }
    return name;
  }

  String get sortableFirstAired {
    if (firstAired == null) {
      return '99990101';
    } else {
      return formatFirstAired('YYYYMMdd');
    }
  }
  Series();

  String get airsAtString {
    bool _airsTime = airsTime != null && airsTime.trim() != '';
    bool _airsDOW = airsDOW != null && airsDOW.trim() != '';
    return (_airsTime && _airsDOW && status != 'Ended') ? "$airsDOW @ $airsTime" : "";
  }

  Map toMap() {
    Map map = {
      'id': id, 'name': name, 'firstAired': _dtToMillis(firstAired), 'airsTime': airsTime, 'airsDOW': airsDOW, 'overview': overview,
      'contentRating': contentRating, 'network': network, 'runTime': runTime, 'banner': banner, 'poster': poster,
      'fanart': fanart, 'language': language, 'status': status, 'libraryLocation': libraryLocation, 'updating': updating,
      'inLibrary': inLibrary, 'knownEpisodes': knownEpisodes, 'downloadedEpisodes': downloadedEpisodes, 'renamePattern': renamePattern,
      'preferredResolution': preferredResolution, 'ignore': ignore, 'lastUpdated': _dtToMillis(lastUpdated),
      'sortableName': name == null ? null : sortableName, 'episodes': (episodes == null) ? null : episodes.map((e) => e.toMap()).toList()
    };
    return map;
  }

  Map toDBMap() {
    Map map = toMap();
    if (map.containsKey('lastUpdated')) {
      map['lastUpdated'] = _toDt(map['lastUpdated']);
    }
    return map;
  }

  void updateFromMap(Map map) {
    if (map.containsKey('id')) id = _toNum(map['id']);
    if (map.containsKey('name')) name = map['name'];
    if (map.containsKey("firstAired")) firstAired = _toDt(map["firstAired"]);
    if (map.containsKey("airsTime")) airsTime = map["airsTime"];
    if (map.containsKey("airsDOW")) airsDOW = map["airsDOW"];
    if (map.containsKey("overview")) overview = map["overview"];
    if (map.containsKey("contentRating")) contentRating = map["contentRating"];
    if (map.containsKey("network")) network = map["network"];
    if (map.containsKey("runTime")) runTime = _toNum(map["runTime"]);
    if (map.containsKey("banner")) banner = map["banner"];
    if (map.containsKey("poster")) poster = map["poster"];
    if (map.containsKey("fanart")) fanart = map["fanart"];
    if (map.containsKey("language")) language = map["language"];
    if (map.containsKey("status")) status = map["status"];
    if (map.containsKey("updating")) updating = map["updating"];
    if (map.containsKey("libraryLocation")) libraryLocation = map["libraryLocation"];
    if (map.containsKey("knownEpisodes")) knownEpisodes = _toNum(map["knownEpisodes"]);
    if (map.containsKey("downloadedEpisodes")) downloadedEpisodes = _toNum(map["downloadedEpisodes"]);
    if (map.containsKey("inLibrary")) inLibrary = map["inLibrary"];
    if (map.containsKey("renamePattern")) renamePattern = map['renamePattern'];
    if (map.containsKey("preferredResolution")) preferredResolution = map['preferredResolution'];
    if (map.containsKey("ignore")) ignore = map['ignore'];
    if (map.containsKey("lastUpdated")) lastUpdated = _toDt(map['lastUpdated']);
    if (map.containsKey("episodes") && map["episodes"] is List) {
      episodes = map["episodes"].map((em) => new Episode.fromMap(em)).toList();
    }
  }

  formatFirstAired(fmt) {
    // Polymer.dart doesn't allow us to use |filter functions
    // inside core-list-dart. so we need this workaround.
    if (this.firstAired == null) {
      return null;
    }
    return new DateFormat(fmt).format(this.firstAired);
  }

  Series.fromMap(Map map) {
    updateFromMap(map);
  }
}


class Episode {
  int id;
  int seriesId;
  String name;
  int seasonNumber;
  int number;
  DateTime firstAired;
  String overview;
  String libraryLocation;
  String image;
  String writer;
  String director;
  String status;

  Series series;
  bool selected;
  int index;
  String get firstAiredDate {
    if (firstAired == null) {
      return 'Unknown';
    }
    return dateFormat.format(firstAired);
  }

  formatFirstAired(fmt) {
    // Polymer.dart doesn't allow us to use |filter functions
    // inside core-list-dart. so we need this workaround.
    if (this.firstAired != null) {
      return new DateFormat(fmt).format(this.firstAired);
    }
    return null;
  }

  String get seasonEpisode {
    String s = seasonNumber.toString().padLeft(2, '0');
    String e = number.toString().padLeft(2, '0');
    return "S${s}E${e}";
  }

  void updateFromMap(Map map) {
    if (map.containsKey("id")) id = _toNum(map["id"]);
    if (map.containsKey("seriesId"))seriesId = _toNum(map["seriesId"]);
    if (map.containsKey("name")) name = map["name"];
    if (map.containsKey("seasonNumber")) seasonNumber = _toNum(map["seasonNumber"]);
    if (map.containsKey("number")) number =  _toNum(map["number"]);
    if (map.containsKey("firstAired")) firstAired = _toDt(map["firstAired"]);
    if (map.containsKey("overview")) overview = map["overview"];
    if (map.containsKey("libraryLocation")) libraryLocation = map["libraryLocation"];
    if (map.containsKey("image")) image = map["image"];
    if (map.containsKey("writer")) writer = map["writer"];
    if (map.containsKey("director")) director = map["director"];
    if (map.containsKey("status")) status = map["status"];
    if (map.containsKey("series") && map['series'] != null) {
      series = new Series.fromMap(map['series']);
    } else {
      Map sMap = {};
      map.forEach((k,v) {
        if (k.startsWith("series__")) {
          sMap[k.substring(8)] = v;
        }
      });
      if (sMap.length > 0) {
        series = new Series.fromMap(sMap);
      }
    }
  }

  Episode.fromMap(Map map) {
    updateFromMap(map);
  }

  Episode();

  String toString() {
    return seasonEpisode;
  }

  Map toMap() {
    return {
      'id': id,
      'seriesId': seriesId,
      'name': name,
      'seasonNumber': seasonNumber,
      'number': number,
      'firstAired': _dtToMillis(firstAired),
      'overview': overview,
      'libraryLocation': libraryLocation,
      'image': image,
      'writer': writer,
      'director': director,
      'status': status,
      'series': series == null ? null : series.toMap()
    };
  }

}


class Torrent {

  String hash;
  String name;
  String errorString;
  int status;
  int totalPeers;
  int connectedPeers;
  DateTime lastActive;
  DateTime startedAt;
  DateTime addedAt;
  DateTime finishedAt;
  Directory downloadDir;
  int rateDownload;
  int rateUpload;
  int totalSize;
  int leftUntilDone;
  int bytesDownloaded;

  // Not updated by transmission
  String relatedContent;
  int processed;

  bool selected;
  int index;
//
//  static DateTime getDT(json, key) {
//    if (!json.containsKey(key)) {
//      return null;
//    }
//    if (json[key] == null) {
//      return null;
//    }
//    return new DateTime.fromMillisecondsSinceEpoch(json[key] * 1000);
//  }

  Torrent.fromMap(Map json) {
    updateFromMap(json);
  }

  Map toDBMap() {
    Map map = toMap();
    if (map['lastActive'] != null) {
      map['lastActive'] = _toDt(map['lastActive']).toIso8601String();
    }
    if (map['startedAt'] != null) {
      map['startedAt'] = _toDt(map['startedAt']).toIso8601String();
    }
    if (map['addedAt'] != null) {
      map['addedAt'] = _toDt(map['addedAt']).toIso8601String();
    }
    if (map['finishedAt'] != null) {
      map['finishedAt'] = _toDt(map['finishedAt']).toIso8601String();
    }
    if (map.containsKey('bytesDownloaded')) {
      map.remove('bytesDownloaded');
    }
    map.remove("processed");
    map.remove("relatedContent");
    return map;

  }

  updateFromMap(Map json) {
    name = json["name"];
    hash = json.containsKey("hash") ? json["hash"] : json['hashString'];
    errorString = json["errorString"];
    status = json["status"];
    totalPeers = json.containsKey('peers') ? json["peers"].length : json["totalPeers"];
    connectedPeers = json.containsKey("peersConnected") ? json['peersConnected'] : json['connectedPeers'];
    lastActive = json.containsKey('activityDate') ? _toDt(json["activityDate"]) : _toDt(json['lastActive']);
    startedAt = json.containsKey('startDate') ? _toDt(json["startDate"]) : _toDt(json['startedAt']);
    addedAt = json.containsKey('addedDate') ? _toDt(json["addedDate"]) : _toDt(json['addedAt']);
    finishedAt = json.containsKey('doneDate') ? _toDt(json["doneDate"]) : _toDt(json['finishedAt']);
    downloadDir = json['downloadDir'] == null ? null : new Directory(json["downloadDir"]);
    rateDownload = json["rateDownload"];
    relatedContent = json['relatedContent'];
    processed = json['processed'];
    rateUpload  = json["rateUpload"];
    totalSize = json["totalSize"];
    leftUntilDone = json["leftUntilDone"];
    bytesDownloaded = totalSize - leftUntilDone;

  }

  Torrent();

  Map toMap() {
    return {
      "name": name,
      "hash": hash,
      "errorString": errorString,
      "status": status,
      "totalPeers": totalPeers,
      "connectedPeers": connectedPeers,
      "lastActive": lastActive == null ? null : lastActive.millisecondsSinceEpoch,
      "startedAt": startedAt == null ? null : startedAt.millisecondsSinceEpoch,
      "addedAt": addedAt == null ? null : addedAt.millisecondsSinceEpoch,
      "finishedAt": finishedAt == null ? null : finishedAt.millisecondsSinceEpoch,
      "downloadDir": downloadDir == null ? null : downloadDir.path,
      "rateDownload": rateDownload,
      "rateUpload": rateUpload,
      "totalSize": totalSize,
      "leftUntilDone": leftUntilDone,
      "bytesDownloaded": bytesDownloaded,
      "relatedContent": relatedContent,
      "processed": processed
    };
  }
}

RegExp varPattern = new RegExp(r'\{\s*([^\}\|\s]+)\s*\|?\s*([^\}]*)\s*\}');
Map filterFunctions = {
  'dotspace': (String s) => s.replaceAll(' ', '.'),
  'title': (String s) => s.split(' ').map((w) => w.toUpperCase().substring(0, 1) + w.toLowerCase().substring(1)).join(' '),
  'lower': (String s) => s.toLowerCase(),
  'upper': (String s) => s.toUpperCase(),
  'zero': (String s, {String arg: '2'}) {
    int zeroes = int.parse(arg);
    while (s.length < zeroes) {
      s = '0' + s;
    }
    return s;
  }
};

renderRename(String pattern, Map data) {
  var val = pattern.replaceAllMapped(varPattern, (match) {
    var variable = match.group(1);
    if (!data.containsKey(variable)) {
      throw new FormatException("No such variable: $variable");
    }
    var filter = match.group(2);
    var sub = data[variable].toString();
    if (filter.length > 0) {
      var calls = filter.split("|").map((c) => c.trim());
      for (var c in calls) {
        var arg = null;
        var func = null;
        if (c.contains(':')) {
          arg = c.split(':')[1];
          func = c.split(':')[0];
        } else {
          func = c;
        }
        if (!filterFunctions.containsKey(func)) {
          throw new FormatException("No such filter: $func");
        }
        if (arg != null) {
          sub = filterFunctions[func](sub, arg: arg);
        } else {
          sub = filterFunctions[func](sub);
        }
      }
    }
    return sub;
  });
  return val;
}

main() {
  Map data = {'season': 3, 'series': 'The Simpsons', 'episode': 2, 'episodeName': 'Bart goes to college', 'extension': 'mkv'};
  String inp = "Season %{season}/%{series|dotspace}.S%{season|zero:2}E%{episode|zero}.%{episodeName|dotspace}.%{extension}";
  print(renderRename(inp, data));
}