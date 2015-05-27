import 'dart:html';
import 'dart:async';
import 'package:react/react_client.dart' as reactClient;
import 'package:react/react.dart';
import 'package:route_hierarchical/client.dart';
import 'package:models/models.dart';
import 'websocket_client.dart';
import 'page.dart';
import 'dbcomponents.dart';


class EpisodeRow extends Component {

  Episode get episode => this.props['episode'];

  shouldComponentUpdate(nextProps, nextState) {
    if (nextProps['episode'] != episode) {
      return true;
    } else if (nextProps['checked'] != props['checked']) {
      return true;
    }
    return false;
  }

  String get checkState => props['checked'] ? 'check' : 'unchecked';

  render() => tr({'className': 'episode-row' + (episode.number % 2 == 0 ? '' : ' odd') + (episode.libraryLocation == null ? '' : ' downloaded')}, [
    td({'className': 'number', 'data-episode-id':episode.id, 'onClick': props['onToggleChecked']}, [span({'className': 'glyphicon glyphicon-${checkState}'}), "${episode.number}."]),
    td({'className': 'name'}, episode.name),
    td({'className': 'firstAired'}, episode.firstAiredDate),
    td({'className': 'status'}, episode.status),
    td({'className': 'icon-cell'}, [
      a({'title':'Add Torrent','data-episode-id': episode.id, 'className': 'glyphicon glyphicon-paperclip', 'onClick': props['onAddTorrentClick']}),
      a({'title':'Search for Torrent','data-episode-id': episode.id, 'className': 'glyphicon glyphicon-search', 'onClick': props['onSearchTorrentClick']})
    ])
  ]);
}

var episodeRow = registerComponent(() => new EpisodeRow());


class SeasonContainer extends Component {

  toggle(event) {
    expanded = !expanded;
  }

  bool get expanded => this.state['expanded'];
  set expanded(val) {
    this.setState({'expanded': val});
  }

  getInitialState() => {'checkedEpisodes': new Set()};

  List<Episode> get episodes => this.props['episodes'];

  onInvertSelectionClick(SyntheticMouseEvent event) {
    print("Inverting Selection");
    Set checked = new Set.from(state['checkedEpisodes']);

    episodes.forEach((e) {
      if (checked.contains(e.id)) {
        checked.remove(e.id);
      } else {
        checked.add(e.id);
      }
    });
    setState({'checkedEpisodes': checked});
  }

  onToggleChecked(SyntheticMouseEvent event) {
    int episodeId = int.parse(event.currentTarget.dataset['episodeId']);
    print('onToggleChecked ${episodeId}');
    Set checked = state['checkedEpisodes'];
    checked = new Set.from(checked);
    if (checked.contains(episodeId)) {
      checked.remove(episodeId);
    } else {
      checked.add(episodeId);
    }
    setState({'checkedEpisodes': checked});
  }

  onSetStatusChange(SyntheticFormEvent event) async {
    if (event.currentTarget.value != '') {
      if (state['checkedEpisodes'].length > 0) {
        await props['ws'].rpc("set_episode_status", args: {'status': event.currentTarget.value, 'episodes': state['checkedEpisodes'].toList()});
      }
      event.currentTarget.value = '';
    }
  }

