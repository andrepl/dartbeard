import 'package:shelf/shelf_io.dart' as io;
import 'package:dartbeard/src/dartbeard.dart';
import 'package:logging_handlers/logging_handlers_shared.dart';
import 'package:logging/logging.dart';


main(List<String> arguments) async {
  var printHandler = new LogPrintHandler();
  Logger.root.level = Level.FINEST;
  Logger.root.onRecord.listen(printHandler);
  AppServer app = new AppServer();
  io.serve(app.handler, '0.0.0.0', 8000);
}


