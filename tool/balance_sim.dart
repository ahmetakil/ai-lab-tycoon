// ignore_for_file: avoid_print
// Headless playthrough with the sim bot (lib/sim/bot.dart). Prints the
// progression curve so you can tune lib/sim/balance.dart without the UI.
//
//   dart run tool/balance_sim.dart [minutes=360] [--log-every=10]
//       [--strategy=balanced|hardware-only|software-first|no-upgrades]
//       [--seed=12345]
//       [--compare]
//
// --compare runs all three strategies and prints a summary table only.
import 'dart:math' as math;

import 'package:ai_lab_tycoon/sim/balance.dart';
import 'package:ai_lab_tycoon/sim/bot.dart';
import 'package:ai_lab_tycoon/sim/content.dart';
import 'package:ai_lab_tycoon/sim/game.dart';

void main(List<String> args) {
  final minutes = args.isNotEmpty && !args.first.startsWith('--')
      ? double.parse(args.first)
      : 360.0;
  String? opt(String name) => args
      .where((a) => a.startsWith('--$name='))
      .map((a) => a.split('=').last)
      .firstOrNull;
  final logEvery = double.parse(opt('log-every') ?? '10');
  final strategy = parseStrategy(opt('strategy') ?? 'balanced');
  final seed = int.parse(opt('seed') ?? '12345');

  if (args.contains('--compare')) {
    compare(minutes, seed);
    return;
  }

  var nextLog = 0.0;
  print('strategy: ${strategy.name}\n');
  print('time  | money      | rev/s     | ARR        | users      | rating | GPUs    | power kW        | util | era');
  final r = runPlaythrough(
    strategy: strategy,
    maxSeconds: minutes * 60,
    stopWhenDone: false,
    seed: seed,
    onEvent: (g, e) {
      final t = fmtTime(g.s.time);
      switch (e) {
        case EraUnlocked(:final era):
          print('$t  >>> ERA: ${era.label}');
        case RivalBeaten(:final rival):
          print('$t  >>> BEAT ${rival.lab} ${rival.model} (${rival.year})');
        case ViralSpikeStarted():
          print('$t  !!! viral spike (capacity ${fmt(g.capacity)}, users ${fmt(g.s.users)})');
        case ModelReleased():
        case TrainingFinished():
          break;
      }
    },
    onTick: (g) {
      if (g.s.time < nextLog) return;
      nextLog += logEvery * 60;
      final gpus = g.s.hardwareCounts.values.fold(0, (a, b) => a + b);
      print('${fmtTime(g.s.time)} | ${fmt(g.s.money, 10)} | ${fmt(g.revenuePerSecond, 9)} | '
          '${fmt(g.arr, 10)} | ${fmt(g.s.users, 10)} | ${g.rating.toStringAsFixed(0).padLeft(6)} | '
          '${fmt(gpus.toDouble(), 7)} | ${fmt(g.powerUsedKw, 7)}/${fmt(g.powerCapKw, 7)} | '
          '${g.utilization.toStringAsFixed(2)} | ${g.s.era.label}'
          '${g.overloaded ? ' OVERLOADED' : ''}${g.dataLimited ? ' data-limited' : ''}');
    },
  );
  printSummary(r);
}

BotStrategy parseStrategy(String s) => switch (s) {
      'balanced' => BotStrategy.balanced,
      'hardware-only' => BotStrategy.hardwareOnly,
      'software-first' => BotStrategy.softwareFirst,
      'no-upgrades' => BotStrategy.noUpgrades,
      _ => throw ArgumentError('unknown strategy $s'),
    };

void printSummary(PlaythroughResult r) {
  final g = r.game;
  print('\n=== summary (${r.strategy.name}) ===');
  for (final e in r.eraTimes.entries) {
    print('era ${e.key.label.padRight(8)} ${fmtTime(e.value)}');
  }
  for (final (rival, t) in r.rivalTimes) {
    print('rival ${fmtTime(t)}  ${rival.lab} ${rival.model} (${rival.year})');
  }
  print('rivals beaten: ${g.s.rivalIndex}/${rivalLadder.length}; '
      'upgrades: ${g.s.ownedUpgrades.length}/${upgrades.length}; '
      'releases: ${r.releases}; viral spikes: ${r.viralSpikes}');
  print('overloaded ${(r.overloadedFraction * 100).toStringAsFixed(1)}% of the time '
      '(${(100 * r.overloadedViralSeconds / r.seconds).toStringAsFixed(1)}% during viral spikes); '
      'longest stretch without a purchase/release: ${(r.longestIdle / 60).toStringAsFixed(1)} min '
      '(from ${fmtTime(r.longestIdleStart)})');
  if (r.ladderDone) {
    print('at the final rival: ${fmt(r.usersAtFinish)} users, ARR ${fmt(r.arrAtFinish)}, '
        '${fmt(r.h100eAtFinish)} H100-equivalents, ${fmt(r.powerKwAtFinish / 1000)} MW');
  }
  print('longest gap between rival wins: ${(r.longestRivalGap / 60).toStringAsFixed(0)} min');
  print('max users ${fmt(r.maxUsersSeen)} (cap ${fmt(maxUsers)}); '
      'final money ${fmt(g.s.money)}, ARR ${fmt(g.arr)}; '
      'power ${fmt(g.powerUsedKw)} kW; H100e ${fmt(h100e(g))}');
}

double h100e(Game g) => hardware.fold(
    0.0, (a, h) => a + (g.s.hardwareCounts[h.id] ?? 0) * h.tflops / 990);

void compare(double minutes, int seed) {
  final results = [
    for (final s in BotStrategy.values)
      runPlaythrough(strategy: s, maxSeconds: minutes * 60, seed: seed),
  ];
  String t(double? s) => s == null ? '   —  ' : fmtTime(s);
  double? rivalAt(PlaythroughResult r, int n) =>
      r.rivalTimes.length >= n ? r.rivalTimes[n - 1].$2 : null;
  print('strategy        | Startup | Lab    | rival 5 | rival 10 | rival 15 | final  | rivals | overload');
  for (final r in results) {
    print('${r.strategy.name.padRight(15)} | ${t(r.eraTimes[Era.startup])}  | '
        '${t(r.eraTimes[Era.lab])} | ${t(rivalAt(r, 5))}  | ${t(rivalAt(r, 10))}   | '
        '${t(rivalAt(r, 15))}   | ${t(r.finishTime)} | '
        '${r.game.s.rivalIndex.toString().padLeft(2)}/${rivalLadder.length}  | '
        '${(r.overloadedFraction * 100).toStringAsFixed(1)}%');
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
