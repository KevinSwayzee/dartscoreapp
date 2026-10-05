/// REST API: thin JSON wrappers around the pure [Engine].
library;

import 'dart:async';
import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import 'engine.dart';
import 'models.dart';

Response _json(Object? body, {int status = 200}) => Response(
      status,
      body: jsonEncode(body),
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

Response _error(String message, int status) =>
    _json({'error': message}, status: status);

Future<Map<String, dynamic>?> _readJson(Request request) async {
  final text = await request.readAsString();
  if (text.trim().isEmpty) return {};
  final parsed = jsonDecode(text);
  return parsed is Map<String, dynamic> ? parsed : null;
}

Router buildApiRouter(Engine engine,
    {Duration idleTimeout = const Duration(minutes: 30)}) {
  final router = Router();

  // Abandon the game when nobody touched it for [idleTimeout]; the tablets'
  // next poll sees hasGame:false and falls back to the config screen.
  // Only POSTs count as activity — GET /state polling must NOT keep a stale
  // game alive, or the timeout could never fire.
  Timer? idleTimer;
  void touch() {
    idleTimer?.cancel();
    idleTimer = Timer(idleTimeout, () {
      if (engine.hasGame) engine.clear();
    });
  }

  touch(); // no game yet → a firing clear() would be a no-op anyway

  router.get('/state', (Request request) {
    return _json(engine.toJson());
  });

  router.post('/game', (Request request) async {
    touch();
    Map<String, dynamic>? body;
    try {
      body = await _readJson(request);
    } catch (_) {
      return _error('invalid JSON body', 400);
    }
    if (body == null) return _error('body must be a JSON object', 400);

    final startScore = body['startScore'];
    final bestOf = body['bestOf'];
    final players = body['players'];
    if (startScore != 301 && startScore != 501) {
      return _error('startScore must be 301 or 501', 400);
    }
    if (bestOf != 3 && bestOf != 5) {
      return _error('bestOf must be 3 or 5', 400);
    }
    if (players is! List ||
        players.isEmpty ||
        players.length > 4 ||
        players.any((p) => p is! String || p.trim().isEmpty)) {
      return _error('players must be 1..4 non-empty names', 400);
    }

    try {
      engine.newMatch(
        MatchConfig(
          startScore: startScore,
          bestOf: bestOf,
          names: players
              .map<String>((p) => (p as String).trim())
              .toList(growable: false),
          doubleOut: body['doubleOut'] != false, // default: on
        ),
        keepStats: body['continueStats'] == true,
      );
    } on ArgumentError catch (e) {
      return _error('${e.message}', 400);
    }
    return _json(engine.toJson());
  });

  router.post('/dart', (Request request) async {
    touch();
    Map<String, dynamic>? body;
    try {
      body = await _readJson(request);
    } catch (_) {
      return _error('invalid JSON body', 400);
    }
    if (body == null) return _error('body must be a JSON object', 400);

    final points = body['points'];
    final doubleFlag = body['double'] == true;
    if (points is! int) return _error('points must be an integer', 400);

    try {
      engine.applyDart(points, doubleFlag: doubleFlag);
    } on StateError catch (e) {
      return _error(e.message, 409);
    } on ArgumentError catch (e) {
      return _error('${e.message}', 400);
    }
    return _json(engine.toJson());
  });

  router.post('/undo', (Request request) {
    touch();
    try {
      engine.undo();
    } on StateError catch (e) {
      return _error(e.message, 409);
    }
    return _json(engine.toJson());
  });

  router.post('/reset', (Request request) {
    touch();
    try {
      engine.reset();
    } on StateError catch (e) {
      return _error(e.message, 409);
    }
    return _json(engine.toJson());
  });

  return router;
}
