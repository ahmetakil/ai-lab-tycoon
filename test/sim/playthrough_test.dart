// Headless playthroughs with the sim bot, at the 1 s / 3 s settings of
// tool/balance_sim.dart (a casual run takes a few seconds), so the numbers
// here match docs/BALANCE.md.
import 'package:ai_lab_tycoon/sim/balance.dart';
import 'package:ai_lab_tycoon/sim/bot.dart';
import 'package:ai_lab_tycoon/sim/content.dart';
import 'package:flutter_test/flutter_test.dart';

const _h = 3600.0;

PlaythroughResult? _casual;
PlaythroughResult get casualRun => _casual ??= runSchedule();

void main() {
  group('casual schedule (4 sessions a day, offline in between)', () {
    late PlaythroughResult r;
    setUpAll(() => r = casualRun);

    test('the ladder takes two to three days of wall-clock time', () {
      expect(r.ladderDone, isTrue, reason: 'stuck at rival ${r.game.s.rivalIndex}/${rivalLadder.length}');
      expect(r.finishTime!, inInclusiveRange(44 * _h, 72 * _h));
    });

    test('eras arrive on schedule', () {
      final e = r.eraTimes;
      expect(e[Era.startup]!, inInclusiveRange(6 * 60, 16 * 60)); // first session hook
      expect(e[Era.smallLab]!, inInclusiveRange(30 * 60, 2 * _h));
      expect(e[Era.mediumLab]!, inInclusiveRange(4 * _h, 14 * _h));
      expect(e[Era.bigLab]!, inInclusiveRange(18 * _h, 34 * _h));
      expect(e[Era.globalLab]!, inInclusiveRange(28 * _h, 50 * _h));
      for (var i = 1; i < Era.values.length; i++) {
        expect(e[Era.values[i]]!, greaterThanOrEqualTo(e[Era.values[i - 1]]!));
      }
    });

    test('every session has something to do', () {
      // Longest active stretch with no purchase, release or new run.
      expect(r.longestIdle, lessThan(15 * 60));
      for (final s in r.sessions.skip(1)) {
        expect(s.firstDecisionAfter, lessThan(60), reason: 'session ${s.index}');
        expect(s.decisions, greaterThanOrEqualTo(2), reason: 'session ${s.index}');
      }
      // A training run usually finishes while you're away.
      final ranAway = r.sessions.skip(1).where((s) => s.runFinishedAway).length;
      expect(ranAway, greaterThanOrEqualTo(r.sessions.length - 2));
    });

    test('numbers stay sane', () {
      expect(r.maxUsersSeen, lessThanOrEqualTo(maxUsers));
      expect(r.minMoney, greaterThanOrEqualTo(0));
      expect(r.arrAtFinish, lessThan(150e9));
      expect(r.usersAtFinish, greaterThanOrEqualTo(rivalLadder.last.users));
    });

    test('it moves all the way to the last room and trains one well-fed cluster', () {
      final g = r.game;
      expect(g.currentRoom.id, rooms.last.id);
      expect(g.s.grids.keys, [rooms.last.id]);
      final c = g.trainingCluster!;
      expect(c.roomId, 'gigasite');
      expect(c.scalingEfficiency, greaterThan(0.95));
      expect(g.clusters('gigasite'), hasLength(1));
      expect(g.rawTflops / g.peakTflops, greaterThan(0.9));
      expect(g.s.networkTier, networkTiers.length - 1);
      expect(g.s.coolingTier, greaterThan(0));
    });
  });

  test('continuous play finishes about as fast as casual (offline earns at full rate)', () {
    final c = runPlaythrough(maxSeconds: 72 * _h, dt: 3, thinkEvery: 6);
    final casual = casualRun;
    expect(c.ladderDone, isTrue);
    expect(c.finishTime!, inInclusiveRange(25 * _h, 66 * _h));
    expect(c.finishTime!, lessThan(casual.finishTime! + 8 * _h));
    expect(c.eraTimes[Era.startup]!, lessThan(16 * 60));
  });

  test('placement and software matter: naive, random and hardware-only fall far behind', () {
    PlaythroughResult run({BotStrategy s = BotStrategy.balanced, BotLayout l = BotLayout.template}) =>
        runSchedule(strategy: s, layout: l);
    final template = casualRun;
    final naive = run(l: BotLayout.naive);
    final random = run(l: BotLayout.random);
    final hwOnly = run(s: BotStrategy.hardwareOnly);
    // Bad placement (no coolers / random coolers) throttles the early rooms
    // (the cooling puzzle): the Small lab comes hours later. Late rooms have
    // central cooling, so they catch up some but still finish later.
    for (final (name, x) in [('naive', naive), ('random', random)]) {
      expect(x.eraTimes[Era.smallLab]!, greaterThan(template.eraTimes[Era.smallLab]! + 2 * _h), reason: name);
      expect(x.ladderDone ? x.finishTime! : double.infinity,
          greaterThan(template.finishTime! + 3 * _h), reason: name);
    }
    expect(naive.finishTime ?? double.infinity, greaterThan(template.finishTime! + 12 * _h));
    // Hardware alone never gets out of the Small lab.
    expect(hwOnly.ladderDone, isFalse);
    expect(hwOnly.game.s.era.index, lessThanOrEqualTo(Era.smallLab.index));
    expect(hwOnly.game.s.rivalIndex, lessThan(template.game.s.rivalIndex ~/ 3));
  });

  test('early game: the bot cools hot GPUs, upgrades its network and moves out', () {
    final garage = runPlaythrough(maxSeconds: 11 * 60, stopWhenDone: false).game;
    expect(garage.currentRoom.id, 'garage');
    expect(garage.s.tileCounts.keys.where((id) => id.startsWith('cool_')), isNotEmpty);
    final closet = runPlaythrough(maxSeconds: 14 * 60, stopWhenDone: false).game;
    expect(closet.currentRoom.id, 'closet');
    expect(closet.s.networkTier, greaterThanOrEqualTo(1));
    expect(closet.trainingCluster!.gpus, greaterThanOrEqualTo(4));
    expect(closet.trainingCluster!.scalingEfficiency, 1);
  });
}
