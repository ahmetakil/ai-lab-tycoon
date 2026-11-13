// ignore_for_file: avoid_print
// Headless playthrough with the sim bot (lib/sim/bot.dart). Prints the
// progression curve so you can tune lib/sim/balance.dart without the UI.
//
//   dart run tool/balance_sim.dart [minutes=360] [--log-every=10]
//       [--strategy=balanced|hardware-only|software-first|no-upgrades]
//       [--layout=template|naive|random] [--seed=12345]
//       [--compare] [--schedule=active|casual] [--dt=1] [--phases]
//       [--seeds=12345,1,777]
//
// The default schedule is active (PlaySchedule.active: continuous play, the
// bot looks every 4 s); the summary lists idle stretches over 90 s.
// --compare runs every strategy (template layout) plus the naive and random
// layouts, and prints a summary table only.
// --schedule=casual plays sessions with offline gaps (lib/sim/bot.dart,
// PlaySchedule.casual) for [minutes] of wall-clock time and prints the
// wall-clock timeline plus a per-session table. With --compare it compares
// strategies on that schedule.
// --phases: the bot specializes at run-phase checkpoints (lib/sim/run_phases.dart)
// instead of taking the all-rounder defaults.
// --seeds=a,b,c: one active run per seed (played on to [minutes], past the
// final rival, to catch the post-game move to the orbital station); prints
// the milestone table, the orbital move and each
// room's fill when its way out (the next room's era) unlocks.
// Every single run ends with the same room table: GPU tiles, cells and power
// (of the building's top tier) when the next era unlocks, and how long the
// room had been at its wall (every cell used, or power ≥ 95% of the
// building's cap) by then.
import 'dart:math' as math;

import 'package:ai_lab_tycoon/sim/balance.dart';
import 'package:ai_lab_tycoon/sim/bot.dart';
import 'package:ai_lab_tycoon/sim/content.dart';
import 'package:ai_lab_tycoon/sim/game.dart';
import 'package:ai_lab_tycoon/sim/model_design.dart';

/// --phases (see the header).
var _specializePhases = false;

void main(List<String> args) {
  _specializePhases = args.contains('--phases');
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
  final schedule = PlaySchedule.byName(opt('schedule') ?? 'active');

  final seeds = opt('seeds');
  if (seeds != null) {
    multiSeed(minutes, [for (final s in seeds.split(',')) int.parse(s)], dt);
    return;
  }
  if (args.contains('--compare')) {
    compare(minutes, seed, schedule: schedule, dt: dt);
    return;
  }
  if (!schedule.continuous) {
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
    specializePhases: _specializePhases,
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
        case RoomMoved(:final to):
          print('$t  >>> MOVED to the ${to.name}');
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
        '${g.currentRoom.id.padLeft(8)} | '
        'pb ${(g.hardwareValue / math.max(1e-9, g.revenuePerSecond) / 60).toStringAsFixed(0).padLeft(4)}m | ${g.s.era.label}'
        '${g.overloaded ? ' OVERLOADED' : ''}${g.dataLimited ? ' data-limited' : ''}',
      );
    },
  );
  printSummary(r);
  printRoomFill(r.roomFill);
}

void printRoomFill(RoomFill fill) {
  print('\nroom fill when the next era unlocks (* the last room: at the final rival)\n'
      '(wall: no empty cell, or no GPU fits the power the building can take now)');
  print('room     | in at | exit era | GPU tiles | cells   | power used / cap         | at wall for (since first hit)');
  for (final s in fill.snaps.values) {
    print(
      '${s.room.id.padRight(8)} | ${fmtTime(s.enteredAt)} | ${s.exit ? fmtTime(s.at) : '${fmtTime(s.at)}*'}    | '
      '${s.gpuTiles.toString().padLeft(9)} | ${'${s.cellsUsed}/${s.room.cells}'.padLeft(7)} | '
      '${'${fmt(s.powerKw)} / ${fmt(s.capKw)} kW (${(100 * s.powerKw / s.capKw).toStringAsFixed(0)}%)'.padRight(24)} | '
      '${s.wallSeconds == null ? '-' : '${(s.wallSeconds! / 60).toStringAsFixed(1)} min'}'
      '${s.firstWallSeconds == null ? '' : ' (${(s.firstWallSeconds! / 60).toStringAsFixed(1)} min)'}',
    );
  }
}

