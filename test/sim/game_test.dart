import 'dart:convert';
import 'dart:math' as math;

import 'package:ai_lab_tycoon/sim/balance.dart';
import 'package:ai_lab_tycoon/sim/bot.dart';
import 'package:ai_lab_tycoon/sim/content.dart';
import 'package:ai_lab_tycoon/sim/game.dart';
import 'package:ai_lab_tycoon/sim/game_state.dart';
import 'package:ai_lab_tycoon/sim/model_design.dart';
import 'package:flutter_test/flutter_test.dart';

import 'grid_helpers.dart';
import 'phase_helpers.dart';

String snapshot(Game g) => jsonEncode(g.s.toJson());

/// A fixed, scripted sequence of player actions.
void scripted(Game g) {
  g.buyUpgrade('mixed_precision');
  g.startTraining(fraction: 0.5, durationSeconds: 60);
  for (var i = 0; i < 1800; i++) {
    if (g.s.pendingEffectiveCompute != null) {
      g.release(open: i.isEven, stuntId: i % 3 == 0 ? 'live_demo' : 'cryptic_tweet');
      g.startTraining(fraction: 0.75, durationSeconds: 60);
    }
    if (i % 30 == 0) {
      final cell = (i ~/ 30) % 16;
      g.placeTile(
        'garage',
        cell % 4,
        cell ~/ 4,
        i % 90 == 0 ? 'net_5g' : (i % 60 == 0 ? 'cool_fan' : 'gpu_gamer'),
      );
    }
    if (i == 700) g.moveTile('garage', 1, 1, 0, 0);
    if (i == 900) g.sellTile('garage', 0, 0);
    if (i % 200 == 0) g.buyNextPowerTier();
    g.tick(1);
  }
}

