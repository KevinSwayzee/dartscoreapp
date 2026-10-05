import 'package:dartscore/src/engine.dart';
import 'package:dartscore/src/models.dart';
import 'package:dartscore/src/smart_home.dart';
import 'package:test/test.dart';

MatchConfig match301(List<String> names,
        {int bestOf = 3, bool doubleOut = true}) =>
    MatchConfig(startScore: 301, bestOf: bestOf, names: names, doubleOut: doubleOut);

extension ThrowMany on Engine {
  /// Applies several darts; indices in [doublesAt] get the explicit D flag.
  void thrown(List<int> points, {Set<int> doublesAt = const {}}) {
    for (var i = 0; i < points.length; i++) {
      applyDart(points[i], doubleFlag: doublesAt.contains(i));
    }
  }
}

void main() {
  group('DartThrow parsing & labels', () {
    test('rejects unreachable values', () {
      for (final p in [-1, 23, 44, 46, 52, 56, 58, 61, 100]) {
        expect(() => DartThrow.parse(p), throwsArgumentError, reason: '$p');
      }
    });

    test('accepts board-valid values', () {
      for (final p in [0, 1, 20, 21, 22, 24, 25, 27, 40, 45, 50, 57, 60]) {
        expect(() => DartThrow.parse(p), returnsNormally, reason: '$p');
      }
    });

    test('rejects double flag on non-double values', () {
      for (final p in [1, 3, 21, 23, 25, 27, 41, 45, 55]) {
        expect(() => DartThrow.parse(p, doubleFlag: true), throwsArgumentError,
            reason: '$p is not a double');
      }
      expect(() => DartThrow.parse(40, doubleFlag: true), returnsNormally);
      expect(() => DartThrow.parse(50, doubleFlag: true), returnsNormally);
    });

    test('auto-detects double-only values', () {
      for (final p in [22, 26, 28, 32, 34, 38, 40, 50]) {
        expect(DartThrow.parse(p).isDouble, isTrue, reason: '$p');
      }
      // Ambiguous values stay singles unless the D toggle is used.
      expect(DartThrow.parse(16).isDouble, isFalse); // S16 or D8
      expect(DartThrow.parse(6).isDouble, isFalse); // S6, T2 or D3
      expect(DartThrow.parse(25).isDouble, isFalse); // outer bull never a D
      expect(DartThrow.parse(24).isDouble, isFalse); // S/T/D — needs toggle
      expect(DartThrow.parse(16, doubleFlag: true).isDouble, isTrue);
      expect(DartThrow.parse(24, doubleFlag: true).isDouble, isTrue);
    });

    test('labels', () {
      expect(DartThrow.parse(0).label, 'Miss');
      expect(DartThrow.parse(60).label, 'T20');
      expect(DartThrow.parse(32).label, 'D16');
      expect(DartThrow.parse(50).label, 'Bull');
      expect(DartThrow.parse(25).label, '25');
      expect(DartThrow.parse(21).label, 'T7');
      expect(DartThrow.parse(19).label, '19');
      expect(DartThrow.parse(10, doubleFlag: true).label, 'D5'); // 10 = 2×5
      expect(DartThrow.parse(20, doubleFlag: true).label, 'D10');
      expect(DartThrow.parse(40, doubleFlag: true).label, 'D20');
    });
  });

  group('bust rules (solo 301)', () {
    // Reach score 121 in one visit of 3 x T20.
    Engine at121() {
      final e = Engine()..newMatch(match301(['A']));
      e.thrown([60, 60, 60]);
      expect(e.snap.scores[0], 121);
      return e;
    }

    test('landing on 1 busts and voids the whole visit', () {
      final e = at121();
      e.thrown([60, 60]); // 61, then 1 → bust on second dart
      expect(e.snap.scores[0], 121); // visit start restored
      final last = e.snap.visits.last;
      expect(last.busted, isTrue);
      expect(last.scored, 0);
      expect(last.darts.length, 2);
    });

    test('going below zero busts and voids the visit', () {
      final e = at121();
      e.thrown([50, 50, 30]); // 71, 21, -9 → bust
      expect(e.snap.scores[0], 121);
      expect(e.snap.visits.last.busted, isTrue);
    });

    test('reaching 0 without a double busts', () {
      final e = at121();
      e.thrown([45, 45, 11]); // 76, 31, 20 (visit over)
      expect(e.snap.scores[0], 20);
      e.thrown([20]); // single 20 (ambiguous value, no toggle) → 0, bust
      expect(e.snap.scores[0], 20);
      expect(e.snap.visits.last.busted, isTrue);
    });
  });

  group('checkout rules', () {
    test('explicit double wins the set', () {
      final e = Engine()..newMatch(match301(['A']));
      e.thrown([60, 60, 60]); // 121
      e.thrown([45, 45, 11]); // 20
      e.thrown([20], doublesAt: {0}); // D10 (20 pts) → checkout
      expect(e.snap.scores[0], 301); // next set started
      expect(e.snap.setsWon[0], 1);
      expect(e.snap.visits.last.checkout, isTrue);
    });

    test('auto-double (D16) checkout without toggle', () {
      final e = Engine()..newMatch(match301(['A']));
      e.thrown([60, 60, 60]); // 121
      e.thrown([40, 40, 9]); // 41, visit over at 32
      expect(e.snap.scores[0], 32);
      e.thrown([32]); // D16 auto → checkout
      expect(e.snap.setsWon[0], 1);
      expect(e.snap.visits.last.checkout, isTrue);
    });

    test('bull checks out; outer bull on 25 busts', () {
      final e = Engine()..newMatch(match301(['A']));
      e.thrown([60, 60, 60]); // 121
      e.thrown([45, 26, 25]); // 76, 50, then single 25 (visit over at 25)
      expect(e.snap.scores[0], 25);
      // Outer bull (25 is never a double) → 0 without double → bust.
      e.thrown([25]);
      expect(e.snap.scores[0], 25);
      expect(e.snap.visits.last.busted, isTrue);
      // Bull checkout: get to exactly 50, then throw the bull.
      final e2 = Engine()..newMatch(match301(['A']));
      e2.thrown([60, 60, 60]); // 121
      e2.thrown([45, 26, 0]); // 76, 50, Miss → visit over at 50
      expect(e2.snap.scores[0], 50);
      e2.thrown([50]); // Bull = D25 → checkout
      expect(e2.snap.setsWon[0], 1);
      expect(e2.snap.visits.last.checkout, isTrue);
    });

    test('turn ends immediately on checkout, before 3 darts', () {
      final e = Engine()..newMatch(match301(['A', 'B']));
      e.thrown([60, 60, 60]); // A → 121
      e.thrown([0, 0, 0]); // B 301
      e.thrown([40, 40, 9]); // A → 32
      e.thrown([0, 0, 0]); // B 301
      e.thrown([32]); // A checks out with a single-dart visit
      expect(e.snap.visits.last.playerIdx, 0);
      expect(e.snap.visits.last.darts.length, 1);
    });
  });

  group('single-out rules (doubleOut: false)', () {
    test('0 without a double checks out', () {
      final e = Engine()..newMatch(match301(['A'], doubleOut: false));
      e.thrown([60, 60, 60]); // 121
      e.thrown([45, 45, 11]); // 76, 31, 20 (visit over)
      e.thrown([20]); // single 20 (would bust with double-out) → checkout
      expect(e.snap.setsWon[0], 1);
      expect(e.snap.visits.last.checkout, isTrue);
    });

    test('1 is not a bust; single 1 checks out', () {
      final e = Engine()..newMatch(match301(['A'], doubleOut: false));
      e.thrown([60, 60, 60]); // 121
      e.thrown([60, 60]); // 61, then 1 — legal without double-out
      expect(e.snap.scores[0], 1);
      expect(e.snap.openVisitPlayer, 0);
      e.thrown([1]); // S1 → 0 → checkout (3rd dart of the visit)
      expect(e.snap.setsWon[0], 1);
      expect(e.snap.visits.last.checkout, isTrue);
    });

    test('going below zero still busts', () {
      final e = Engine()..newMatch(match301(['A'], doubleOut: false));
      e.thrown([60, 60, 60]); // 121
      e.thrown([50, 50, 30]); // 71, 21, -9 → bust
      expect(e.snap.scores[0], 121);
      expect(e.snap.visits.last.busted, isTrue);
    });

    test('attempts count on any one-dart finish value', () {
      final e = Engine()..newMatch(match301(['A'], doubleOut: false));
      e.thrown([60, 60, 60]); // 121 — above any one-dart finish
      e.thrown([60, 17, 0]); // 61, then 44 — both unthrowable → no attempts
      expect(e.snap.checkoutAttempts[0], 0);
      e.thrown([25, 0, 0]); // 19, then two misses while on a finish → 2
      expect(e.snap.checkoutAttempts[0], 2);
      e.thrown([19]); // single 19 → attempt 3, converted
      expect(e.snap.checkoutAttempts[0], 3);
      expect(e.snap.checkouts[0], 1);
    });
  });

  group('turn / set / match progression', () {
    test('turn advances after 3 darts; stays with player after 1-2 darts', () {
      final e = Engine()..newMatch(match301(['A', 'B']));
      e.thrown([20]);
      expect(e.snap.currentPlayer, 0);
      expect(e.snap.openVisitPlayer, 0);
      expect(e.snap.openVisitDarts.length, 1);
      e.thrown([20, 20]); // 3rd dart
      expect(e.snap.currentPlayer, 1);
      expect(e.snap.openVisitPlayer, null);
    });

    test('checkout wins set, scores reset, first thrower alternates', () {
      final e = Engine()..newMatch(match301(['A', 'B']));
      // Set 1 → A
      e.thrown([60, 60, 60]); // A 121
      e.thrown([0, 0, 0]); // B 301
      e.thrown([40, 40, 9]); // A 32
      e.thrown([0, 0, 0]); // B 301
      e.thrown([32]); // A checkout
      expect(e.snap.setsWon, [1, 0]);
      expect(e.snap.matchOver, isFalse);
      expect(e.snap.currentSet, 1);
      expect(e.snap.scores, [301, 301]);
      expect(e.snap.currentPlayer, 1); // set 2 starts with B (setNo % n)

      // Set 2 → B
      e.thrown([40, 40, 19]); // B 202
      e.thrown([0, 0, 0]); // A 301
      e.thrown([60, 60, 60]); // B 22
      e.thrown([0, 0, 0]); // A 301
      e.thrown([22]); // B: D11 auto → checkout
      expect(e.snap.setsWon, [1, 1]);
      expect(e.snap.currentSet, 2);
      expect(e.snap.currentPlayer, 0); // set 3 starts with A again

      // Set 3 → A wins the match (setsToWin 2)
      e.thrown([60, 60, 60]); // A 121
      e.thrown([0, 0, 0]); // B 301
      e.thrown([40, 40, 9]); // A 32
      e.thrown([0, 0, 0]); // B 301
      e.thrown([32]); // A checkout → 2-1
      expect(e.snap.matchOver, isTrue);
      expect(e.snap.matchWinner, 0);
      expect(e.snap.setsWon, [2, 1]);
    });

    test('rejects 5 players, bad startScore, bad bestOf', () {
      expect(() => match301(['A', 'B', 'C', 'D', 'E']), throwsArgumentError);
      expect(() => MatchConfig(startScore: 400, bestOf: 3, names: ['A']),
          throwsArgumentError);
      expect(() => MatchConfig(startScore: 301, bestOf: 4, names: ['A']),
          throwsArgumentError);
    });
  });

  group('undo', () {
    test('undo pops the last dart', () {
      final e = Engine()..newMatch(match301(['A', 'B']));
      e.thrown([60]);
      e.undo();
      expect(e.snap.scores[0], 301);
      expect(e.snap.openVisitPlayer, null);
      expect(e.history, isEmpty);
    });

    test('undo across a bust restores the pre-bust visit', () {
      final e = Engine()..newMatch(match301(['A']));
      e.thrown([60, 60, 60]); // 121
      e.thrown([60, 60]); // 61, then 1 → bust back to 121
      expect(e.snap.visits.last.busted, isTrue);
      e.undo(); // removes the busting dart
      expect(e.snap.visits.last.busted, isFalse);
      expect(e.snap.openVisitPlayer, 0);
      expect(e.snap.openVisitDarts.length, 1);
      expect(e.snap.scores[0], 61); // live mid-visit score, no bust
    });

    test('undo un-wins a match', () {
      final e = Engine()..newMatch(match301(['A']));
      // Solo best-of-3: win two sets to win the match.
      e.thrown([60, 60, 60, 40, 40, 9, 32]); // set 1: 121 → 32 → checkout
      e.thrown([60, 60, 60, 40, 40, 9]); // set 2: 121 → 32
      e.thrown([32]); // checkout → match won
      expect(e.snap.matchOver, isTrue);
      e.undo();
      expect(e.snap.matchOver, isFalse);
      expect(e.snap.scores[0], 32);
      expect(e.snap.setsWon[0], 1);
      expect(e.snap.currentPlayer, 0);
    });

    test('no game / empty undo / dart after match over throw StateError', () {
      final e = Engine();
      expect(() => e.undo(), throwsStateError);
      expect(() => e.applyDart(20), throwsStateError);
      e.newMatch(match301(['A']));
      e.thrown([60, 60, 60, 40, 40, 9, 32]); // set 1
      e.thrown([60, 60, 60, 40, 40, 9, 32]); // set 2 → match over
      expect(e.snap.matchOver, isTrue);
      expect(() => e.applyDart(20), throwsStateError);
    });
  });

  group('stats', () {
    test('3-dart average, last and best visit', () {
      final e = Engine()..newMatch(match301(['A', 'B']));
      expect(e.avgFor(0), 0); // no darts yet
      e.thrown([60, 60, 60]); // A visit 180
      e.thrown([20, 20, 20]); // B visit 60
      e.thrown([40, 40, 9]); // A visit 89
      expect(e.snap.dartsThrown[0], 6);
      expect(e.avgFor(0), closeTo((180 + 89) / 6 * 3, 0.001));
      expect(e.lastVisitFor(0), 89);
      expect(e.bestVisitFor(0), 180);
      expect(e.lastVisitFor(1), 60);
    });

    test('busted darts count as thrown but score nothing', () {
      final e = Engine()..newMatch(match301(['A']));
      e.thrown([60, 60, 60]); // 121, 3 darts
      e.thrown([60, 60]); // 61, then 1 → bust
      expect(e.snap.dartsThrown[0], 5);
      expect(e.snap.scores[0], 121);
      expect(e.avgFor(0), closeTo(180 / 5 * 3, 0.001));
    });

    test('rematch with keepStats carries totals; without it resets', () {
      final e = Engine()..newMatch(match301(['A', 'B']));
      e.thrown([60, 60, 60]); // A visit 180
      e.thrown([0, 0, 0]); // B
      e.thrown([40, 40, 9]); // A visit 89 (32 left)
      e.thrown([0, 0, 0]); // B
      e.thrown([32]); // A checkout (32) → set 1
      final darts1 = e.combinedDartsFor(0); // 7
      final avg1 = e.avgFor(0);
      expect(e.highestCheckoutFor(0), 32);
      expect(e.visitsOverFor(0, 100), 1); // only the 180 (89 and 32 don't count)

      // Rematch, continue stats: baseline = match-1 totals.
      e.newMatch(match301(['A', 'B']), keepStats: true);
      expect(e.combinedDartsFor(0), darts1);
      expect(e.avgFor(0), closeTo(avg1, 0.001));
      expect(e.highestCheckoutFor(0), 32);
      expect(e.visitsOverFor(0, 100), 1);

      // One more 180 visit in match 2 → counters grow from the baseline.
      e.thrown([60, 60, 60]);
      expect(e.combinedDartsFor(0), darts1 + 3);
      expect(e.visitsOverFor(0, 100), 2);
      expect(e.visitsOverFor(0, 140), 2);

      // Rematch WITHOUT keepStats → everything back to zero.
      e.newMatch(match301(['A', 'B']));
      expect(e.combinedDartsFor(0), 0);
      expect(e.avgFor(0), 0);
      expect(e.highestCheckoutFor(0), 0);
      expect(e.visitsOverFor(0, 100), 0);
    });

    test('checkout attempts: darts on a reachable double count', () {
      final e = Engine()..newMatch(match301(['A']));
      e.thrown([60, 60, 60]); // 121 — not on a double
      e.thrown([40, 40, 1]); // 81, 41, 40 (visit over; none thrown on double)
      expect(e.snap.checkoutAttempts[0], 0);
      // now on 40 (D20): miss, then S10 (→30, still on double), then D15 → hit
      e.thrown([0]); // attempt 1, missed
      e.thrown([10]); // attempt 2, scored but not a finish (30 left)
      e.thrown([30], doublesAt: {0}); // attempt 3 → D15 checkout
      expect(e.snap.checkoutAttempts[0], 3);
      expect(e.snap.checkouts[0], 1);
      e.undo(); // undo the successful dart → still 2 attempts
      expect(e.snap.checkoutAttempts[0], 2);
      expect(e.snap.checkouts[0], 0);
    });

    test('100+ / 140+ counters and highest checkout', () {
      final e = Engine()..newMatch(match301(['A', 'B']));
      e.thrown([60, 60, 60]); // A visit 180 → 100+ and 140+ (121 left)
      e.thrown([0, 0, 0]); // B
      e.thrown([60, 25, 15]); // A visit exactly 100 → 100+ only (21 left)
      e.thrown([0, 0, 0]); // B
      e.thrown([1, 0, 0]); // A visit 1 (20 left)
      e.thrown([0, 0, 0]); // B
      e.thrown([20], doublesAt: {0}); // A: D10 checkout → 20-point checkout
      expect(e.snap.visits.last.checkout, isTrue);
      expect(e.visitsOverFor(0, 100), 2); // 180 and 100
      expect(e.visitsOverFor(0, 140), 1); // only the 180
      expect(e.highestCheckoutFor(0), 20);
      expect(e.visitsOverFor(1, 100), 0);
      expect(e.highestCheckoutFor(1), 0);

      // set 2 (B throws first): a bull finish raises A's best checkout to 50
      e.thrown([0, 0, 0]); // B
      e.thrown([60, 60, 60]); // A 121
      e.thrown([0, 0, 0]); // B
      e.thrown([45, 26, 0]); // A: 76, 50, miss (visit over at 50)
      e.thrown([0, 0, 0]); // B
      e.thrown([50]); // A: Bull → 50-point checkout
      expect(e.highestCheckoutFor(0), 50);
    });
  });

  group('events', () {
    test('180, checkout and matchWon events fire once, not on undo', () {
      final collector = _CollectingSmartHome();
      final e = Engine(smartHome: collector)..newMatch(match301(['A']));
      e.thrown([60, 60, 60]);
      expect(collector.types, contains(GameEventType.score180));
      expect(collector.types, contains(GameEventType.visitCompleted));
      e.thrown([40, 40, 9, 32]); // set 1 checkout
      expect(collector.types, contains(GameEventType.checkout));
      expect(collector.types, contains(GameEventType.setWon));
      expect(collector.types, isNot(contains(GameEventType.matchWon)));
      e.thrown([60, 60, 60, 40, 40, 9, 32]); // set 2 → match won
      expect(collector.types, contains(GameEventType.matchWon));
      collector.types.clear();
      e.undo(); // replay must NOT re-emit anything
      expect(collector.types, isEmpty);
    });
  });

  group('idle timeout support', () {
    test('clear() abandons the game completely', () {
      final e = Engine()..newMatch(match301(['A', 'B']));
      e.thrown([60]);
      expect(e.hasGame, isTrue);
      e.clear();
      expect(e.hasGame, isFalse);
      expect(e.toJson()['hasGame'], isFalse);
      expect(() => e.applyDart(20), throwsStateError);
      // a fresh match afterwards starts clean
      e.newMatch(match301(['A', 'B']));
      expect(e.snap.scores, [301, 301]);
      expect(e.snap.dartsThrown, [0, 0]);
    });
  });

  group('serialization', () {
    test('toJson exposes game flag, players, rev, history length', () {
      expect(Engine().toJson()['hasGame'], isFalse);
      final e = Engine()..newMatch(match301(['A', 'B'], bestOf: 5));
      final j1 = e.toJson();
      expect(j1['hasGame'], isTrue);
      expect((j1['players'] as List).length, 2);
      expect(j1['config']['setsToWin'], 3);
      expect(j1['config']['doubleOut'], isTrue); // default when not set
      final rev1 = j1['rev'] as int;
      e.applyDart(20);
      final j2 = e.toJson();
      expect(j2['rev'], greaterThan(rev1));
      expect(j2['historyLength'], 1);
      expect(j2['openVisit'], isNotNull);
    });
  });
}

class _CollectingSmartHome implements SmartHomeService {
  final types = <GameEventType>[];

  @override
  void onEvent(GameEvent event) => types.add(event.type);
}
