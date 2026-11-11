import 'package:ai_lab_tycoon/sim/content.dart';
import 'package:ai_lab_tycoon/sim/game.dart';
import 'package:ai_lab_tycoon/sim/game_state.dart';
import 'package:ai_lab_tycoon/ui/app.dart';
import 'package:ai_lab_tycoon/ui/format.dart';
import 'package:ai_lab_tycoon/ui/game_controller.dart';
import 'package:ai_lab_tycoon/ui/screens/overview_screen.dart';
import 'package:ai_lab_tycoon/ui/screens/research_screen.dart';
import 'package:ai_lab_tycoon/ui/shell/game_modal.dart';
import 'package:ai_lab_tycoon/ui/world/world_layout.dart';
import 'package:ai_lab_tycoon/ui/world/world_map.dart';
import 'package:ai_lab_tycoon/ui/widgets/effects.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Loads a fresh controller, pumps the app, runs [body], then disposes the
/// controller so its periodic timers don't leak out of the test.
Future<void> withApp(
  WidgetTester tester,
  Future<void> Function(GameController c) body, {
  GameState? state,
  bool tutorial = false,
}) async {
  // Skip the first-launch intro (owned by the moments layer) and, unless a
  // test is about it, the tutorial card.
  SharedPreferences.setMockInitialValues({
    'intro_seen_v1': true,
    if (!tutorial) 'tutorial_done_v1': true,
  });
  tester.view.physicalSize = const Size(430, 932);
  tester.view.devicePixelRatio = 1;
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
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  }
}

Future<void> openTool(WidgetTester tester, String id) async {
  await tester.tap(find.byKey(ValueKey('tool-$id')));
  // Two frames: one starts the slide/fade-in, the next finishes it.
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pump(const Duration(milliseconds: 400));
}

/// Screen position of a grid cell's centre, through the camera transform.
Offset cellOnScreen(WidgetTester tester, String room, int x, int y) {
  final box = tester.renderObject<RenderBox>(find.byKey(ValueKey('room-floor-$room')));
  return box.localToGlobal(cellCenterLocal(room, x, y));
}

Future<void> tapCell(WidgetTester tester, String room, int x, int y) async {
  await tester.tapAt(cellOnScreen(tester, room, x, y));
  await tester.pump(const Duration(milliseconds: 400));
}

Finder get modalScrollable =>
    find.descendant(of: find.byType(GameModalCard), matching: find.byType(Scrollable)).first;

