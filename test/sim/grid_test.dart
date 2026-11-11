import 'dart:math' as math;

import 'package:ai_lab_tycoon/sim/content.dart';
import 'package:ai_lab_tycoon/sim/game.dart';
import 'package:ai_lab_tycoon/sim/game_state.dart';
import 'package:ai_lab_tycoon/sim/grid.dart';
import 'package:flutter_test/flutter_test.dart';

import 'grid_helpers.dart';

const empty4 = ['....', '....', '....', '....'];

void main() {
  final gamer = tileById('gpu_gamer')!;
  final garage = roomById('garage')!;

  group('heat', () {
    test('ambient cooling is shared evenly: 3 GPUs are fine, the 4th is hot', () {
      final three = gameWith({
        'garage': ['G.G.', '....', 'G...', '....'],
      });
      final st = three.tileStatus('garage', 0, 0)!;
      expect(st.ambientCooling, closeTo(garage.ambientTotal / 3, 1e-9));
      expect(st.netHeat, lessThan(0));
      expect(st.speed, 1);

      final four = gameWith({
        'garage': ['G.G.', '....', 'G.G.', '....'],
      });
      final hot = four.tileStatus('garage', 0, 0)!;
      final net = gamer.heat - garage.ambientTotal / 4;
      expect(net, greaterThan(0));
      expect(hot.netHeat, closeTo(net, 1e-9));
      expect(hot.speed, closeTo(1 - 0.7 * net / gamer.heat, 1e-9));
      expect(hot.throttling, isTrue);
      expect(four.rawTflops, closeTo(4 * gamer.tflops * hot.speed, 1e-6));
      expect(four.peakTflops, 4 * gamer.tflops);
    });

    test('a cooler splits its cooling evenly among adjacent GPUs', () {
      final fan = tileById('cool_fan')!;
      final g = gameWith({
        'garage': ['GFG.', '....', 'G..G', '....'],
      });
      final ambient = garage.ambientTotal / 4;
      for (final (x, y) in [(0, 0), (2, 0)]) {
        final st = g.tileStatus('garage', x, y)!;
        expect(st.adjacentCooling, closeTo(fan.cooling / 2, 1e-9));
        expect(st.netHeat, closeTo(gamer.heat - ambient - fan.cooling / 2, 1e-9));
      }
      // Not next to the fan: ambient only.
      expect(g.tileStatus('garage', 0, 2)!.adjacentCooling, 0);
      expect(g.tileStatus('garage', 1, 0)!.adjacentGpus, 2);

      // One neighbour gets the whole fan.
      final solo = gameWith({
        'garage': ['GF..', '....', 'G..G', '...G'],
      });
      expect(solo.tileStatus('garage', 0, 0)!.adjacentCooling, fan.cooling);
      expect(solo.tileStatus('garage', 0, 0)!.speed, 1);
      expect(solo.tileStatus('garage', 3, 3)!.speed, lessThan(1));
    });

    test('throttle formula and floor', () {
      expect(throttleSpeed(10, -5), 1);
      expect(throttleSpeed(10, 0), 1);
      expect(throttleSpeed(10, 5), closeTo(0.65, 1e-9));
      expect(throttleSpeed(10, 10), closeTo(minThrottleSpeed, 1e-9));
      expect(throttleSpeed(10, 100), minThrottleSpeed);
    });

    test('a packed garage of old GPUs throttles hard, coolers fix it', () {
      final hot = gameWith({
        'garage': ['oooo', 'oooo', 'oooo', 'oooo'],
      });
      final s = hot.tileStatus('garage', 1, 1)!;
      expect(s.speed, lessThan(0.6));
      final cooled = gameWith({
        'garage': ['oWoW', 'WoWo', 'oWoW', 'WoWo'],
      });
      expect(cooled.tileStatus('garage', 0, 0)!.speed, 1);
    });
  });

  group('clusters', () {
    test('GPU-to-GPU adjacency alone does not connect', () {
      final g = gameWith({
        'garage': ['GG..', '....', '....', '....'],
      });
      final cs = g.clusters('garage');
      expect(cs, hasLength(2));
      expect(cs.every((c) => !c.networked && c.gpus == 1), isTrue);
      expect(
        g.tileStatus('garage', 0, 0)!.clusterId,
        isNot(g.tileStatus('garage', 1, 0)!.clusterId),
      );
    });

    test('a switch joins the GPUs around it', () {
      final g = gameWith({
        'garage': ['G5G.', '.G..', '....', '....'],
      });
      final cs = g.clusters('garage');
      expect(cs, hasLength(1));
      final c = cs.single;
      expect(c.gpus, 3);
      expect(c.gpuCap, tileById('net_5g')!.gpuCap);
      expect(c.scalingEfficiency, 1);
      expect(c.gpuCells, containsAll([(0, 0), (2, 0), (1, 1)]));
      expect(c.switchCells, [(1, 0)]);
      expect(g.tileStatus('garage', 1, 0)!.clusterId, c.id);
    });

    test('switch networks merge through switches and through a shared GPU', () {
      // Two separate switches, bridged by the GPU at (2,0).
      final bridged = gameWith({
        'garage': ['G5G5', '...G', 'G5..', '....'],
      });
      final cs = bridged.clusters('garage')..sort((a, b) => b.gpus.compareTo(a.gpus));
      expect(cs, hasLength(2));
      expect(cs.first.gpus, 3); // (0,0), (2,0), (3,1)
      expect(cs.first.switchCells, hasLength(2));
      expect(cs.last.gpus, 1); // (0,2) on its own switch
      expect(cs.last.networked, isTrue);

      // Adjacent switches link up.
      final linked = gameWith({
        'garage': ['G55G', '....', '....', '....'],
      });
      expect(linked.clusters('garage').single.gpus, 2);
    });

    test('bottleneck: the slowest switch caps the whole cluster', () {
      final rows = ['GhGt', '.G.G', 'GtG.', '....'];
      final g = gameWith({'garage': rows});
      final c = g.clusters('garage').single;
      expect(c.gpus, 6);
      expect(c.gpuCap, tileById('net_home')!.gpuCap);
      expect(c.bottleneckTileId, 'net_home');
      expect(c.scalingEfficiency, closeTo(math.sqrt(4 / 6), 1e-9));
      expect(c.trainingTflops, closeTo(c.effectiveTflops * c.scalingEfficiency, 1e-9));

      // Upgrade the router: no more bottleneck.
      expect(g.replaceTile('garage', 1, 0, 'net_10g'), isTrue);
      final c2 = g.clusters('garage').single;
      expect(c2.gpuCap, 32);
      expect(c2.scalingEfficiency, 1);
    });

    test('scaling efficiency matches the GRID.md example', () {
      // "Your 5 Gbit switch can keep 8 GPUs fed. With 32 GPUs, training runs
      // at 50%."
      expect(scalingEfficiencyFor(32, 8), closeTo(0.5, 1e-12));
      expect(scalingEfficiencyFor(8, 8), 1);
    });

    test('training uses the best cluster across rooms; the rest serves', () {
      final g = gameWith({
        'garage': ['G5G.', '.G..', '....', '....'],
        'closet': ['AxA...', '......', '......', '......', '......', 'A.....'],
      });
      final t = g.trainingCluster!;
      expect(t.roomId, 'closet');
      expect(t.gpus, 16);
      expect(t.isTraining, isTrue);
      expect(g.clusters('garage').single.isTraining, isFalse);
      expect(g.tileStatus('closet', 0, 0)!.inTrainingCluster, isTrue);
      expect(g.tileStatus('closet', 0, 5)!.inTrainingCluster, isFalse);
      // The pick is the max of effective TFLOPS × scaling efficiency.
      final all = [for (final r in g.ownedRooms) ...g.clusters(r.id)];
      final best = all.map((c) => c.trainingTflops).reduce(math.max);
      expect(t.trainingTflops, closeTo(best, 1e-9));

      // Training takes the committed fraction of that cluster only.
      expect(g.startTraining(fraction: 0.5, durationSeconds: 60), isTrue);
      expect(g.trainingTflops, closeTo(t.trainingTflops * 0.5, 1e-9));
      expect(g.servingTflops, closeTo(g.effectiveTflops - t.effectiveTflops * 0.5, 1e-9));
      expect(
        g.trainingFlopsPerSecond(0.5) / (t.trainingTflops * 0.5 * 1e12 * 1440),
        closeTo(1, 1e-12),
      );
    });

    test('a well-networked block beats a bigger bottlenecked one', () {
      // 6 GPUs behind a home router (cap 4) train at sqrt(4/6) ≈ 82%.
      final g = gameWith({
        'garage': ['GhGt', '.G.G', 'GtG.', '....'],
      });
      final bottlenecked = g.trainingClusterTflops;
      g.replaceTile('garage', 1, 0, 'net_5g'); // cap 8 ≥ 6 GPUs
      expect(g.trainingClusterTflops, greaterThan(bottlenecked * 1.2));
    });

    test('derived stats are cached until the grid changes', () {
      final g = gameWith({
        'garage': ['G5G.', '....', '....', '....'],
      });
      final first = g.grid;
      g.tick(1);
      g.s.ownedUpgrades.add('mixed_precision'); // utilization isn't cached
      expect(identical(g.grid, first), isTrue);
      g.placeTile('garage', 1, 1, 'gpu_gamer');
      expect(identical(g.grid, first), isFalse);
      expect(g.clusters('garage').single.gpus, 3);
    });
  });

  group('place, move, sell', () {
    test('block reasons are human-readable and checked in order', () {
      final g = gameWith(
        {
          'garage': ['G...', '....', '....', '....'],
        },
        money: 100,
        powerTier: 0,
        era: Era.garage,
      );
      expect(g.placeBlockReason('garage', 0, 0, 'cool_fan'), contains('taken'));
      expect(g.placeBlockReason('garage', 4, 0, 'cool_fan'), contains('outside'));
      expect(
        g.placeBlockReason('closet', 0, 0, 'srv_a_class'),
        contains('Buy the Server closet first'),
      );
      expect(
        g.placeBlockReason('garage', 1, 0, 'srv_a_class'),
        contains('doesn\'t fit in the Garage'),
      );
      expect(g.placeBlockReason('garage', 1, 0, 'cool_fan'), contains('Costs'));
      expect(g.placeBlockReason('garage', 1, 0, 'cool_fan', ignoreMoney: true), isNull);
      g.s.money = 1e9;
      expect(g.canPlace('garage', 1, 0, 'cool_fan'), isTrue);
      // Power: the outlet holds 4 gaming GPUs.
      for (final (x, y) in [(1, 0), (2, 0), (3, 0)]) {
        expect(g.placeTile('garage', x, y, 'gpu_gamer'), isTrue);
      }
      expect(g.placeBlockReason('garage', 0, 1, 'gpu_gamer'), contains('Not enough power'));
      expect(g.powerUsedKw, lessThanOrEqualTo(g.powerCapKw + 1e-9));
    });

    test('era, upgrade and power-tier locks', () {
      final g = gameWith(
        {'garage': empty4, 'closet': List.filled(6, '......')},
        era: Era.startup,
        powerTier: 2,
      );
      expect(
        g.placeBlockReason('closet', 0, 0, 'net_ib'),
        contains('Requires High-speed interconnect'),
      );
      g.s.ownedUpgrades.add('interconnect');
      expect(g.placeBlockReason('closet', 0, 0, 'net_ib'), isNull);
      expect(
        g.placeBlockReason('closet', 0, 0, 'srv_h_class'),
        contains('Colocation cage power tier'),
      );
      expect(g.placeBlockReason('closet', 0, 0, 'cool_rear_door'), contains('Liquid cooling'));
      g.s.era = Era.garage;
      expect(g.placeBlockReason('closet', 0, 0, 'srv_a_class'), contains('Startup era'));
    });

    test('placing costs money; moving is free and swaps', () {
      final g = Game(GameState(money: 1000));
      expect(g.tileAt('garage', 1, 1), 'gpu_gamer');
      expect(g.placeTile('garage', 0, 0, 'net_home'), isTrue);
      expect(g.s.money, 1000 - tileById('net_home')!.cost);
      final money = g.s.money;
      expect(g.moveTile('garage', 0, 0, 3, 3), isTrue);
      expect(g.tileAt('garage', 3, 3), 'net_home');
      expect(g.tileAt('garage', 0, 0), isNull);
      expect(g.moveTile('garage', 3, 3, 1, 1), isTrue); // swap
      expect(g.tileAt('garage', 1, 1), 'net_home');
      expect(g.tileAt('garage', 3, 3), 'gpu_gamer');
      expect(g.s.money, money);
      expect(g.moveTile('garage', 0, 0, 1, 0), isFalse); // nothing there
      expect(g.moveTile('garage', 1, 1, 4, 1), isFalse); // out of bounds
      expect(g.moveTile('closet', 0, 0, 1, 0), isFalse); // not owned
    });

    test('selling refunds half; the last GPU stays', () {
      final g = Game(GameState(money: 0));
      expect(g.sellValue('gpu_gamer'), gamer.cost / 2);
      expect(g.sellBlockReason('garage', 1, 1), contains('last GPU'));
      expect(g.sellTile('garage', 1, 1), isFalse);
      expect(g.sellTile('garage', 0, 0), isFalse); // empty
      g.s.money = 5000;
      g.placeTile('garage', 0, 0, 'gpu_gamer');
      g.placeTile('garage', 0, 1, 'cool_fan');
      final money = g.s.money;
      expect(g.sellTile('garage', 0, 1), isTrue);
      expect(g.s.money, money + tileById('cool_fan')!.cost / 2);
      expect(g.sellTile('garage', 1, 1), isTrue);
      expect(g.totalGpus, 1);
    });

    test('replacing pays the difference and only needs the extra power', () {
      final g = gameWith(
        {
          'garage': ['G...', '....', '....', '....'],
        },
        money: 2000,
        powerTier: 0,
        era: Era.garage,
      );
      expect(g.replaceBlockReason('garage', 1, 0, 'net_5g'), contains('nothing there'));
      expect(g.replaceTile('garage', 0, 0, 'gpu_v_class'), isTrue);
      expect(g.s.money, 2000 - 3000 + gamer.cost / 2);
      expect(g.tileAt('garage', 0, 0), 'gpu_v_class');
    });

    test('rooms are gated by era, power tier and money', () {
      final g = Game(GameState(money: 1e9));
      expect(g.isRoomOwned('garage'), isTrue);
      expect(g.roomBlockReason('closet'), contains('Startup era'));
      g.s.era = Era.startup;
      expect(g.roomBlockReason('closet'), contains('Office'));
      g.s.powerTier = 2;
      expect(g.canBuyRoom('closet'), isTrue);
      g.s.money = 10;
      expect(g.roomBlockReason('closet'), contains('Costs'));
      g.s.money = 1e9;
      expect(g.buyRoom('closet'), isTrue);
      expect(g.isRoomOwned('closet'), isTrue);
      expect(g.s.money, 1e9 - roomById('closet')!.cost);
      expect(g.buyRoom('closet'), isFalse);
      expect(g.clusters('closet'), isEmpty);
      expect(g.placeTile('closet', 2, 2, 'srv_a_class'), isTrue);
    });

    test('the power cap is global across rooms', () {
      final g = gameWith(
        {
          'garage': ['VVVV', 'VVVV', 'VVVV', '....'],
          'closet': List.filled(6, '......'),
        },
        era: Era.startup,
        powerTier: 2,
      ); // 40 kW
      final garageKw = g.powerUsedKw;
      expect(garageKw, closeTo(12 * 0.5, 1e-9));
      final a = tileById('srv_a_class')!;
      final fit = ((g.powerCapKw - garageKw) / a.powerKw).floor();
      for (var i = 0; i < fit; i++) {
        expect(g.placeTile('closet', i, 0, 'srv_a_class'), isTrue);
      }
      expect(g.placeBlockReason('closet', 0, 1, 'srv_a_class'), contains('Not enough power'));
      // Freeing garage power makes room in the closet.
      for (var y = 0; y < 3; y++) {
        for (var x = 0; x < 4; x++) {
          expect(g.sellTile('garage', x, y), isTrue);
        }
      }
      expect(g.canPlace('closet', 0, 1, 'srv_a_class'), isTrue);
    });

    test('liquid cooling lowers GPU power draw (not cooling or network)', () {
      final g = gameWith({
        'garage': ['G5G.', 'W...', '....', '....'],
      });
      final gpuKw = 2 * gamer.powerKw;
      final otherKw = 0.02 + 0.9;
      expect(g.powerUsedKw, closeTo(gpuKw + otherKw, 1e-9));
      g.s.ownedUpgrades.add('liquid_cooling');
      expect(g.powerUsedKw, closeTo(gpuKw * 0.85 + otherKw, 1e-9));
    });
  });

  group('early game teaches switches and fans', () {
    test('start: one GPU trains alone, cash for a fan or a router', () {
      final g = Game();
      expect(g.totalGpus, 1);
      expect(g.trainingCluster!.gpus, 1);
      expect(g.s.money, greaterThanOrEqualTo(tileById('cool_fan')!.cost));
      expect(g.s.money, greaterThanOrEqualTo(tileById('net_home')!.cost));
    });

    test('a 2nd GPU only trains together once a switch joins them', () {
      final g = Game(GameState(money: 1e4));
      g.placeTile('garage', 3, 1, 'gpu_gamer');
      final solo = g.trainingClusterTflops;
      expect(g.trainingCluster!.gpus, 1);
      g.placeTile('garage', 2, 1, 'net_home');
      expect(g.trainingCluster!.gpus, 2);
      expect(g.trainingClusterTflops, closeTo(2 * solo, 1e-9));
    });
  });

  test('every room fits its era and power tiers; tiles fit their rooms', () {
    for (final r in rooms) {
      expect(r.minPowerTier, inInclusiveRange(0, powerTiers.length - 1));
      expect(r.width * r.height, r.cells);
      expect(tiles.where((t) => t.isGpu && t.rooms.contains(r.id)), isNotEmpty, reason: r.id);
      expect(tiles.where((t) => t.isCooling && t.rooms.contains(r.id)), isNotEmpty, reason: r.id);
      expect(tiles.where((t) => t.isNetwork && t.rooms.contains(r.id)), isNotEmpty, reason: r.id);
    }
  });
}
