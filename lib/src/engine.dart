/// Game engine: the full match state is derived by replaying the dart
/// history against the match config. Undo simply pops the last dart and
/// replays again — so undo is always consistent, even across busts, set
/// boundaries or an un-won match.
library;

import 'models.dart';
import 'smart_home.dart';

/// Derived snapshot of a match after replaying (a prefix of) the history.
class Snapshot {
  final List<int> scores;
  final List<int> setsWon;
  final int currentPlayer;
  final int currentSet; // 0-based
  final List<Visit> visits;
  final List<LogEntry> log;
  final List<int> dartsThrown;
  final List<int> pointsScored;
  final List<int> checkouts;
  final List<int> checkoutAttempts;
  final bool matchOver;
  final int? matchWinner;

  // Open (unfinished) visit, if the current player has thrown 1-2 darts.
  final int? openVisitPlayer;
  final int? openVisitStart;
  final List<DartThrow> openVisitDarts;

  const Snapshot({
    required this.scores,
    required this.setsWon,
    required this.currentPlayer,
    required this.currentSet,
    required this.visits,
    required this.log,
    required this.dartsThrown,
    required this.pointsScored,
    required this.checkouts,
    required this.checkoutAttempts,
    required this.matchOver,
    required this.matchWinner,
    required this.openVisitPlayer,
    required this.openVisitStart,
    required this.openVisitDarts,
  });
}

class ReplayResult {
  final Snapshot snapshot;
  final List<GameEvent> events;

  const ReplayResult(this.snapshot, this.events);
}

/// Scores finishable with ONE dart when no double is required: any board-
/// valid value 1..60 (singles, doubles, triples, bull). Used to count
/// checkout attempts in single-out games.
bool _singleOutFinishable(int score) =>
    score >= 1 && score <= 60 && DartThrow.isValidThrow(score);

/// Pure replay — no side effects. Events are collected, not emitted.
ReplayResult replay(MatchConfig config, List<DartThrow> history) {
  final n = config.names.length;
  final scores = List.filled(n, config.startScore);
  final setsWon = List.filled(n, 0);
  final dartsThrown = List.filled(n, 0);
  final pointsScored = List.filled(n, 0);
  final checkouts = List.filled(n, 0);
  final checkoutAttempts = List.filled(n, 0);
  final visits = <Visit>[];
  final log = <LogEntry>[];
  final events = <GameEvent>[];

  var current = 0; // first thrower of set k is setNo % n (see set end below)
  var setNo = 0;
  var matchOver = false;
  int? matchWinner;

  int? visitPlayer;
  var visitStart = 0;
  final visitDarts = <DartThrow>[];

  void closeVisit({bool busted = false, bool checkout = false}) {
    final p = visitPlayer!;
    final endScore = scores[p];
    final scored = busted ? 0 : visitStart - endScore;
    visits.add(Visit(
      playerIdx: p,
      setNumber: setNo,
      startScore: visitStart,
      darts: List.of(visitDarts),
      busted: busted,
      checkout: checkout,
      endScore: endScore,
    ));
    pointsScored[p] += scored;
    final name = config.names[p];

    if (busted) {
      log.add(LogEntry('$name: Bust! back to $visitStart', 'bust'));
    } else {
      log.add(LogEntry(
          '$name: ${visitDarts.map((d) => d.label).join(' ')} = $scored',
          'info'));
      if (scored == 180) {
        log.add(LogEntry('180! by $name', 'checkout'));
        events.add(GameEvent(
            GameEventType.score180, {'player': name, 'playerIdx': p}));
      }
    }
    events.add(GameEvent(GameEventType.visitCompleted,
        {'player': name, 'playerIdx': p, 'scored': scored, 'busted': busted}));

    visitPlayer = null;
    visitDarts.clear();
    current = (current + 1) % n;
  }

  for (final d in history) {
    if (matchOver) break;
    if (visitPlayer == null) {
      visitPlayer = current;
      visitStart = scores[current];
    }
    final p = visitPlayer!;
    dartsThrown[p]++;
    visitDarts.add(d);

    // Any dart thrown while the score is finishable with one dart counts as
    // a checkout attempt (double-out: a reachable double or the bull;
    // single-out: any board-valid value 1..60); a converting dart counts as
    // both attempt and success.
    final onCheckout = config.doubleOut
        ? (scores[p] >= 2 && scores[p] <= 40 && scores[p].isEven) ||
            scores[p] == 50
        : _singleOutFinishable(scores[p]);
    if (onCheckout) checkoutAttempts[p]++;

    final after = scores[p] - d.points;
    final bust = after < 0 ||
        (config.doubleOut &&
            (after == 1 || (after == 0 && !d.isDouble)));

    if (bust) {
      scores[p] = visitStart;
      closeVisit(busted: true);
    } else {
      scores[p] = after;
      if (after == 0) {
        // Checkout: exactly 0 (with a double when double-out is on).
        checkouts[p]++;
        setsWon[p]++;
        closeVisit(checkout: true);
        final name = config.names[p];
        final scoreLine = config.names
            .asMap()
            .entries
            .map((e) => '${e.value} ${setsWon[e.key]}')
            .join(' - ');
        events.add(GameEvent(
            GameEventType.checkout, {'player': name, 'playerIdx': p}));
        if (setsWon[p] >= config.setsToWin) {
          matchOver = true;
          matchWinner = p;
          log.add(
              LogEntry('Checkout! $name WINS THE MATCH ($scoreLine)', 'match'));
          events.add(GameEvent(GameEventType.matchWon,
              {'player': name, 'playerIdx': p, 'sets': setsWon[p]}));
        } else {
          log.add(LogEntry(
              'Checkout! $name wins set ${setNo + 1} ($scoreLine)', 'set'));
          events.add(GameEvent(GameEventType.setWon,
              {'player': name, 'playerIdx': p, 'sets': setsWon[p]}));
          setNo++;
          for (var i = 0; i < n; i++) {
            scores[i] = config.startScore;
          }
          current = setNo % n; // alternate first thrower per set
        }
      } else if (visitDarts.length == 3) {
        closeVisit();
      }
    }
  }

  return ReplayResult(
    Snapshot(
      scores: scores,
      setsWon: setsWon,
      currentPlayer: current,
      currentSet: setNo,
      visits: visits,
      log: log,
      dartsThrown: dartsThrown,
      pointsScored: pointsScored,
      checkouts: checkouts,
      checkoutAttempts: checkoutAttempts,
      matchOver: matchOver,
      matchWinner: matchWinner,
      openVisitPlayer: visitPlayer,
      openVisitStart: visitPlayer == null ? null : visitStart,
      openVisitDarts: List.of(visitDarts),
    ),
    events,
  );
}

