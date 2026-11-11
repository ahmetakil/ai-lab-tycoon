// ignore_for_file: avoid_print
// Headless playthrough with a simple greedy bot. Prints the progression curve
// so you can tune lib/sim/balance.dart without touching the UI.
//
//   dart run tool/balance_sim.dart [minutes=240] [--log-every=10]
import 'dart:math' as math;

import 'package:ai_lab_tycoon/sim/content.dart';
import 'package:ai_lab_tycoon/sim/game.dart';

void main(List<String> args) {
  final minutes = args.isNotEmpty && !args.first.startsWith('--')
      ? double.parse(args.first)
      : 240.0;
  final logEvery = args
          .where((a) => a.startsWith('--log-every='))
          .map((a) => double.parse(a.split('=').last))
          .firstOrNull ??
      10.0;

  final g = Game();
  final bot = GreedyBot(g);
  var nextLog = 0.0;

  print('time   | money      | rev/s     | ARR        | users      | rating | GPUs | power kW      | util | era');
  while (g.s.time < minutes * 60) {
    bot.act();
    g.tick(1);
    for (final e in g.events) {
      final t = fmtTime(g.s.time);
      switch (e) {
        case EraUnlocked(:final era):
          print('$t  >>> ERA: ${era.label}');
        case RivalBeaten(:final rival):
          print('$t  >>> BEAT ${rival.lab} ${rival.model} (${rival.year})');
        case ViralSpikeStarted():
          print('$t  !!! viral spike (capacity ${fmt(g.capacity)}, users ${fmt(g.s.users)})');
        case ModelReleased(:final release, :final stunt, :final stuntSucceeded):
          print('$t  --- released ${release.name}: rating ${release.rating.toStringAsFixed(0)}, '
              'effC ${release.effectiveCompute.toStringAsExponential(1)}'
              '${stunt.id == 'none' ? '' : ' (${stunt.name}${stuntSucceeded ? '' : ' FAILED'})'}');
        case TrainingFinished():
          break;
      }
    }
    g.events.clear();

    if (g.s.time >= nextLog) {
      nextLog += logEvery * 60;
      final gpus = g.s.hardwareCounts.values.fold(0, (a, b) => a + b);
      print('${fmtTime(g.s.time)} | ${fmt(g.s.money, 10)} | ${fmt(g.revenuePerSecond, 9)} | '
          '${fmt(g.arr, 10)} | ${fmt(g.s.users, 10)} | ${g.rating.toStringAsFixed(0).padLeft(6)} | '
          '${gpus.toString().padLeft(4)} | ${fmt(g.powerUsedKw, 6)}/${fmt(g.powerCapKw, 6)} | '
          '${g.utilization.toStringAsFixed(2)} | ${g.s.era.label}'
          '${g.overloaded ? ' OVERLOADED' : ''}${g.dataLimited ? ' data-limited' : ''}');
    }
  }
  print('\nupgrades owned: ${g.s.ownedUpgrades.length}/${upgrades.length}; '
      'rivals beaten: ${g.s.rivalIndex}/${rivalLadder.length}');
}

class GreedyBot {
  final Game g;
  GreedyBot(this.g);

  void act() {
    final s = g.s;
    if (s.pendingEffectiveCompute != null) {
      if (g.ratingOf(s.pendingEffectiveCompute!) > g.rating) {
        g.release(open: false, stuntId: 'cryptic_tweet');
      } else {
        g.discardPending();
      }
    }
    if (g.canStartTraining) {
      final duration = switch (s.era) {
        Era.garage => 120.0,
        Era.startup => 300.0,
        Era.lab => 600.0,
      };
      g.startTraining(fraction: 0.5, durationSeconds: duration);
    }
    if (s.viralSecondsLeft > 0 && g.overloaded) g.rentCloud();

    // Upgrades: buy the cheapest available one, or save for it if close.
    final available = upgrades
        .where((u) =>
            !s.ownedUpgrades.contains(u.id) &&
            g.isUnlocked(u.era) &&
            u.requires.every(s.ownedUpgrades.contains))
        .toList()
      ..sort((a, b) => a.cost.compareTo(b.cost));
    if (available.isNotEmpty) {
      final u = available.first;
      if (g.buyUpgrade(u.id)) return;
      if (u.cost < 60 * g.revenuePerSecond) return; // save up
    }

    // Hardware vs power: pick the best TFLOPS/$ unit; if power-blocked, buy power.
    final unlocked = hardware.where((h) => g.isUnlocked(h.era)).toList()
      ..sort((a, b) => (b.tflops / b.cost).compareTo(a.tflops / a.cost));
    final best = unlocked.first;
    final headroom = g.powerCapKw - g.powerUsedKw;
    if (headroom < best.powerKw * g.powerMult) {
      final next = g.nextPowerTier;
      if (next != null && g.isUnlocked(next.era)) {
        if (!g.buyNextPowerTier()) return; // save for power
      } else {
        return; // capped out; wait for next era
      }
    }
    final n = g.maxBuyable(best);
    if (n > 0) g.buyHardware(best.id, n);
  }
}

String fmtTime(double secs) {
  final m = (secs / 60).floor();
  return '${(m ~/ 60).toString().padLeft(2)}h${(m % 60).toString().padLeft(2, '0')}';
}

String fmt(double v, [int width = 0]) {
  String out;
  final a = v.abs();
  if (a >= 1e12) {
    out = '${(v / 1e12).toStringAsFixed(2)}T';
  } else if (a >= 1e9) {
    out = '${(v / 1e9).toStringAsFixed(2)}B';
  } else if (a >= 1e6) {
    out = '${(v / 1e6).toStringAsFixed(2)}M';
  } else if (a >= 1e3) {
    out = '${(v / 1e3).toStringAsFixed(1)}k';
  } else {
    out = v.toStringAsFixed(math.min(2, a < 10 ? 2 : 0));
  }
  return out.padLeft(width);
}