/// --seeds: milestones (h:mm:ss) and the room table for each seed.
void multiSeed(double minutes, List<int> seeds, double dt) {
  String hms(double? s) {
    if (s == null) return '   —   ';
    final t = s.round();
    return '${t ~/ 3600}:${(t ~/ 60 % 60).toString().padLeft(2, '0')}:${(t % 60).toString().padLeft(2, '0')}';
  }

  final rows = <String>[];
  final fills = <String>[];
  final orbit = <String>[];
  for (final seed in seeds) {
    // Plays on past the final rival (to [minutes]) to catch the post-game
    // move to the orbital station; the last room's fill before it moved.
    var lastGpuTiles = 0, lastCells = 0;
    double? movedAt;
    int? leftGpuTiles, leftCells;
    final r = runPlaythrough(
      maxSeconds: minutes * 60,
      seed: seed,
      dt: dt,
      stopWhenDone: false,
      specializePhases: _specializePhases,
      onTick: (g) {
        lastGpuTiles = g.grid.rooms[g.currentRoom.id]?.gpuTiles ?? 0;
        lastCells = g.s.grids[g.currentRoom.id]!.where((c) => c != null).length;
      },
      onEvent: (g, e) {
        if (e case RoomMoved(:final from, :final to) when to.fromFill > 0) {
          movedAt = g.s.time;
          leftGpuTiles = lastGpuTiles;
          leftCells = lastCells;
          orbit.add(
            '${seed.toString().padRight(5)} | moved to the ${to.name} at ${hms(movedAt)}: '
            '${from.id} ${leftGpuTiles}g (${(100 * leftGpuTiles! / from.cells).toStringAsFixed(0)}% of cells), '
            '$leftCells/${from.cells} cells used',
          );
        }
      },
    );
    if (movedAt == null) orbit.add('${seed.toString().padRight(5)} | no orbital move by ${hms(minutes * 60)}');
    final fill = r.roomFill;
    rows.add(
      '${seed.toString().padRight(5)} | ${[for (final e in Era.values.skip(1)) hms(r.eraTimes[e]).padLeft(8)].join(' | ')} | '
      '${hms(r.finishTime).padLeft(8)} | ${(r.longestIdle / 60).toStringAsFixed(1)}m | '
      '${r.idleLog.length} idle>90s (${(r.idleLog.fold(0.0, (a, e) => a + e.$2) / 60).toStringAsFixed(0)} min)',
    );
    fills.add(
      '${seed.toString().padRight(5)} | ${[
        for (final s in fill.snaps.values)
          '${s.room.id} ${s.gpuTiles}g ${s.cellsUsed}/${s.room.cells} ${(100 * s.powerKw / s.capKw).toStringAsFixed(0)}% '
              'wall ${s.wallSeconds == null ? '-' : (s.wallSeconds! / 60).toStringAsFixed(1)}'
              '${s.firstWallSeconds == null ? '' : '/${(s.firstWallSeconds! / 60).toStringAsFixed(1)}'}',
      ].join(' | ')}',
    );
  }
  print('seed  | ${[for (final e in Era.values.skip(1)) e.shortLabel.padLeft(8)].join(' | ')} | final    | idle max | idle');
  rows.forEach(print);
  print('\nroom fill at its exit era: GPU tiles, cells used, power % of the building cap, minutes at the wall');
  fills.forEach(print);
  print('\npost-game: the move to the orbital station (gigasite fill on the tick before)');
  orbit.forEach(print);
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
    'upgrades: ${g.s.ownedUpgrades.length}/${allUpgrades.length}; '
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
  printIdle(r);
  print(
    'max users ${fmt(r.maxUsersSeen)} (cap ${fmt(maxUsers)}); '
    'final money ${fmt(g.s.money)}, ARR ${fmt(g.arr)}; '
    'power ${fmt(g.powerUsedKw)} kW; H100e ${fmt(h100e(g))}',
  );
}

/// Idle stretches (no purchase, release or new run) over 90 s.
void printIdle(PlaythroughResult r) {
  final log = r.idleLog;
  final over2 = log.where((e) => e.$2 >= 120).length;
  print(
    'idle stretches over 90 s: ${log.length} ($over2 of 2 min or more), '
    'total ${(log.fold(0.0, (a, e) => a + e.$2) / 60).toStringAsFixed(1)} min',
  );
  for (final (start, len, era, what) in log.take(400)) {
    print('  idle ${fmtTime(start)} ${(len / 60).toStringAsFixed(1).padLeft(4)} min  ${era.shortLabel.padRight(12)} saving for $what');
  }
}

double h100e(Game g) => g.peakTflops / 990;

void compare(
  double minutes,
  int seed, {
  required PlaySchedule schedule,
  double dt = 1,
}) {
  PlaythroughResult run(BotStrategy s, BotLayout l) =>
      schedule.continuous
          ? runPlaythrough(
            strategy: s,
            layout: l,
            maxSeconds: minutes * 60,
            seed: seed,
            dt: dt,
            specializePhases: _specializePhases,
          )
          : runSchedule(
            schedule: schedule,
            strategy: s,
            layout: l,
            maxWallSeconds: minutes * 60,
            seed: seed,
            dt: dt,
            specializePhases: _specializePhases,
          );
  final results = [
    for (final s in BotStrategy.values) run(s, BotLayout.template),
    for (final l in [BotLayout.naive, BotLayout.random])
      run(BotStrategy.balanced, l),
  ];
  String t(double? s) => s == null ? '   —  ' : fmtTime(s);
  print(
    '${schedule.name}, ${fmtTime(minutes * 60)} cap\n'
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
    specializePhases: _specializePhases,
    onEvent: (g, e, wall) {
      final t = '${fmtTime(wall)} (sim ${fmtTime(g.s.time)})';
      switch (e) {
        case EraUnlocked(:final era):
          print('$t  >>> ERA: ${era.label}');
        case RivalBeaten(:final rival):
          print('$t  >>> BEAT ${rival.lab} ${rival.model} (${rival.year})');
        case RoomMoved(:final to):
          print('$t  >>> MOVED to the ${to.name}');
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
    'upgrades: ${g.s.ownedUpgrades.length}/${allUpgrades.length}; '
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
