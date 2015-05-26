import 'dart:html';
import 'dart:async';
import 'package:react/react_client.dart' as reactClient;
import 'package:react/react.dart';
import 'package:route_hierarchical/client.dart';
import 'package:models/models.dart';
import 'websocket_client.dart';
import 'page.dart';

class SettingsPage extends Page {

  List<Map> fieldOptions = [
    {'setting': 'library_root', 'group': 'General', 'type': 'text', 'label': "Library Root", 'help': 'The full path to the directory containing your TV shows. (ie. /media/media/TV)'},
    {'setting': 'username', 'group': 'General', 'type': 'text', 'label': "Username", 'help': 'blank = no authentication'},
    {'setting': 'password', 'group': 'General', 'type': 'password', 'label': "Password", 'help': ''},
    {'setting': 'transmission_host', 'group': 'Transmission', 'type': 'text', 'label': 'host/IP', 'help': ''},
    {'setting': 'transmission_port', 'group': 'Transmission', 'type': 'number', 'label': 'port', 'help': ''},
    {'setting': 'tvdb_api_key', 'group': "API Keys", 'type': 'text', 'label': 'TVDB', 'help': ''},
    {'setting': 'btn_api_key', 'group': "API Keys", 'type': 'text', 'label': 'BTN', 'help': ''},
    {'setting': 'plex_host', 'group': 'Plex', 'type': 'text', 'label': 'Host/IP'},
    {'setting': 'plex_port', 'group': 'Plex', 'type': 'text', 'label': 'Port'},
  ];

  List<String> EVENTS = [];

  getInitialState() => {'settings': {}, 'original': {}, 'validation': {}};

  void onWebSocketEvent(WebSocketEvent event) async {
    print("Received websocket event ${event.type}: ${event.data}");
  }

  validateSetting(k, v) {
    print("Validating $k=$v");
    ws.rpc('validate_setting', args: {'setting': k, 'value': v}).then((resp) {
      state['validation'][k] = resp['result'];
      setState({'validation': state['validation']});
    });
  }

  componentDidMount(rootNode) async {
    await super.componentDidMount(rootNode);
    var result = await ws.rpc('get_config');
    print(result);
    this.setState({
      'settings': result['result'],
      'original': new Map.from(result['result']),
      'validation': {}
    });

    result['result'].forEach(validateSetting);
    print("setResult");
    redraw();
  }

  onSettingChanged(SyntheticFormEvent event) {
    var k = event.currentTarget.name;
    var v = event.currentTarget.value;
    state['settings'][k] = v;
    state['validation'][k] = null;
    setState({'settings': state['settings'], 'validation': state['validation']});
    ws.rpc('validate_setting', args: {'setting': k, 'value': v}).then((resp) {
      state['validation'][k] = resp['result'];
      setState({'validation': state['validation']});
    });
  }

  renderRows() {
    List rows = [];
    String lastCat = null;
    String validationState;
    for (Map field in fieldOptions) {
      if (field['group'] != lastCat) {
        lastCat = field['group'];
        rows.add(tr({'colSpan': 3}, th({}, h2({}, field['group']))));
      }
      if (state['validation'][field['setting']] == null) {
        validationState = 'pending';
      } else if (state['validation'][field['setting']]['valid']) {
        validationState = 'valid';
      } else {
        validationState = 'invalid';
      }
      rows.add(tr({}, [
        th({}, field['label']),
        td({}, input({
          'type': field['type'],
          'name': field['setting'],
          'value': state['settings'][field['setting']],
          'onChange': this.onSettingChanged,
          'className': validationState,
        })),
        td({}, validationState == 'invalid' ? state['validation'][field['setting']]['error'] : field['help'])
      ]));
    }
    return rows;
  }

  onSubmit(SyntheticFormEvent event) {
    event.preventDefault();
    ws.rpc("save_config", args: state['settings']);
  }

  render() {
    print("render");
    return div({'className': ''}, [
      getHeader("Settings", []),
      div({'className': 'scroll-pane', 'key': 'scroll-pane'},
        form({'onSubmit': onSubmit},
          table({},
            renderRows()..addAll([
              tr({}, td({'colSpan': 3, 'type': 'submit'}, button({}, "Save Changes")))
            ])
          )
        )
      ),
    ]);
  }
}

var settingsPage = registerComponent(() => new SettingsPage());
