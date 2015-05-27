library dartbeard.conf;

import "dart:convert";
import "dart:io";
import "dart:async";
import "dart:mirrors";
import "package:path/path.dart" as path;

class Conf {
  static final Conf _conf = new Conf._internal();

  factory Conf() {
    return _conf;
  }

  static Map _defaultConfig = {
    new Symbol('cache_directory'): 'cache',
    new Symbol('username'): "admin",
    new Symbol('password'): "admin",
    new Symbol('transmission_host'): "localhost",
    new Symbol('transmission_port'): 9090,
    new Symbol('database_uri'): 'postgresql://dartbeard:dartbeard@localhost:5432/dartbeard',
    new Symbol('library_root'): null,
    new Symbol('tvdb_api_key'): null,
    new Symbol('btn_api_key'): null,
    new Symbol('default_preferred_resolution'): "720p",
    new Symbol('default_rename_pattern'): "Season {seasonNumber}/{series|dotspace}.S{seasonNumber|zero:2}E{number|zero}.{name|dotspace}.{extension}",
    new Symbol('plex_host'): null,
    new Symbol('plex_port'): 32400,
  };

  String get cache_directory => _getProp(new Symbol('cache_directory'));
  String get username => _getProp(new Symbol('username'));
  String get password => _getProp(new Symbol('password'));
  String get transmission_host => _getProp(new Symbol('transmission_host'));
  int get transmission_port => _getProp(new Symbol('transmission_port'));
  String get database_uri => _getProp(new Symbol('database_uri'));
  String get library_root => _getProp(new Symbol('library_root'));
  String get tvdb_api_key => _getProp(new Symbol('tvdb_api_key'));
  String get btn_api_key => _getProp(new Symbol('btn_api_key'));
  String get default_preferred_resolution => _getProp(new Symbol('default_preferred_resolution'));
  String get default_rename_pattern => _getProp(new Symbol('default_rename_pattern'));
  String get plex_host => _getProp(new Symbol('plex_host'));
  int get plex_port => _getProp(new Symbol('plex_port'));

  Map _config = {};

  File _configFile;

  Map toMap() {
    Map map = {};
    _defaultConfig.forEach((k,v) {
      map[MirrorSystem.getName(k)] = v;
    });
    _config.forEach((k, v) {
      map[MirrorSystem.getName(k)] = v;
    });
    return map;
  }

  Conf._internal() {
    _configFile = new File(path.join(path.dirname(Platform.script.toString()).substring(7), 'settings.json'));
    reload();
  }

  _getProp(Symbol name) {
    if (_config.containsKey(name)) {
      return _config[name];
    } else if (_defaultConfig.containsKey(name)) {
      return _defaultConfig[name];
    }
    throw new Exception("No Such Property");
  }

  _setProp(Symbol name, value) {
    if (_defaultConfig.containsKey(name)) {
      _config[name] = value;
    }
  }

  noSuchMethod(Invocation invocation) {
    if (invocation.isGetter) {
      _getProp(invocation.memberName);
    } else if (invocation.isSetter) {
      _setProp(invocation.memberName, invocation.positionalArguments.first);
    } else {
      throw new NoSuchMethodError(this, invocation.memberName, invocation.positionalArguments, invocation.namedArguments);
    }
  }

  void reload() {
    if (!_configFile.existsSync()) {
      Map defaults = {};
      _defaultConfig.forEach((k, v) => defaults[MirrorSystem.getName(k)] = v);
      _configFile.writeAsStringSync(JSON.encode(defaults));
    }
    Map parsed = JSON.decode(_configFile.readAsStringSync());

    parsed.forEach((k, v) {
      _config[new Symbol(k)] = v;
    });

  }

  void updateFromMap(Map config) {
    config.forEach((k, v) {
      _config[new Symbol(k)] = v;
    });
  }

  void save() {
    Map cfg = {};
    _config.forEach((k, v) {
      cfg[MirrorSystem.getName(k)] = v;
    });
    _configFile.writeAsStringSync(JSON.encode(cfg));
  }

  validate(setting, value) async {
    if (setting == 'library_root') {
      Directory dir = new Directory(value);
      bool exists;
      try {
        exists = await dir.exists();
      } catch (exc) {
        print(exc);
      }
      Map res = {"valid": exists, 'error': exists ? null : "Directory doesn't exist"};
      return res;
    } else if (setting == 'transmission_port') {
      int intVal = null;
      if (value is String) {
        try {
          intVal = int.parse(value);
        } catch (exception) {
          return {"valid": false, 'error': "Non-numeric"};
        }
      } else {
        intVal = value;
      }
      if (intVal <= 0 || intVal > 65534) {
        return {"valid": false, 'error': 'Out of range'};
      }
    }
    return {"valid": true};
  }

  String toString() {
    return toMap().toString();
  }

}