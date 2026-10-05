/// Smart-home integration placeholder.
///
/// The game engine emits [GameEvent]s at interesting moments (180, checkout,
/// match won, …). Right now they are consumed by [NoopSmartHome], which does
/// nothing. To add smart-home control later, implement [SmartHomeService]
/// (e.g. talking to Home Assistant) and wire it up in `bin/server.dart` —
/// no changes to the engine or API are needed.
library;

enum GameEventType {
  visitCompleted, // a player's turn ended normally (3 darts)
  score180, // a visit totalled 180
  checkout, // a player hit a double to win a set
  setWon, // a set was won
  matchWon, // the whole match was won
}

class GameEvent {
  final GameEventType type;
  final Map<String, Object?> data;

  const GameEvent(this.type, this.data);

  @override
  String toString() => 'GameEvent(${type.name}, $data)';
}

abstract class SmartHomeService {
  void onEvent(GameEvent event);
}

/// Default implementation: does nothing.
class NoopSmartHome implements SmartHomeService {
  @override
  void onEvent(GameEvent event) {}
}

/// ---- FUTURE IMPLEMENTATION (deliberately not active yet) ----
//
// class HomeAssistantSmartHome implements SmartHomeService {
//   static const _haUrl = 'http://homeassistant.local:8123';
//   static const _token = '...long-lived access token...';
//
//   @override
//   void onEvent(GameEvent e) {
//     switch (e.type) {
//       case GameEventType.score180:
//         // flash the bar lights: POST $_haUrl/api/services/light/turn_on
//         break;
//       case GameEventType.matchWon:
//         // party mode: POST $_haUrl/api/scripts/turn_on {entity_id: dart_celebration}
//         break;
//       default:
//         break;
//     }
//   }
// }