/// Stats carried over from previous matches (Rematch → "continue stats").
class StatsBaseline {
  final int darts;
  final int points;
  final int over100;
  final int over140;
  final int checkouts;
  final int attempts;
  final int highestCheckout;
  final int bestVisit;
  final int lastVisit;

  const StatsBaseline({
    this.darts = 0,
    this.points = 0,
    this.over100 = 0,
    this.over140 = 0,
    this.checkouts = 0,
    this.attempts = 0,
    this.highestCheckout = 0,
    this.bestVisit = 0,
    this.lastVisit = 0,
  });
}

/// Holds the live match: config + dart history + revision counter.
class Engine {
  MatchConfig? _config;
  List<StatsBaseline> _base = const [];
  final List<DartThrow> _history = [];
  late ReplayResult _result;
  int _emittedEvents = 0;

  /// Bumped on every mutation; clients poll and skip renders when unchanged.
  int rev = 0;

  /// Receives only NEW events caused by the latest mutation (not during
  /// undo/reset replays).
  final SmartHomeService smartHome;

  Engine({SmartHomeService? smartHome})
      : smartHome = smartHome ?? NoopSmartHome() {
    _result = ReplayResult(_emptySnapshot(), const []);
  }

  static Snapshot _emptySnapshot() => const Snapshot(
        scores: [],
        setsWon: [],
        currentPlayer: 0,
        currentSet: 0,
        visits: [],
        log: [],
        dartsThrown: [],
        pointsScored: [],
        checkouts: [],
        checkoutAttempts: [],
        matchOver: false,
        matchWinner: null,
        openVisitPlayer: null,
        openVisitStart: null,
        openVisitDarts: [],
      );

  bool get hasGame => _config != null;
  MatchConfig get config => _config!;
  Snapshot get snap => _result.snapshot;
  List<DartThrow> get history => List.unmodifiable(_history);

  void _replayAndSync({bool emitNew = false}) {
    _result = replay(_config!, _history);
    if (emitNew) {
      for (var i = _emittedEvents; i < _result.events.length; i++) {
        smartHome.onEvent(_result.events[i]);
      }
    }
    _emittedEvents = _result.events.length;
  }

  /// Starts a new match (also used for "New match" / "Rematch").
  /// With [keepStats] the accumulated stats of the previous match carry over
  /// (per player, by position) — used for "Rematch → continue stats".
  void newMatch(MatchConfig cfg, {bool keepStats = false}) {
    if (keepStats && _config != null && _history.isNotEmpty) {
      _base = [
        for (var i = 0; i < _config!.names.length && i < cfg.names.length; i++)
          StatsBaseline(
            darts: combinedDartsFor(i),
            points: _baseFor(i).points + snap.pointsScored[i],
            over100: visitsOverFor(i, 100),
            over140: visitsOverFor(i, 140),
            checkouts: _baseFor(i).checkouts + snap.checkouts[i],
            attempts: _baseFor(i).attempts + snap.checkoutAttempts[i],
            highestCheckout: highestCheckoutFor(i),
            bestVisit: bestVisitFor(i),
            lastVisit: lastVisitFor(i),
          )
      ];
    } else {
      _base = const [];
    }
    _config = cfg;
    _history.clear();
    _replayAndSync();
    rev++;
  }

