import 'dart:convert';

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
        'hall': List.filled(10, '..........'),
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
    test('Startup at the users threshold, Lab at the rating threshold', () {
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

      g.s.users = startupUnlockUsers;
      g.s.hype = 1e6; // keep demand above users so they don't churn
      g.tick(0.01);
      expect(g.s.era, Era.startup);
      expect(g.events.whereType<EraUnlocked>().single.era, Era.startup);
      expect(g.isUnlocked(Era.startup), isTrue);
      expect(g.isUnlocked(Era.lab), isFalse);

      g.events.clear();
      g.s.releases.add(
        ModelRelease(name: 'big', effectiveCompute: 1e24, rating: 0, open: false, time: g.s.time),
      );
      expect(g.rating, greaterThanOrEqualTo(labUnlockRating));
      g.tick(0.01);
      expect(g.s.era, Era.lab);
      expect(g.events.whereType<EraUnlocked>().single.era, Era.lab);
    });

    test('eras never skip: Lab rating in the Garage only unlocks Startup', () {
      final g = Game();
      g.s.releases.add(
        const ModelRelease(name: 'x', effectiveCompute: 1e24, rating: 0, open: false, time: 0),
      );
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
