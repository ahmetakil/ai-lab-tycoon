import 'package:ai_lab_tycoon/sim/content.dart';
import 'package:ai_lab_tycoon/sim/game.dart';
import 'package:ai_lab_tycoon/sim/game_state.dart';
import 'package:ai_lab_tycoon/sim/model_design.dart';
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
import '../sim/phase_helpers.dart';

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
  // Phones tuck rarely used tools (Power, Lab, Settings) behind "More".
  if (find.byKey(ValueKey('tool-$id')).evaluate().isEmpty) {
    await tester.tap(find.byKey(const ValueKey('tool-more')));
    await tester.pump(const Duration(milliseconds: 100));
  }
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
      // The money label tweens toward a balance that grows every tick, so it
      // may trail the live value by a few dollars.
      final m = c.game.s.money;
      expect(
        [for (var d = -20; d <= 0; d++) find.text(formatMoney(m + d))]
            .any((f) => f.evaluate().length == 1),
        isTrue,
        reason: 'HUD shows the balance (${formatMoney(m)})',
      );
      expect(find.text('No training run'), findsOneWidget);
      // Phone rail: Power, Lab and Settings sit behind "More".
      expect(find.byKey(const ValueKey('tool-settings')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('tool-more')));
      await tester.pump(const Duration(milliseconds: 100));
      for (final t in ['Build', 'Research', 'Train', 'Power', 'Rivals', 'Lab', 'Settings']) {
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
      // The next plot is a faint silhouette with its "move here" sign.
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

  testWidgets('tutorial walks through train, second GPU, release', (tester) async {
    await withApp(tester, (c) async {
      Future<void> settle() async {
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pump(const Duration(milliseconds: 400));
      }

      expect(find.text('Train your first model'), findsOneWidget);
      expect(find.text('TUTORIAL 1/3'), findsOneWidget);
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
      // Anywhere works: the whole room is one cluster.
      await tapCell(tester, 'garage', 3, 0);
      await settle();
      expect(c.game.tileAt('garage', 3, 0), 'gpu_old');
      expect(c.game.trainingCluster!.gpus, 2);
      expect(find.textContaining('Cabled!'), findsOneWidget);
      expect(find.text('TUTORIAL 3/3'), findsOneWidget);

      // The run finishes: step 3 is the release.
      c.act((g) => g.advance(600 + 2, onStep: decideDefaults(g)));
      await settle();
      expect(find.text('Your model is trained!'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('tutorial-skip')));
      await settle();
      expect(find.byKey(const ValueKey('tutorial')), findsNothing);
    }, tutorial: true);
  });

  testWidgets('build: place a GPU and a cooler, drag to paint, older parts', (tester) async {
    await withApp(tester, (c) async {
      await openTool(tester, 'build');
      final before = c.game.s.money;
      final gpu = tileById('gpu_gamer')!;
      final fan = tileById('cool_fan')!;

      // Pick the RTX 4090, tap an empty cell: placed and cabled in.
      await tester.tap(find.byKey(const ValueKey('part-gpu_gamer')));
      await tester.pump(const Duration(milliseconds: 200));
      await tapCell(tester, 'garage', 3, 1);
      expect(c.game.tileAt('garage', 3, 1), 'gpu_gamer');
      expect(c.game.trainingCluster!.gpus, 2);

      // Tapping a taken cell explains why instead of placing.
      await tapCell(tester, 'garage', 1, 1);
      expect(find.textContaining('That spot is taken'), findsOneWidget);

      // Cooling tab (no Network tab any more), a fan between the two GPUs.
      expect(find.byKey(const ValueKey('kind-network')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('kind-cooling')));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.byKey(const ValueKey('part-cool_fan')));
      await tester.pump(const Duration(milliseconds: 200));
      await tapCell(tester, 'garage', 2, 1);
      expect(c.game.tileAt('garage', 2, 1), 'cool_fan');
      expect(c.game.s.money, closeTo(before - gpu.cost - fan.cost, 5));
      expect(find.textContaining('Training cluster: 2 GPUs on Copper Ethernet 1G'), findsWidgets);
      expect(find.byKey(const ValueKey('cluster-label')), findsOneWidget);

      // Drag to paint fans along a row.
      final from = cellOnScreen(tester, 'garage', 0, 0);
      final to = cellOnScreen(tester, 'garage', 3, 0);
      final gesture = await tester.startGesture(from);
      for (var i = 1; i <= 8; i++) {
        await gesture.moveTo(Offset.lerp(from, to, i / 8)!);
        await tester.pump(const Duration(milliseconds: 16));
      }
      await gesture.up();
      await tester.pump(const Duration(milliseconds: 300));
      for (var x = 0; x < 4; x++) {
        expect(c.game.tileAt('garage', x, 0), 'cool_fan', reason: 'painted $x');
      }
      expect(find.textContaining('Placed 4 ×'), findsOneWidget);

      // Done leaves build mode; tapping a tile then opens its info card.
      await tester.tap(find.byKey(const ValueKey('cancel-mode')));
      await tester.pump(const Duration(milliseconds: 300));
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

  testWidgets('a later room offers every unlocked part, older ones grouped', (tester) async {
    final hall = List<String?>.filled(14 * 14, null)..[0] = 'rack_h_class';
    await withApp(tester, (c) async {
      await openTool(tester, 'build');
      expect(find.byKey(const ValueKey('part-rack_h_class')), findsOneWidget);
      expect(find.byKey(const ValueKey('part-gpu_gamer')), findsNothing);
      await tester.dragUntilVisible(
        find.byKey(const ValueKey('tray-older')),
        find.byKey(const ValueKey('tray-hall-gpu')),
        const Offset(-200, 0),
      );
      await tester.tap(find.byKey(const ValueKey('tray-older')));
      await tester.pump(const Duration(milliseconds: 300));
      // An old gaming card is still placeable in the hall (just a poor deal).
      await tester.dragUntilVisible(
        find.byKey(const ValueKey('part-gpu_gamer')),
        find.byKey(const ValueKey('tray-hall-gpu')),
        const Offset(-200, 0),
      );
      expect(find.textContaining('TF/kW'), findsWidgets);
      expect(c.game.placeBlockReason('hall', 5, 5, 'gpu_gamer'), isNull);
    }, state: GameState(money: 1e9, era: Era.mediumLab, powerTier: 4, grids: {'hall': hall}));
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

  testWidgets('power-blocked GPUs and the move checklist explain themselves', (tester) async {
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
      await tester.tap(find.byKey(const ValueKey('cancel-mode')));
      await tester.pump(const Duration(milliseconds: 300));

      // The next place has a checklist: cash (the only must), then what the
      // era brings, each with progress and a button.
      await tester.tap(find.byKey(const ValueKey('unlock-closet')));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byKey(const ValueKey('move-checklist')), findsOneWidget);
      expect(find.byKey(const ValueKey('req-cash')), findsOneWidget);
      expect(find.byKey(const ValueKey('req-era')), findsOneWidget);
      expect(find.byKey(const ValueKey('req-power')), findsOneWidget);
      expect(find.textContaining('/ 3k users'), findsOneWidget);
      expect(find.textContaining('grow users by releasing better models'), findsOneWidget);
      // Power is information: the closet's bigger electrical service.
      expect(find.textContaining('up to 3-phase service'), findsOneWidget);
      expect(find.byKey(const ValueKey('req-go-power')), findsNothing);
      expect(find.text('Move to Server closet'), findsOneWidget);
    }, state: GameState(money: 1000, grids: {'garage': garage}));
  });

  testWidgets('power past the building\'s limit offers a move, not an upgrade', (tester) async {
    final garage = List<String?>.filled(16, null);
    garage[0] = 'gpu_gamer';
    await withApp(tester, (c) async {
      // Startup era unlocks 3-phase service, but the garage can't take it.
      expect(c.game.powerNeedsMove, isTrue);
      await openTool(tester, 'power');
      expect(find.text('CURRENT SUPPLY'), findsOneWidget);
      expect(find.text('3-phase service'), findsOneWidget);
      expect(
        find.text('Needs a bigger building: move to the Server closet first.'),
        findsOneWidget,
      );
      expect(find.text('Upgrade'), findsNothing);
      // The move button opens the move modal.
      await tester.ensureVisible(find.byKey(const ValueKey('power-move')));
      await tester.tap(find.byKey(const ValueKey('power-move')));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byKey(const ValueKey('move-checklist')), findsOneWidget);
      expect(c.game.s.powerTier, 1);
    }, state: GameState(money: 1e6, era: Era.startup, users: 4000, powerTier: 1, grids: {'garage': garage}));
  });

  testWidgets('moving to the closet: money only, everything comes along', (tester) async {
    await withApp(tester, (c) async {
      final cam = tester.state<WorldMapState>(find.byType(WorldMap)).camera;
      final z0 = cam.zoom;
      expect(find.byKey(const ValueKey('room-garage')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('unlock-closet')));
      await tester.pump(const Duration(milliseconds: 400));
      // Still the garage era: moving only needs the cash.
      expect(find.byKey(const ValueKey('req-cash')), findsOneWidget);
      await tester.ensureVisible(find.byKey(const ValueKey('buy-room')));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.byKey(const ValueKey('buy-room')));
      await tester.pump(const Duration(milliseconds: 300));
      expect(c.game.currentRoom.id, 'closet');
      // The starting GPU moved with you, centred: (1,1) → (2,2).
      expect(c.game.tileAt('closet', 2, 2), 'gpu_gamer');
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byKey(const ValueKey('move-banner')), findsOneWidget);
      await tester.pump(const Duration(seconds: 3));
      expect(find.byKey(const ValueKey('move-banner')), findsNothing);
      expect(find.byKey(const ValueKey('room-closet')), findsOneWidget);
      expect(find.byKey(const ValueKey('room-floor-closet')), findsOneWidget);
      expect(find.byKey(const ValueKey('room-garage')), findsNothing);
      expect(cam.zoom, isNot(z0));
      // The next place along the road is now the colo.
      expect(find.byKey(const ValueKey('unlock-colo')), findsOneWidget);
    }, state: GameState(money: 1e5));
  });

  testWidgets('HUD: network meter, goal strip and the leaderboard', (tester) async {
    final garage = List<String?>.filled(16, 'gpu_old')..[15] = null;
    await withApp(tester, (c) async {
      Future<void> settle() async {
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pump(const Duration(milliseconds: 400));
      }

      // 15 GPUs on copper 1G (feeds 4): over the cap, red, scaling shown.
      expect(find.text('15/4'), findsOneWidget);
      expect(
        find.byWidgetPredicate((w) => w is Tooltip && (w.message ?? '').contains('scaling')),
        findsWidgets,
      );
      await tester.tap(find.byKey(const ValueKey('network-chip')));
      await settle();
      expect(find.byKey(const ValueKey('network-explain')), findsOneWidget);
      expect(find.textContaining('keeps 4 GPUs fed'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('buy-network')));
      await settle();
      expect(c.game.network.id, 'copper10g');
      await tester.tap(find.byKey(const ValueKey('modal-close')).last);
      await settle();
      // Fed again: the phone gauge drops its readout.
      expect(c.game.networkCap, 32);
      expect(find.text('15/32'), findsNothing);

      // Goal strip: the next era and how to get there.
      expect(find.textContaining('Next era: Startup'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('goal-strip')));
      await settle();
      expect(find.byKey(const ValueKey('next-era-title')), findsOneWidget);
      expect(find.textContaining('Move to the Server closet'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('modal-close')).last);
      await settle();

      // Rating plate: "RATING" + the rival to beat; tap opens the leaderboard.
      expect(find.textContaining('beat Tiny-Transformer'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('rating-chip')));
      await settle();
      expect(find.byKey(const ValueKey('leaderboard')), findsOneWidget);
      expect(find.byKey(const ValueKey('leaderboard-you')), findsOneWidget);
      expect(find.textContaining('rating to pass Tiny-Transformer'), findsOneWidget);
    }, state: GameState(money: 1e4, powerTier: 1, grids: {'garage': garage}));
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

  testWidgets('research tabs: available now, then one tab per research track', (tester) async {
    await withApp(tester, (c) async {
      await openTool(tester, 'research');
      final data = allUpgrades.firstWhere((u) => trackOf(u.id) == ResearchTrack.data && u.era == Era.garage);
      final soft = allUpgrades.firstWhere((u) => trackOf(u.id) == ResearchTrack.infrastructure && u.era == Era.garage);
      final later = allUpgrades.firstWhere((u) => trackOf(u.id) == ResearchTrack.data && u.era == Era.startup);
      // "Available now" is the default tab and lists garage research of every track.
      for (final t in [null, ...ResearchTrack.values]) {
        expect(find.byKey(ValueKey('research-tab-chip-${t?.name ?? 'available'}')), findsOneWidget);
      }
      expect(find.byKey(const ValueKey('research-tab-available')), findsOneWidget);
      expect(find.text(soft.name), findsWidgets);
      expect(find.text(later.name), findsNothing);
      // Counts on the chips: what you can research now in each track.
      final nData = allUpgrades.where((u) => trackOf(u.id) == ResearchTrack.data && u.era == Era.garage).length;
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('research-tab-chip-data')),
          matching: find.text('$nData'),
        ),
        findsOneWidget,
      );

      await tester.ensureVisible(find.byKey(const ValueKey('research-tab-chip-data')));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.byKey(const ValueKey('research-tab-chip-data')));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byKey(const ValueKey('research-tab-data')), findsOneWidget);
      expect(find.text(data.name), findsWidgets);
      expect(find.text(soft.name), findsNothing);
      // The data track also shows what unlocks later, with the gate spelled out.
      await tester.scrollUntilVisible(find.text(later.name), 200, scrollable: modalScrollable);
      expect(find.textContaining('Unlocks in Startup: reach 3k users'), findsWidgets);

      await tester.ensureVisible(find.byKey(const ValueKey('research-tab-chip-infrastructure')));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.byKey(const ValueKey('research-tab-chip-infrastructure')));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text(soft.name), findsWidgets);
      expect(find.text(data.name), findsNothing);
      expect(tester.takeException(), isNull);
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
      // Each checkpoint waits for a decision: take the defaults.
      c.act((g) => g.advance(c.game.s.run!.durationSeconds + 3, onStep: decideDefaults(g)));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Release model'), findsWidgets);
      await tester.tap(find.byKey(const ValueKey('modal-close')));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.textContaining('Release ready'), findsOneWidget);
      expect(find.byKey(const ValueKey('ctx-release')), findsOneWidget);
      expect(find.byTooltip('Release your new model (T)'), findsOneWidget);
    });
  });

  testWidgets('training: model design is one tap away and remembered', (tester) async {
    await withApp(tester, (c) async {
      await openTool(tester, 'train');
      // Collapsed by default: a summary row, no option chips.
      expect(find.byKey(const ValueKey('run-setup-toggle')), findsOneWidget);
      expect(find.byKey(const ValueKey('run-setup')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('run-setup-toggle')));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byKey(const ValueKey('run-setup')), findsOneWidget);
      // Locked options say why; picking an unlocked one changes the run.
      final bigShort = find.byKey(const ValueKey('design-sizing-bigShort'));
      await tester.scrollUntilVisible(bigShort, 200, scrollable: modalScrollable);
      await tester.tap(bigShort);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.scrollUntilVisible(find.text('Start training'), 200, scrollable: modalScrollable);
      await tester.tap(find.text('Start training'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(c.game.s.run!.spec.sizing, Sizing.bigShort);
      expect(c.game.s.lastSpec.sizing, Sizing.bigShort);
      expect(find.byKey(const ValueKey('run-spec')), findsOneWidget);
      // The next run starts from the remembered setup with one tap.
      c.act((g) => g.cancelTraining());
      await tester.pump(const Duration(milliseconds: 300));
      await tester.scrollUntilVisible(find.text('Start training'), 200, scrollable: modalScrollable);
      await tester.tap(find.text('Start training'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(c.game.s.run!.spec.sizing, Sizing.bigShort);
      // Finished: the benchmark profile shows before release.
      // Each checkpoint waits for a decision: take the defaults.
      c.act((g) => g.advance(c.game.s.run!.durationSeconds + 3, onStep: decideDefaults(g)));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byKey(const ValueKey('pending-benchmark-strip')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  test('effect chips flag costs; design research lists what it unlocks', () {
    const costly = Effects(ratingAdd: 60, serveEffMult: 0.6);
    final chips = effectChips(costly);
    expect(chips.map((c) => c.text), contains('×${formatNumber(0.6)} serving efficiency'));
    expect(chips.map((c) => c.text), contains('+${formatNumber(60)} rating'));
    expect(chips.firstWhere((c) => c.text.contains('serving')).isCost, isTrue);
    // Reasoning's effect now lives in run setup.
    expect(effectChips(researchById('reasoning')!.effects), isEmpty);
    expect(designUnlockLines('reasoning'), ['Post-training: RL reasoning']);
    expect(designUnlockLines('router_balancing'), ['Removes the MoE routing-collapse risk']);
    final cooling = upgrades.firstWhere((u) => u.id == 'liquid_cooling');
    expect(
      effectChips(cooling.effects).single.text,
      '−${formatPercent(1 - cooling.effects.powerMult)} power',
    );
  });
}
