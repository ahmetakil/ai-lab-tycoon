import 'dart:math' as math;

import 'package:ai_lab_tycoon/sim/balance.dart';
import 'package:ai_lab_tycoon/sim/content.dart';
import 'package:ai_lab_tycoon/sim/game.dart';
import 'package:ai_lab_tycoon/sim/game_state.dart';
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
      expectUnique('hardware', hardware.map((h) => h.id));
      expectUnique('power tier', powerTiers.map((p) => p.id));
      expectUnique('upgrade', upgrades.map((u) => u.id));
      expectUnique('launch stunt', launchStunts.map((l) => l.id));
      expectUnique('rival snapshot',
          rivalLadder.map((r) => '${r.labId}/${r.model}'));
      // One namespace across hardware/power/upgrades too (icon file names
      // are prefixed, but a shared id would still be confusing).
      expectUnique('content', [
        ...hardware.map((h) => h.id),
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
      for (final h in hardware) {
        for (final r in h.requires) {
          expect(ids, contains(r), reason: '${h.id} requires unknown $r');
        }
        expect(h.minPowerTier, inInclusiveRange(0, powerTiers.length - 1));
      }
    });

    test('ids existing saves rely on are still present', () {
      const v1Hardware = ['gamer', 'v_class', 'a_class', 'h_class', 'b_class'];
      const v1Power = ['outlet', 'panel', 'office', 'colo', 'hall', 'campus',
          'plant'];
      const v1Upgrades = ['mixed_precision', 'batching', 'kv_cache', 'lora',
          'common_crawl', 'cuda_kernels', 'flash_attention', 'quantization',
          'interconnect', 'liquid_cooling', 'code_data', 'dedup',
          'instruction_tuning', 'rlhf', 'moe', 'fp8', 'parallelism',
          'distillation', 'speculative', 'synthetic_data', 'rlaif',
          'reasoning'];
      expect(hardware.map((h) => h.id), containsAll(v1Hardware));
      // Power tiers are saved by index: the v1 tiers must keep their slots.
      expect(powerTiers.take(v1Power.length).map((p) => p.id), v1Power);
      expect(upgrades.map((u) => u.id), containsAll(v1Upgrades));
    });

    test('upgrade count stays reasonable and blurbs are one-liners', () {
      expect(upgrades.length, inInclusiveRange(25, 32));
      for (final u in upgrades) {
        expect(u.blurb.length, lessThanOrEqualTo(140), reason: u.id);
        expect(u.blurb, isNot(contains('\n')), reason: u.id);
      }
    });

    test('power tiers grow and newer GPUs dominate older ones', () {
      for (var i = 1; i < powerTiers.length; i++) {
        expect(powerTiers[i].capacityKw,
            greaterThan(powerTiers[i - 1].capacityKw));
        expect(powerTiers[i].era.index,
            greaterThanOrEqualTo(powerTiers[i - 1].era.index));
      }
      expect(powerTiers.last.capacityKw, greaterThanOrEqualTo(3e6)); // GW era
      for (var i = 1; i < hardware.length; i++) {
        final a = hardware[i - 1], b = hardware[i];
        expect(b.tflops / b.cost, greaterThan(a.tflops / a.cost),
            reason: '${b.id} should beat ${a.id} per dollar');
        expect(b.tflopsPerKw, greaterThan(a.tflopsPerKw),
            reason: '${b.id} should beat ${a.id} per kW');
      }
    });
  });

  group('rival ladder', () {
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
          expect(r.rating, greaterThan(prev.rating),
              reason: '${r.model} must be harder than ${prev.model}');
          expect(r.year, greaterThanOrEqualTo(prev.year), reason: r.model);
        }
        // Users mostly climb; real dips (small consumer apps) are allowed but
        // never absurd.
        expect(r.users, greaterThanOrEqualTo(0.1 * maxUsersSoFar),
            reason: r.model);
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
        final expected = ratingBase +
            ratingPerDoubling *
                (math.log(r.trainingFlops / startEffectiveCompute) / math.ln2) +
            r.postTrainingBonus;
        expect(r.rating, closeTo(expected, 1.0), reason: r.model);
      }
    });

    test('the final rival is reachable with the full upgrade stack', () {
      final s = GameState(ownedUpgrades: upgrades.map((u) => u.id).toSet());
      final g = Game(s);
      // Data-optimal compute (no diminishing returns yet) with every upgrade.
      final best = g.ratingOf(g.dataOptimalCompute);
      expect(best, greaterThan(rivalLadder.last.rating));
    });
  });
}
