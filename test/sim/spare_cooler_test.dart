import 'package:ai_lab_tycoon/sim/balance.dart';
import 'package:ai_lab_tycoon/sim/game.dart';
import 'package:ai_lab_tycoon/sim/game_state.dart';
import 'package:flutter_test/flutter_test.dart';

/// A playtester's full garage: 8 V100s (1.00 PFLOPS, just under the
/// Startup gate) with 6 window ACs and 2 fans, rows alternating.
Game _overCooled() {
  const layout = [
    'V', 'A', 'V', 'A', //
    'A', 'V', 'A', 'V',
    'V', 'A', 'V', 'A',
    'F', 'V', 'F', 'V',
  ];
  final cells = [
    for (final c in layout)
      switch (c) {
        'V' => 'gpu_v_class',
        'A' => 'cool_window_ac',
        _ => 'cool_fan',
      },
  ];
  return Game(
    GameState(
      grids: {'garage': cells},
      powerTier: 1,
      money: 1e5,
      ownedUpgrades: {'mixed_precision'},
    ),
  );
}

void main() {
  test(
    'an over-cooled full garage points at coolers to swap, and swapping one crosses the gate',
    () {
      final g = _overCooled();
      bool cool(Game g) {
        final rs = g.grid.rooms['garage']!;
        return [
          for (var j = 0; j < 16; j++)
            if (rs.defs[j]?.isGpu == true) rs.netHeat[j],
        ].every((h) => h <= 0);
      }

      expect(cool(g), isTrue, reason: 'nothing throttles');
      final spare = g.spareCoolers();
      expect(spare, isNotEmpty);
      // The gate counts the GPUs you own (peak TFLOPS), so any one swap
      // crosses it (the new GPU may run a little warm).
      for (final i in spare) {
        final h = _overCooled();
        expect(h.replaceTile('garage', i % 4, i ~/ 4, 'gpu_v_class'), isTrue);
        expect(
          h.nextEraGoal!.current,
          greaterThanOrEqualTo(startupUnlockTflops),
        );
      }
    },
  );

  test('a cooler that keeps a GPU cool is not spare', () {
    final cells =
        List<String?>.filled(16, null)
          ..[0] = 'gpu_v_class'
          ..[1] = 'gpu_v_class'
          ..[2] = 'gpu_v_class'
          ..[3] = 'gpu_v_class'
          ..[4] = 'cool_fan';
    final g = Game(GameState(grids: {'garage': cells}, powerTier: 1));
    // 4 V100s (heat 20) on the garage's 16 ambient cooling: the fan matters.
    expect(g.spareCoolers(), isEmpty);
  });
}
