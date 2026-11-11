import 'package:ai_lab_tycoon/sim/content.dart';
import 'package:ai_lab_tycoon/sim/game.dart';
import 'package:ai_lab_tycoon/sim/game_state.dart';
import 'package:ai_lab_tycoon/ui/app.dart';
import 'package:ai_lab_tycoon/ui/format.dart';
import 'package:ai_lab_tycoon/ui/game_controller.dart';
import 'package:ai_lab_tycoon/ui/screens/research_screen.dart';
import 'package:ai_lab_tycoon/ui/widgets/effects.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Loads a fresh controller, pumps the app, runs [body], then disposes the
/// controller so its periodic timers don't leak out of the test.
Future<void> withApp(
  WidgetTester tester,
  Future<void> Function(GameController c) body, {
  GameState? state,
}) async {
  // Skip the first-launch intro (owned by the moments layer).
  SharedPreferences.setMockInitialValues({'intro_seen_v1': true});
  await tester.binding.setSurfaceSize(const Size(430, 932));
  final c = await GameController.load();
  if (state != null) c.game = Game(state);
  await tester.pumpWidget(AiLabTycoonApp(controller: c));
  await tester.pump(const Duration(milliseconds: 500));
  try {
    await body(c);
  } finally {
    await tester.pumpWidget(const SizedBox());
    // Let toast/celebration timers from the moments layer run out.
    await tester.pump(const Duration(seconds: 15));
    c.dispose();
    await tester.binding.setSurfaceSize(null);
  }
}

Future<void> openTab(WidgetTester tester, String label) async {
  await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text(label)));
  await tester.pump(const Duration(milliseconds: 500));
}

void main() {
  testWidgets('app builds with HUD, tabs and the lab screen', (tester) async {
    await withApp(tester, (c) async {
      expect(find.text('Garage Labs'), findsOneWidget);
      expect(find.text('CASH'), findsOneWidget);
      expect(find.text(formatMoney(c.game.s.money)), findsOneWidget);
      await tester.scrollUntilVisible(find.text('Start training'), 200);
      expect(find.text('Start training'), findsOneWidget);
      await tester.scrollUntilVisible(find.textContaining('GPU utilization'), 200);
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('buying hardware updates owned count and money', (tester) async {
    await withApp(tester, (c) async {
      await openTab(tester, 'Hardware');
      final before = c.game.s.money;
      expect(c.game.s.hardwareCounts['gamer'], 1);
      // First "Buy" is the Gaming GPU ($1.6k ≤ $5k).
      final buy = find.widgetWithText(NeonButton, 'Buy').first;
      await tester.scrollUntilVisible(buy, 200);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(buy);
      await tester.pump(const Duration(milliseconds: 600));
      expect(c.game.s.hardwareCounts['gamer'], 2);
      expect(c.game.s.money, lessThan(before));
      expect(find.text('×2'), findsWidgets);
      // The HUD tweens money; let it settle.
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.text(formatMoney(c.game.s.money)), findsWidgets);
    }, state: GameState(money: 5000));
  });

  testWidgets('power-blocked GPUs explain themselves', (tester) async {
    await withApp(tester, (c) async {
      await openTab(tester, 'Hardware');
      await tester.scrollUntilVisible(find.text('Used V-class Datacenter GPU'), 200);
      expect(find.text('Needs more power'), findsWidgets);
      await tester.scrollUntilVisible(find.text('Unlocks in Startup'), 200);
    }, state: GameState(money: 1e6, hardwareCounts: {'gamer': 4}));
  });

  testWidgets('research shows blurbs and buys an upgrade', (tester) async {
    await withApp(tester, (c) async {
      await openTab(tester, 'Research');
      final mp = upgrades.firstWhere((u) => u.id == 'mixed_precision');
      await tester.scrollUntilVisible(find.text(mp.blurb), 200);
      expect(find.text(effectChips(mp.effects).first.text), findsWidgets);
      expect(find.text('Requires: Custom CUDA kernels'), findsNothing); // startup-locked
      final buy = find.widgetWithText(NeonButton, 'Research').first;
      await tester.scrollUntilVisible(buy, 200);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(buy);
      await tester.pump(const Duration(milliseconds: 600));
      expect(c.game.s.ownedUpgrades, {'mixed_precision'});
    }, state: GameState(money: 2e6));
  });

  testWidgets('training: start shows a run, pending shows release', (tester) async {
    await withApp(tester, (c) async {
      await tester.scrollUntilVisible(find.text('Start training'), 200);
      await tester.tap(find.text('Start training'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(c.game.s.run, isNotNull);
      await tester.scrollUntilVisible(find.text('Pause'), 200);
      c.act((g) => g.advance(c.game.s.run!.durationSeconds + 1));
      await tester.pump(const Duration(milliseconds: 300));
      // The pending card moves to the top of the list.
      await tester.scrollUntilVisible(find.text('Release model'), -200);
      expect(find.text('Release model'), findsOneWidget);
    });
  });

  test('effect chips flag costs', () {
    final reasoning = upgrades.firstWhere((u) => u.id == 'reasoning');
    final chips = effectChips(reasoning.effects);
    expect(
      chips.map((c) => c.text),
      contains('×${formatNumber(reasoning.effects.serveEffMult)} serving efficiency'),
    );
    expect(
      chips.map((c) => c.text),
      contains('+${formatNumber(reasoning.effects.ratingAdd)} rating'),
    );
    expect(chips.firstWhere((c) => c.text.contains('serving')).isCost, isTrue);
    final cooling = upgrades.firstWhere((u) => u.id == 'liquid_cooling');
    expect(
      effectChips(cooling.effects).single.text,
      '−${formatPercent(1 - cooling.effects.powerMult)} power',
    );
  });
}
