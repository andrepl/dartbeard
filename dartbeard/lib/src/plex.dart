library dartbeard.plex;

import 'dart:async';

import 'package:xml/xml.dart' as XML;
import 'package:http/http.dart' as http;


class Plex {

  DateTime _lastSectionIdTime = new DateTime.fromMillisecondsSinceEpoch(0);

  String _host;
  int _port;
  String _libraryRoot;
  int _sectionId = null;

  get host => _host;
  get libraryRoot => _libraryRoot;
  get port => _port;

  set host(String val) {
    _host = val;
    _sectionId = null;
  }

  set port(int val) {
    _port = val;
    _sectionId = null;
  }

  set libraryRoot(String val) {
    _libraryRoot = val;
    _sectionId = null;
  }

  Plex();

  getSectionId() async {
    if (_sectionId != null) {
      if (new DateTime.now().difference(_lastSectionIdTime) < new Duration(minutes: 1)) {
        return _sectionId;
      }
    }

    var resp = await http.get("http://$host:$port/library/sections");

    XML.XmlDocument doc = XML.parse(resp.body);
    List dirs = doc.findAllElements("Directory").toList();
    for (XML.XmlElement dir in dirs) {
      int key = int.parse(dir.getAttribute('key'));
      for (XML.XmlElement child in dir.findElements('Location')) {
        String locPath = child.getAttribute('path');
        if (!locPath.endsWith('/')) {
          locPath += '/';
        }
        String libPath = libraryRoot;
        if (!libPath.endsWith('/')) {
          libPath += '/';
        }
        if (libPath == locPath) {
          // This is the one to refresh;
          _lastSectionIdTime = new DateTime.now();
          _sectionId = key;
          return _sectionId;
        }
      }
    }
    return null;
  }

  refresh() async {
    if (host != null && libraryRoot != null) {
      int sectionId = await getSectionId();
      String url = "http://$host:$port/library/sections/$sectionId/refresh";
      await http.get(url);
    }
  }

}

main() {
  Plex plex = new Plex();
  plex.host = 'scruffy';
  plex.port = 32400;
  plex.tvPath = '/media/media/TV';
  plex.refresh();
}