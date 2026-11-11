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

  testWidgets('datacenter: place a GPU and a switch by tapping cells', (tester) async {
    await withApp(tester, (c) async {
      await openTab(tester, 'Datacenter');
      expect(find.text('Place a GPU, then a switch next to it.'), findsOneWidget);
      final before = c.game.s.money;
      final gpu = tileById('gpu_gamer')!;
      final sw = tileById('net_5g')!;

      // Pick the RTX 4090, tap an empty cell: placed.
      await tester.tap(find.byKey(const ValueKey('part-gpu_gamer')));
      await tester.pump(const Duration(milliseconds: 200));
      await tester.tap(find.byKey(const ValueKey('cell-3-1')));
      await tester.pump(const Duration(milliseconds: 500));
      expect(c.game.tileAt('garage', 3, 1), 'gpu_gamer');

      // Tapping a taken cell explains why instead of placing.
      await tester.tap(find.byKey(const ValueKey('cell-1-1')));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.textContaining('That spot is taken'), findsOneWidget);

      // Network tab, 5 Gbit switch between the two GPUs.
      await tester.tap(find.byKey(const ValueKey('kind-network')));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.byKey(const ValueKey('part-net_5g')));
      await tester.pump(const Duration(milliseconds: 200));
      await tester.tap(find.byKey(const ValueKey('cell-2-1')));
      await tester.pump(const Duration(milliseconds: 500));
      expect(c.game.tileAt('garage', 2, 1), 'net_5g');
      // Revenue keeps ticking during pumps, so allow a little drift.
      expect(c.game.s.money, closeTo(before - gpu.cost - sw.cost, 5));

      final cluster = c.game.trainingCluster!;
      expect(cluster.networked, isTrue);
      expect(cluster.gpus, 2);
      expect(find.textContaining('Training cluster: 2 GPUs on 5 Gbit switch'), findsWidgets);
      expect(find.text('Place a GPU, then a switch next to it.'), findsNothing);

      // Done leaves placement mode; tapping a tile then opens its info sheet.
      await tester.tap(find.byKey(const ValueKey('cancel-mode')));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.byKey(const ValueKey('cell-3-1')));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text(gpu.blurb), findsOneWidget);
      expect(find.textContaining('Part of your training cluster'), findsOneWidget);

      // Sell it from the sheet: refunds half.
      final mid = c.game.s.money;
      await tester.tap(find.byKey(const ValueKey('tile-sell')));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));
      expect(c.game.tileAt('garage', 3, 1), isNull);
      expect(c.game.s.money, closeTo(mid + gpu.cost / 2, 5));
      expect(tester.takeException(), isNull);
    }, state: GameState(money: 10000));
  });

  testWidgets('datacenter: move swaps tiles', (tester) async {
    await withApp(tester, (c) async {
      await openTab(tester, 'Datacenter');
      await tester.tap(find.byKey(const ValueKey('cell-1-1')));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.byKey(const ValueKey('tile-move')));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.byKey(const ValueKey('cell-0-3')));
      await tester.pump(const Duration(milliseconds: 500));
      expect(c.game.tileAt('garage', 1, 1), isNull);
      expect(c.game.tileAt('garage', 0, 3), 'gpu_gamer');
    });
  });

  testWidgets('power-blocked GPUs explain themselves', (tester) async {
    final garage = List<String?>.filled(16, null);
    for (var i = 0; i < 4; i++) {
      garage[i] = 'gpu_gamer'; // 4 × 0.45 kW fills the 1.8 kW outlet
    }
    await withApp(tester, (c) async {
      await openTab(tester, 'Datacenter');
      expect(find.text('Used V100'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('part-gpu_v_class')));
      await tester.pump(const Duration(milliseconds: 200));
      await tester.tap(find.byKey(const ValueKey('cell-0-2')));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.textContaining('Not enough power'), findsOneWidget);
      expect(c.game.tileAt('garage', 0, 2), isNull);

      // The next room says why it's locked.
      await tester.tap(find.byKey(const ValueKey('room-closet')));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text(c.game.roomBlockReason('closet')!), findsOneWidget);
    }, state: GameState(money: 1e6, grids: {'garage': garage}));
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
