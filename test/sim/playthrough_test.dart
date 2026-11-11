// Headless playthroughs with the sim bot. Long schedules use a coarse step
// (and a bot that looks every 6-10 s) so the suite stays quick; the numbers
// barely move compared with the 1 s / 3 s settings of tool/balance_sim.dart.
import 'package:ai_lab_tycoon/sim/balance.dart';
import 'package:ai_lab_tycoon/sim/bot.dart';
import 'package:ai_lab_tycoon/sim/content.dart';
import 'package:flutter_test/flutter_test.dart';

const _h = 3600.0;

PlaythroughResult? _casual;
PlaythroughResult get casualRun => _casual ??= runSchedule(dt: 3, thinkEvery: 6);

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

    test('it builds every room and trains on one big, well-fed cluster', () {
      final g = r.game;
      expect(g.ownedRooms.map((r) => r.id), rooms.map((r) => r.id));
      final c = g.trainingCluster!;
      expect(c.roomId, 'gigasite');
      expect(c.scalingEfficiency, 1);
      for (final room in g.ownedRooms) {
        expect(g.clusters(room.id).where((c) => c.networked), hasLength(1), reason: room.id);
      }
      expect(g.rawTflops / g.peakTflops, greaterThan(0.9));
    });
  });

  test('continuous play is faster than casual, but not trivially', () {
    final c = runPlaythrough(maxSeconds: 60 * _h, dt: 6, thinkEvery: 12);
    final casual = casualRun;
    expect(c.ladderDone, isTrue);
    expect(c.finishTime!, inInclusiveRange(25 * _h, 55 * _h));
    expect(c.finishTime!, lessThan(casual.finishTime!));
    expect(c.eraTimes[Era.startup]!, lessThan(16 * 60));
  });

  test('placement and software matter: naive, random and hardware-only fall far behind', () {
    const wall = 40 * _h;
    PlaythroughResult run({BotStrategy s = BotStrategy.balanced, BotLayout l = BotLayout.template}) =>
        runSchedule(strategy: s, layout: l, maxWallSeconds: wall, dt: 3, thinkEvery: 6, stopWhenDone: false);
    final template = run();
    final naive = run(l: BotLayout.naive);
    final random = run(l: BotLayout.random);
    final hwOnly = run(s: BotStrategy.hardwareOnly);
    final best = template.game.s.rivalIndex;
    for (final (name, x) in [('naive', naive), ('random', random), ('hardware-only', hwOnly)]) {
      expect(x.game.s.rivalIndex, lessThan(best * 0.75), reason: name);
      expect(x.game.rating, lessThan(template.game.rating - 60), reason: name);
      expect(x.game.s.era.index, lessThan(template.game.s.era.index), reason: name);
    }
  });

  test('early game: the bot networks its GPUs and cools the hot ones', () {
    final r = runPlaythrough(maxSeconds: 14 * 60, stopWhenDone: false);
    final counts = r.game.s.tileCounts;
    expect(counts.keys.where((id) => id.startsWith('net_')), isNotEmpty);
    expect(counts.keys.where((id) => id.startsWith('cool_')), isNotEmpty);
    expect(r.game.trainingCluster!.gpus, greaterThanOrEqualTo(4));
  });
}
