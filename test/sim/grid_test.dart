import 'dart:math' as math;

import 'package:ai_lab_tycoon/sim/balance.dart';
import 'package:ai_lab_tycoon/sim/content.dart';
import 'package:ai_lab_tycoon/sim/game.dart';
import 'package:ai_lab_tycoon/sim/game_state.dart';
import 'package:ai_lab_tycoon/sim/grid.dart';
import 'package:flutter_test/flutter_test.dart';

import 'grid_helpers.dart';

const empty4 = ['....', '....', '....', '....'];
final empty7 = List.filled(7, '.......');

void main() {
  final gamer = tileById('gpu_gamer')!;
  final garage = roomById('garage')!;

  group('heat', () {
    test('ambient cooling is shared evenly: 3 GPUs are fine, the 4th is hot', () {
      final three = gameWith(['G.G.', '....', 'G...', '....']);
      final st = three.tileStatus('garage', 0, 0)!;
      expect(st.ambientCooling, closeTo(garage.ambientTotal / 3, 1e-9));
      expect(st.netHeat, lessThan(0));
      expect(st.speed, 1);

      final four = gameWith(['G.G.', '....', 'G.G.', '....']);
      final hot = four.tileStatus('garage', 0, 0)!;
      final net = gamer.heat - garage.ambientTotal / 4;
      expect(net, greaterThan(0));
      expect(hot.netHeat, closeTo(net, 1e-9));
      expect(hot.speed, closeTo(1 - throttleSlope * net / gamer.heat, 1e-9));
      expect(hot.throttling, isTrue);
      expect(four.rawTflops, closeTo(4 * gamer.tflops * hot.speed, 1e-6));
      expect(four.peakTflops, 4 * gamer.tflops);
    });

    test('a cooler splits its cooling evenly among adjacent GPUs', () {
      final fan = tileById('cool_fan')!;
      final g = gameWith(['GFG.', '....', 'G..G', '....']);
      final ambient = garage.ambientTotal / 4;
      for (final (x, y) in [(0, 0), (2, 0)]) {
        final st = g.tileStatus('garage', x, y)!;
        expect(st.adjacentCooling, closeTo(fan.cooling / 2, 1e-9));
        expect(st.netHeat, closeTo(gamer.heat - ambient - fan.cooling / 2, 1e-9));
      }
      expect(g.tileStatus('garage', 0, 2)!.adjacentCooling, 0);
      expect(g.tileStatus('garage', 1, 0)!.adjacentGpus, 2);

      final solo = gameWith(['GF..', '....', 'G..G', '...G']);
      expect(solo.tileStatus('garage', 0, 0)!.adjacentCooling, fan.cooling);
      expect(solo.tileStatus('garage', 0, 0)!.speed, 1);
      expect(solo.tileStatus('garage', 3, 3)!.speed, lessThan(1));
    });

    test('throttle formula and floor', () {
      expect(throttleSpeed(10, -5), 1);
      expect(throttleSpeed(10, 0), 1);
      expect(throttleSpeed(10, 5), closeTo(1 - throttleSlope * 0.5, 1e-9));
      expect(throttleSpeed(10, 100), minThrottleSpeed);
    });

    test('a packed garage of old GPUs throttles hard, coolers fix it', () {
      final hot = gameWith(['oooo', 'oooo', 'oooo', 'oooo']);
      expect(hot.tileStatus('garage', 1, 1)!.speed, lessThan(0.6));
      final cooled = gameWith(['oWoW', 'WoWo', 'oWoW', 'WoWo']);
      expect(cooled.tileStatus('garage', 0, 0)!.speed, 1);
    });

    test('central cooling cools every GPU tile, no neighbours needed', () {
      final rows = List.filled(14, 'RRRRRRRRRRRRRR');
      final hot = gameIn('hall', rows);
      expect(hot.tileStatus('hall', 5, 5)!.throttling, isTrue);
      final plant = gameIn('hall', rows, coolingTier: coolingTiers.length - 1);
      final st = plant.tileStatus('hall', 5, 5)!;
      expect(st.plantCooling, coolingTiers.last.perGpuTile);
      expect(st.throttling, isFalse);
      expect(plant.rawTflops, greaterThan(hot.rawTflops * 2));
    });

    test('central cooling tiers are bought in order and gated', () {
      final g = Game(GameState(money: 1e12));
      expect(g.coolingTiersVisible, isFalse);
      expect(g.coolingBlockReason(), contains('Unlocks in'));
      g.s.era = Era.mediumLab;
      expect(g.coolingBlockReason(), isNull);
      expect(g.buyNextCoolingTier(), isTrue);
      expect(g.cooling.id, coolingTiers[1].id);
      g.s.era = Era.bigLab;
      expect(g.buyNextCoolingTier(), isTrue);
      expect(g.coolingBlockReason(), contains('Liquid cooling'));
    });
  });

  group('one cluster, network tier', () {
    test('every GPU in the room is one cluster, wherever it sits', () {
      final g = gameWith(['G..G', '....', '.F..', 'G..G']);
      final cs = g.clusters('garage');
      expect(cs, hasLength(1));
      expect(cs.single.gpus, 4);
      expect(cs.single.isTraining, isTrue);
      expect(cs.single.gpuCells, hasLength(4));
      expect(g.tileStatus('garage', 0, 0)!.inTrainingCluster, isTrue);
      expect(g.tileStatus('garage', 1, 2)!.clusterId, isNull); // a fan
    });

    test('the network tier caps the cluster: sqrt(cap / gpus) past it', () {
      final rows = ['GGGG', 'G...', 'G...', '....'];
      final g = gameWith(rows);
      final c = g.trainingCluster!;
      expect(c.gpus, 6);
      expect(c.gpuCap, networkTiers.first.gpuCap);
      expect(c.overCap, isTrue);
      expect(c.scalingEfficiency, closeTo(math.sqrt(4 / 6), 1e-9));
      expect(c.trainingTflops, closeTo(c.effectiveTflops * c.scalingEfficiency, 1e-9));
      final before = g.trainingClusterTflops;
      expect(g.buyNextNetworkTier(), isTrue);
      expect(g.trainingCluster!.gpuCap, networkTiers[1].gpuCap);
      expect(g.trainingCluster!.scalingEfficiency, 1);
      expect(g.trainingClusterTflops, greaterThan(before * 1.2));
    });

    test('a lone tile always trains at full speed (one box)', () {
      final g = gameIn('closet', ['A......', ...List.filled(6, '.......')]);
      expect(g.trainingCluster!.gpus, 8);
      expect(g.trainingCluster!.scalingEfficiency, 1);
    });

    test('scaling efficiency formula', () {
      expect(scalingEfficiencyFor(32, 8), closeTo(0.5, 1e-12));
      expect(scalingEfficiencyFor(8, 8), 1);
    });

    test('network tiers are bought in order, gated by era and research', () {
      final g = Game(GameState(money: 1e12, networkTier: 2));
      expect(g.networkBlockReason(), contains('Unlocks in'));
      g.s.era = Era.smallLab;
      expect(g.networkBlockReason(), contains('High-speed interconnect'));
      g.s.ownedUpgrades.add('interconnect');
      expect(g.buyNextNetworkTier(), isTrue);
      expect(g.network.id, 'ib400g');
      final caps = networkTiers.map((n) => n.gpuCap).toList();
      for (var i = 1; i < caps.length; i++) {
        expect(caps[i], greaterThan(caps[i - 1]));
      }
    });

    test('training takes the run fraction; the rest serves', () {
      final g = gameIn('closet', ['AAA....', ...List.filled(6, '.......')], networkTier: networkTiers.length - 1);
      final t = g.trainingCluster!;
      expect(g.startTraining(fraction: 0.5, durationSeconds: 60), isTrue);
      expect(g.trainingTflops, closeTo(t.trainingTflops * 0.5, 1e-9));
      expect(g.servingTflops, closeTo(g.effectiveTflops * 0.5, 1e-9));
      expect(
        g.trainingFlopsPerSecond(0.5) / (t.trainingTflops * 0.5 * 1e12 * g.s.era.computeTimeScale),
        closeTo(1, 1e-12),
      );
    });

    test('derived stats are cached until the grid or a tier changes', () {
      final g = gameWith(['GG..', '....', '....', '....']);
      final first = g.grid;
      g.tick(1);
      g.s.ownedUpgrades.add('mixed_precision'); // utilization isn't cached
      expect(identical(g.grid, first), isTrue);
      g.s.networkTier = 1;
      expect(identical(g.grid, first), isFalse);
      final second = g.grid;
      g.placeTile('garage', 1, 1, 'gpu_gamer');
      expect(identical(g.grid, second), isFalse);
      expect(g.clusters('garage').single.gpus, 3);
    });
  });

  group('place, move, sell', () {
    test('block reasons are human-readable and checked in order', () {
      final g = gameWith(['G...', '....', '....', '....'], money: 100, powerTier: 0, era: Era.garage);
      expect(g.placeBlockReason('garage', 0, 0, 'cool_fan'), contains('taken'));
      expect(g.placeBlockReason('garage', 4, 0, 'cool_fan'), contains('outside'));
      expect(g.placeBlockReason('closet', 0, 0, 'srv_a_class'), contains('not in the Server closet'));
      // Unlocked parts go in any room: only cash, power, the cell and unlocks block.
      expect(g.placeBlockReason('garage', 1, 0, 'srv_a_class'), contains('Unlocks in Startup'));
      expect(g.placeBlockReason('garage', 1, 0, 'cool_fan'), contains('Costs'));
      expect(g.placeBlockReason('garage', 1, 0, 'cool_fan', ignoreMoney: true), isNull);
      g.s.money = 1e9;
      expect(g.canPlace('garage', 1, 0, 'cool_fan'), isTrue);
      for (final (x, y) in [(1, 0), (2, 0), (3, 0)]) {
        expect(g.placeTile('garage', x, y, 'gpu_gamer'), isTrue);
      }
      expect(g.placeBlockReason('garage', 0, 1, 'gpu_gamer'), contains('Not enough power'));
      expect(g.placeBlockReason('garage', 0, 1, 'gpu_gamer'), contains('Power'));
    });

    test('era, upgrade and power-tier locks name what to do', () {
      final g = gameIn('closet', empty7, era: Era.smallLab, powerTier: 2);
      expect(
        g.placeBlockReason('closet', 0, 0, 'srv_h_class'),
        'Needs power: Leased colo circuits. Move to the Colocation cage first.',
      );
      expect(g.placeBlockReason('closet', 0, 0, 'cool_rear_door'), contains('Research Liquid cooling'));
      g.s.era = Era.startup;
      g.s.users = 0;
      // The next era's gate is spelled out.
      expect(
        g.placeBlockReason('closet', 0, 0, 'srv_h_class'),
        startsWith('Unlocks in Small lab: reach rating 990'),
      );
      g.s.era = Era.garage;
      expect(g.placeBlockReason('closet', 0, 0, 'srv_a_class'), contains('own 1.05 PFLOPS of GPUs'));
    });

    test('any unlocked part goes in any room (an old card in a big hall is allowed)', () {
      final g = gameIn('hall', List.filled(14, '..............'), era: Era.mediumLab, powerTier: 4);
      expect(g.placeBlockReason('hall', 0, 0, 'gpu_gamer'), isNull);
      expect(g.placeBlockReason('hall', 0, 0, 'cool_fan'), isNull);
      // Tray order: this era's parts (and newer) first, then the older ones.
      final ids = g.tilesForRoom('hall').map((t) => t.id).toList();
      expect(ids.indexOf('rack_h_class'), lessThan(ids.indexOf('gpu_gamer')));
      expect(g.isOlderPart(gamer, 'hall'), isTrue);
      expect(g.isOlderPart(tileById('rack_h_class')!, 'hall'), isFalse);
      // Unlocked newer parts also go in an earlier room you haven't left yet.
      final early = gameIn('closet', List.filled(7, '.......'), era: Era.mediumLab, powerTier: 4);
      expect(early.placeBlockReason('closet', 0, 0, 'rack_h_class'), isNull);
      // Research still gates.
      expect(early.placeBlockReason('closet', 0, 0, 'rack_b_class'), contains('Research Liquid cooling'));
    });

    test('placing costs money; moving is free and swaps', () {
      final g = Game(GameState(money: 1000));
      expect(g.tileAt('garage', 1, 1), 'gpu_old');
      expect(g.placeTile('garage', 0, 0, 'cool_fan'), isTrue);
      expect(g.s.money, 1000 - tileById('cool_fan')!.cost);
      final money = g.s.money;
      expect(g.moveTile('garage', 0, 0, 3, 3), isTrue);
      expect(g.tileAt('garage', 3, 3), 'cool_fan');
      expect(g.moveTile('garage', 3, 3, 1, 1), isTrue); // swap
      expect(g.tileAt('garage', 1, 1), 'cool_fan');
      expect(g.tileAt('garage', 3, 3), 'gpu_old');
      expect(g.s.money, money);
      expect(g.moveTile('garage', 0, 0, 1, 0), isFalse); // nothing there
      expect(g.moveTile('garage', 1, 1, 4, 1), isFalse); // out of bounds
      expect(g.moveTile('closet', 0, 0, 1, 0), isFalse); // not here
    });

    test('selling refunds half; the last GPU stays', () {
      final g = Game(GameState(money: 0));
      expect(g.sellValue('gpu_gamer'), gamer.cost / 2);
      expect(g.sellBlockReason('garage', 1, 1), contains('last GPU'));
      expect(g.sellTile('garage', 1, 1), isFalse);
      g.s.money = 5000;
      g.placeTile('garage', 0, 0, 'gpu_gamer');
      g.placeTile('garage', 0, 1, 'cool_fan');
      final money = g.s.money;
      expect(g.sellTile('garage', 0, 1), isTrue);
      expect(g.s.money, money + tileById('cool_fan')!.cost / 2);
      expect(g.sellTile('garage', 1, 1), isTrue);
      expect(g.totalGpus, 1);
    });

    test('replacing pays the difference', () {
      final g = gameWith(['G...', '....', '....', '....'], money: 2000, powerTier: 0, era: Era.garage);
      expect(g.replaceBlockReason('garage', 1, 0, 'cool_fan'), contains('nothing there'));
      // The V100's tensor cores need mixed precision first.
      expect(g.replaceBlockReason('garage', 0, 0, 'gpu_v_class'), contains('Research Mixed precision'));
      g.s.ownedUpgrades.add('mixed_precision');
      expect(g.replaceTile('garage', 0, 0, 'gpu_v_class'), isTrue);
      expect(g.s.money, 2000 - 3000 + gamer.cost / 2);
    });

    test('liquid cooling lowers GPU power draw (not coolers)', () {
      final g = gameWith(['GG..', 'W...', '....', '....']);
      final gpuKw = 2 * gamer.powerKw;
      expect(g.powerUsedKw, closeTo(gpuKw + 0.9, 1e-9));
      g.s.ownedUpgrades.add('liquid_cooling');
      expect(g.powerUsedKw, closeTo(gpuKw * 0.85 + 0.9, 1e-9));
    });
  });

  group('moving to the next room', () {
    Game readyGarage() {
      final g = gameWith(['GFo.', '.G..', 'W..V', '....'], era: Era.startup, powerTier: 2, networkTier: 1);
      g.s.money = 1e6;
      return g;
    }

    test('only the next room; it needs its era and its price; the checklist says both', () {
      final g = Game(GameState(money: 100));
      expect(g.nextRoom!.id, 'closet');
      expect(g.roomBlockReason('colo'), 'Move to the Server closet first.');
      expect(g.roomBlockReason('garage'), contains('already in'));
      final reqs = g.moveRequirements('closet');
      expect(reqs.map((r) => r.kind), ['era', 'cash', 'power']);
      expect(reqs.map((r) => r.required), [true, true, false]);
      expect(reqs.take(2).every((r) => !r.done), isTrue);
      expect(reqs[0].line, 'Startup era: 0.03 / 1.05 PFLOPS (fill the room with faster GPUs; swap old cards and unneeded coolers for V100s)');
      expect(reqs[0].action, RequirementAction.none);
      expect(reqs[1].detail, '\$100 / \$15.0k');
      // Power is information: the bigger building lifts the limit.
      expect(reqs[2].line, 'Power limit: 10 kW → 65 kW (up to 3-phase service)');
      expect(reqs[2].done, isTrue);
      expect(reqs[2].action, RequirementAction.none);
      // The era comes first: cash alone doesn't open the closet.
      expect(g.roomBlockReason('closet'),
          'Opens in the Startup era: own 1.05 PFLOPS of GPUs (you have 30 TFLOPS).');
      g.s.money = 1e6;
      expect(g.canBuyRoom('closet'), isFalse);
      expect(g.moveTo('closet'), isFalse);
      expect(g.moveRequirements('closet')[1].done, isTrue);
      // With the era, the price is the last gate.
      g.s.era = Era.startup;
      g.s.money = 100;
      expect(g.roomBlockReason('closet'), 'Costs \$15.0k. You have \$100.');
      g.s.money = 1e6;
      expect(g.canBuyRoom('closet'), isTrue);
      expect(g.moveRequirements('closet').every((r) => r.done), isTrue);
      // A later room's era says which era comes first.
      final h = Game(GameState(money: 1e9, era: Era.startup, grids: {'closet': GameState.emptyGrid(roomById('closet')!)}));
      expect(h.roomBlockReason('colo'), startsWith('Opens in the Small lab era: reach rating 990'));
      final late = Game(GameState(money: 1e9, era: Era.garage, grids: {'closet': GameState.emptyGrid(roomById('closet')!)}));
      expect(late.roomBlockReason('colo'), 'Opens in the Small lab era (after Startup).');
      expect(late.moveRequirements('colo').first.detail, 'after Startup');
    });

    test('moving carries every tile with the same relative layout', () {
      final g = readyGarage();
      final before = <(int, int), String>{
        for (var y = 0; y < 4; y++)
          for (var x = 0; x < 4; x++)
            if (g.tileAt('garage', x, y) case final id?) (x, y): id,
      };
      final money = g.s.money;
      expect(g.moveTo('closet'), isTrue);
      expect(g.s.money, money - roomById('closet')!.cost);
      final (ox, oy) = Game.moveOffset(garage, roomById('closet')!);
      expect((ox, oy), (1, 1)); // 4×4 → 7×7
      for (final MapEntry(key: (x, y), :value) in before.entries) {
        expect(g.tileAt('closet', x + ox, y + oy), value);
      }
      final after = g.s.grids['closet']!.whereType<String>().length;
      expect(after, before.length);
      final moved = g.events.whereType<RoomMoved>().single;
      expect((moved.from.id, moved.to.id, moved.offset), ('garage', 'closet', (1, 1)));
    });

    test('the old room is gone and the training cluster is preserved', () {
      final g = readyGarage();
      final c0 = g.trainingCluster!;
      g.startTraining(fraction: 0.5, durationSeconds: 60);
      g.tick(10);
      final flops = g.s.run!.computeFlops;
      expect(g.moveTo('closet'), isTrue);
      expect(g.s.grids.keys, ['closet']);
      expect(g.isRoomOwned('garage'), isFalse);
      expect(g.ownedRooms.single.id, 'closet');
      expect(g.tileAt('garage', 1, 1), isNull);
      expect(g.placeBlockReason('garage', 0, 0, 'cool_fan'), contains('not in the Garage'));
      expect(g.roomBlockReason('garage'), contains('moved out'));
      final c1 = g.trainingCluster!;
      expect(c1.roomId, 'closet');
      expect(c1.gpus, c0.gpus);
      final (ox, oy) = Game.moveOffset(garage, roomById('closet')!);
      expect(c1.gpuCells.map((p) => (p.$1 - ox, p.$2 - oy)).toSet(), c0.gpuCells.toSet());
      // The closet's free cooling is bigger: nothing runs slower.
      expect(c1.rawTflops, greaterThanOrEqualTo(c0.rawTflops - 1e-9));
      // The run keeps going.
      expect(g.s.run!.computeFlops, flops);
      g.tick(1);
      expect(g.s.run!.computeFlops, greaterThan(flops));
    });

    test('moving is deterministic and sequential to the last room', () {
      final g = Game(GameState(money: 1e15, era: Era.globalLab, powerTier: powerTiers.length - 1));
      var (x, y) = startGpuCell;
      for (final (i, r) in rooms.indexed.skip(1)) {
        expect(g.moveTo(r.id), isTrue, reason: r.id);
        final (ox, oy) = Game.moveOffset(rooms[i - 1], r);
        x += ox;
        y += oy;
        expect(g.tileAt(r.id, x, y), 'gpu_old', reason: r.id);
      }
      expect(g.nextRoom, isNull);
      expect(g.currentRoom.id, 'gigasite');
    });

    test('every room is at least as large as the one before', () {
      for (var i = 1; i < rooms.length; i++) {
        expect(rooms[i].width, greaterThanOrEqualTo(rooms[i - 1].width));
        expect(rooms[i].height, greaterThanOrEqualTo(rooms[i - 1].height));
      }
    });
  });

  test('every room has its own GPUs and coolers', () {
    for (final r in rooms) {
      expect(r.maxPowerTier, inInclusiveRange(0, powerTiers.length - 1));
      expect(tiles.where((t) => t.isGpu && t.rooms.contains(r.id)), isNotEmpty, reason: r.id);
      expect(tiles.where((t) => t.isCooling && t.rooms.contains(r.id)), isNotEmpty, reason: r.id);
    }
    expect(maxSupplyPremium, greaterThan(1));
  });
}
