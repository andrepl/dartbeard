library dartbeard.util;

import "dart:async";
import "dart:io";


var seasonEpPattern = new RegExp(r"(?:\W|^)S(\d{1,4})(E\d+((?:E|\-|\-E)\d+)*)", caseSensitive: false);
var lastResortNumberPattern = new RegExp(r"(?:\D|^)(\d{1,4})(x\d+((?:x|\-|\-x)\d+)*)", caseSensitive: false);
var episodeRepeatPattern = new RegExp(r"(\d+)", caseSensitive: false);
var airDatePattern = new RegExp(r"(?:\D|^)(\d\d\d\d)\D(\d{1,2})\D(\d{1,2})(?:\D|$)", caseSensitive: false);

class FileInfo {
  String path;
  int season;
  List<int> episodes;
  bool isDateNamed = false;
  String airDate = null;
  FileInfo(this.path, this.season, this.episodes);
}

bool isNumeric(s) {
  if (s is int || s is double) {
    return true;
  }
  if(s == null) {
    return false;
  }

  // TODO according to DartDoc num.parse() includes both (double.parse and int.parse)
  return num.parse(s) != null;
}

num toNumeric(s) {
  if (s is int || s is double) {
    return s;
  }
  if (s == null) {
    return null;
  }
  return num.parse(s);
}

Set validExtensions = new Set.from(['mkv', 'mov', 'avi', 'mpg', 'mp4', 'mpeg4', 'ts', 'wmv', 'm4v']);

bool isVideoFile(filename) {
  var ext = filename.split(".").last.toLowerCase();
  return (validExtensions.contains(ext));
}

linkFile(File src, File dest) async {
  bool exists = await dest.exists();
  if (exists) {
    throw new OSError("destination file $dest already exists");
  }
  ProcessResult processResult = await Process.run('ln', [src.path, dest.path]);
  if (processResult.exitCode != 0) {
    throw new OSError("Error linking ${src.path} to ${dest.path}");
  }
}

Future<Directory> mkdirs(Directory dir) {
  return dir.create(recursive: true);
}

Future<List<File>> getFilesRecursively(String path) async {
  Directory dir = new Directory(path);
  bool exists = await dir.exists();
  if (!exists) {
    return null;
  }
  List<File> contents = await (dir.list(recursive: true).where((e) => e is File).toList());
  return contents;
}

String cleanSeriesName(String name) {
  return name.replaceAllMapped(new RegExp(r'[^\w\d\s:\._\(\)-]'), (m) {
    return '.';
  });
}

DateTime toSecondResolution(DateTime dt) {
  if (dt.millisecond == 0) return dt;
  return dt.subtract(new Duration(milliseconds: dt.millisecond));
}

FileInfo getFileInfo(String filename) {
  Match m = seasonEpPattern.firstMatch(filename);
  if (m != null) {
    // Season/Ep Num
    String epList = m.group(2);
    List<int> epNums = [];
    episodeRepeatPattern.allMatches(epList).forEach((e) {
      epNums.add(int.parse(e.group(1)));
    });
    int season = int.parse(m.group(1));
    return new FileInfo(filename, season, epNums);
  }

  // Date Based
  m = airDatePattern.firstMatch(filename);
  if (m != null) {
    int year = int.parse(m.group(1));
    int month = int.parse(m.group(2));
    int day = int.parse(m.group(3));
    FileInfo info = new FileInfo(filename, null, null);
    info.isDateNamed = true;
    info.airDate = "$year-$month-$day";
    return info;
  }
  // Last Resort Number Match
  m = lastResortNumberPattern.firstMatch(filename);
  if (m != null) {
    String epList = m.group(2);
    List<int> epNums = [];
    episodeRepeatPattern.allMatches(epList).forEach((e) {
      epNums.add(int.parse(e.group(1)));
    });
    int season = int.parse(m.group(1));
    return new FileInfo(filename, season, epNums);
  }
  // No Match
  return new FileInfo(filename, null, null);
}