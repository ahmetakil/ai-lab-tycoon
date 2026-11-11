// ignore_for_file: avoid_print
// Headless playthrough with the sim bot (lib/sim/bot.dart). Prints the
// progression curve so you can tune lib/sim/balance.dart without the UI.
//
//   dart run tool/balance_sim.dart [minutes=360] [--log-every=10]
//       [--strategy=balanced|hardware-only|software-first|no-upgrades]
//       [--layout=template|naive|random] [--seed=12345]
//       [--compare] [--schedule=casual|continuous] [--dt=1]
//
// --compare runs every strategy (template layout) plus the naive and random
// layouts, and prints a summary table only.
// --schedule=casual plays sessions with offline gaps (lib/sim/bot.dart,
// PlaySchedule.casual) for [minutes] of wall-clock time and prints the
// wall-clock timeline plus a per-session table. With --compare it compares
// strategies on that schedule.
import 'dart:math' as math;

import 'package:ai_lab_tycoon/sim/balance.dart';
import 'package:ai_lab_tycoon/sim/bot.dart';
import 'package:ai_lab_tycoon/sim/content.dart';
import 'package:ai_lab_tycoon/sim/game.dart';

void main(List<String> args) {
  final minutes =
      args.isNotEmpty && !args.first.startsWith('--')
          ? double.parse(args.first)
          : 360.0;
  String? opt(String name) =>
      args
          .where((a) => a.startsWith('--$name='))
          .map((a) => a.split('=').last)
          .firstOrNull;
  final logEvery = double.parse(opt('log-every') ?? '10');
  final strategy = parseStrategy(opt('strategy') ?? 'balanced');
  final layout = BotLayout.values.byName(opt('layout') ?? 'template');
  final seed = int.parse(opt('seed') ?? '12345');
  final dt = double.parse(opt('dt') ?? '1');
  final schedule = PlaySchedule.byName(opt('schedule') ?? 'continuous');

  if (args.contains('--compare')) {
    compare(minutes, seed, schedule: schedule, dt: dt);
    return;
  }
  if (schedule != null) {
    scheduled(schedule, minutes, seed, strategy, layout, dt);
    return;
  }

  var nextLog = 0.0;
  print('strategy: ${strategy.name}, layout: ${layout.name}\n');
  print(
    'time  | money      | rev/s     | ARR        | users      | rating | GPUs    | power kW        | util | train cluster          | rooms | era',
  );
  final r = runPlaythrough(
    strategy: strategy,
    layout: layout,
    maxSeconds: minutes * 60,
    stopWhenDone: false,
    seed: seed,
    dt: dt,
    onEvent: (g, e) {
      final t = fmtTime(g.s.time);
      switch (e) {
        case EraUnlocked(:final era):
          print('$t  >>> ERA: ${era.label}');
        case RivalBeaten(:final rival):
          print('$t  >>> BEAT ${rival.lab} ${rival.model} (${rival.year})');
        case ViralSpikeStarted():
          print(
            '$t  !!! viral spike (capacity ${fmt(g.capacity)}, users ${fmt(g.s.users)})',
          );
        case ModelReleased():
        case TrainingFinished():
          break;
      }
    },
    onTick: (g) {
      if (g.s.time < nextLog) return;
      nextLog += logEvery * 60;
      final gpus = g.totalGpus;
      final c = g.trainingCluster;
      final cluster =
          c == null
              ? '—'
              : '${fmt(c.gpus)} GPU ${c.roomId} ${(c.scalingEfficiency * 100).toStringAsFixed(0)}%';
      print(
        '${fmtTime(g.s.time)} | ${fmt(g.s.money, 10)} | ${fmt(g.revenuePerSecond, 9)} | '
        '${fmt(g.arr, 10)} | ${fmt(g.s.users, 10)} | ${g.rating.toStringAsFixed(0).padLeft(6)} | '
        '${fmt(gpus, 7)} | ${fmt(g.powerUsedKw, 7)}/${fmt(g.powerCapKw, 7)} | '
        '${g.utilization.toStringAsFixed(2)} | ${cluster.padRight(22)} | '
        '${g.ownedRooms.length.toString().padLeft(5)} | '
        'pb ${(g.hardwareValue / math.max(1e-9, g.revenuePerSecond) / 60).toStringAsFixed(0).padLeft(4)}m | ${g.s.era.label}'
        '${g.overloaded ? ' OVERLOADED' : ''}${g.dataLimited ? ' data-limited' : ''}',
      );
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
  print('\n=== summary (${r.strategy.name}, ${r.layout.name}) ===');
  for (final e in r.eraTimes.entries) {
    print('era ${e.key.label.padRight(8)} ${fmtTime(e.value)}');
  }
  for (final (rival, t) in r.rivalTimes) {
    print('rival ${fmtTime(t)}  ${rival.lab} ${rival.model} (${rival.year})');
  }
  print(
    'rivals beaten: ${g.s.rivalIndex}/${rivalLadder.length}; '
    'upgrades: ${g.s.ownedUpgrades.length}/${upgrades.length}; '
    'releases: ${r.releases}; viral spikes: ${r.viralSpikes}',
  );
  print(
    'overloaded ${(r.overloadedFraction * 100).toStringAsFixed(1)}% of the time '
    '(${(100 * r.overloadedViralSeconds / r.seconds).toStringAsFixed(1)}% during viral spikes); '
    'longest stretch without a purchase/release: ${(r.longestIdle / 60).toStringAsFixed(1)} min '
    '(from ${fmtTime(r.longestIdleStart)})',
  );
  if (r.ladderDone) {
    print(
      'at the final rival: ${fmt(r.usersAtFinish)} users, ARR ${fmt(r.arrAtFinish)}, '
      '${fmt(r.h100eAtFinish)} H100-equivalents, ${fmt(r.powerKwAtFinish / 1000)} MW',
    );
  }
  print(
    'longest gap between rival wins: ${(r.longestRivalGap / 60).toStringAsFixed(0)} min',
  );
  print(
    'max users ${fmt(r.maxUsersSeen)} (cap ${fmt(maxUsers)}); '
    'final money ${fmt(g.s.money)}, ARR ${fmt(g.arr)}; '
    'power ${fmt(g.powerUsedKw)} kW; H100e ${fmt(h100e(g))}',
  );
}

double h100e(Game g) => g.peakTflops / 990;

void compare(
  double minutes,
  int seed, {
  PlaySchedule? schedule,
  double dt = 1,
}) {
  PlaythroughResult run(BotStrategy s, BotLayout l) =>
      schedule == null
          ? runPlaythrough(
            strategy: s,
            layout: l,
            maxSeconds: minutes * 60,
            seed: seed,
            dt: dt,
          )
          : runSchedule(
            schedule: schedule,
            strategy: s,
            layout: l,
            maxWallSeconds: minutes * 60,
            seed: seed,
            dt: dt,
          );
  final results = [
    for (final s in BotStrategy.values) run(s, BotLayout.template),
    for (final l in [BotLayout.naive, BotLayout.random])
      run(BotStrategy.balanced, l),
  ];
  String t(double? s) => s == null ? '   —  ' : fmtTime(s);
  print(
    '${schedule?.name ?? 'continuous'}, ${fmtTime(minutes * 60)} cap\n'
    'strategy / layout        | ${[for (final e in Era.values.skip(1)) e.shortLabel.padRight(12)].join(' | ')} | final  | rivals',
  );
  for (final r in results) {
    print(
      '${'${r.strategy.name} / ${r.layout.name}'.padRight(23)} | '
      '${[for (final e in Era.values.skip(1)) t(r.eraTimes[e]).padRight(12)].join(' | ')} | '
      '${t(r.finishTime)} | '
      '${r.game.s.rivalIndex.toString().padLeft(2)}/${rivalLadder.length}',
    );
  }
}

void scheduled(
  PlaySchedule schedule,
  double minutes,
  int seed,
  BotStrategy strategy,
  BotLayout layout,
  double dt,
) {
  print(
    'schedule: ${schedule.name}, strategy: ${strategy.name}, layout: ${layout.name}'
    ' (times are wall-clock, offline gaps included)\n',
  );
  final r = runSchedule(
    schedule: schedule,
    strategy: strategy,
    layout: layout,
    maxWallSeconds: minutes * 60,
    seed: seed,
    dt: dt,
    onEvent: (g, e, wall) {
      final t = '${fmtTime(wall)} (sim ${fmtTime(g.s.time)})';
      switch (e) {
        case EraUnlocked(:final era):
          print('$t  >>> ERA: ${era.label}');
        case RivalBeaten(:final rival):
          print('$t  >>> BEAT ${rival.lab} ${rival.model} (${rival.year})');
        default:
          break;
      }
    },
  );
  print(
    '\nsess | wall start | sim start | len | era at start | ran away | 1st act | decisions (buy/rel) | idle max | rivals | eras',
  );
  for (final s in r.sessions) {
    print(
      '${s.index.toString().padLeft(4)} | ${fmtTime(s.wallStart).padLeft(10)} | '
      '${fmtTime(s.simStart).padLeft(9)} | ${(s.length / 60).toStringAsFixed(0).padLeft(3)} | '
      '${s.eraAtStart.label.padRight(12)} | ${(s.runFinishedAway ? 'yes' : '-').padRight(8)} | '
      '${s.firstDecisionAfter.isInfinite ? '   —' : '${s.firstDecisionAfter.toStringAsFixed(0).padLeft(3)}s'}   | '
      '${'${s.decisions.toString().padLeft(4)} (${s.purchases}/${s.releases})'.padRight(19)}'
      ' | ${(s.longestIdle / 60).toStringAsFixed(1).padLeft(5)}m | ${s.rivalsBeaten.toString().padLeft(6)} | '
      '${s.erasUnlocked.map((e) => e.shortLabel).join(', ')}',
    );
  }
  final g = r.game;
  print('\n=== summary (${schedule.name}) ===');
  for (final e in r.eraTimes.entries) {
    print('era ${e.key.label.padRight(14)} ${fmtTime(e.value)}');
  }
  print(
    'rivals beaten: ${g.s.rivalIndex}/${rivalLadder.length}; '
    'upgrades: ${g.s.ownedUpgrades.length}/${upgrades.length}; '
    'releases: ${r.releases}; viral spikes: ${r.viralSpikes}',
  );
  if (r.ladderDone) {
    print(
      'final rival at ${fmtTime(r.finishTime!)} wall-clock '
      '(sim ${fmtTime(r.simFinishTime!)}, ${r.sessions.length} sessions, '
      '${fmtTime(r.sessions.fold(0.0, (a, s) => a + s.length))} active): '
      '${fmt(r.usersAtFinish)} users, ARR ${fmt(r.arrAtFinish)}, '
      '${fmt(r.h100eAtFinish)} H100e, ${fmt(r.powerKwAtFinish / 1000)} MW',
    );
  }
  print(
    'longest active stretch with nothing done: ${(r.longestIdle / 60).toStringAsFixed(1)} min '
    '(session starting ${fmtTime(r.longestIdleStart)}); '
    'sessions with a finished run on return: '
    '${r.sessions.where((s) => s.runFinishedAway).length}/${r.sessions.length}',
  );
  final ds = r.sessions.map((s) => s.decisions).toList()..sort();
  if (ds.isNotEmpty) {
    print(
      'decisions per session: min ${ds.first}, median ${ds[ds.length ~/ 2]}, max ${ds.last}',
    );
  }
  print(
    'max users ${fmt(r.maxUsersSeen)}; min money ${fmt(r.minMoney)}; '
    'final money ${fmt(g.s.money)}, ARR ${fmt(g.arr)}',
  );
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