  /// Records one dart. Throws [StateError] when no game / match over and
  /// [ArgumentError] on invalid input.
  void applyDart(int points, {bool doubleFlag = false}) {
    if (_config == null) throw StateError('no game');
    if (snap.matchOver) throw StateError('match is over');
    final d = DartThrow.parse(points, doubleFlag: doubleFlag);
    _history.add(d);
    _replayAndSync(emitNew: true);
    rev++;
  }

  /// Removes the last dart and recomputes.
  void undo() {
    if (_config == null) throw StateError('no game');
    if (_history.isEmpty) throw StateError('nothing to undo');
    _history.removeLast();
    _replayAndSync();
    rev++;
  }

  /// Restart the current match with the same config.
  void reset() {
    if (_config == null) throw StateError('no game');
    _history.clear();
    _replayAndSync();
    rev++;
  }

  /// Abandon the game entirely — back to "no game" (used by the API's idle
  /// timeout; the next client poll then shows the config screen).
  void clear() {
    _config = null;
    _base = const [];
    _history.clear();
    _result = ReplayResult(_emptySnapshot(), const []);
    _emittedEvents = 0;
    rev++;
  }

  // ---- stats (current match + carried-over baseline) ----

  StatsBaseline _baseFor(int player) =>
      player < _base.length ? _base[player] : const StatsBaseline();

  int combinedDartsFor(int player) =>
      _baseFor(player).darts + _result.snapshot.dartsThrown[player];

  int combinedPointsFor(int player) =>
      _baseFor(player).points + _result.snapshot.pointsScored[player];

  /// Number of scoring visits (busts excluded) with at least [threshold]
  /// points, including carried-over stats — used for the 100+ / 140+ counters.
  int visitsOverFor(int player, int threshold) {
    final base =
        threshold == 100 ? _baseFor(player).over100 : _baseFor(player).over140;
    return base +
        _result.snapshot.visits
            .where((v) =>
                v.playerIdx == player && !v.busted && v.scored >= threshold)
            .length;
  }

  /// Value of the highest checkout (0 = none yet), incl. carried-over stats.
  int highestCheckoutFor(int player) {
    var best = _baseFor(player).highestCheckout;
    for (final v in _result.snapshot.visits) {
      if (v.playerIdx == player && v.checkout && v.scored > best) {
        best = v.scored;
      }
    }
    return best;
  }

  double avgFor(int player) {
    final darts = combinedDartsFor(player);
    return darts == 0 ? 0 : combinedPointsFor(player) / darts * 3;
  }

  int lastVisitFor(int player) {
    for (final v in _result.snapshot.visits.reversed) {
      if (v.playerIdx == player && v.setNumber == snap.currentSet) {
        return v.scored;
      }
    }
    return _baseFor(player).lastVisit;
  }

  int bestVisitFor(int player) {
    var best = _baseFor(player).bestVisit;
    for (final v in _result.snapshot.visits) {
      if (v.playerIdx == player && !v.busted && v.scored > best) {
        best = v.scored;
      }
    }
    return best;
  }

  // ---- API serialisation ----

  Map<String, dynamic> toJson() {
    final cfg = _config;
    if (cfg == null) return {'rev': rev, 'hasGame': false};
    final s = snap;
    return {
      'rev': rev,
      'hasGame': true,
      'config': {
        'startScore': cfg.startScore,
        'bestOf': cfg.bestOf,
        'setsToWin': cfg.setsToWin,
        'names': cfg.names,
        'doubleOut': cfg.doubleOut,
      },
      'players': [
        for (var i = 0; i < cfg.names.length; i++)
          {
            'name': cfg.names[i],
            'score': s.scores[i],
            'setsWon': s.setsWon[i],
            'active': i == s.currentPlayer && !s.matchOver,
            'avg': double.parse(avgFor(i).toStringAsFixed(1)),
            'lastVisit': lastVisitFor(i),
            'bestVisit': bestVisitFor(i),
            'dartsThrown': combinedDartsFor(i),
            'checkouts': _baseFor(i).checkouts + s.checkouts[i],
            'checkoutAttempts': _baseFor(i).attempts + s.checkoutAttempts[i],
            'over100': visitsOverFor(i, 100),
            'over140': visitsOverFor(i, 140),
            'highestCheckout': highestCheckoutFor(i),
          }
      ],
      'currentPlayer': s.currentPlayer,
      'currentSet': s.currentSet + 1,
      'matchOver': s.matchOver,
      'matchWinner': s.matchWinner,
      'openVisit': s.openVisitPlayer == null
          ? null
          : {
              'player': s.openVisitPlayer,
              'startScore': s.openVisitStart,
              'labels': s.openVisitDarts.map((d) => d.label).toList(),
            },
      'visits': s.visits.map((v) => v.toJson()).toList(),
      'log': s.log.map((l) => l.toJson()).toList(),
      'historyLength': _history.length,
    };
  }
}
