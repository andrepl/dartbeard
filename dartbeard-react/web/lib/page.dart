import 'dart:html';
import 'dart:async';
import 'package:react/react_client.dart' as reactClient;
import 'package:react/react.dart';
import 'package:route_hierarchical/client.dart';
import 'package:models/models.dart';
import 'websocket_client.dart';

abstract class Page extends Component {

    WebSocketClient get ws => this.props['ws'];
    List<String> EVENTS = [];
    StreamSubscription sub;

    getHeader(String title, contents) {
      List body = [
        button({'id': 'menu-toggler', 'type': "button", 'className': "btn btn-default", 'aria-label': "Left Align"}, [
          span({'className': "glyphicon glyphicon-menu-hamburger", 'aria-hidden': "true", 'onClick': this.toggleMenu})
        ]),
        h1({}, title)
      ];
      if (contents is List) {
        body.addAll(contents);
      } else if (contents is Component) {
        body.add(contents);
      }
      return div({'className': 'content-header'}, body);
    }

    void toggleMenu(event) {
      document.getElementById('sidebar-wrapper').classes.toggle('expanded');
    }

    void onWebSocketEvent(WebSocketEvent event) {}

    componentDidMount(rootNode) async {
      ws.subscribe(EVENTS, this);
      sub = ws.events.where((e) => EVENTS.contains(e.type)).listen(onWebSocketEvent);
    }

    componentWillUnmount() async {
      ws.unsubscribe(EVENTS, this);
      sub.cancel();
    }
}