library dartbeard.btn;

import 'dart:async';

import 'dart:convert';
import "dart:io";


class BTN {

  String apiKey;
  int reqId = 0;
  HttpClient client = new HttpClient();

  BTN();

  Future<HttpClientResponse> request(method, args) async {
    String req = JSON.encode({'method': method, 'params': args, 'id': 'accd', 'jsonrpc': '2.0'});
    HttpClientRequest request = await client.postUrl(Uri.parse("http://api.btnapps.net/"));
    request.headers.add("Content-type", "application/json");
    request.write(req);
    HttpClientResponse response = await request.close();
    return response;
  }

  search(query) async {
    HttpClientResponse resp = await request("getTorrents", [apiKey, query, 1000, 0]);
    Map response = JSON.decode((await UTF8.decodeStream(resp)));
    if (int.parse(response['result']['results']) > 0) {
      return response['result']['torrents'].values.toList();
    } else {
      return [];
    }
  }

}

