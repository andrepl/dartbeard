import 'dart:html';
import 'dart:async';
import 'package:react/react_client.dart' as reactClient;
import 'package:react/react.dart';

class IconButton extends Component {
  render() => button(this.props, span({'className': 'glyphicon glyphicon-${this.props['icon']}'}));
}
var iconButton = registerComponent(() => new IconButton());

class GrowlItem extends Component {
  getDefaultProps() => {'message': '', 'removeAt': (new DateTime.now()).millisecondsSinceEpoch};

  render() => div({'className': 'growl'}, this.props['message']);
}
var growlItem = registerComponent(() => new GrowlItem());

class TorrentForm extends Component {

  renderForm() {
    Map torrentInfo = props['torrentInfo'];
    if (torrentInfo.containsKey('choices')) {

      var header = [tr({}, [
        th({}, ''),
        th({}, 'Details'),
        th({}, span({'className': 'glyphicon glyphicon-upload'})),
        th({}, span({'className': 'glyphicon glyphicon-download'}))
      ])];
      if (torrentInfo['choices'].length > 0) {
        torrentInfo['choices'][0]['default'] = true;
      }
      List trows = [header];
      trows.addAll(torrentInfo['choices'].map((choice) => tr({'title': choice['ReleaseName']}, [
        td({},input({
          'defaultChecked': choice['default'] == true,
          'type': 'radio',
          'name': 'url',
          'value': choice['DownloadURL']
        })),
        td({}, "${choice['Container']} / ${choice['Codec']} / ${choice['Source']} / ${choice['Resolution']} / ${choice['Origin']}"),
        td({}, "${choice['Seeders']}"),
        td({}, "${choice['Leechers']}")
      ])));
      trows.add(tr({}, td({'style': {'text-align': 'right'}, 'colSpan': 4}, button({'type': 'submit'}, 'Add Torrent'))));
      return table({'className': 'torrent-choices'}, trows);
    } else {
      return table({}, [
        tr({}, [
          th({}, "URL:"),
          td({}, input({'className': 'torrent-url', 'type': 'text'})),
          td({'rowSpan': 2}, button({'type': 'submit'}, "Add Torrent"))
        ]),
        tr({}, [
          th({}, "File:"),
          td({}, input({'type': 'file'}))
        ])
      ]);

    }
  }

  renderWindow() => div({'className': 'modal-window'}, [
    div({'className': 'modal-titlebar'}, [
      h4({'className': 'title'}, "Add Torrent"),
      button({'className': 'close-modal', 'onClick': props['close']},
        span({'className': 'glyphicon glyphicon-remove'}, ""))
    ]),
    div({'className': 'modal-body'}, [
      form({'onSubmit': onFormSubmit}, renderForm())
    ])
  ]);

  onFormSubmit(SyntheticFormEvent event) {
    event.preventDefault();

    print("Type: ${event.type}");
    print("currentTarget: ${event.currentTarget}");

    var fileInput = querySelector("input[type='file']");
    var urlInput = querySelector("input.torrent-url[type='text']");

    File file = null;
    Map torrentInfo = new Map.from(props['torrentInfo']);
    if (urlInput == null) {
      torrentInfo['url'] = querySelector("input:checked[name='url']").value;
      props['onSubmit'](torrentInfo);
    } else {
      if (urlInput.value != null && urlInput.value.length > 0) {
        torrentInfo['url'] = urlInput.value;
      }
      if (fileInput.files.length > 0) {
        FileReader reader = new FileReader();
        file = fileInput.files[0];
        reader.onLoadEnd.listen((Event e) {
          torrentInfo['url'] = reader.result;
          print("Submitting from file");
          props['onSubmit'](torrentInfo);
        });
        reader.readAsDataUrl(file);
      } else {
        print("Submitting without file");
        props['onSubmit'](torrentInfo);
      }
    }
  }

  render() {
    return div({'className': 'modal-backdrop' + (props['opened'] ? ' opened' : '')}, props['opened'] ? renderWindow() : null);
  }

}
var torrentForm = registerComponent(() => new TorrentForm());

class GrowlContainer extends Component {

  getInitialState() => {'items': []};
  Timer timer = null;

  componentDidMount(rootNode) {
    timer = new Timer.periodic(new Duration(milliseconds: 10), tick);
  }

  int msgId = 0;

  void tick(_) {
    List items = this.state['items'];
    DateTime now = new DateTime.now();
    items.removeWhere((e) => e['removeAt'] <= now.millisecondsSinceEpoch);
    setState({'items': items});
  }

  getMessage(id) {
    return state['items'].firstWhere((i) => i['key'] == 'growl-$id', orElse: () => null);
  }

  updateMessage(id, newMsg) {
    Map msg = getMessage(id);
    if (msg != null) {
      msg.addAll(newMsg);
    }
    setState({'items': state['items']});
  }

  removeMessage(id) {
    Map msg = getMessage(id);
    msg['removeAt'] = new DateTime.now().millisecondsSinceEpoch -1;
    setState({'items': state['items']});
  }

  add(Map msg, {int duration: 4000}) {
    List<Map> items = this.state['items'];
    msg['removeAt'] = (new DateTime.now()).millisecondsSinceEpoch + duration;
    msg['key'] = 'growl-${msgId++}';
    items.add(msg);
    setState({'items': items});
    return msgId;
  }

  render() => div({'className': 'growl-container'}, this.state['items'].map((e) => growlItem(e)));
}

var growlContainer = registerComponent(() => new GrowlContainer());
