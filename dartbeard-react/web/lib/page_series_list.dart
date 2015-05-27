import 'dart:html';
import 'dart:async';
import 'package:react/react_client.dart' as reactClient;
import 'package:react/react.dart';
import 'package:route_hierarchical/client.dart';
import 'package:models/models.dart';
import 'websocket_client.dart';
import 'page.dart';

class SeriesProgress extends Component {
  get percentage => (this.props['value'] / this.props['maxvalue']) * 100.0;

  render() => div({'className': 'series-progress'}, [
    div({'className': 'progress-outer'}, div({'className': 'progress-inner', 'style': {'width': '${percentage}%'}})),
    div({'className': 'progress-label'}, "${this.props['value']}/${this.props['maxvalue']}")
  ]);
}
var seriesProgress = registerComponent(() => new SeriesProgress());

class SeriesItem extends Component {
  render() {
    Series s = this.props['series'];
    return div({'className': 'list-item'}, [
      a({'href': '#series/${s.id}'}, img({'className': 'banner', 'src': (s.banner == null ? null : '/imgcache/thetvdb.com/banners/' + s.banner)})),
      seriesProgress({'value': s.downloadedEpisodes, 'maxvalue': s.knownEpisodes}),
      div({'className': 'series-detail'}, [
        div({}, [label({}, 'Status:'), span({}, s.status)]),
        div({}, [label({}, 'Network:'), span({}, s.network)]),
        div({}, [label({}, 'Rating:'), span({}, s.contentRating)]),
        div({}, [label({}, 'First Aired:'), span({}, s.firstAiredDate)]),
      ]),
      div({'className': 'button-bar'}, [
        button({'disabled': s.updating, 'onClick': this.props['onClickRefresh']}, [span({'className': 'glyphicon glyphicon-refresh'})])
      ])
    ]);
  }
}
var seriesItem = registerComponent(() => new SeriesItem());


class SeriesListPage extends Page {

  List<String> EVENTS = ['series::insert', 'series::update', 'series::delete'];

  getInitialState() => {'seriesList': [], 'searchString': '', 'sortBy': 'sortableName'};

  void onWebSocketEvent(WebSocketEvent event) async {
    print("${event.type} => ${event.data}");
    if (event.type == 'series::update') {
      this.state['seriesList'].singleWhere((s) => s.id == event.data['id']).updateFromMap(event.data['fields']);
      this.redraw();
    } else if (event.type == 'series::insert') {
      print(event.data);
      Map data = (await ws.rpc("get_series", args: event.data))['result'];
      Series s = new Series.fromMap(data);
      var where = this.state['seriesList'].where((s) => s.id == event.data['id']);
      if (where.length > 0) {
        print("Trying to add when already exists!");
      } else {
        this.state['seriesList'].add(s);
        this.state['seriesList'].sort((a,b) => a.toMap()[this.state['sortBy']].compareTo(b.toMap()[this.state['sortBy']]));
      }
      this.redraw();
    } else if (event.type == 'series::delete') {
      this.state['seriesList'].removeWhere((s) => s.id == event.data['id']);
      this.redraw();
    }
    print("Received websocket event ${event.type}: ${event.data}");
  }

  componentDidMount(rootNode) async {
    await super.componentDidMount(rootNode);
    var result = await ws.rpc('get_all_series');
    List<Series> sl = result['result'].map((m) => new Series.fromMap(m)).toList();
    sl.sort((a,b) => a.toMap()[this.state['sortBy']].compareTo(b.toMap()[this.state['sortBy']]));
    this.setState({'seriesList': sl});
  }

  void onSearchChange(SyntheticFormEvent event) {
    this.setState({'searchString': event.currentTarget.value});
  }

  void onSortChange(SyntheticFormEvent event) {
    this.setState({'sortBy': event.currentTarget.value});
    print(event.currentTarget.value);
    this.state['seriesList'].sort((a,b) => a.toMap()[event.currentTarget.value].compareTo(b.toMap()[event.currentTarget.value]));
  }

  void onClickRefresh(id, SyntheticMouseEvent event) {
    print(event.currentTarget);
    print(id);
    ws.rpc("update_series", args: {'id': id, 'scan': true}).then((resp) {
      Series series = this.state['seriesList'].singleWhere((s) => s.id == id);
      print("updated");
    });
  }

  render() => div({'className': ''}, [
    getHeader("All Series", [
      div({}, input({'type': 'text', 'placeholder': 'Search', 'onChange': onSearchChange})),
      div({}, select({'placeholder': 'Sort By', 'onChange': onSortChange}, [
        option({'value': 'sortableName'}, 'Name'),
        option({'value': 'firstAired'}, 'First Aired'),
      ]))
    ]),
    div({'className': 'scroll-pane', 'key': 'scroll-pane'},
    this.state['seriesList']
      .where((s) => s.name.toLowerCase().contains(this.state['searchString'].toLowerCase()))
      .map((s) => seriesItem({'series': s, 'key': s.id, 'onClickRefresh': (e) => this.onClickRefresh(s.id, e) }))),
  ]);
}

var seriesListPage = registerComponent(() => new SeriesListPage());
