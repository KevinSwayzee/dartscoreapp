/// Pure data model for a darts match — no I/O, no shelf imports.
library;

class MatchConfig {
  final int startScore; // 301 or 501
  final int bestOf; // 3 or 5
  final List<String> names; // 1..4 players
  final bool doubleOut; // false = single-out: any dart reaching 0 wins

  int get setsToWin => bestOf ~/ 2 + 1;

  MatchConfig({
    required this.startScore,
    required this.bestOf,
    required this.names,
    this.doubleOut = true,
  }) {
    if (startScore != 301 && startScore != 501) {
      throw ArgumentError('startScore must be 301 or 501');
    }
    if (bestOf != 3 && bestOf != 5) {
      throw ArgumentError('bestOf must be 3 or 5');
    }
    if (names.isEmpty || names.length > 4) {
      throw ArgumentError('need 1..4 players');
    }
  }

  factory MatchConfig.fromJson(Map<String, dynamic> json) => MatchConfig(
        startScore: json['startScore'] as int,
        bestOf: json['bestOf'] as int,
        names: (json['players'] as List).cast<String>(),
        doubleOut: json['doubleOut'] != false,
      );
}

/// One dart as recorded in history.
///
/// [points] is the raw value 0..60; [isDouble] says whether it counts as a
/// double (explicit "D" toggle on the keypad, or auto-detected for values
/// only reachable as a double: 22, 26, 32, 34, 38, 46, 50).
class DartThrow {
  final int points;
  final bool isDouble;

  const DartThrow(this.points, this.isDouble);

  /// Values that can ONLY be scored as a double (D11..D20 or the bull), so
  /// an unmodified keypad entry is unambiguous.
  static const Set<int> doubleOnlyValues = {22, 26, 28, 32, 34, 38, 40, 50};

  /// Whether [points] can be played as a double: D1..D20 or the bull.
  static bool isDoubleValue(int points) =>
      (points >= 2 && points <= 40 && points.isEven) || points == 50;

  /// Whether [points] is achievable on a real board at all: singles 1-20 and
  /// 25, all triples (multiples of 3 up to 60), doubles (even up to 40) and
  /// the bull. Rejects e.g. 23, 44, 46, 56.
  static bool isValidThrow(int points) =>
      points == 0 ||
      (points >= 1 && points <= 20) ||
      points == 25 ||
      points == 50 ||
      points % 3 == 0 ||
      (points.isEven && points <= 40);

  /// Parses keypad input into a recorded throw. Throws [ArgumentError] on
  /// invalid input (unreachable value, or "D" on a non-double value).
  factory DartThrow.parse(int points, {bool doubleFlag = false}) {
    if (points < 0 || points > 60 || !isValidThrow(points)) {
      throw ArgumentError('$points is not a scoreable value');
    }
    if (doubleFlag && !isDoubleValue(points)) {
      throw ArgumentError('$points is not a double value');
    }
    return DartThrow(points, doubleFlag || doubleOnlyValues.contains(points));
  }

  /// Display label, e.g. T20, D16, Bull, 25, Miss.
  String get label {
    if (points == 0) return 'Miss';
    if (isDouble) return points == 50 ? 'Bull' : 'D${points ~/ 2}';
    if (points == 25) return '25';
    if (points % 3 == 0 && points ~/ 3 >= 1 && points ~/ 3 <= 20) {
      return 'T${points ~/ 3}';
    }
    return '$points';
  }

  Map<String, dynamic> toJson() => {
        'points': points,
        'isDouble': isDouble,
        'label': label,
      };
}

/// A completed turn: up to 3 darts by one player.
class Visit {
  final int playerIdx;
  final int setNumber; // 0-based
  final int startScore;
  final List<DartThrow> darts;
  final bool busted;
  final bool checkout;
  final int endScore;

  Visit({
    required this.playerIdx,
    required this.setNumber,
    required this.startScore,
    required this.darts,
    required this.busted,
    required this.checkout,
    required this.endScore,
  });

  int get scored => busted ? 0 : startScore - endScore;

  String get label => darts.map((d) => d.label).join(' ');

  Map<String, dynamic> toJson() => {
        'player': playerIdx,
        'set': setNumber,
        'labels': darts.map((d) => d.label).toList(),
        'scored': scored,
        'busted': busted,
        'checkout': checkout,
      };
}

class LogEntry {
  final String text;
  final String kind; // info | bust | checkout | set | match

  const LogEntry(this.text, this.kind);

  Map<String, dynamic> toJson() => {'text': text, 'kind': kind};
}