  render() {
    String label = props['seasonNumber'] == 0 ? "Specials" : "Season ${props['seasonNumber']}";
    String chevron = expanded ? 'down' : 'right';

    return div({'className': 'season-panel'}, [
      div({'className': 'season-panel-title-bar'}, [
        h2({'onClick': toggle, 'style': {'cursor': 'pointer'}}, [
          span({'className': 'glyphicon glyphicon-chevron-$chevron'}),
          label
        ]),
      ]),
      expanded ? div({'className': 'season-options'}, [
        div({'className': 'buttons-left'}, [
          button({'onClick': onInvertSelectionClick, 'title': 'Invert selection'}, span({'className': 'glyphicon glyphicon-check'})),
          select({'style': {'height': '26px'}, 'title': 'Change status of selected episodes', 'onChange': onSetStatusChange}, [
            option({'value': ''}, '-Change Status-'),
            option({'value': 'Wanted'}, 'Wanted'),
            option({'value': 'Ignored'}, 'Ignored'),
            option({'value': 'Downloaded'}, 'Downloaded'),
          ])
        ]),
        div({'className': 'buttons-right'}, [
          button({'data-season-number': props['seasonNumber'], 'onClick': props['onAddTorrentClick']}, [span({'className': 'glyphicon glyphicon-paperclip', 'title': 'Add Season Pack Torrent'})]),
          button({'data-season-number': props['seasonNumber'], 'onClick': props['onSearchTorrentClick']}, [span({'className': 'glyphicon glyphicon-search', 'title': 'Search for Torrents'})])
        ])
      ]) : null,
      table({'className': 'episode-list'}, expanded ? [
        thead({}, tr({}, [
          th({},"#"), th({}, "Name"), th({}, "Date"), th({}, "Status"), th({}, "")
        ])),
        tbody({}, episodes.map((e) => episodeRow({
          'episode': e,
          'onAddTorrentClick': props['onAddTorrentClick'],
          'onSearchTorrentClick': props['onSearchTorrentClick'],
          'onToggleChecked': onToggleChecked,
          'checked': state['checkedEpisodes'].contains(e.id)
        })))
      ] : null)
    ]);
  }
}
var seasonContainer = registerComponent(() => new SeasonContainer());


class SeriesDetailPage extends  Page {

  List<String> EVENTS = ['series::insert', 'series::update', 'series::delete', 'episode::insert', 'episode::update', 'episode::delete'];

  List<int> get seasons {
    List<int> result = [];
    for (int snum in this.state['series'].episodes.map((e) => e.seasonNumber)) {
      if (!result.contains(snum)) result.add(snum);
    }
    result.sort();
    return result.reversed.toList();
  }

  getInitialState() => {'series': new Series(), 'default_preferred_resolution': '', 'default_rename_pattern': '', };

  bool get formDirty {
    Series s = state['series'];
    return (
      s.renamePattern != state['renamePattern']
      || s.preferredResolution != state['preferredResolution']
      || s.ignore != state['ignore']
    );
  }

  onWebSocketEvent(WebSocketEvent event) {
    print(event.type);
    if (event.type == 'series::update' && event.data['id'] == state['series'].id) {
      state['series'].updateFromMap(event.data['fields']);
      setState(event.data['fields']);
      redraw();
    } else if (event.type == 'episode::delete') {
      print(event.data);
    } else if (event.type == 'episode::update') {
      Episode ep;
      try {
        ep = state['series'].episodes.where((e) => event.data['id'] == e.id).first;
      } catch (exception) {
        print(exception);
      }

      state['series'].episodes.remove(ep);
      ep = new Episode.fromMap(ep.toMap());
      ep.updateFromMap(event.data['fields']);
      state['series'].episodes = new List.from(state['series'].episodes);
      state['series'].episodes.add(ep);
      setState({'episodes': state['series'].toMap()['episodes']});
    } else if (event.type == 'episode::insert') {
      print(event.data);
    }
  }

  componentDidMount(rootNode) async {
    await super.componentDidMount(rootNode);
    Map config = await ws.rpc("get_config");
    config = config['result'];
    var result = await ws.rpc('get_series', args: {'id': int.parse(this.props['seriesId']), 'includeEpisodes': true});
    Series s = new Series.fromMap(result['result']);
    Map newState = {'series': s,'default_preferred_resolution': config['default_preferred_resolution'], 'default_rename_pattern': config['default_rename_pattern']};
    newState.addAll(s.toMap());
    setState(newState);
  }

  getSeasonEpisodes(int season) {
    List<Episode> eps = this.state['series'].episodes.where((e) => e.seasonNumber == season).toList();
    eps.sort((a, b) => a.number.compareTo(b.number));
    List result = eps.reversed.toList();
    //print("Getting season eps for s$season ${result}");
    return result;
  }

  onDeleteSeries(SyntheticMouseEvent event) {
    if (window.confirm("Are you sure?")) {
      ws.rpc('delete_series', args: {'id': this.state['series'].id});
      window.location.hash = 'series-list';
    }
  }

  onRefresh(SyntheticMouseEvent event) {
    ws.rpc('update_series', args: {'id': this.state['series'].id, 'scan': true});
  }

