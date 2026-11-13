import 'dart:math' as math;

import 'package:ai_lab_tycoon/sim/content.dart';
import 'package:ai_lab_tycoon/sim/game.dart';
import 'package:ai_lab_tycoon/sim/game_state.dart';
import 'package:flutter_test/flutter_test.dart';

import 'grid_helpers.dart';

void main() {
  // The default garage: one used RTX 2060 (gpu_old) at (1, 1), 1.8 kW cap.
  final old = tileById('gpu_old')!;
  final v100 = tileById('gpu_v_class')!;
  double oldPrice(int owned) => old.cost * math.pow(1 + old.priceGrowth, owned);
  double v100Price(int owned) =>
      v100.cost * math.pow(1 + v100.priceGrowth, owned);

  group('build plan', () {
    test('cost includes the supply-crunch growth of each planned GPU', () {
      final g = Game(GameState(money: 1e6));
      const plan = [
        PlannedTile(0, 0, 'gpu_old'),
        PlannedTile(2, 0, 'gpu_old'),
        PlannedTile(3, 0, 'cool_fan'),
      ];
      expect(
        g.planCost(plan),
        closeTo(oldPrice(1) + oldPrice(2) + tileById('cool_fan')!.cost, 1e-6),
      );
      expect(
        g.planPowerKw(plan),
        closeTo(2 * old.powerKw + tileById('cool_fan')!.powerKw, 1e-9),
      );
      // Nothing is bought by planning.
      expect(g.s.money, 1e6);
      expect(g.tileAt('garage', 0, 0), isNull);
    });

    test('money for the running total limits the plan', () {
      // Enough for two more RTX 2060s at their grown prices, not three.
      final money = oldPrice(1) + oldPrice(2) + 1;
      final g = Game(GameState(money: money, powerTier: 1));
      final plan = <PlannedTile>[];
      for (final x in [0, 2]) {
        final p = PlannedTile(x, 0, 'gpu_old');
        expect(g.planBlockReason('garage', plan, p), isNull);
        plan.add(p);
      }
      // A third at list price would still fit; the grown price doesn't.
      expect(money - g.planCost(plan), lessThan(oldPrice(3)));
      expect(
        g.planBlockReason('garage', plan, const PlannedTile(3, 0, 'gpu_old')),
        startsWith('Not enough money for another'),
      );
    });

    test('taken cells, planned cells, and power with the plan included', () {
      final g = Game(GameState(money: 1e9));
      final plan = <PlannedTile>[const PlannedTile(0, 0, 'gpu_gamer')];
      expect(
        g.planBlockReason('garage', plan, const PlannedTile(1, 1, 'gpu_gamer')),
        startsWith('That spot is taken'),
      );
      expect(
        g.planBlockReason('garage', plan, const PlannedTile(0, 0, 'cool_fan')),
        contains('already in your plan'),
      );
      // 1.8 kW outlet: the 2060 plus RTX 4090s at 0.45 kW each run out.
      final gamer = tileById('gpu_gamer')!;
      var x = 0;
      String? reason;
      while (reason == null) {
        final p = PlannedTile(x++, 2, 'gpu_gamer');
        reason = g.planBlockReason('garage', plan, p);
        if (reason == null) plan.add(p);
      }
      expect(reason, startsWith('Not enough power'));
      expect(
        g.powerUsedKw + g.planPowerKw(plan),
        lessThanOrEqualTo(g.powerCapKw + 1e-9),
      );
      expect(
        g.powerUsedKw + g.planPowerKw(plan) + gamer.powerKw,
        greaterThan(g.powerCapKw),
      );
    });

    test(
      'withPlan previews heat and the cluster without touching the game',
      () {
        final g = Game(GameState(money: 1e9));
        final preview = g.withPlan('garage', const [
          PlannedTile(0, 1, 'gpu_old'),
          PlannedTile(2, 1, 'gpu_old'),
        ]);
        expect(preview.trainingCluster!.gpus, 3);
        expect(g.trainingCluster!.gpus, 1);
        expect(preview.tileStatus('garage', 0, 1)!.def.id, 'gpu_old');
        expect(g.tileStatus('garage', 0, 1), isNull);
      },
    );

    test(
      'placePlan carries it out in order and returns what no longer fits',
      () {
        final g = Game(
          GameState(money: oldPrice(1) + oldPrice(2) + 1, powerTier: 1),
        );
        const plan = [
          PlannedTile(0, 0, 'gpu_old'),
          PlannedTile(2, 0, 'gpu_old'),
        ];
        expect(g.planBlockReason('garage', [plan.first], plan.last), isNull);
        g.s.money -= 100; // spent elsewhere since planning
        expect(g.placePlan('garage', plan), [plan.last]);
        expect(g.tileAt('garage', 0, 0), 'gpu_old');
        expect(g.tileAt('garage', 2, 0), isNull);
      },
    );
  });

  group('upgrade GPUs', () {
    const mp = {'mixed_precision'};
    test('targets the best affordable GPU and swaps the weakest first', () {
      // A 4090 and a 2060; money for a V100 at list price, and for one swap.
      final g = gameWith(
        ['G...', '....', '....', '...o'],
        money: v100Price(0) + 1,
        era: Era.garage,
        ownedUpgrades: mp,
      );
      final swaps = g.upgradePlan('garage');
      expect(swaps, [const PlannedTile(3, 3, 'gpu_v_class', replace: true)]);
      // Swapping the 4090 would be cheaper, but the 2060 is weaker.
      expect(g.planCost(swaps), closeTo(v100Price(0) - old.cost / 2, 1e-6));
    });

    test('money limit includes price growth', () {
      final rows = ['oo..', '....', '....', '....'];
      final two = v100Price(0) + v100Price(1) - 2 * old.cost / 2;
      final short = gameWith(
        rows,
        money: two - 1,
        era: Era.garage,
        ownedUpgrades: mp,
      );
      // One V100 short: two cheaper 4090 swaps add more TFLOPS than one V100.
      final cheap = short.upgradePlan('garage');
      expect(cheap.map((s) => s.tileId).toSet(), {'gpu_gamer'});
      expect(cheap, hasLength(2));
      final enough = gameWith(
        rows,
        money: two + 0.01,
        era: Era.garage,
        ownedUpgrades: mp,
      );
      final swaps = enough.upgradePlan('garage');
      expect(swaps, hasLength(2));
      expect(enough.planCost(swaps), closeTo(two, 1e-6));
      // Done: both swaps go through and spend exactly that.
      expect(enough.placePlan('garage', swaps), isEmpty);
      expect(enough.s.money, closeTo(0.01, 1e-6));
      expect(enough.tileAt('garage', 1, 0), 'gpu_v_class');
    });

    test('respects the power cap given the earlier swaps', () {
      // 4 × 0.35 kW = 1.4 kW of 1.8; each V100 swap adds 0.15 kW: two fit.
      final g = gameWith(
        ['oooo', '....', '....', '....'],
        powerTier: 0,
        era: Era.garage,
        ownedUpgrades: mp,
      );
      final swaps = g.upgradePlan('garage');
      expect(swaps.map((s) => s.tileId).toSet(), hasLength(1));
      expect(swaps, isNotEmpty);
      final after = g.withPlan('garage', swaps);
      expect(after.powerUsedKw, lessThanOrEqualTo(after.powerCapKw));
    });

    test(
      'never swaps for fewer TFLOPS, and offers nothing when nothing is better',
      () {
        final g = gameWith(
          ['VVVo', '....', '....', '....'],
          era: Era.garage,
          ownedUpgrades: mp,
        );
        expect(g.upgradePlan('garage'), [
          const PlannedTile(3, 0, 'gpu_v_class', replace: true),
        ]);
        final best = gameWith(
          ['VV..', '....', '....', '....'],
          era: Era.garage,
          ownedUpgrades: mp,
        );
        expect(best.upgradePlan('garage'), isEmpty);
        // Without the research the 4090 is the best: a 4090 room stays as is.
        final gamers = gameWith([
          'GG..',
          '....',
          '....',
          '....',
        ], era: Era.garage);
        expect(gamers.upgradePlan('garage'), isEmpty);
        // Broke: nothing either.
        final broke = gameWith(
          ['oo..', '....', '....', '....'],
          money: 10,
          era: Era.garage,
        );
        expect(broke.upgradePlan('garage'), isEmpty);
      },
    );

    test('oldest model first, then tier by tier while the money lasts', () {
      // A 2060 behind two 4090s, plenty of money: all three become V100s,
      // the 2060 first.
      final rich = gameWith(
        ['GoG.', '....', '....', '....'],
        money: 1e9,
        era: Era.garage,
        ownedUpgrades: mp,
      );
      final all = rich.upgradePlan('garage');
      expect(all.first, const PlannedTile(1, 0, 'gpu_v_class', replace: true));
      expect(all, hasLength(3));
      expect(all.map((s) => s.tileId).toSet(), {'gpu_v_class'});
      // Money for one V100 swap only: it goes to the 2060, not a 4090.
      final one = gameWith(
        ['GoG.', '....', '....', '....'],
        money: v100Price(0) - old.cost / 2 + 1,
        era: Era.garage,
        ownedUpgrades: mp,
      );
      final swaps = one.upgradePlan('garage');
      expect(swaps.map((s) => (s.x, s.y)), [(1, 0)]);
    });

    test('skips cells already in the plan and counts the plan\'s spending', () {
      final g = gameWith(
        ['oo..', '....', '....', '....'],
        era: Era.garage,
        ownedUpgrades: mp,
      );
      const first = [PlannedTile(0, 0, 'gpu_gamer', replace: true)];
      final more = g.upgradePlan('garage', plan: first);
      expect(more, [const PlannedTile(1, 0, 'gpu_v_class', replace: true)]);
      expect(g.upgradePlan('garage', max: 1), hasLength(1));
    });
  });
}
