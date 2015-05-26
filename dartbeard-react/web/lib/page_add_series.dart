import 'dart:html';
import 'dart:async';
import 'package:react/react_client.dart' as reactClient;
import 'package:react/react.dart';
import 'package:route_hierarchical/client.dart';
import 'package:models/models.dart';
import 'websocket_client.dart';
import 'page.dart';
import 'dbcomponents.dart';



class AddSeriesPage extends  Page {

  List<String> EVENTS = ['series::update'];
  Timer searchTimer = null;

  getInitialState() => {'availableDirectories': [], 'searchResults': [], 'searchString': '', 'selectedDirectory': null};

  componentDidMount(rootNode) async {
    await super.componentDidMount(rootNode);
    await loadAvailableDirs();
  }

  loadAvailableDirs() async {
    var result = await ws.rpc('get_unused_series_directories');
    if (result['result'].length > 0) {
      result['result'].insert(0, "");
    }
    this.setState({'availableDirectories': result['result'] == null ? [] : result['result']});
  }

  render() {
    List formContents = [
      label({}, "Series Search: "),
      input({'onChange': onSearchStringChange, 'value': state['searchString']}),
    ];
    var available = state['availableDirectories'];
    if (available.length > 0) {
      print("AVAIL DIRS: ${available.length} $available");
      formContents.insert(0, select({'onChange': onDirectoryChange, 'value': state['selectedDirectory']}, state['availableDirectories'].map((d) => option({'value': d}, d))));
      formContents.insert(0, label({}, "Existing Directory: "));
    }

    return div({'className': ''}, [
      getHeader("Add New Series", null),
      div({'className': 'scroll-pane', 'key': 'scroll-pane'}, new List.from([
        form({'className': 'add-series-form'}, formContents)
      ])..addAll(renderResults()))
    ]);
  }

  doSearch() async {
    var result = await ws.rpc("new_series_search", args: {"seriesName": state['searchString']});
    setState({'searchResults': result['result'].map((m) => new Series.fromMap(m))});
  }

  triggerSearch(int delay) {
    if (searchTimer != null) {
      searchTimer.cancel();
    }
    searchTimer = new Timer(new Duration(milliseconds: delay), () {
      doSearch();
    });
  }

  onDirectoryChange(SyntheticFormEvent event) {
    this.setState({'selectedDirectory': event.currentTarget.value, 'searchString': event.currentTarget.value});
    triggerSearch(100);
  }

  onSearchStringChange(SyntheticFormEvent event) {
    this.setState({'searchString': event.currentTarget.value});
    triggerSearch(1000);
  }

  onClickAdd(SyntheticFormEvent event) async {
    int seriesId = int.parse(event.currentTarget.dataset['seriesId']);
    await ws.rpc("update_series", args: {'id': seriesId, 'libraryLocation': state['selectedDirectory']});
    setState({'searchResults': [], 'searchString': '', 'selectedDirectory': null, 'availableDirectories': []});
    loadAvailableDirs();
  }

  renderResults() {
    return state['searchResults'].map((s) => div({'className': 'list-item' + (s.inLibrary ? ' in-library' : '')}, [
      s.banner == null ? h1({}, s.name) : img({'className': 'banner', 'src': '//thetvdb.com/banners/' + s.banner}),
      div({'className': 'series-detail'}, [
        div({}, [label({}, 'Network:'), span({}, s.network)]),
        div({}, [label({}, 'First Aired:'), span({}, s.firstAiredDate)]),
      ]),
      blockquote({}, s.overview),
      div({'className': 'button-bar'}, [
        button({
          'data-series-id': s.id,
          'disabled': s.inLibrary, 'onClick': onClickAdd
        }, [
          span({'className': 'glyphicon glyphicon-plus'}),
          s.inLibrary ? "Already in Library" : "Add This Series"
        ])
      ])
    ]));
  }

  onWebSocketEvent(WebSocketEvent event) {
    print("WebSocketEvent");
    if (event.type == 'series::update') {
      print("loadingDirs");
      loadAvailableDirs();
    }
  }
}

var addSeriesPage = registerComponent(() => new AddSeriesPage());