void main() {
  group('model design', () {
    /// A Medium-lab state with a decent cluster and the era's research.
    Game midGame() {
      final g = Game(GameState(
        era: Era.mediumLab,
        networkTier: 4,
        money: 1e12,
        ownedUpgrades: {
          for (final u in allUpgrades)
            if (u.era.index <= Era.mediumLab.index) u.id,
        },
      ));
      g.s.grids
        ..clear()
        ..['hall'] = GameState.emptyGrid(roomById('hall')!);
      for (var i = 0; i < 20; i++) {
        g.s.grids['hall']![i] = 'rack_h_class';
      }
      g.s.touchGrid();
      return g;
    }

    test('a run remembers its setup; the next one starts from it', () {
      final g = Game();
      final spec = const ModelSpec(sizing: Sizing.bigShort);
      expect(g.startTraining(fraction: 0.5, durationSeconds: 60, spec: spec), isTrue);
      expect(g.s.run!.spec, spec);
      expect(g.s.lastSpec, spec);
      g.cancelTraining();
      // One-tap start: no spec given = the remembered one.
      g.startTraining(fraction: 0.5, durationSeconds: 60);
      expect(g.s.run!.spec, spec);
    });

    test('locked choices fall back to the safe default', () {
      final g = Game();
      g.startTraining(
        fraction: 0.5,
        durationSeconds: 60,
        spec: const ModelSpec(architecture: Architecture.moe, postTraining: PostTraining.reasoning),
      );
      expect(g.s.run!.spec.architecture, Architecture.dense);
      expect(g.s.run!.spec.postTraining, PostTraining.sft);
    });

    test('the design reaches the release: rating, serving, demand, benchmarks', () {
      final g = midGame();
      final good = ModelSpec.bestGuessFor(g.designContext);
      g.startTraining(fraction: 0.5, durationSeconds: g.runDurations.first, spec: good);
      // Online, each checkpoint waits for a decision.
      g.advance(g.runDurations.first + 3, onStep: decideDefaults(g));
      final predicted = g.pendingRating!;
      expect(g.s.pendingDesign!.spec, good);
      expect(g.release(open: false), isTrue);
      final m = g.s.currentModel;
      expect(m.rating, closeTo(predicted, 1e-9));
      final phaseServe = m.design!.phases.fold(1.0, (a, o) => a * o.serve);
      expect(m.design!.phases, hasLength(3));
      expect(m.design!.serveCostMult, closeTo(evaluate(good, g.designContext).serveCostMult * phaseServe, 1e-9));
      expect(g.currentPerUserTflops,
          closeTo(g.perUserTflops(m.design!.serveCompute) * m.design!.serveCostMult, 1e-12));
      expect(m.design!.strengths.coding, greaterThan(1));
    });

    test('bad choices make a clearly worse model from the same run', () {
      final g = midGame();
      final d = g.runDurations.last;
      final good = g.predictRating(0.5, d, spec: ModelSpec.bestGuessFor(g.designContext));
      final bad = g.predictRating(0.5, d,
          spec: const ModelSpec(sizing: Sizing.bigShort, postTraining: PostTraining.none, context: ContextLength.k2));
      expect(bad, lessThan(good - 60));
      // Extreme RL hacks the reward model: worse than plain SFT.
      final sft = g.predictRating(0.5, d, spec: const ModelSpec(postTraining: PostTraining.sft));
      final hacked = g.predictRating(0.5, d,
          spec: const ModelSpec(postTraining: PostTraining.rlhf, rlStrength: RlStrength.extreme));
      expect(hacked, lessThan(sft));
    });

    test('MoE without router balancing can collapse (seeded, deterministic)', () {
      var collapses = 0;
      for (var seed = 1; seed <= 40; seed++) {
        final g = midGame()..s.rngState = seed;
        g.s.ownedUpgrades.remove('router_balancing');
        g.startTraining(
          fraction: 0.5,
          durationSeconds: g.runDurations.first,
          spec: const ModelSpec(architecture: Architecture.moe),
        );
        g.advance(g.runDurations.first + 3, onStep: decideDefaults(g));
        final done = g.events.whereType<TrainingFinished>().single;
        if (done.mishaps.isNotEmpty) collapses++;
      }
      expect(collapses, inInclusiveRange(4, 20)); // ~25%
    });

    test('design research is buyable and survives a save', () {
      final g = midGame()..s.ownedUpgrades.removeAll(['gqa', 'sliding_window']);
      expect(g.buyUpgrade('gqa'), isTrue);
      g.startTraining(fraction: 0.5, durationSeconds: 60, spec: const ModelSpec(attention: Attention.gqa));
      final loaded = GameState.fromJson(jsonDecode(jsonEncode(g.s.toJson())) as Map<String, dynamic>);
      expect(loaded.ownedUpgrades, contains('gqa'));
      expect(loaded.lastSpec.attention, Attention.gqa);
      expect(loaded.run!.spec.attention, Attention.gqa);
    });

    test('the identity upgrades no longer double count their design option', () {
      for (final id in ['moe', 'chinchilla_scaling', 'quantization', 'long_context', 'reasoning']) {
        final e = researchById(id)!.effects;
        expect(e.trainEffMult, 1, reason: id);
        expect(e.serveEffMult, 1, reason: id);
        expect(e.ratingAdd, 0, reason: id);
        expect(optionsUnlockedBy(id), isNotEmpty, reason: id);
      }
    });
  });

  group('determinism', () {
    test('same seed + same actions → same state', () {
      final a = Game(GameState(rngState: 42));
      final b = Game(GameState(rngState: 42));
      scripted(a);
      scripted(b);
      expect(snapshot(a), snapshot(b));
    });

    test('same seed + same bot → same playthrough', () {
      final a = runPlaythrough(maxSeconds: 3600, seed: 7);
      final b = runPlaythrough(maxSeconds: 3600, seed: 7);
      expect(snapshot(a.game), snapshot(b.game));
      expect(a.rivalTimes.map((r) => r.$2), b.rivalTimes.map((r) => r.$2));
    });

    test('a different seed changes the random events', () {
      final a = runPlaythrough(maxSeconds: 3600, seed: 1);
      final b = runPlaythrough(maxSeconds: 3600, seed: 2);
      expect(a.game.s.rngState, isNot(b.game.s.rngState));
    });
  });

  group('save / load', () {
    test('JSON roundtrip mid-game is lossless', () {
      final r = runPlaythrough(maxSeconds: 2400, stopWhenDone: false);
      final g = r.game;
      g.startTraining(fraction: 0.5, durationSeconds: 600); // may be running
      final json = jsonEncode(g.s.toJson());
      final restored = GameState.fromJson(jsonDecode(json) as Map<String, dynamic>);
      expect(jsonEncode(restored.toJson()), json);

      // And it keeps simulating identically.
      final g2 = Game(restored);
      g.advance(300);
      g2.advance(300);
      expect(snapshot(g2), snapshot(g));
    });

    test('a v1 save (menu-shop format) starts a fresh game, no crash', () {
      const old = '''
      {"v":1,"time":1234.5,"money":9000,"users":4200,"hype":1.3,
       "powerTier":1,"hardware":{"gamer":3,"v_class":2,"quantum_toaster":9},
       "upgrades":["mixed_precision","batching","made_up_upgrade"],
       "openReleases":1,
       "run":{"fraction":0.5,"duration":120,"elapsed":30,"flops":1e18},
       "pending":null,
       "releases":[{"name":"Fine-tuned open model","effC":1e18,"rating":700,
                    "open":true,"time":0}],
       "rivalIndex":1,"viral":0,"cloud":0,"rng":999,"era":"garage"}''';
      final s = GameState.fromJson(jsonDecode(old) as Map<String, dynamic>);
      expect(s.startedFromOldSave, isTrue);
      expect(jsonEncode(s.toJson()), jsonEncode(GameState().toJson()));
      // No version at all counts as old too.
      expect(GameState.fromJson({'money': 1}).startedFromOldSave, isTrue);
      Game(s).advance(60);
    });

    test('a save drops unknown ids, keeps the rest', () {
      final s = GameState.fromJson({
        'v': saveVersion,
        'money': 1,
        'era': 'not_an_era',
        'upgrades': ['batching', 'made_up'],
        'networkTier': 99,
        'coolingTier': 2,
        'grids': {
          'garage': ['gpu_gamer', 'quantum_toaster', 'srv_a_class', null],
          'moon_base': ['gpu_gamer'],
        },
      });
      expect(s.startedFromOldSave, isFalse);
      expect(s.era, Era.garage);
      expect(s.ownedUpgrades, {'batching'});
      expect(s.grids.keys, ['garage']);
      expect(s.grids['garage'], hasLength(16));
      // Unknown ids drop; any known tile loads in any room.
      expect(s.grids['garage']!.whereType<String>(), ['gpu_gamer', 'srv_a_class']);
      expect(s.networkTier, networkTiers.length - 1);
      expect(s.coolingTier, 2);
      expect(s.releases, hasLength(1));
      Game(s).advance(10);
    });

    test('one room per save, any known tile in it', () {
      final s = GameState.fromJson({
        'v': saveVersion,
        'grids': {
          'closet': ['gpu_gamer', 'srv_a_class', 'made_up', ...List.filled(46, null)],
        },
      });
      expect(s.roomId, 'closet');
      expect(s.grids['closet']!.whereType<String>(), ['gpu_gamer', 'srv_a_class']);
      final back = GameState.fromJson(jsonDecode(jsonEncode(s.toJson())) as Map<String, dynamic>);
      expect(back.roomId, 'closet');
    });

    test('v3 saves (several rooms at once) start fresh', () {
      final s = GameState.fromJson({'v': 3, 'grids': {'garage': [], 'closet': []}});
      expect(s.startedFromOldSave, isTrue);
      expect(s.roomId, 'garage');
    });

    test('a save without grids gets the starting garage', () {
      final s = GameState.fromJson({'v': saveVersion});
      expect(s.grids.keys, ['garage']);
      expect(s.tileAt('garage', 1, 1), 'gpu_gamer');
    });
  });

  group('offline', () {
    test('offline progress is capped at 2 hours, earns at a reduced rate and has no viral spikes', () {
      final g = runPlaythrough(maxSeconds: 1800, stopWhenDone: false).game;
      final t0 = g.s.time;
      final report = g.applyOffline(48 * 3600);
      expect(report.seconds, offlineCapSeconds);
      expect(g.s.time, closeTo(t0 + offlineCapSeconds, 1e-6));
      expect(g.events.whereType<ViralSpikeStarted>(), isEmpty);
      expect(report.moneyEarned, greaterThan(0));
      // Away, revenue counts at offlineEarningsRate of the live rate.
      expect(offlineEarningsRate, inInclusiveRange(0.05, 0.5));
    });

    test('offline catch-up is deterministic and matches 1-second steps', () {
      final r = runPlaythrough(maxSeconds: 1800, stopWhenDone: false);
      r.game.startTraining(fraction: 0.5, durationSeconds: 3600);
      final saved = snapshot(r.game);
      Game load() => Game(GameState.fromJson(jsonDecode(saved) as Map<String, dynamic>));
      final a = load(), b = load(), fine = load();
      final ra = a.applyOffline(6 * 3600); // capped at offlineCapSeconds
      b.applyOffline(6 * 3600);
      expect(snapshot(a), snapshot(b));
      expect(Game.offlineStep(offlineCapSeconds), greaterThan(1));
      fine.advance(offlineCapSeconds, offline: true);
      expect(a.s.money, closeTo(fine.s.money, fine.s.money * 0.01));
      expect(a.s.users, closeTo(fine.s.users, fine.s.users * 0.01));
      // The 1 h run finished while away and waits to be released.
      expect(ra.trainingFinished, isTrue);
      // (Coarse steps end the run up to a step late: within 2%.)
      expect(a.s.pendingEffectiveCompute, closeTo(fine.s.pendingEffectiveCompute!, fine.s.pendingEffectiveCompute! * 0.02));
    });

    test('negative offline time does nothing', () {
      final g = Game();
      final report = g.applyOffline(-50);
      expect(report.seconds, 0);
      expect(g.s.time, 0);
    });
  });

  group('power limits', () {
    test('next power tier is era-gated', () {
      final g = Game(GameState(money: 1e9, powerTier: 1));
      expect(g.nextPowerTier!.era, Era.startup);
      expect(g.powerBlockReason(), startsWith('Unlocks in Startup'));
      expect(g.buyNextPowerTier(), isFalse);
      g.s.era = Era.startup;
      expect(g.moveTo('closet'), isTrue);
      expect(g.buyNextPowerTier(), isTrue);
    });

    test('the building limits power: move first, then buy', () {
      final g = Game(GameState(money: 1e9, era: Era.startup, powerTier: 1));
      expect(g.currentRoom.id, 'garage');
      expect(g.powerNeedsMove, isTrue);
      expect(
        g.powerBlockReason(),
        'Needs a bigger building: move to the Server closet first.',
      );
      expect(g.buyNextPowerTier(), isFalse);
      expect(g.s.powerTier, 1);
      // Moving keeps the tier you have; it doesn't buy power.
      final money = g.s.money;
      expect(g.moveTo('closet'), isTrue);
      expect(g.s.powerTier, 1);
      expect(g.s.money, money - roomById('closet')!.cost);
      expect(g.powerNeedsMove, isFalse);
      expect(g.powerBlockReason(), isNull);
      expect(g.buyNextPowerTier(), isTrue);
      expect(powerTiers[g.s.powerTier].name, '3-phase service');
    });

    test('every power tier is buyable in some room, in order', () {
      final g = Game(GameState(money: 1e15, era: Era.globalLab));
      while (g.nextPowerTier != null) {
        if (g.powerNeedsMove) {
          expect(g.powerBlockReason(), contains(g.nextRoom!.name));
          expect(g.moveTo(g.nextRoom!.id), isTrue);
        }
        final id = g.nextPowerTier!.id;
        expect(g.buyNextPowerTier(), isTrue, reason: id);
        expect(g.s.powerTier, lessThanOrEqualTo(g.currentRoom.maxPowerTier));
      }
      expect(g.powerBlockReason(), 'You have the biggest power supply.');
    });

    test('rack-scale GPUs need liquid cooling and a big enough site', () {
      final g = gameIn('hall', List.filled(14, '..............'), powerTier: 4);
      expect(g.placeBlockReason('hall', 0, 0, 'rack_b_class'), contains('Liquid cooling'));
      g.s.ownedUpgrades.add('liquid_cooling');
      expect(
        g.placeBlockReason('hall', 0, 0, 'rack_b_class'),
        'Needs power: On-site substation.',
      );
      g.s.powerTier = 5;
      expect(g.placeTile('hall', 0, 0, 'rack_b_class'), isTrue);
    });
  });

  group('era unlocks', () {
    test('Startup at the users threshold, then one rating gate after another', () {
      // Four gaming GPUs can serve the users the unlock needs.
      final g = gameWith(['G.G.', '....', 'G.G.', '....'], era: Era.garage, powerTier: 0);
      expect(g.capacity, greaterThan(startupUnlockUsers));
      expect(g.moveRequirements('closet').firstWhere((r) => r.kind == 'era').detail, contains('/ 3k users'));
      expect(g.eraLockReason(Era.startup), contains('Unlocks in Startup: reach 3k users'));
      expect(g.nextEraGoal!.era, Era.startup);
      expect(g.nextEraGoal!.metric, 'users');

      g.s.users = startupUnlockUsers;
      g.s.hype = 1e6; // keep demand above users so they don't churn
      g.tick(0.01);
      expect(g.s.era, Era.startup);
      expect(g.events.whereType<EraUnlocked>().single.era, Era.startup);
      expect(g.isUnlocked(Era.startup), isTrue);
      expect(g.isUnlocked(Era.smallLab), isFalse);

      // Each later gate is a model rating; ship a model that clears it.
      for (final (era, gate) in [
        (Era.smallLab, smallLabUnlockRating),
        (Era.mediumLab, mediumLabUnlockRating),
        (Era.bigLab, bigLabUnlockRating),
        (Era.globalLab, globalLabUnlockRating),
      ]) {
        g.events.clear();
        expect(g.nextEraGoal!.era, era);
        expect(g.nextEraGoal!.target, gate);
        final effC = startEffectiveCompute *
            math.pow(2, (gate + 1 - ratingBase - g.ratingBonus) / ratingPerDoubling);
        g.s.releases.add(
          ModelRelease(name: era.name, effectiveCompute: effC.toDouble(), rating: 0, open: false, time: g.s.time),
        );
        expect(g.rating, greaterThanOrEqualTo(gate));
        g.tick(0.01);
        expect(g.s.era, era);
        expect(g.events.whereType<EraUnlocked>().single.era, era);
      }
      expect(g.nextEraGoal, isNull);
      expect(Era.values.last, Era.globalLab);
    });

    test('eras never skip: a frontier rating in the Garage unlocks one era per tick', () {
      final g = Game();
      g.s.releases.add(
        const ModelRelease(name: 'x', effectiveCompute: 1e30, rating: 0, open: false, time: 0),
      );
      g.s.users = 1e9;
      g.tick(1);
      expect(g.s.era, Era.startup);
      g.tick(1);
      expect(g.s.era, Era.smallLab);
    });

    test('rivals wait for their era', () {
      final g = Game();
      g.s.releases.add(
        const ModelRelease(name: 'x', effectiveCompute: 1e33, rating: 0, open: false, time: 0),
      );
      g.s.users = 5e9;
      g.s.hype = 1e6;
      g.tick(0.01);
      // One tick: Startup unlocks, so only the Garage and Startup rivals fall.
      expect(rivalLadder.take(g.s.rivalIndex).map((r) => r.era).toSet(), {Era.garage, Era.startup});
      for (var i = 0; i < 10; i++) {
        g.tick(0.01);
      }
      expect(g.s.era, Era.globalLab);
      expect(g.s.rivalIndex, rivalLadder.length);
    });

    test('launch stunts are era-gated', () {
      final g = Game();
      g.s.pendingEffectiveCompute = 1e19;
      expect(g.release(open: false, stuntId: 'keynote'), isFalse);
      expect(g.s.pendingEffectiveCompute, isNotNull);
      expect(g.release(open: false, stuntId: 'cryptic_tweet'), isTrue);
    });
  });

  group('run lengths and time compression', () {
    test('runs take seconds to minutes and never get shorter era by era', () {
      for (var i = 1; i < Era.values.length; i++) {
        final a = Era.values[i - 1], b = Era.values[i];
        expect(b.runDurations.last, greaterThanOrEqualTo(a.runDurations.last));
      }
      for (final e in Era.values) {
        // Active play: 30 s at the shortest, 5 min at the longest.
        expect(e.runDurations.first, greaterThanOrEqualTo(30), reason: e.name);
        expect(e.runDurations.last, lessThanOrEqualTo(300), reason: e.name);
        // The longest run is still days to weeks of compute.
        final days = e.runDurations.last * e.computeTimeScale / 86400;
        expect(days, inInclusiveRange(3, 60), reason: e.name);
      }
      expect(Era.garage.runDurations.first, 30);
      expect(Era.globalLab.runDurations, [60, 180, 300]);
    });

    test('a run keeps the time compression it started with', () {
      final g = gameWith(['G...', '....', '....', '....'], era: Era.garage, powerTier: 1);
      final before = g.trainingFlopsPerSecond(1);
      expect(g.startTraining(fraction: 1, durationSeconds: 600), isTrue);
      expect(g.s.run!.timeScale, Era.garage.computeTimeScale);
      g.s.era = Era.globalLab; // e.g. an unlock mid-run
      expect(g.trainingFlopsPerSecond(1), closeTo(before, before * 1e-9));
      final s = GameState.fromJson(jsonDecode(jsonEncode(g.s.toJson())) as Map<String, dynamic>);
      expect(s.run!.timeScale, Era.garage.computeTimeScale);
    });
  });

  group('GPU supply crunch', () {
    test('each GPU of a type makes the next pricier, capped, and selling refunds list', () {
      final g = gameIn('closet', List.filled(7, '.......'), era: Era.startup);
      final a = tileById('srv_a_class')!;
      expect(g.tilePrice(a), a.cost);
      expect(g.placeTile('closet', 0, 0, 'srv_a_class'), isTrue);
      expect(g.tilePrice(a), closeTo(a.cost * (1 + a.priceGrowth), 1e-6));
      for (var x = 1; x < 6; x++) {
        for (var y = 0; y < 6; y++) {
          g.s.setTile('closet', x, y, 'srv_a_class');
        }
      }
      expect(g.tilePrice(a), a.cost * maxSupplyPremium);
      expect(g.sellValue('srv_a_class'), a.cost * 0.5);
      // Garage GPUs and non-GPU gear have no crunch.
      expect(g.tilePrice(tileById('gpu_gamer')!), tileById('gpu_gamer')!.cost);
      expect(g.tilePrice(tileById('cool_crac')!), tileById('cool_crac')!.cost);
    });
  });

  group('users and events', () {
    test('users fill up to capacity (waitlist) instead of overloading', () {
      final g = Game();
      g.s.hype = 1e6; // demand far above capacity
      g.advance(600);
      expect(g.s.users, closeTo(g.capacity, g.capacity * 0.02));
      expect(g.overloaded, isFalse);
      expect(g.waitlistUsers, greaterThan(0));
    });

    test('a viral spike overloads, then a cooldown keeps them rare', () {
      final g = Game(GameState(users: 100, hype: 1e6));
      g.s.releases.add(
        const ModelRelease(name: 'm', effectiveCompute: 2e18, rating: 0, open: false, time: 0),
      );
      final spikes = <double>[];
      for (var i = 0; i < 6 * 3600; i++) {
        g.tick(1);
        for (final e in g.events) {
          if (e is ViralSpikeStarted) spikes.add(g.s.time);
        }
        g.events.clear();
      }
      expect(spikes, isNotEmpty);
      for (var i = 1; i < spikes.length; i++) {
        expect(
          spikes[i] - spikes[i - 1],
          greaterThanOrEqualTo(viralDurationSeconds + viralCooldownSeconds),
        );
      }
    });

    test('hype from releases does not compound without bound', () {
      final g = Game();
      for (var i = 0; i < 20; i++) {
        g.s.pendingEffectiveCompute = 1e18 * (2 << i);
        g.release(open: true, stuntId: 'cryptic_tweet');
      }
      expect(g.s.hype, lessThanOrEqualTo(maxHype));
    });
  });
}
