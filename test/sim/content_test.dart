import 'dart:math' as math;

import 'package:ai_lab_tycoon/sim/balance.dart';
import 'package:ai_lab_tycoon/sim/content.dart';
import 'package:ai_lab_tycoon/sim/game.dart';
import 'package:ai_lab_tycoon/sim/game_state.dart';
import 'package:ai_lab_tycoon/sim/model_design.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('content ids', () {
    void expectUnique(String what, Iterable<String> ids) {
      final seen = <String>{};
      for (final id in ids) {
        expect(seen.add(id), isTrue, reason: 'duplicate $what id "$id"');
      }
    }

    test('every content id is unique', () {
      expectUnique('tile', tiles.map((t) => t.id));
      expectUnique('room', rooms.map((r) => r.id));
      expectUnique('power tier', powerTiers.map((p) => p.id));
      expectUnique('upgrade', upgrades.map((u) => u.id));
      expectUnique('launch stunt', launchStunts.map((l) => l.id));
      expectUnique('rival snapshot', rivalLadder.map((r) => '${r.labId}/${r.model}'));
      // One namespace across hardware/power/upgrades too (icon file names
      // are prefixed, but a shared id would still be confusing).
      expectUnique('content', [
        ...tiles.map((t) => t.id),
        ...powerTiers.map((p) => p.id),
        ...upgrades.map((u) => u.id),
      ]);
    });

    test('requirements point at real upgrades', () {
      final ids = upgrades.map((u) => u.id).toSet();
      for (final u in upgrades) {
        for (final r in u.requires) {
          expect(ids, contains(r), reason: '${u.id} requires unknown $r');
        }
      }
      final roomIds = rooms.map((r) => r.id).toSet();
      for (final t in tiles) {
        for (final r in t.requires) {
          expect(ids, contains(r), reason: '${t.id} requires unknown $r');
        }
        expect(t.minPowerTier, inInclusiveRange(0, powerTiers.length - 1));
        expect(t.rooms, isNotEmpty, reason: t.id);
        expect(roomIds, containsAll(t.rooms), reason: t.id);
        // A tile never unlocks before every room it fits in could.
        expect(
          t.rooms.map((r) => roomById(r)!.era.index).reduce(math.min),
          lessThanOrEqualTo(t.era.index),
          reason: t.id,
        );
      }
    });

    test('tile and room ids from docs/GRID.md are all present (art uses them)', () {
      const gridTiles = [
        'gpu_old',
        'gpu_gamer',
        'gpu_v_class',
        'srv_a_class',
        'srv_h_class',
        'rack_h_class',
        'rack_b_class',
        'rack_r_class',
        'pod_b_class',
        'bldg_r_class',
        'bldg_p_class',
        'bldg_s_class',
        'mod_z_class',
        'cool_fan',
        'cool_window_ac',
        'cool_crac',
        'cool_rear_door',
        'cool_liquid',
        'cool_chiller',
        'cool_tower',
        'cool_dry',
        'cool_radiator',
      ];
      const gridRooms = ['garage', 'closet', 'colo', 'hall', 'campus', 'gigasite', 'orbital'];
      expect(tiles.map((t) => t.id), containsAll(gridTiles));
      expect(rooms.map((r) => r.id), gridRooms);
    });

    test('ids existing saves rely on are still present', () {
      const v1Power = ['outlet', 'panel', 'office', 'colo', 'hall', 'campus', 'plant'];
      const v6Power = [...v1Power, 'gw_campus', 'nuclear_restart', 'multi_site'];
      const v1Upgrades = [
        'mixed_precision',
        'batching',
        'kv_cache',
        'lora',
        'common_crawl',
        'cuda_kernels',
        'flash_attention',
        'quantization',
        'interconnect',
        'liquid_cooling',
        'code_data',
        'dedup',
        'instruction_tuning',
        'rlhf',
        'moe',
        'fp8',
        'parallelism',
        'distillation',
        'speculative',
        'synthetic_data',
        'rlaif',
        'reasoning',
      ];
      // Power tiers are saved by index: the v1 tiers must keep their slots.
      expect(powerTiers.take(v6Power.length).map((p) => p.id), v6Power);
      expect(upgrades.map((u) => u.id), containsAll(v1Upgrades));
    });

    test('upgrade count stays reasonable and blurbs are one-liners', () {
      expect(upgrades.length, inInclusiveRange(25, 40));
      for (final u in upgrades) {
        expect(u.blurb.length, lessThanOrEqualTo(140), reason: u.id);
        expect(u.blurb, isNot(contains('\n')), reason: u.id);
      }
      for (final t in tiles) {
        expect(t.blurb.length, inInclusiveRange(20, 140), reason: t.id);
        expect(t.blurb, isNot(contains('\n')), reason: t.id);
      }
    });

    test('tile numbers are consistent with their kind', () {
      for (final t in tiles) {
        expect(t.cost, greaterThan(0), reason: t.id);
        expect(t.powerKw, greaterThan(0), reason: t.id);
        switch (t.kind) {
          case TileKind.gpu:
            expect(t.tflops, greaterThan(0), reason: t.id);
            expect(t.heat, greaterThan(0), reason: t.id);
            expect(t.gpusPerTile, greaterThanOrEqualTo(1), reason: t.id);
            // Per-GPU numbers stay in real-world ranges; the speculative
            // (sci-fi) tiers past Rubin may beat them, and say so.
            // (A speculative "GPU" is whatever package the tier is built
            // from: photonic stacks, cryo-logic chips, orbital modules.)
            expect(t.tflops / t.gpusPerTile, inInclusiveRange(20, t.speculative ? 2e6 : 4000), reason: t.id);
            expect(t.powerKw / t.gpusPerTile, inInclusiveRange(t.speculative ? 0.05 : 0.2, t.speculative ? 40 : 4),
                reason: t.id);
          case TileKind.cooling:
            expect(t.cooling, greaterThan(0), reason: t.id);
        }
        // Made-up tech comes last and is the endgame only.
        if (t.speculative) {
          expect(t.era, Era.globalLab, reason: t.id);
          expect(t.requires, isNotEmpty, reason: t.id);
        }
      }
      final gpus = tiles.where((t) => t.isGpu).toList();
      expect(gpus.skipWhile((t) => !t.speculative).every((t) => t.speculative), isTrue);
      // Network tiers grow: copper 2–4 GPUs ... optical in the millions,
      // gated in era order, with ids the cable art uses.
      for (var i = 1; i < networkTiers.length; i++) {
        expect(networkTiers[i].gpuCap, greaterThan(networkTiers[i - 1].gpuCap));
        expect(networkTiers[i].era.index, greaterThanOrEqualTo(networkTiers[i - 1].era.index));
        expect(networkTiers[i].cost, greaterThan(networkTiers[i - 1].cost));
      }
      expect(networkTiers.first.gpuCap, inInclusiveRange(2, 4));
      expect(networkTiers.first.cost, 0);
      expect(networkTiers.last.gpuCap, greaterThanOrEqualTo(1e6));
      expect(networkTiers.map((n) => n.id), ['copper1g', 'copper10g', 'fiber100g', 'ib400g', 'ibspine', 'nvlink', 'optical']);
      // Central cooling grows too; tier 0 is free room air.
      expect(coolingTiers.first.perGpuTile, 0);
      for (var i = 1; i < coolingTiers.length; i++) {
        expect(coolingTiers[i].perGpuTile, greaterThan(coolingTiers[i - 1].perGpuTile));
      }
      expect(coolingTiers.skip(1).map((c) => c.id), ['chiller', 'tower', 'liquid', 'dry', 'cryo']);
    });

    test('power tiers grow and newer GPUs dominate older ones', () {
      for (var i = 1; i < powerTiers.length; i++) {
        expect(powerTiers[i].capacityKw, greaterThan(powerTiers[i - 1].capacityKw));
        expect(powerTiers[i].era.index, greaterThanOrEqualTo(powerTiers[i - 1].era.index));
      }
      expect(powerTiers.last.capacityKw, greaterThanOrEqualTo(3e6)); // GW era
      // Newer GPUs win per kW (the old 2060 is the cheap, hot trap).
      final gpus = tiles.where((t) => t.isGpu).toList();
      for (var i = 1; i < gpus.length; i++) {
        final a = gpus[i - 1], b = gpus[i];
        expect(b.tflopsPerKw, greaterThan(a.tflopsPerKw), reason: '${b.id} should beat ${a.id} per kW');
      }
      final old = tileById('gpu_old')!, gamer = tileById('gpu_gamer')!;
      expect(old.cost, lessThan(gamer.cost));
      expect(old.heat, greaterThan(gamer.heat));
    });
  });

  group('the next tier is more bang for the buck (hard to get comes from gates)', () {
    // At list price, in content order (era by era): every newer tier
    // delivers more per dollar than the one before it, no exceptions.
    void rising<T>(String what, List<T> tiers, String Function(T) id, double Function(T) perDollar) {
      for (var i = 1; i < tiers.length; i++) {
        expect(perDollar(tiers[i]), greaterThan(perDollar(tiers[i - 1])),
            reason: '$what: ${id(tiers[i])} should beat ${id(tiers[i - 1])} per \$');
      }
    }

    test('GPUs: TFLOPS per \$', () {
      final gpus = tiles.where((t) => t.isGpu).toList();
      expect(gpus.map((t) => t.era.index).toList(), orderedEquals([...gpus.map((t) => t.era.index)]..sort()));
      rising('GPU', gpus, (t) => t.id, (t) => t.tflops / t.cost);
    });

    test('coolers: cooling per \$', () {
      final coolers = tiles.where((t) => t.isCooling).toList();
      expect(coolers.map((t) => t.era.index).toList(), orderedEquals([...coolers.map((t) => t.era.index)]..sort()));
      rising('cooler', coolers, (t) => t.id, (t) => t.cooling / t.cost);
    });

    test('network tiers: GPUs fed per \$', () {
      rising('network', networkTiers.where((n) => n.cost > 0).toList(), (n) => n.id, (n) => n.gpuCap / n.cost);
    });

    test('central cooling: cooling per GPU tile per \$', () {
      rising('cooling plant', coolingTiers.where((c) => c.cost > 0).toList(), (c) => c.id, (c) => c.perGpuTile / c.cost);
    });

    test('power tiers: kW per \$', () {
      rising('power', powerTiers.where((p) => p.cost > 0).toList(), (p) => p.id, (p) => p.capacityKw / p.cost);
    });

    test('newer tiers are gated: era, research, power tier or a steeper supply crunch', () {
      // Every GPU after the garage's first needs something beyond money.
      for (final t in tiles.where((t) => t.isGpu && t.id != 'gpu_old')) {
        final gated = t.era.index > 0 || t.requires.isNotEmpty || t.minPowerTier > 0 || t.priceGrowth > 0;
        expect(gated, isTrue, reason: t.id);
        expect(t.priceGrowth, greaterThan(0), reason: '${t.id}: no supply crunch');
      }
    });
  });

  group('eras', () {
    test('every era unlocks a room, GPU and cooling tiles, a power tier and 3-7 upgrades', () {
      for (final era in Era.values) {
        // One room per era opens with it; the orbital station is an extra,
        // post-game room in the last era (gated by research and fill).
        expect(rooms.where((r) => r.era == era && r.requires.isEmpty), hasLength(1), reason: era.name);
        for (final kind in TileKind.values) {
          expect(tiles.where((t) => t.era == era && t.kind == kind), isNotEmpty, reason: '${era.name} ${kind.name}');
        }
        expect(powerTiers.where((p) => p.era == era), isNotEmpty, reason: era.name);
        // 7: the Medium lab also has Data mixture ablations (run-phase
        // unlock); the Frontier also carries the speculative hardware research.
        expect(upgrades.where((u) => u.era == era).length, inInclusiveRange(3, era == Era.globalLab ? 8 : 7),
            reason: era.name);
      }
    });

    test('the post-game orbital station comes last, behind research and a full gigasite', () {
      final extra = rooms.where((r) => r.requires.isNotEmpty).toList();
      expect(extra.map((r) => r.id), ['orbital']);
      final orbital = extra.single;
      expect(rooms.last, same(orbital));
      expect(orbital.era, Era.values.last);
      expect(orbital.fromFill, inInclusiveRange(0.5, 1));
      expect(orbital.speculative, isTrue);
      final ids = upgrades.map((u) => u.id).toSet();
      expect(ids, containsAll(orbital.requires));
      // Orbit-only parts can't be placed anywhere else.
      for (final t in tiles.where((t) => t.nativeOnly)) {
        expect(t.rooms, {'orbital'}, reason: t.id);
      }
    });

    test('nothing requires an upgrade from a later era', () {
      final byId = {for (final u in upgrades) u.id: u};
      for (final u in upgrades) {
        for (final r in u.requires) {
          expect(byId[r]!.era.index, lessThanOrEqualTo(u.era.index), reason: '${u.id} needs $r');
        }
      }
      for (final t in tiles) {
        for (final r in t.requires) {
          expect(byId[r]!.era.index, lessThanOrEqualTo(t.era.index), reason: '${t.id} needs $r');
        }
        expect(powerTiers[t.minPowerTier].era.index, lessThanOrEqualTo(t.era.index), reason: t.id);
      }
      // Each room's electrical service takes every power tier of its own
      // era (no era needs a place it hasn't unlocked yet), and grows.
      for (var i = 0; i < rooms.length; i++) {
        final r = rooms[i];
        expect(r.maxPowerTier, inInclusiveRange(0, powerTiers.length - 1), reason: r.id);
        if (i > 0) expect(r.maxPowerTier, greaterThan(rooms[i - 1].maxPowerTier), reason: r.id);
        for (var p = 0; p < powerTiers.length; p++) {
          // (Tiers only the post-game station takes are exempt.)
          if (Game.roomForPowerTier(p).requires.isNotEmpty) continue;
          if (powerTiers[p].era.index <= r.era.index) {
            expect(p, lessThanOrEqualTo(r.maxPowerTier), reason: '${r.id} takes ${powerTiers[p].id}');
          }
        }
      }
      expect(rooms.last.maxPowerTier, powerTiers.length - 1);
      // Power tiers are named after the supply, never after a place you
      // move to later (the garage outlet is the garage's own).
      for (final p in powerTiers) {
        for (final r in rooms.skip(1)) {
          expect(p.name.toLowerCase(), isNot(contains(r.name.toLowerCase())), reason: p.id);
        }
      }
      for (final n in [...networkTiers.map((n) => (n.id, n.era, n.requires)), ...coolingTiers.map((c) => (c.id, c.era, c.requires))]) {
        for (final r in n.$3) {
          expect(byId[r]!.era.index, lessThanOrEqualTo(n.$2.index), reason: '${n.$1} needs $r');
        }
      }
    });

    test('labels and durations exist for every era', () {
      for (final era in Era.values) {
        expect(era.label, isNotEmpty);
        expect(era.runDurations, hasLength(3));
        expect(era.computeTimeScale, greaterThan(0));
      }
    });
  });

  group('rival ladder', () {
    test('rivals are spread over the eras in order; the big labs meet in Big lab', () {
      for (var i = 1; i < rivalLadder.length; i++) {
        expect(rivalLadder[i].era.index, greaterThanOrEqualTo(rivalLadder[i - 1].era.index));
      }
      for (final era in Era.values) {
        expect(rivalLadder.where((r) => r.era == era), isNotEmpty, reason: era.name);
      }
      final big = rivalLadder.where((r) => r.era == Era.bigLab).map((r) => r.lab).toSet();
      expect(big, containsAll(['ClosedAI', 'Anthropomorphic']));
      final frontier = rivalLadder.where((r) => r.era == Era.globalLab).map((r) => r.lab).toSet();
      expect(frontier, containsAll(['ClosedAI', 'Anthropomorphic', 'Gogol DeepThought']));
      expect(rivalLadder.last.era, Era.globalLab);
    });

    test('has 16-22 snapshots from 2017 to 2026', () {
      expect(rivalLadder.length, inInclusiveRange(16, 22));
      expect(rivalLadder.first.lab, 'Hugging Hands Collective');
      expect(rivalLadder.first.year, 2017);
      expect(rivalLadder.last.year, 2026);
    });

    test('difficulty is monotonic', () {
      var maxUsersSoFar = 0.0;
      for (var i = 0; i < rivalLadder.length; i++) {
        final r = rivalLadder[i];
        if (i > 0) {
          final prev = rivalLadder[i - 1];
          expect(
            r.rating,
            greaterThan(prev.rating),
            reason: '${r.model} must be harder than ${prev.model}',
          );
          expect(r.year, greaterThanOrEqualTo(prev.year), reason: r.model);
        }
        // Users mostly climb; real dips (small consumer apps) are allowed but
        // never absurd.
        expect(r.users, greaterThanOrEqualTo(0.1 * maxUsersSoFar), reason: r.model);
        maxUsersSoFar = math.max(maxUsersSoFar, r.users);
        expect(r.users, lessThanOrEqualTo(maxUsers));
        expect(r.quip, isNotEmpty, reason: r.model);
        expect(r.gpus, greaterThan(0), reason: r.model);
      }
      // The two big user milestones are the last word.
      expect(rivalLadder.last.users, maxUsersSoFar);
    });

    test('ratings come from training FLOPs through the game formula', () {
      for (final r in rivalLadder) {
        expect(r.trainingFlops, greaterThan(0), reason: r.model);
        final expected =
            ratingBase +
            ratingPerDoubling * (math.log(r.trainingFlops / startEffectiveCompute) / math.ln2) +
            r.postTrainingBonus;
        expect(r.rating, closeTo(expected, 1.0), reason: r.model);
      }
    });

    test('the final rival is reachable with the full upgrade stack and a good design', () {
      final s = GameState(
        ownedUpgrades: allUpgrades.map((u) => u.id).toSet(),
        era: Era.globalLab,
        networkTier: networkTiers.length - 1,
      );
      final g = Game(s);
      // Data-optimal compute (no diminishing returns yet) with every upgrade
      // and the best design for rating.
      final raw = g.dataOptimalCompute / g.trainEffMult;
      final spec = ModelSpec.bestGuessFor(g.designContextFor(raw), serveWeight: 0, demandWeight: 0);
      expect(g.predictRatingForFlops(raw, spec), greaterThan(rivalLadder.last.rating));
    });
  });
}
