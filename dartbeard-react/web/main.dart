
import 'dart:html';
import 'dart:async';
import 'package:react/react_client.dart' as reactClient;
import 'package:react/react.dart';
import 'package:route_hierarchical/client.dart';
import 'package:models/models.dart';
import 'lib/page_series_detail.dart';
import 'lib/page_settings.dart';
import 'lib/page_series_list.dart';
import 'lib/page_add_series.dart';
import 'lib/page_upcoming_episodes.dart';
import 'lib/websocket_client.dart';
import 'lib/dbcomponents.dart';

class NavItem extends Component {
  void render() {
    print(this.props);
    return li({'className': this.props['active'] ? 'active' : ''},
    a({'href': this.props['href'], }, [
      span({'className': 'glyphicon glyphicon-' + this.props['icon']}),
      span({'className': 'nav-label'}, this.props['label'])
    ]));
  }
}

var navItem = registerComponent(() => new NavItem());

class App extends Component {

  Function currentPageComponent;
  WebSocketClient ws = new WebSocketClient("ws://${window.location.hostname}:8000/ws/");
  Map currentPageParams = {};

  void onNotify(WebSocketEvent event) {
    this.ref('growler').add(event.data);
    print("Notifying ${event.data}");
  }

  void componentWillMount() {
    ws.connectSocket();
    ws.subscribe(['notify'], this);
    ws.events.where((e) => e.type == 'notify').listen(onNotify);
    window.on['growl'].listen((e) => this.ref('growler').add(e.detail));
    var router = new Router(useFragment: true);
    router.root
      ..addRoute(
        name: 'upcoming',
        path: 'upcoming',
        defaultRoute: true,
        enter: enterRoute)
      ..addRoute(
        name: 'series-list',
        path: 'series-list',
        defaultRoute: false,
        enter: enterRoute)
      ..addRoute(
        name: 'add-series',
        path: 'add-series',
        defaultRoute: false,
        enter: enterRoute)
      ..addRoute(
        name: 'series-detail',
        path: 'series/:seriesId',
        defaultRoute: false,
        enter: enterRoute)
      ..addRoute(
        name: 'settings',
        path: 'settings',
        defaultRoute: false,
        enter: enterRoute);
    router.listen();
  }

  void enterRoute(RouteEnterEvent event) {
    print("route name ${event.route.name}");
    if (event.route.name == 'upcoming') {
      this.currentPageComponent = upcomingPage;
      this.currentPageParams = {};
    } else if (event.route.name == 'series-list') {
      this.currentPageComponent = seriesListPage;
      this.currentPageParams = {};
    } else if (event.route.name == 'add-series') {
      this.currentPageComponent = addSeriesPage;
      this.currentPageParams = {};
    } else if (event.route.name == 'series-detail') {
      this.currentPageComponent = seriesDetailPage;
      this.currentPageParams = event.parameters;
    } else if (event.route.name == 'settings') {
      this.currentPageComponent = settingsPage;
      this.currentPageParams = {};
    }
    this.setState({'currentRoute': event.route.name});

  }

  void componentDidMount(/*DOMElement*/rootNode) {}
  void componentWillReceiveProps(newProps) {}
  bool shouldComponentUpdate(nextProps, nextState) => true;
  void componentWillUpdate(nextProps, nextState) {}
  void componentDidUpdate(prevProps, prevState, /*DOMElement */ rootNode) {}
  void componentWillUnmount() {}

  void openTorrentForm(Map props) {
    setState({'modal': props});
  }

  Map get pageParams {
    Map defaults = {'ws': ws, 'growler': this.ref('growler'), 'openTorrentForm': openTorrentForm, 'config': state['config']};
    defaults.addAll(currentPageParams);
    return defaults;
  }

  onAddTorrent(Map torrentInfo) async {
    print("Sending addTorrent request");
    var resp = await ws.rpc("add_torrent", args: torrentInfo);
    setState({'modal': null});
    resp = resp['result'];
    if (resp.containsKey("torrent-duplicate")) {
      this.ref('growler').add({'message': 'Add Failed, duplicate torrent'});
    } else {
      this.ref('growler').add({'message': '${resp['torrent-added']['name']} successfully added.'});
    }
  }

  Map getInitialState() => {
    'currentRoute': '',
    'modal': null
  };

  Map getDefaultProps() => {};

  closeTorrentForm(SyntheticMouseEvent event) {
    setState({'modal': null});
  }

  render() => div({'className': 'app-main'}, [
    div({'id': 'sidebar-wrapper'}, [
      ul({'className': 'sidebar-nav'}, [
        li({'className': 'sidebar-brand'}, a({'href': '#'}, "DartBeard")),
        navItem({'icon': 'time',
                 'href': '#upcoming',
                 'label': 'Upcoming',
                 'active': this.state['currentRoute'] == 'upcoming'}),
        navItem({'icon': 'list-alt',
                 'href': '#series-list',
                 'label': "All Series",
                 'active': this.state['currentRoute'] == 'series-list'}),
        navItem({'icon': 'search',
                 'href': '#add-series',
                 'label': "Add Series",
                 'active': this.state['currentRoute'] == 'add-series'}),
        navItem({'icon': 'cog',
                 'href': '#settings',
                 'label': "Settings",
                 'active': this.state['currentRoute'] == 'settings'})
      ])
    ]),
    div({'id': 'page-content-wrapper'}, currentPageComponent == null ? "" : currentPageComponent(pageParams)),
    growlContainer({'key': 'growler', 'ref': "growler"}),
    torrentForm({'opened': state['modal'] != null, 'close': closeTorrentForm, 'torrentInfo': state['modal'], 'onSubmit': onAddTorrent})
  ]);
}

var app = registerComponent(() => new App());

main() {
  //this should be called once at the begging of application
  reactClient.setClientConfiguration();
  var component = app({}, "Hello world!");
  render(component, querySelector('body'));
}