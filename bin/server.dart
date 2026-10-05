/// DartScore server entry point.
///
/// Serves the static tablet UI from `web/` and the JSON API under `/api/`.
/// Binds to 0.0.0.0 so any device on the LAN (your tablet) can reach it.
library;

import 'dart:io';

import 'package:dartscore/src/api.dart';
import 'package:dartscore/src/engine.dart';
import 'package:dartscore/src/smart_home.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';
import 'package:shelf_static/shelf_static.dart';

Future<void> main(List<String> args) async {
  final port = int.tryParse(Platform.environment['PORT'] ?? '') ?? 8080;
  // Minutes of no scoring/undo/config activity after which the current game
  // is discarded and all clients fall back to the config screen.
  final idleMin =
      double.tryParse(Platform.environment['IDLE_TIMEOUT_MIN'] ?? '') ?? 30;

  // Wire smart-home integration here later, e.g.:
  //   final smartHome = HomeAssistantSmartHome();
  final engine = Engine(smartHome: NoopSmartHome());

  // web/ lives next to the parent of bin/, resolved from the script location
  // so it works both with `dart run` and a compiled exe in the repo.
  final scriptDir = File.fromUri(Platform.script).parent.parent.path;
  final webRoot = '$scriptDir/web';

  final api = buildApiRouter(engine,
      idleTimeout: Duration(seconds: (idleMin * 60).round()));
  final staticHandler =
      createStaticHandler(webRoot, defaultDocument: 'index.html');

  final root = Router()
    ..mount('/api/', api.call)
    ..all('/<ignored|.*>', (Request request) async {
      if (request.method == 'GET' || request.method == 'HEAD') {
        final response = await staticHandler(request);
        if (response.statusCode != 404) return response;
      }
      return staticHandler(request);
    });

  final handler =
      const Pipeline().addMiddleware(logRequests()).addHandler(root.call);

  final server = await shelf_io.serve(handler, InternetAddress.anyIPv4, port);
  final addresses = await NetworkInterface.list(
      type: InternetAddressType.IPv4, includeLoopback: false);
  stdout.writeln('DartScore listening on port ${server.port}');
  for (final iface in addresses) {
    for (final addr in iface.addresses) {
      stdout.writeln('  tablet: http://${addr.address}:${server.port}');
    }
  }
}
