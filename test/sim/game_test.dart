import 'dart:convert';
import 'dart:math' as math;

import 'package:ai_lab_tycoon/sim/balance.dart';
import 'package:ai_lab_tycoon/sim/bot.dart';
import 'package:ai_lab_tycoon/sim/content.dart';
import 'package:ai_lab_tycoon/sim/game.dart';
import 'package:ai_lab_tycoon/sim/game_state.dart';
import 'package:flutter_test/flutter_test.dart';

import 'grid_helpers.dart';

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

    test('v2 save drops unknown ids and misplaced tiles, keeps the rest', () {
      final s = GameState.fromJson({
        'v': saveVersion,
        'money': 1,
        'era': 'not_an_era',
        'upgrades': ['batching', 'made_up'],
        'grids': {
          'garage': ['gpu_gamer', 'quantum_toaster', 'srv_a_class', null],
          'moon_base': ['gpu_gamer'],
          'closet': List.filled(36, 'srv_a_class'),
        },
      });
      expect(s.startedFromOldSave, isFalse);
      expect(s.era, Era.garage);
      expect(s.ownedUpgrades, {'batching'});
      expect(s.grids.keys, unorderedEquals(['garage', 'closet']));
      expect(s.grids['garage'], hasLength(16));
      expect(s.grids['garage']!.whereType<String>(), ['gpu_gamer']);
      expect(s.tileCounts['srv_a_class'], 36);
      expect(s.releases, hasLength(1));
      Game(s).advance(10);
    });

    test('a v2 save without grids gets the starting garage', () {
      final s = GameState.fromJson({'v': saveVersion});
      expect(s.grids.keys, ['garage']);
      expect(s.tileAt('garage', 1, 1), 'gpu_gamer');
    });
  });

  group('offline', () {
    test('offline progress is capped at 8 hours and has no viral spikes', () {
      final g = runPlaythrough(maxSeconds: 1800, stopWhenDone: false).game;
      final t0 = g.s.time;
      final report = g.applyOffline(48 * 3600);
      expect(report.seconds, offlineCapSeconds);
      expect(g.s.time, closeTo(t0 + offlineCapSeconds, 1e-6));
      expect(g.events.whereType<ViralSpikeStarted>(), isEmpty);
      expect(report.moneyEarned, greaterThan(0));
    });

    test('offline catch-up is deterministic and matches 1-second steps', () {
      final r = runPlaythrough(maxSeconds: 1800, stopWhenDone: false);
      r.game.startTraining(fraction: 0.5, durationSeconds: 3 * 3600);
      final saved = snapshot(r.game);
      Game load() => Game(GameState.fromJson(jsonDecode(saved) as Map<String, dynamic>));
      final a = load(), b = load(), fine = load();
      final ra = a.applyOffline(6 * 3600);
      b.applyOffline(6 * 3600);
      expect(snapshot(a), snapshot(b));
      expect(Game.offlineStep(6 * 3600), greaterThan(1));
      fine.advance(6 * 3600, offline: true);
      expect(a.s.money, closeTo(fine.s.money, fine.s.money * 0.01));
      expect(a.s.users, closeTo(fine.s.users, fine.s.users * 0.01));
      // The 3 h run finished while away and waits to be released.
      expect(ra.trainingFinished, isTrue);
      expect(a.s.pendingEffectiveCompute, closeTo(fine.s.pendingEffectiveCompute!, fine.s.pendingEffectiveCompute! * 0.01));
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
      expect(g.buyNextPowerTier(), isFalse);
      g.s.era = Era.startup;
      expect(g.buyNextPowerTier(), isTrue);
    });

    test('rack-scale GPUs need liquid cooling and a big enough site', () {
      final g = gameWith({
        'garage': ['G...', '....', '....', '....'],
        'hall': List.filled(12, '............'),
      }, powerTier: 4);
      expect(g.placeBlockReason('hall', 0, 0, 'rack_b_class'), contains('Liquid cooling'));
      g.s.ownedUpgrades.add('liquid_cooling');
      expect(
        g.placeBlockReason('hall', 0, 0, 'rack_b_class'),
        contains('Datacenter campus power tier'),
      );
      g.s.powerTier = 5;
      expect(g.placeTile('hall', 0, 0, 'rack_b_class'), isTrue);
    });
  });

  group('era unlocks', () {
    test('Startup at the users threshold, then one rating gate after another', () {
      // Four gaming GPUs can serve the users the unlock needs.
      final g = gameWith(
        {
          'garage': ['G.G.', '....', 'G.G.', '....'],
        },
        era: Era.garage,
        powerTier: 0,
      );
      expect(g.capacity, greaterThan(startupUnlockUsers));
      expect(g.roomBlockReason('closet'), contains('Startup era'));
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
    test('runs get longer and time compression gentler era by era', () {
      for (var i = 1; i < Era.values.length; i++) {
        final a = Era.values[i - 1], b = Era.values[i];
        expect(b.runDurations.last, greaterThanOrEqualTo(a.runDurations.last));
        expect(b.computeTimeScale, lessThanOrEqualTo(a.computeTimeScale));
      }
      expect(Era.garage.runDurations.first, 60);
      // A late run lasts hours, so it finishes while you're away, but never
      // longer than the offline cap.
      expect(Era.globalLab.runDurations.last, greaterThanOrEqualTo(4 * 3600));
      expect(Era.globalLab.runDurations.last, lessThanOrEqualTo(offlineCapSeconds));
    });

    test('a run keeps the time compression it started with', () {
      final g = gameWith({'garage': ['G...', '....', '....', '....']}, era: Era.garage, powerTier: 1);
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
      final g = gameWith({
        'garage': ['G...', '....', '....', '....'],
        'closet': List.filled(6, '......'),
      }, era: Era.startup);
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
      expect(g.tilePrice(tileById('net_100g')!), tileById('net_100g')!.cost);
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
