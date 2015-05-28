import 'dart:html';
import 'dart:async';
import 'package:intl/intl.dart';
import 'package:react/react_client.dart' as reactClient;
import 'package:react/react.dart';
import 'package:route_hierarchical/client.dart';
import 'package:models/models.dart';
import 'websocket_client.dart';
import 'page.dart';


class UpcomingItem extends Component {
  render() {
    Episode e = this.props['episode'];
    return div({'className': 'list-item'}, [
      a({'href': '#series/${e.seriesId}'}, img({'className': 'banner', 'src': (e.series.banner == null ? null : '/imgcache/thetvdb.com/banners/' + e.series.banner)})),
      div({'className': 'series-detail'}, [
        div({}, [label({}, '${e.formatFirstAired('jm')}:'), span({}, '${e.seasonEpisode} - ${e.name}')]),
      ])
    ]);
  }
}
var upcomingItem = registerComponent(() => new UpcomingItem());


class UpcomingPage extends Page {

  List<String> EVENTS = ['series::insert', 'series::update', 'series::delete', 'episode::insert', 'episode::update', 'episode::delete'];

  episodeMatch(Episode ep) {
    String ss = this.state['searchString'].toLowerCase();
    return ep.name.toLowerCase().contains(ss)
    || ep.overview.toLowerCase().contains(ss)
    || ep.series.name.toLowerCase().contains(ss);
  }

  List withHeaders() {
    List result = [];
    String lastDate = null;
    Map relativeHeaders = {
      new DateFormat("yyyyMMdd").format(new DateTime.now().subtract(new Duration(days:1))): 'Yesterday',
      new DateFormat("yyyyMMdd").format(new DateTime.now()): 'Today',
      new DateFormat("yyyyMMdd").format(new DateTime.now().add(new Duration(days:1))): 'Tomorrow'
    };

    for (Episode e in this.state['episodeList']) {
      if (!episodeMatch(e)) continue;
      if (lastDate == null || lastDate != e.firstAiredDate) {
        String dateStr = e.formatFirstAired('EEEE, MMM d');
        var epDate = e.formatFirstAired('yyyyMMdd');
        if (relativeHeaders.containsKey(epDate)) {
          dateStr += ' [${relativeHeaders[epDate]}]';
        }
        result.add(div({'className': 'date-header'}, dateStr));
        lastDate = e.firstAiredDate;
      }
      result.add(upcomingItem({'episode': e, 'key': e.id}));
    }
    return result;
  }

  componentDidMount(rootNode) async {
    await super.componentDidMount(rootNode);
    var result = await ws.rpc('get_upcoming_episodes');
    List<Episode> sl = result['result'].map((m) => new Episode.fromMap(m)).toList();
    this.setState({'episodeList': sl});
  }

  void onSearchChange(SyntheticFormEvent event) {
    this.setState({'searchString': event.currentTarget.value});
  }

  getInitialState() => {'episodeList': [], 'searchString': ''};

  render() => div({'className': ''}, [
    getHeader("Upcoming Episodes", div({}, input({'type': 'text', 'placeholder': 'Search', 'onChange': onSearchChange}))),
    div({'className': 'scroll-pane', 'key': 'scroll-pane'}, withHeaders())
  ]);
}
var upcomingPage = registerComponent(() => new UpcomingPage());
