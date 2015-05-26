import 'dart:html';
import 'dart:async';
import 'dart:convert';

class WebSocketEvent {
  String type;
  Map data;
  WebSocketEvent(this.type, this.data);
}

class WebSocketClient {
  String url;
  WebSocket ws;
  int _seq = 0;
  Map <String, Function> callbacks = {};
  Map <String, Completer> completers = {};
  StreamController eventController = new StreamController.broadcast();
  Stream get events => eventController.stream;
  Map<String,Set> eventSubscriptions = {};
  WebSocketClient(this.url);

  void onOpen(Event e) {
    print("Connected to server");
  }

  void onMessage(MessageEvent e) {
    Map response = JSON.decode(e.data);
    if (response.containsKey("tag")) {
        Function cb = callbacks.remove(response["tag"]);
        if (cb != null) {
          cb(response);
        }
        Completer completer = completers[response["tag"]];
        completer.complete(response);
    } else if (response.containsKey("event")) {
      var event = new WebSocketEvent(response["event"]["type"], response["event"]["data"]);
      eventController.add(event);
    }
  }

  void onClose(Event e) {
    print("Disconnected From server.");
    new Timer(new Duration(seconds: 5), connectSocket);
  }

  String getTag() {
    return (_seq++).toString();
  }

  subscribe (events, identifier) {
    List<String>  newSubs = [];
    for (var event in events) {
      if (eventSubscriptions[event] == null) {
        print("First sub for $event");
        eventSubscriptions[event] = new Set();
      }

      if (eventSubscriptions[event].length == 0) {
        newSubs.add(event);
      }
      eventSubscriptions[event].add(identifier);
    }
    if (newSubs.length > 0) {
      print("Subscribing to $newSubs");
      rpc("subscribe", args: {"events": newSubs});
    } else {
      print("No new subscriptions in ${events} (already subscribed to: ${eventSubscriptions.keys}");
    }
  }

  unsubscribe (events, identifier) {
    List<String> unsubs = [];
    for (var event in events) {
      if (eventSubscriptions.containsKey(event)) {
        eventSubscriptions[event].remove(identifier);
        if (eventSubscriptions[event].length == 0) {
          unsubs.add(event);
        }
      }
    }
    rpc("unsubscribe", args: {"events": unsubs});
  }

  Future rpc(String method, {Map args, Function callback}) async {

    Completer completer = new Completer();

    if (ws.readyState != WebSocket.OPEN) {
      print("Waiting for connection");
      await ws.onOpen.first;
    }

    String tag = getTag();
    if (callback != null) {
      callbacks[tag] = callback;
    }
    completers[tag] = completer;

    ws.send(JSON.encode({
      "method": method,
      "args": args,
      "tag": tag
    }));
    return completer.future;
  }

  connectSocket() {
    print("Connecting to $url");
    ws = new WebSocket(url);
    ws.onOpen.listen((Event e) => onOpen(e));
    ws.onMessage.listen((MessageEvent e) => onMessage(e));
    ws.onClose.listen((Event e) => onClose(e));
  }

}