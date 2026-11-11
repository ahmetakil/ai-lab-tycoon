import 'package:ai_lab_tycoon/sim/balance.dart';
import 'package:ai_lab_tycoon/sim/bot.dart';
import 'package:ai_lab_tycoon/sim/content.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('bot playthrough (balanced)', () {
    late PlaythroughResult r;
    setUpAll(() => r = runPlaythrough(maxSeconds: 6 * 3600));

    test('finishes the whole ladder within 6 simulated hours', () {
      expect(r.ladderDone, isTrue,
          reason: 'stuck at rival ${r.game.s.rivalIndex}/${rivalLadder.length}');
      expect(r.finishTime!, lessThan(6 * 3600));
      expect(r.finishTime!, greaterThan(3 * 3600)); // not trivially fast
    });

    test('first session: Startup, Lab and early rivals on schedule', () {
      expect(r.eraTimes[Era.startup]!, inInclusiveRange(6 * 60, 14 * 60));
      expect(r.eraTimes[Era.lab]!, inInclusiveRange(30 * 60, 55 * 60));
      final early = r.rivalTimes.where((x) => x.$2 <= 30 * 60);
      expect(early.length, greaterThanOrEqualTo(2));
    });

    test('no dead stretches, overload is occasional, numbers stay sane', () {
      expect(r.longestIdle, lessThan(10 * 60));
      expect(r.overloadedFraction, lessThan(0.15));
      expect(r.viralSpikes, greaterThan(3));
      expect(r.maxUsersSeen, lessThanOrEqualTo(maxUsers));
      expect(r.minMoney, greaterThanOrEqualTo(0));
      expect(r.arrAtFinish, lessThan(200e9)); // credible 2026-lab revenue
    });
  });

  test('software matters: hardware-only is clearly slower than balanced', () {
    const t = 4 * 3600.0;
    final balanced = runPlaythrough(maxSeconds: t);
    final hwOnly = runPlaythrough(
        maxSeconds: t, strategy: BotStrategy.hardwareOnly);
    expect(hwOnly.game.s.rivalIndex, lessThan(balanced.game.s.rivalIndex ~/ 2));
    expect(hwOnly.game.rating, lessThan(balanced.game.rating - 100));
  });
}