void main() {
  test('screen-to-cell maths round-trips for every room cell', () {
    for (final r in rooms) {
      final geo = geoOf(r.id);
      for (var y = 0; y < r.height; y++) {
        for (var x = 0; x < r.width; x++) {
          expect(geo.cellAtLocal(geo.cellCenterLocal(x, y)), (x, y), reason: '${r.id} $x,$y');
          // Near the diamond's corners still lands on the same cell.
          final d = geo.cellDiamond(x, y, inset: 0.08);
          for (final p in d) {
            expect(geo.cellAtLocal(p), (x, y), reason: '${r.id} $x,$y corner');
          }
        }
      }
      expect(geo.cellAtLocal(geo.svgToLocal(geo.gridSvg(-0.5, 0.5))), isNull);
    }
  });

  testWidgets('app builds with HUD, toolbar and the world map', (tester) async {
    await withApp(tester, (c) async {
      expect(find.byType(WorldMap), findsOneWidget);
      expect(find.text(formatMoney(c.game.s.money)), findsOneWidget);
      expect(find.text('No run'), findsOneWidget);
      for (final t in ['Build', 'Research', 'Train', 'Rivals', 'Lab', 'Settings']) {
        expect(
          find.descendant(
            of: find.byKey(ValueKey('tool-${t == 'Lab' ? 'stats' : t.toLowerCase()}')),
            matching: find.text(t),
          ),
          findsOneWidget,
        );
      }
      expect(find.byTooltip('Research upgrades (R)'), findsOneWidget);
      expect(find.byKey(const ValueKey('room-floor-garage')), findsOneWidget);
      // The next plot is a faint silhouette with its unlock sign.
      expect(find.byKey(const ValueKey('plot-closet')), findsOneWidget);
      expect(find.byKey(const ValueKey('unlock-closet')), findsOneWidget);
      expect(find.byKey(const ValueKey('founder')), findsOneWidget);

      await openTool(tester, 'stats');
      expect(find.text('Garage Labs'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Start training'),
        200,
        scrollable: modalScrollable,
      );
      expect(find.text('Start training'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.textContaining('GPU utilization'),
        200,
        scrollable: modalScrollable,
      );
      await tester.tap(find.byKey(const ValueKey('modal-close')));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(GameModalCard), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('mouse wheel zooms and drag pans the camera', (tester) async {
    await withApp(tester, (c) async {
      final cam = tester.state<WorldMapState>(find.byType(WorldMap)).camera;
      final z0 = cam.zoom, c0 = cam.center;
      final pointer = TestPointer(1, PointerDeviceKind.mouse);
      const at = Offset(215, 500);
      await tester.sendEventToBinding(pointer.hover(at));
      await tester.sendEventToBinding(pointer.scroll(const Offset(0, 300)));
      await tester.pump();
      expect(cam.zoom, lessThan(z0));
      await tester.dragFrom(const Offset(215, 700), const Offset(-60, -40));
      await tester.pump();
      expect(cam.center, isNot(c0));
    });
  });

  testWidgets('tutorial walks through train, second GPU, switch', (tester) async {
    await withApp(tester, (c) async {
      Future<void> settle() async {
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pump(const Duration(milliseconds: 400));
      }

      expect(find.text('Train your first model'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('tutorial-action')));
      await settle();
      expect(find.byType(TrainingPanel), findsOneWidget);
      await tester.tapAt(const Offset(5, 925)); // dismiss the modal
      await settle();

      c.act((g) => g.startTraining(fraction: 0.5, durationSeconds: 600));
      c.game.s.money = 5000;
      await settle();
      expect(find.textContaining('Add a second GPU'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('tutorial-action')));
      await settle();
      expect(find.text('Tap a glowing floor cell'), findsOneWidget);
      await tapCell(tester, 'garage', 3, 1);
      await settle();
      expect(c.game.tileAt('garage', 3, 1), 'gpu_old');

      expect(find.text('Link your GPUs with a switch'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('tutorial-action')));
      await settle();
      expect(find.text('Place it touching both GPUs'), findsOneWidget);
      await tapCell(tester, 'garage', 2, 1);
      await settle();
      expect(c.game.tileAt('garage', 2, 1), 'net_home');
      expect(c.game.trainingCluster!.gpus, 2);
      expect(find.textContaining('Linked!'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('tutorial-skip')));
      await settle();
      expect(find.byKey(const ValueKey('tutorial')), findsNothing);
    }, tutorial: true);
  });

  testWidgets('build: place a GPU and a switch by tapping floor cells', (tester) async {
    await withApp(tester, (c) async {
      await openTool(tester, 'build');
      final before = c.game.s.money;
      final gpu = tileById('gpu_gamer')!;
      final sw = tileById('net_5g')!;

      // Pick the RTX 4090, tap an empty cell: placed.
      await tester.tap(find.byKey(const ValueKey('part-gpu_gamer')));
      await tester.pump(const Duration(milliseconds: 200));
      await tapCell(tester, 'garage', 3, 1);
      expect(c.game.tileAt('garage', 3, 1), 'gpu_gamer');

      // Tapping a taken cell explains why instead of placing.
      await tapCell(tester, 'garage', 1, 1);
      expect(find.textContaining('That spot is taken'), findsOneWidget);

      // Network tab, 5 Gbit switch between the two GPUs.
      await tester.tap(find.byKey(const ValueKey('kind-network')));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.byKey(const ValueKey('part-net_5g')));
      await tester.pump(const Duration(milliseconds: 200));
      await tapCell(tester, 'garage', 2, 1);
      expect(c.game.tileAt('garage', 2, 1), 'net_5g');
      // Revenue keeps ticking during pumps, so allow a little drift.
      expect(c.game.s.money, closeTo(before - gpu.cost - sw.cost, 5));

      final cluster = c.game.trainingCluster!;
      expect(cluster.networked, isTrue);
      expect(cluster.gpus, 2);
      expect(find.textContaining('Training cluster: 2 GPUs on 5 Gbit switch'), findsWidgets);

      // Done leaves build mode; tapping a tile then opens its info card.
      await tester.tap(find.byKey(const ValueKey('cancel-mode')));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byKey(const ValueKey('part-net_5g')), findsNothing);
      await tapCell(tester, 'garage', 3, 1);
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text(gpu.blurb), findsOneWidget);
      expect(find.textContaining('Part of your training cluster'), findsOneWidget);

      // Sell it from the card: refunds half.
      final mid = c.game.s.money;
      await tester.tap(find.byKey(const ValueKey('tile-sell')));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));
      expect(c.game.tileAt('garage', 3, 1), isNull);
      expect(c.game.s.money, closeTo(mid + gpu.cost / 2, 5));
      expect(tester.takeException(), isNull);
    }, state: GameState(money: 10000));
  });

  testWidgets('move swaps tiles', (tester) async {
    await withApp(tester, (c) async {
      await tapCell(tester, 'garage', 1, 1);
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.byKey(const ValueKey('tile-move')));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.textContaining('Moving RTX 4090'), findsOneWidget);
      await tapCell(tester, 'garage', 0, 3);
      expect(c.game.tileAt('garage', 1, 1), isNull);
      expect(c.game.tileAt('garage', 0, 3), 'gpu_gamer');
    });
  });

  testWidgets('power-blocked GPUs and the locked room explain themselves', (tester) async {
    final garage = List<String?>.filled(16, null);
    for (var i = 0; i < 4; i++) {
      garage[i] = 'gpu_gamer'; // 4 × 0.45 kW fills the 1.8 kW outlet
    }
    await withApp(tester, (c) async {
      await openTool(tester, 'build');
      expect(find.text('Used V100'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('part-gpu_v_class')));
      await tester.pump(const Duration(milliseconds: 200));
      await tapCell(tester, 'garage', 0, 2);
      expect(find.textContaining('Not enough power'), findsOneWidget);
      expect(c.game.tileAt('garage', 0, 2), isNull);

      // The next room says why it's locked.
      await tester.tap(find.byKey(const ValueKey('room-closet')));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text(c.game.roomBlockReason('closet')!), findsWidgets);
    }, state: GameState(money: 1e6, grids: {'garage': garage}));
  });

  testWidgets('unlock area: buying the closet reveals it and pulls the camera back', (
    tester,
  ) async {
    await withApp(tester, (c) async {
      final cam = tester.state<WorldMapState>(find.byType(WorldMap)).camera;
      final z0 = cam.zoom;
      await tester.tap(find.byKey(const ValueKey('unlock-closet')));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.byKey(const ValueKey('buy-room')));
      await tester.pump(const Duration(milliseconds: 300));
      expect(c.game.isRoomOwned('closet'), isTrue);
      await tester.pump(const Duration(seconds: 2));
      expect(find.byKey(const ValueKey('room-closet')), findsOneWidget);
      expect(find.byKey(const ValueKey('room-floor-closet')), findsOneWidget);
      expect(cam.zoom, lessThan(z0));
      // The next plot along the road is now the colo.
      expect(find.byKey(const ValueKey('unlock-colo')), findsOneWidget);
    }, state: GameState(money: 1e5, era: Era.startup, powerTier: 2));
  });

  testWidgets('research shows blurbs and buys an upgrade', (tester) async {
    await withApp(tester, (c) async {
      await openTool(tester, 'research');
      final mp = upgrades.firstWhere((u) => u.id == 'mixed_precision');
      await tester.scrollUntilVisible(find.text(mp.blurb), 200, scrollable: modalScrollable);
      expect(find.text(effectChips(mp.effects).first.text), findsWidgets);
      expect(find.text('Requires: Custom CUDA kernels'), findsNothing); // startup-locked
      final buy = find.widgetWithText(NeonButton, 'Research').first;
      await tester.scrollUntilVisible(buy, 200, scrollable: modalScrollable);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(buy);
      await tester.pump(const Duration(milliseconds: 600));
      expect(c.game.s.ownedUpgrades, {'mixed_precision'});
      // A "what changed" card explains the effect in real numbers.
      expect(find.text('Researched: ${mp.name}'), findsOneWidget);
      expect(find.text('WHAT CHANGED'), findsOneWidget);
      expect(find.text('Training compute'), findsOneWidget);
    }, state: GameState(money: 2e6));
  });

  testWidgets('training: start shows a run, pending shows release', (tester) async {
    await withApp(tester, (c) async {
      await openTool(tester, 'train');
      await tester.tap(find.text('Start training'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(c.game.s.run, isNotNull);
      expect(find.text('Pause'), findsOneWidget);
      expect(find.textContaining('Training GL-'), findsOneWidget); // project bar
      c.act((g) => g.advance(c.game.s.run!.durationSeconds + 1));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Release model'), findsWidgets);
      await tester.tap(find.byKey(const ValueKey('modal-close')));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.textContaining('Release ready'), findsOneWidget);
      expect(find.byKey(const ValueKey('ctx-release')), findsOneWidget);
      expect(find.byTooltip('Release your new model (T)'), findsOneWidget);
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
