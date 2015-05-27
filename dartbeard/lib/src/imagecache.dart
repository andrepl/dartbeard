library dartbeard.imagecache;

import 'dart:async';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:mime/mime.dart' as mime;
import 'package:shelf/shelf.dart';
import 'package:path/path.dart' as path;
import 'package:dartbeard/src/util.dart' as util;
import 'package:http_parser/src/http_date.dart';
class ImageCache {
  Directory cacheDirectory;
  Duration cacheDuration;


  handleRequest (Request request) async {
    var segs = [cacheDirectory.path]..addAll(request.url.pathSegments);

    var fsPath = path.joinAll(segs);

    var entityType = FileSystemEntity.typeSync(fsPath, followLinks: true);

    File file = new File(fsPath);
    if (entityType == FileSystemEntityType.FILE) {
      var resolvedPath = file.resolveSymbolicLinksSync();
      if (!path.isWithin(cacheDirectory.path, resolvedPath)) {
        // Do not serve a file outside of the original fileSystemPath
        return new Response.notFound('Not Found');
      }
    }

    if (entityType == FileSystemEntityType.NOT_FOUND) {
      String host = segs[1];
      String imgPath = segs.sublist(2).join('/');
      http.Response resp = await http.get('http://$host/$imgPath');
      File newFile = new File(path.normalize(fsPath));
      if (!(await newFile.parent.exists())) {
        await newFile.parent.create(recursive: true);
      }
      await newFile.writeAsBytes(resp.bodyBytes);
      file = newFile;
    }

    var uri = request.requestedUri;

    var fileStat = file.statSync();
    var ifModifiedSince = request.ifModifiedSince;

    if (ifModifiedSince != null) {
      var fileChangeAtSecResolution = util.toSecondResolution(fileStat.changed);
      if (!fileChangeAtSecResolution.isAfter(ifModifiedSince)) {
        return new Response.notModified();
      }
    }

    var headers = <String, String>{
      HttpHeaders.CONTENT_LENGTH: fileStat.size.toString(),
      HttpHeaders.LAST_MODIFIED: formatHttpDate(fileStat.changed)
    };

    var contentType = mime.lookupMimeType(file.path);
    if (contentType != null) {
      headers[HttpHeaders.CONTENT_TYPE] = contentType;
    }

    return new Response.ok(file.openRead(), headers: headers);
  }
}