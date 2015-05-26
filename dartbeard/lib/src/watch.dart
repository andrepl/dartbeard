library dartbeard.watch;

import "dart:io";
import "package:path/path.dart" as path;


class Watcher {

  Set<String> scanRequired = new Set();

  Directory root;

  Map<Directory, StreamSubscription> subscribed = {};

  Watcher([String root]) {
    if (root != null) {
      setRootDirectory(root);
    }
  }

  String getScanDirectory() {
    if (scanRequired.length > 0) {
      String first = scanRequired.elementAt(0);
      scanRequired.remove(first);
      return first;
    }
    return null;
  }

  Directory findTopLevel(Directory dir) {
    while(dir.parent.path != root.path) {
      dir = dir.parent;
    }
    return dir;
  }

  void onEvent(Directory dir, FileSystemEvent event) {
    if (event.isDirectory && event.type == FileSystemEvent.CREATE) {
      Directory dir = new Directory(event.path);

      subscribed[dir] = dir.watch().listen((event) => onEvent(dir, event), onDone: () => onDone(dir));
    } else if (!event.isDirectory) {
      var tl = findTopLevel(dir);
      scanRequired.add(path.split(tl.path).removeLast());
    }
  }

  void onDone(Directory dir) {
    //print("Done watching ${dir}");
    var removed = subscribed.remove(dir);
    //print("removed ${removed}");
  }

  void setRootDirectory(String root) {
    subscribed.forEach((k, v) => v.cancel());
    subscribed.clear();
    this.root = new Directory(root);
    subscribed[this.root] = this.root.watch().listen((event) => onEvent(this.root, event), onDone: () => onDone(this.root));
    this.root.list(recursive: true).where((e) => e is Directory).listen((Directory entry) {
      subscribed[entry] = entry.watch().listen((event) => onEvent(entry, event), onDone: () => onDone(entry));
    }, onDone: () {
      // TODO: Log something
   });
  }
}
