import 'package:ai_lab_tycoon/sim/balance.dart';
import 'package:ai_lab_tycoon/sim/bot.dart';
import 'package:ai_lab_tycoon/sim/content.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('bot playthrough (balanced, template layout)', () {
    late PlaythroughResult r;
    setUpAll(() => r = runPlaythrough(maxSeconds: 6 * 3600));

    test('finishes the whole ladder within 6 simulated hours', () {
      expect(
        r.ladderDone,
        isTrue,
        reason: 'stuck at rival ${r.game.s.rivalIndex}/${rivalLadder.length}',
      );
      expect(r.finishTime!, lessThan(6 * 3600));
      expect(r.finishTime!, greaterThan(3.5 * 3600)); // not trivially fast
    });

    test('first session: Startup, Lab and early rivals on schedule', () {
      expect(r.eraTimes[Era.startup]!, inInclusiveRange(6 * 60, 14 * 60));
      expect(r.eraTimes[Era.lab]!, inInclusiveRange(30 * 60, 55 * 60));
      final early = r.rivalTimes.where((x) => x.$2 <= 30 * 60);
      expect(early.length, greaterThanOrEqualTo(2));
    });

    test('no dead stretches, overload is occasional, numbers stay sane', () {
      expect(r.longestIdle, lessThan(10.5 * 60));
      expect(r.overloadedFraction, lessThan(0.15));
      expect(r.viralSpikes, greaterThan(3));
      expect(r.maxUsersSeen, lessThanOrEqualTo(maxUsers));
      expect(r.minMoney, greaterThanOrEqualTo(0));
      expect(r.arrAtFinish, lessThan(200e9)); // credible 2026-lab revenue
    });

    test('it builds every room and trains on one big, well-fed cluster', () {
      final g = r.game;
      expect(g.ownedRooms.map((r) => r.id), rooms.map((r) => r.id));
      final c = g.trainingCluster!;
      expect(c.roomId, 'gigasite');
      expect(c.scalingEfficiency, 1);
      // One cluster per room (the template never splits a room).
      for (final room in g.ownedRooms) {
        expect(g.clusters(room.id).where((c) => c.networked), hasLength(1), reason: room.id);
      }
      // Hardly any heat throttling.
      expect(g.rawTflops / g.peakTflops, greaterThan(0.9));
    });
  });

  test('placement matters: naive and random layouts are far slower', () {
    const t = 3 * 3600.0;
    final template = runPlaythrough(maxSeconds: t);
    final naive = runPlaythrough(maxSeconds: t, layout: BotLayout.naive);
    final random = runPlaythrough(maxSeconds: t, layout: BotLayout.random);
    final best = template.game.s.rivalIndex;
    expect(naive.game.s.rivalIndex, lessThan(best ~/ 2));
    expect(random.game.s.rivalIndex, lessThan(best ~/ 2));
    expect(naive.game.rating, lessThan(template.game.rating - 150));
    expect(random.game.rating, lessThan(template.game.rating - 100));
  });

  test('early game: the bot networks its GPUs and cools the hot ones', () {
    final r = runPlaythrough(maxSeconds: 10 * 60, stopWhenDone: false);
    final counts = r.game.s.tileCounts;
    expect(counts.keys.where((id) => id.startsWith('net_')), isNotEmpty);
    expect(counts.keys.where((id) => id.startsWith('cool_')), isNotEmpty);
    expect(r.game.trainingCluster!.gpus, greaterThanOrEqualTo(4));
  });

  test('software matters: hardware-only is clearly slower than balanced', () {
    const t = 4 * 3600.0;
    final balanced = runPlaythrough(maxSeconds: t);
    final hwOnly = runPlaythrough(maxSeconds: t, strategy: BotStrategy.hardwareOnly);
    expect(hwOnly.game.s.rivalIndex, lessThan(balanced.game.s.rivalIndex ~/ 2));
    expect(hwOnly.game.rating, lessThan(balanced.game.rating - 100));
  });
}
