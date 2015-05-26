library dartbeard.tvdb;

import "dart:async";
import "dart:core";
import "dart:convert";

import "package:http/http.dart" as http;
import 'package:xml/xml.dart' as xml;
import 'package:models/models.dart';

class Time {
  int hour;
  int minute;
  Time(this.hour, this.minute);
}

class TVDB {
  String apiKey = null;
  String baseUrl = "http://thetvdb.com/";

  Future search(String search, String lang) async {
    List<Series> results = [];
    Uri url = new Uri(scheme: 'http', host: "thetvdb.com", path: "/api/GetSeries.php", queryParameters: {"seriesname": search, "language": lang});
    var resp = await http.get(url);
    if (resp.statusCode == 200) {
      var doc = xml.parse(resp.body);
      doc.findAllElements("Series").forEach((series) {
        var data = {};
        for (var c in series.children) {
          if (c.nodeType == xml.XmlNodeType.ELEMENT) {
            String field = _seriesFieldMap[c.name.toString()];
            if (field == null) {
              field = c.name.toString();
            }
            data[field] = c.text;
          }
        }

        results.add(new Series.fromMap(data));
      });
    }
    return results;
  }
  Map _seriesFieldMap = {
    "Airs_DayOfWeek": "airsDOW",
    "Airs_Time": "airsTime",
    "ContentRating": "contentRating",
    "FirstAired": "firstAired",
    "IMDB_ID": "imdbId",
    "Network": "network",
    "Overview": "overview",
    "Runtime": "runTime",
    "SeriesName": "name",
    "Status": "status",
    "banner": "banner",
    "poster": "poster",
  };

  Map _episodeFieldMap = {
    "Director": "director",
    "FirstAired": "firstAired",
    "Overview": "overview",
    "SeasonNumber": "seasonNumber",
    "Writer": "writer",
    "filename": "image",
    "EpisodeNumber": "number",
    "EpisodeName": "name",
    "seriesid": "seriesId",
  };


  List<RegExp> timeParsers = [
    new RegExp(r"(\d+)\D(\d+)\s?(a|p).*", caseSensitive: false),
    new RegExp(r"(\d+)\s?(a|p).*", caseSensitive: false),
    new RegExp(r"(\d+)\D(\d+).*", caseSensitive: false),
  ];

  Time parseTime(String ts) {
    Match m;
    for (RegExp re in timeParsers) {
      m = re.firstMatch(ts);
      if (m != null) {
        break;
      }
    }
    if (m == null) {
      return null;
    }

    if (m.groupCount == 3) {
      int hr = int.parse(m.group(1));
      int min = int.parse(m.group(2));
      if (m.group(3).toLowerCase() == 'p') {
        hr += 12;
      }
      return new Time(hr, min);
    } else if (m.groupCount == 2) {
      int hr = int.parse(m.group(1));
      int min = 0;
      try {
        min = int.parse(m.group(2));
      } catch (exc) {
        if (m.group(2).toLowerCase() == 'p') {
          hr += 12;
        }
      }
      return new Time(hr, min);
    }
  }

  Map parseEpisode(tree, Map series) {

    Map map = {};
    for (var c in tree.children) {
      if (c.nodeType == xml.XmlNodeType.ELEMENT) {
        String field = _episodeFieldMap[c.name.toString()];
        if (field == null) {
          field = c.name.toString();
        }
        map[field] = c.text.toString();
      }
    }
    DateTime firstAired;
    try {
      firstAired = DateTime.parse(map['firstAired']);
      var times = series['airsTime'];
      if (times != null) {
        Time t = parseTime(series['airsTime']);
        firstAired = new DateTime(firstAired.year, firstAired.month, firstAired.day, t.hour, t.minute, 0, 0);
      }
    } catch (exc) {
    }
    if (firstAired != null) {
      map['firstAired'] = firstAired.toIso8601String();
    } else {
      map['firstAired'] = null;
    }
    return map;
  }

  Future getSeries(int id, {bool includeEpisodes: false}) async {
    String path = "/api/${apiKey}/series/${id}/en.xml";
    if (includeEpisodes) {
      path = "/api/${apiKey}/series/${id}/all/en.xml";
    }
    Map data = {};
    Uri url = new Uri(scheme: 'http', host: "thetvdb.com", path: path);
    http.Response resp = await http.get(url);
    if (resp.statusCode == 200) {
      String body = UTF8.decode(resp.bodyBytes);
      if (!body.trimRight().endsWith("</Data>")) {
        body += "</Data>";
      }
      var doc = xml.parse(body);
      var root = doc.findAllElements("Series").first;
      for (var c in root.children) {
        if (c.nodeType == xml.XmlNodeType.ELEMENT) {
          String field = _seriesFieldMap[c.name.toString()];
          if (field == null) {
            field = c.name.toString();
          }
          data[field] = c.text;
          if (data[field] == '') {
            data[field] = null;
          }
        }
      }

      if (includeEpisodes) {
        data["episodes"] = doc.findAllElements("Episode").map((e) => parseEpisode(e, data)).toList();
      }
    }
    return data;
  }
}
