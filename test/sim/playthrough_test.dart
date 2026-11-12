// Headless playthroughs with the sim bot, at the settings of
// tool/balance_sim.dart (1 s ticks, the active schedule's 4 s reaction), so
// the numbers here match docs/BALANCE.md. An active run takes a few seconds.
import 'package:ai_lab_tycoon/sim/balance.dart';
import 'package:ai_lab_tycoon/sim/bot.dart';
import 'package:ai_lab_tycoon/sim/content.dart';
import 'package:ai_lab_tycoon/sim/model_design.dart';
import 'package:flutter_test/flutter_test.dart';

const _h = 3600.0;
const _m = 60.0;

PlaythroughResult? _active;
PlaythroughResult get activeRun => _active ??= runSchedule();

void main() {
  group('active schedule (continuous play, a few seconds to react)', () {
    late PlaythroughResult r;
    setUpAll(() => r = activeRun);

    test('the ladder takes 6-8 hours of active play', () {
      expect(r.ladderDone, isTrue, reason: 'stuck at rival ${r.game.s.rivalIndex}/${rivalLadder.length}');
      expect(r.finishTime!, inInclusiveRange(6 * _h, 8 * _h));
    });

    test('eras arrive on schedule', () {
      final e = r.eraTimes;
      // Targets (docs/BALANCE.md) with a few minutes of slack for seeds.
      expect(e[Era.startup]!, inInclusiveRange(3 * _m, 5 * _m));
      expect(e[Era.smallLab]!, inInclusiveRange(15 * _m, 25 * _m));
      expect(e[Era.mediumLab]!, inInclusiveRange(75 * _m, 105 * _m));
      expect(e[Era.bigLab]!, inInclusiveRange(2.9 * _h, 4 * _h));
      expect(e[Era.globalLab]!, inInclusiveRange(4.4 * _h, 5.5 * _h));
      for (var i = 1; i < Era.values.length; i++) {
        expect(e[Era.values[i]]!, greaterThanOrEqualTo(e[Era.values[i - 1]]!));
      }
    });

    test('a steady stream of decisions, never two idle minutes', () {
      // Longest stretch with no purchase, release, new run, checkpoint call
      // or viral-spike response.
      expect(r.longestIdle, lessThan(2 * _m));
      // About one decision every 30-90 s on average.
      expect(r.finishTime! / r.decisions, inInclusiveRange(15, 90));
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

  test('other seeds land in the same window', () {
    for (final seed in [1, 777]) {
      final r = runSchedule(seed: seed);
      expect(r.ladderDone, isTrue, reason: 'seed $seed');
      expect(r.finishTime!, inInclusiveRange(6 * _h, 8 * _h), reason: 'seed $seed');
      expect(r.longestIdle, lessThan(2 * _m), reason: 'seed $seed');
    }
  });

  test('specialized run-phase picks stay in the window too', () {
    final r = runSchedule(specializePhases: true);
    expect(r.ladderDone, isTrue);
    expect(r.finishTime!, inInclusiveRange(6 * _h, 8 * _h));
    expect(r.longestIdle, lessThan(2 * _m));
  });

  test('casual sessions still finish; offline helps only a little', () {
    // 4 sessions a day (3 h 15 of play), 2 h offline cap at 10% earnings.
    final c = runSchedule(schedule: PlaySchedule.casual, maxWallSeconds: 72 * _h);
    expect(c.ladderDone, isTrue);
    expect(c.finishTime!, inInclusiveRange(20 * _h, 48 * _h));
    final played = c.sessions.fold(0.0, (a, s) => a + s.length);
    // Breaks shave off some play, but most of the game is still played.
    expect(played, greaterThan(0.8 * activeRun.finishTime!));
    expect(c.longestIdle, lessThan(2 * _m));
  });

  test('placement and software matter: naive, random and hardware-only fall behind', () {
    PlaythroughResult run({BotStrategy s = BotStrategy.balanced, BotLayout l = BotLayout.template}) =>
        runSchedule(strategy: s, layout: l);
    final template = activeRun;
    final naive = run(l: BotLayout.naive);
    final random = run(l: BotLayout.random);
    final hwOnly = run(s: BotStrategy.hardwareOnly);
    // Bad placement (no coolers / random coolers) throttles the early rooms
    // (the cooling puzzle): the Small lab comes later and so does the end.
    for (final (name, x) in [('naive', naive), ('random', random)]) {
      expect(x.eraTimes[Era.smallLab]!, greaterThan(template.eraTimes[Era.smallLab]! + 8 * _m), reason: name);
      expect(x.ladderDone ? x.finishTime! : double.infinity,
          greaterThan(template.finishTime! + 30 * _m), reason: name);
    }
    // Hardware alone stalls by the Small lab.
    expect(hwOnly.ladderDone, isFalse);
    expect(hwOnly.game.s.era.index, lessThanOrEqualTo(Era.smallLab.index));
    expect(hwOnly.game.s.rivalIndex, lessThan(template.game.s.rivalIndex ~/ 3));
  });

  test('early game: the bot cools hot GPUs, upgrades its network and moves out', () {
    final garage = runPlaythrough(maxSeconds: 4 * _m, stopWhenDone: false).game;
    expect(garage.currentRoom.id, 'garage');
    expect(garage.s.tileCounts.keys.where((id) => id.startsWith('cool_')), isNotEmpty);
    final closet = runPlaythrough(maxSeconds: 8 * _m, stopWhenDone: false).game;
    expect(closet.currentRoom.id, 'closet');
    expect(closet.s.networkTier, greaterThanOrEqualTo(1));
    expect(closet.trainingCluster!.gpus, greaterThanOrEqualTo(4));
    expect(closet.trainingCluster!.scalingEfficiency, 1);
  });

  test('bad model design: a huge under-trained base model falls far behind', () {
    // Big & short (2 tokens/param), web crawl only, full attention, 2k
    // context, no post-training: the bot plays normally otherwise.
    const bad = ModelSpec(
      sizing: Sizing.bigShort,
      postTraining: PostTraining.none,
      dataMix: DataMix.web,
      context: ContextLength.k2,
    );
    final r = runSchedule(fixedSpec: bad, maxWallSeconds: 8 * _h);
    final template = activeRun;
    // Every release is a base model: much lower rating per run and few users.
    final designed = r.game.s.releases.where((m) => m.design != null).toList();
    expect(designed, isNotEmpty);
    expect(designed.every((m) => m.design!.spec.postTraining == PostTraining.none), isTrue);
    expect(r.game.rating, lessThan(template.game.rating - 100));
    expect(r.game.s.rivalIndex, lessThan(template.game.s.rivalIndex ~/ 2));
    expect(r.ladderDone, isFalse);
  });
}
