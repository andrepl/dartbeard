library dartbeard.btn;

import 'dart:async';

import 'dart:convert';
import "dart:io";
import 'package:logging/logging.dart';


class BTN {
  final logger = new Logger("dartbeard");
  String apiKey;
  int reqId = 0;
  HttpClient client = new HttpClient();

  BTN();

  Future<HttpClientResponse> request(method, args) async {
    String req = JSON.encode({'method': method, 'params': args, 'id': 'accd', 'jsonrpc': '2.0'});
    try {
      HttpClientRequest request = await client.postUrl(Uri.parse("http://api.btnapps.net/"));
      request.headers.add("Content-type", "application/json");
      request.write(req);
      HttpClientResponse response = await request.close();
    } catch (err) {
      console.warn("Failed to reach BTN");
      console.warn(err);
      return null;
    }
    return response;
  }

  search(query) async {
    HttpClientResponse resp = await request("getTorrents", [apiKey, query, 1000, 0]);
    if (resp == null) {
      return [];
    }
    Map response;
    try {
      response = JSON.decode((await UTF8.decodeStream(resp)));
    } on FormatException catch (e, stack) {
      logger.severe("BTN Returned error response", e, stack);
      return [];
    }
    if (int.parse(response['result']['results']) > 0) {
      return response['result']['torrents'].values.toList();
    } else {
      return [];
    }
  }

}