  onAddTorrentClick(SyntheticMouseEvent event) {
    event.preventDefault();
    print("torrentClick");
    var data = event.currentTarget.dataset;
    var args = {'seriesId': this.props['seriesId']};
    if (data.containsKey('episodeId')) {
      args['episodeId'] = data['episodeId'];
    }
    if (data.containsKey('seasonNumber')) {
      args['seasonNumber'] = data['seasonNumber'];
    }
    props['openTorrentForm'](args);
  }

  onSearchTorrentClick(SyntheticMouseEvent event) async {
    if (event.currentTarget.dataset.containsKey('episodeId')) {
      int epId = int.parse(event.currentTarget.dataset['episodeId']);
      var resp = await ws.rpc("search_torrent", args: {'episodeId': epId});
      List<Map> choices = resp['result'];
      if (choices.length > 0) {
        props['openTorrentForm']({'seriesId': this.props['seriesId'], 'episodeId': event.currentTarget.dataset['episodeId'], 'choices': choices});
      } else {
        var ep = new Episode.fromMap(state['episodes'].where((e) => e['id'] == epId).first);
        props['growler'].add({'message': "No results for ${state['name']} ${ep.seasonEpisode}"});
      }
    }  else if (event.currentTarget.dataset.containsKey('seasonNumber')) {

      int seriesId;
      if (props['seriesId'] is String) {
        seriesId = int.parse(props['seriesId']);
      } else {
        seriesId = props['seriesId'];
      }
      int seasonNumber = int.parse(event.currentTarget.dataset['seasonNumber']);
      var resp = await ws.rpc("search_torrent", args: {'seriesId': seriesId, 'seasonNumber': seasonNumber});
      List<Map> choices = resp['result'];
      if (choices.length > 0) {
        print(choices);
        props['openTorrentForm']({'seriesId': seriesId, 'seasonNumber': seasonNumber, 'choices': choices});
      } else {
        props['growler'].add({'message': 'No Results for ${state['name']} Season ${seasonNumber}'});
      }
    }
  }

  onUnlockClick(SyntheticMouseEvent event) async {
    var resp = await ws.rpc("unlock_series", args: {'id': state['series'].id});
    print(resp);
  }

  onChangePreferredResolution(SyntheticFormEvent event) {
    String value = event.currentTarget.value;
    print("Set state to $value");
    setState({'preferredResolution': value});
  }

  onChangeIgnore(SyntheticFormEvent event) {
    var value = event.currentTarget.checked;
    print("Set state to $value");
    setState({'ignore': value});
  }

  onChangeRenamePattern(SyntheticFormEvent event) {
    String value = event.currentTarget.value;
    if (value == '') {
      value = null;
    }
    print("Set state to $value");
    setState({'renamePattern': value});
  }

  onFocusRenamePattern(SyntheticFormEvent event) {
    setState({'renameFocused': true});
  }

  onBlurRenamePattern(SyntheticFormEvent event) {
    setState({'renameFocused': false});
  }

  onBackfillSeries(SyntheticMouseEvent event) async {
    ws.rpc("backfill_series", args: {'id': state['series'].id});
  }

  onSaveChangesClick(SyntheticMouseEvent event) {
    event.preventDefault();
    event.currentTarget.disabled = true;
    Series s = state['series'];
    Map settings = {'id': s.id};
    if (state['renamePattern'] != s.renamePattern) {
      settings['renamePattern'] = state['renamePattern'];
    }
    if (state['preferredResolution'] != s.preferredResolution) {
      settings['preferredResolution'] = state['preferredResolution'];
    }
    if (state['ignore'] != s.ignore) {
      settings['ignore'] = state['ignore'];
    }

    ws.rpc("save_series_settings", args: settings);

  }

  renderExampleRename() {
    Map data = {'seasonNumber': 1, 'series': state['name'], 'number': 1, 'name': 'Episode Title', 'extension': 'mkv'};
    var pattern = state['renamePattern'] == null ? state['default_rename_pattern'] : state['renamePattern'];
    var rendered;
    try {
      rendered = "Ex: " + renderRename(pattern, data);
    } catch (exception) {
      rendered = exception.toString();
    }

    return rendered;

  }

  renderDlEntry(key, value) {
    return dl({}, [dt({}, key), dd({}, value)]);
  }

