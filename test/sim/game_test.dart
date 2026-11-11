import 'dart:convert';

import 'package:ai_lab_tycoon/sim/balance.dart';
import 'package:ai_lab_tycoon/sim/bot.dart';
import 'package:ai_lab_tycoon/sim/content.dart';
import 'package:ai_lab_tycoon/sim/game.dart';
import 'package:ai_lab_tycoon/sim/game_state.dart';
import 'package:flutter_test/flutter_test.dart';

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
    if (i % 30 == 0) g.buyHardware('gamer');
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
      final restored =
          GameState.fromJson(jsonDecode(json) as Map<String, dynamic>);
      expect(jsonEncode(restored.toJson()), json);

      // And it keeps simulating identically.
      final g2 = Game(restored);
      g.advance(300);
      g2.advance(300);
      expect(snapshot(g2), snapshot(g));
    });

    test('old v1 save without newer fields loads with defaults', () {
      // Shape written by the original v1 code: no viralCd, no labName, no
      // run.paused, and content ids that no longer exist.
      const old = '''
      {"v":1,"time":1234.5,"money":9000,"users":4200,"hype":1.3,
       "powerTier":1,"hardware":{"gamer":3,"v_class":2,"quantum_toaster":9},
       "upgrades":["mixed_precision","batching","made_up_upgrade"],
       "openReleases":1,
       "run":{"fraction":0.5,"duration":120,"elapsed":30,"flops":1e18},
       "pending":null,
       "releases":[{"name":"Fine-tuned open model","effC":1e18,"rating":700,
                    "open":true,"time":0},
                   {"name":"Model 1","effC":4e18,"rating":746,"open":true,
                    "time":600}],
       "rivalIndex":1,"viral":0,"cloud":0,"rng":999,"era":"garage"}''';
      final s = GameState.fromJson(jsonDecode(old) as Map<String, dynamic>);
      expect(s.money, 9000);
      expect(s.labName, 'Garage Labs');
      expect(s.viralCooldownLeft, 0);
      expect(s.run!.paused, isFalse);
      expect(s.hardwareCounts, {'gamer': 3, 'v_class': 2});
      expect(s.ownedUpgrades, {'mixed_precision', 'batching'});
      expect(s.currentModel.name, 'Model 1');
      // Loads into a working game.
      final g = Game(s)..advance(120);
      expect(g.s.time, closeTo(1354.5, 1e-9));
      expect(g.s.money, greaterThan(9000));
    });

    test('minimal save with almost nothing in it still loads', () {
      final s = GameState.fromJson({'money': 1, 'era': 'not_an_era'});
      expect(s.era, Era.garage);
      expect(s.hardwareCounts, {'gamer': 1});
      expect(s.releases, hasLength(1));
      Game(s).advance(10);
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

    test('negative offline time does nothing', () {
      final g = Game();
      final report = g.applyOffline(-50);
      expect(report.seconds, 0);
      expect(g.s.time, 0);
    });
  });

  group('power limits', () {
    test('cannot buy past the power cap', () {
      final g = Game(GameState(money: 1e6));
      final gamer = hardware.firstWhere((h) => h.id == 'gamer');
      // Outlet: 1.8 kW, one gamer already draws 0.45 kW → room for 3 more.
      expect(g.maxBuyable(gamer), 3);
      expect(g.buyHardware('gamer', 4), isFalse);
      expect(g.buyHardware('gamer', 3), isTrue);
      expect(g.buyHardware('gamer'), isFalse);
      expect(g.powerUsedKw, lessThanOrEqualTo(g.powerCapKw + 1e-9));
      expect(g.buyNextPowerTier(), isTrue);
      expect(g.buyHardware('gamer'), isTrue);
    });

    test('money limits buying too', () {
      final g = Game(GameState(money: 2500));
      expect(g.maxBuyable(hardware.first), 1);
    });

    test('next power tier is era-gated', () {
      final g = Game(GameState(money: 1e9, powerTier: 1));
      expect(g.nextPowerTier!.era, Era.startup);
      expect(g.buyNextPowerTier(), isFalse);
      g.s.era = Era.startup;
      expect(g.buyNextPowerTier(), isTrue);
    });

    test('rack-scale GPUs need liquid cooling and a big enough site', () {
      final b = hardware.firstWhere((h) => h.id == 'b_class');
      final g = Game(GameState(money: 1e12, era: Era.lab, powerTier: 4));
      expect(g.isHardwareAvailable(b), isFalse);
      expect(g.maxBuyable(b), 0);
      g.s.powerTier = b.minPowerTier;
      expect(g.isHardwareAvailable(b), isFalse); // still no liquid cooling
      g.s.ownedUpgrades.add('liquid_cooling');
      expect(g.isHardwareAvailable(b), isTrue);
      expect(g.buyHardware('b_class', 10), isTrue);
    });

    test('liquid cooling lowers power draw', () {
      final g = Game(GameState(hardwareCounts: {'gamer': 4}));
      final before = g.powerUsedKw;
      g.s.ownedUpgrades.add('liquid_cooling');
      expect(g.powerUsedKw, closeTo(before * 0.85, 1e-9));
    });
  });

  group('era unlocks', () {
    test('Startup at the users threshold, Lab at the rating threshold', () {
      // Four gaming GPUs can serve the 5k users the unlock needs.
      final g = Game(GameState(hardwareCounts: {'gamer': 4}));
      expect(g.capacity, greaterThan(startupUnlockUsers));
      final a = hardware.firstWhere((h) => h.id == 'a_class');
      g.s.money = 1e9;
      expect(g.maxBuyable(a), 0); // Startup hardware locked in the Garage

      g.s.users = startupUnlockUsers;
      g.s.hype = 1e6; // keep demand above users so they don't churn
      g.tick(0.01);
      expect(g.s.era, Era.startup);
      expect(g.events.whereType<EraUnlocked>().single.era, Era.startup);
      expect(g.isUnlocked(Era.startup), isTrue);
      expect(g.isUnlocked(Era.lab), isFalse);

      g.events.clear();
      g.s.releases.add(ModelRelease(
        name: 'big',
        effectiveCompute: 1e24,
        rating: 0,
        open: false,
        time: g.s.time,
      ));
      expect(g.rating, greaterThanOrEqualTo(labUnlockRating));
      g.tick(0.01);
      expect(g.s.era, Era.lab);
      expect(g.events.whereType<EraUnlocked>().single.era, Era.lab);
    });

    test('eras never skip: Lab rating in the Garage only unlocks Startup', () {
      final g = Game();
      g.s.releases.add(const ModelRelease(
          name: 'x', effectiveCompute: 1e24, rating: 0, open: false, time: 0));
      g.tick(1);
      expect(g.s.era, Era.garage);
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
      g.s.releases.add(const ModelRelease(
          name: 'm', effectiveCompute: 2e18, rating: 0, open: false, time: 0));
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
        expect(spikes[i] - spikes[i - 1],
            greaterThanOrEqualTo(viralDurationSeconds + viralCooldownSeconds));
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
