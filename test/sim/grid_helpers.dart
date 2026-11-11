import 'package:ai_lab_tycoon/sim/content.dart';
import 'package:ai_lab_tycoon/sim/game.dart';
import 'package:ai_lab_tycoon/sim/game_state.dart';

/// One-letter codes for drawing test grids.
const tileCodes = {
  'o': 'gpu_old',
  'G': 'gpu_gamer',
  'V': 'gpu_v_class',
  'A': 'srv_a_class',
  'H': 'srv_h_class',
  'F': 'cool_fan',
  'W': 'cool_window_ac',
  'C': 'cool_crac',
  'h': 'net_home',
  '5': 'net_5g',
  't': 'net_10g',
  'x': 'net_100g',
};

/// Row-major cells for [roomId] from rows like 'G5G.' ('.' = empty).
List<String?> gridOf(String roomId, List<String> rows) {
  final room = roomById(roomId)!;
  assert(rows.length == room.height, 'need ${room.height} rows');
  return [
    for (final row in rows)
      for (var x = 0; x < room.width; x++)
        x < row.length && row[x] != '.' ? tileCodes[row[x]]! : null,
  ];
}

/// A game with the given room layouts, lots of money and every power tier.
Game gameWith(
  Map<String, List<String>> layouts, {
  double money = 1e12,
  int powerTier = 9,
  Era era = Era.lab,
  Set<String>? ownedUpgrades,
}) => Game(
  GameState(
    money: money,
    powerTier: powerTier,
    era: era,
    ownedUpgrades: ownedUpgrades,
    grids: {for (final e in layouts.entries) e.key: gridOf(e.key, e.value)},
  ),
);