  renderRenameHelp() {
    return div({'className': 'rename-help'}, [
      h4({}, 'Variables'),
      dl({'className': 'inline'}, [
        dt({}, "series"), dd({}, "Series Name"),
        dt({}, "name"), dd({}, "Episode Name"),
        dt({}, "seasonNumber"), dd({}, "Season Number"),
        dt({}, "number"), dd({}, "Episode Number"),
        dt({}, "extension"), dd({}, "File Extension"),
      ]),
      h4({}, 'Filters'),
      dl({'className': 'inline'}, [
        dt({}, "zero"), dd({}, "Zero-Pad(width=2)"),
        dt({}, "dotspace"), dd({}, "Replace spaces with .'s"),
        dt({}, "title"), dd({}, "'Title Case'"),
        dt({}, "lower"), dd({}, "'lower case'"),
        dt({}, "upper"), dd({}, "'UPPER CASE'"),

      ])
    ]);
  }

  render() {
    Series s = this.state['series'];
    return div({'className': ''}, [
      state['renameFocused'] ? renderRenameHelp() : null,
      getHeader(s.name, null),
      div({'className': 'scroll-pane', 'key': 'scroll-pane'}, new List.from([
        div({'className': 'series-detail-header'}, [
          div({'className': 'series-detail-poster-wrap'}, img({'className': 'poster', 'src': (s.poster == null ? null : '/imgcache/thetvdb.com/banners/' + s.poster)})),
          div({'className': 'series-detail-header-content'}, [
            table({'className': 'series-detail'}, [
              tbody({},[
                tr({},[th({},"Status: "), td({}, state['status']), th({},"Network: "), td({}, state['network'])]),
                tr({},[th({},"Rating: "), td({}, state['contentRating']), th({},"Airing: "), td({}, s.airsAtString)]),
                tr({},[th({},"Run Time: "), td({}, state['runTime'] != null ? "${state['runTime']}m" : ""), th({},""), td({}, "")]),
              ])
            ]),
            hr({}),
            form({}, table({'className': 'series-settings'}, [
              tr({}, [
                th({}, "Preferred Resolution: "),
                td({}, select({'value': state['preferredResolution'], 'onChange': onChangePreferredResolution}, [
                  option({'value': ''}, 'default (${state['default_preferred_resolution']})'),
                  option({'value': 'SD'}, 'SD'),
                  option({'value': '720p'}, '720p'),
                  option({'value': '1080p'}, '1080p')
                ])),
                th({}, "Ignore New Torrents:"),
                td({}, input({'type': 'checkbox', 'checked': state['ignore'], 'onChange': onChangeIgnore}))
              ]),

              tr({}, [
                th({}, "Rename Pattern: "),
                td({'colSpan': 3, 'style': {'width': '100%'}}, input({
                  'type': 'text',
                  'placeholder':'${state['default_rename_pattern']}',
                  'value': state['renamePattern'] == null ? '' : state['renamePattern'],
                  'onChange': onChangeRenamePattern,
                  'onFocus': onFocusRenamePattern,
                  'onBlur': onBlurRenamePattern
                }))
              ]),

              tr({},state['renameFocused'] ? td({'colSpan': 4}, renderExampleRename()) : td({'colSpan': 4}, '\u00a0')),
              tr({}, td({'colSpan': 4, 'style': {'textAlign': 'right'}}, formDirty ? button({'onClick': onSaveChangesClick}, 'Save Changes') : ''))

            ])),
            div({'className': 'button-bar'}, [
              button({'onClick': onBackfillSeries, 'title': 'Backfill Series'}, span({'className': 'glyphicon glyphicon-import'})),
              button({'onClick': onDeleteSeries, 'title': 'Delete Series'}, span({'className': 'glyphicon glyphicon-trash'})),
              button({'onClick': onRefresh, 'title': 'Update Series'}, span({'className': 'glyphicon glyphicon-refresh'}))
            ])
          ]),
          div({'className': 'lock-indicator', 'title': "Series is updating"}, state['updating'] ? span({'className': 'glyphicon glyphicon-lock', 'onClick':onUnlockClick}) : ""),
        ])
      ])..addAll(seasons.map((int snum) => seasonContainer({
        'ws': ws,
        'key': 's$snum',
        'seasonNumber': snum,
        'episodes': getSeasonEpisodes(snum),
        'onAddTorrentClick': onAddTorrentClick,
        'onSearchTorrentClick': onSearchTorrentClick})).toList()))
    ]);
  }
}
var seriesDetailPage = registerComponent(() => new SeriesDetailPage());
