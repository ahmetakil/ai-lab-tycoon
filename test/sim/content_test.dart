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
        'cool_fan',
        'cool_window_ac',
        'cool_crac',
        'cool_rear_door',
        'cool_liquid',
        'cool_chiller',
        'cool_tower',
      ];
      const gridRooms = ['garage', 'closet', 'colo', 'hall', 'campus', 'gigasite'];
      expect(tiles.map((t) => t.id), containsAll(gridTiles));
      expect(rooms.map((r) => r.id), gridRooms);
    });

    test('ids existing saves rely on are still present', () {
      const v1Power = ['outlet', 'panel', 'office', 'colo', 'hall', 'campus', 'plant'];
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
      expect(powerTiers.take(v1Power.length).map((p) => p.id), v1Power);
      expect(upgrades.map((u) => u.id), containsAll(v1Upgrades));
    });

    test('upgrade count stays reasonable and blurbs are one-liners', () {
      expect(upgrades.length, inInclusiveRange(25, 36));
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
            // Per-GPU numbers stay in real-world ranges.
            expect(t.tflops / t.gpusPerTile, inInclusiveRange(20, 4000), reason: t.id);
            expect(t.powerKw / t.gpusPerTile, inInclusiveRange(0.2, 4), reason: t.id);
          case TileKind.cooling:
            expect(t.cooling, greaterThan(0), reason: t.id);
        }
      }
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
      expect(coolingTiers.skip(1).map((c) => c.id), ['chiller', 'tower', 'liquid', 'dry']);
    });

    test('power tiers grow and newer GPUs dominate older ones', () {
      for (var i = 1; i < powerTiers.length; i++) {
        expect(powerTiers[i].capacityKw, greaterThan(powerTiers[i - 1].capacityKw));
        expect(powerTiers[i].era.index, greaterThanOrEqualTo(powerTiers[i - 1].era.index));
      }
      expect(powerTiers.last.capacityKw, greaterThanOrEqualTo(3e6)); // GW era
      // The old gaming GPU is the deliberate trap: cheap but worse on
      // everything. Every other GPU tile beats all earlier ones, except that
      // the hall's H100 rack costs more per TFLOPS than the HGX server before
      // it (the 2023 shortage paces the hall; it still wins per kW and per
      // cell).
      final gpus = tiles.where((t) => t.isGpu).toList();
      for (var i = 1; i < gpus.length; i++) {
        final a = gpus[i - 1], b = gpus[i];
        if (a.id != 'gpu_old' && b.id != 'rack_h_class') {
          expect(
            b.tflops / b.cost,
            greaterThan(a.tflops / a.cost),
            reason: '${b.id} should beat ${a.id} per dollar',
          );
        }
        expect(
          b.tflopsPerKw,
          greaterThan(a.tflopsPerKw),
          reason: '${b.id} should beat ${a.id} per kW',
        );
      }
      final old = tileById('gpu_old')!, gamer = tileById('gpu_gamer')!;
      expect(old.cost, lessThan(gamer.cost));
      expect(old.heat, greaterThan(gamer.heat));
    });
  });

  group('eras', () {
    test('every era unlocks a room, GPU and cooling tiles, a power tier and 3-6 upgrades', () {
      for (final era in Era.values) {
        expect(rooms.where((r) => r.era == era), hasLength(1), reason: era.name);
        for (final kind in TileKind.values) {
          expect(tiles.where((t) => t.era == era && t.kind == kind), isNotEmpty, reason: '${era.name} ${kind.name}');
        }
        expect(powerTiers.where((p) => p.era == era), isNotEmpty, reason: era.name);
        expect(upgrades.where((u) => u.era == era).length, inInclusiveRange(3, 6), reason: era.name);
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
