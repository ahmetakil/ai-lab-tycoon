// Renders the world map, every toolbar modal and build mode at phone and
// desktop sizes with early/mid/late-game saves, and fails on any layout
// exception (overflows etc.).
// Set LAYOUT_PREVIEW_DIR=/some/dir to also write PNG screenshots.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:ai_lab_tycoon/sim/bot.dart';
import 'package:ai_lab_tycoon/sim/content.dart';
import 'package:ai_lab_tycoon/sim/game.dart';
import 'package:ai_lab_tycoon/sim/game_state.dart';
import 'package:ai_lab_tycoon/sim/model_design.dart';
import 'package:ai_lab_tycoon/sim/news.dart';
import 'package:ai_lab_tycoon/ui/app.dart';
import 'package:ai_lab_tycoon/ui/game_controller.dart';
import 'package:ai_lab_tycoon/ui/moments/event_presenter.dart';
import 'package:ai_lab_tycoon/ui/moments/release_card.dart';
import 'package:ai_lab_tycoon/ui/shell/game_modal.dart';
import 'package:ai_lab_tycoon/ui/world/world_layout.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _out = Platform.environment['LAYOUT_PREVIEW_DIR'];

Future<void> _font(String family, List<String> paths) async {
  final loader = FontLoader(family);
  for (final p in paths) {
    if (File(p).existsSync()) {
      loader.addFont(Future.value(ByteData.sublistView(File(p).readAsBytesSync())));
    }
  }
  await loader.load();
}

Future<void> _loadFonts() async {
  final sdk = '${Platform.environment['FLUTTER_ROOT']}/bin/cache/artifacts/material_fonts';
  await _font('MaterialIcons', ['$sdk/MaterialIcons-Regular.otf']);
  await _font('SpaceGrotesk', [
    for (final w in ['Regular', 'Medium', 'Bold']) 'assets/fonts/SpaceGrotesk/SpaceGrotesk-$w.ttf',
  ]);
  await _font('JetBrainsMono', [
    for (final w in ['Regular', 'Bold']) 'assets/fonts/JetBrainsMono/JetBrainsMono-$w.ttf',
  ]);
}

final _saves = <String, String>{};

/// A save from a bot playthrough: continuous play for early stages, the
/// casual schedule (coarse steps, real offline path) for the long ones.
GameState _stateAt(String stage, double seconds, {bool casual = false}) {
  if (seconds == 0) return GameState();
  final json = _saves.putIfAbsent(stage, () {
    final r =
        casual
            ? runSchedule(maxWallSeconds: seconds, stopWhenDone: false)
            : runPlaythrough(maxSeconds: seconds, stopWhenDone: false);
    r.game.events.clear();
    return jsonEncode(r.game.s.toJson());
  });
  // Round-trip through JSON like a real save.
  return GameState.fromJson(jsonDecode(json) as Map<String, dynamic>);
}

/// Screen position of a grid cell's centre (through the camera transform).
Offset cellOnScreen(WidgetTester tester, String room, int x, int y) {
  final box = tester.renderObject<RenderBox>(find.byKey(ValueKey('room-floor-$room')));
  return box.localToGlobal(cellCenterLocal(room, x, y));
}

Future<void> _shot(WidgetTester tester, GlobalKey key, String name) async {
  if (_out == null) return;
  await tester.runAsync(() async {
    final b = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final img = await b.toImage(pixelRatio: 1);
    final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
    File('$_out/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
  });
}

/// Sets both the render surface and the view (so MediaQuery matches).
Future<void> _setSize(WidgetTester tester, Size? size) async {
  if (size == null) {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  } else {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
  }
  await tester.binding.setSurfaceSize(size);
}

/// Pump frames so images decode and animations settle a little.
Future<void> _settle(WidgetTester tester, [int ms = 600]) async {
  for (var i = 0; i < 4; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 40)));
    await tester.pump(Duration(milliseconds: ms ~/ 4));
  }
}

void main() {
  const sizes = [Size(360, 740), Size(390, 844), Size(1400, 900)];
  // (seconds, casual schedule?): Garage, Startup, Small lab, Medium lab
  // (casual, day 1 evening), Frontier lab (casual, day 2 evening).
  const stages = <String, (double, bool)>{
    'start': (0.0, false),
    'startup': (20 * 60.0, false),
    'smalllab': (100 * 60.0, false),
    'mediumlab': (12 * 3600.0, true),
    'frontier': (36 * 3600.0, true),
  };
  const tools = ['research', 'train', 'power', 'rivals', 'stats', 'settings'];
  // HUD plates and the goal strip open their own modals.
  const plates = ['network-chip', 'goal-strip', 'cooling-chip'];

  for (final size in sizes) {
    for (final stage in stages.entries) {
      testWidgets('no layout errors at ${size.width.toInt()}w, ${stage.key}', (tester) async {
        if (_out != null) await tester.runAsync(_loadFonts);
        SharedPreferences.setMockInitialValues({'intro_seen_v1': true});
        await _setSize(tester, size);
        final c = await GameController.load();
        c.game = Game(_stateAt(stage.key, stage.value.$1, casual: stage.value.$2));
        final key = GlobalKey();
        await tester.pumpWidget(RepaintBoundary(key: key, child: AiLabTycoonApp(controller: c)));
        await _settle(tester);
        expect(tester.takeException(), isNull, reason: 'map');
        final tag = '${size.width.toInt()}_${stage.key}';
        await _shot(tester, key, '${tag}_map');

        for (final tool in tools) {
          await tester.tap(find.byKey(ValueKey('tool-$tool')));
          await _settle(tester, 500);
          expect(tester.takeException(), isNull, reason: '$tool modal');
          await _shot(tester, key, '${tag}_$tool');
          // Scroll the modal to surface overflows further down.
          final scrollable = find.descendant(
            of:
                find.byType(Dialog).evaluate().isEmpty
                    ? find.byType(Material).last
                    : find.byType(Dialog),
            matching: find.byType(Scrollable),
          );
          if (scrollable.evaluate().isNotEmpty) {
            for (var i = 0; i < 6; i++) {
              await tester.drag(scrollable.first, const Offset(0, -500), warnIfMissed: false);
              await tester.pump(const Duration(milliseconds: 100));
            }
            expect(tester.takeException(), isNull, reason: '$tool modal (scrolled)');
          }
          await tester.tap(find.byKey(const ValueKey('modal-close')).last);
          await _settle(tester, 400);
        }

        for (final plate in plates) {
          final f = find.byKey(ValueKey(plate));
          if (f.evaluate().isEmpty) continue; // cooling shows from the Medium lab (wide HUD)
          await tester.tap(f.first);
          await _settle(tester, 500);
          expect(tester.takeException(), isNull, reason: '$plate modal');
          await _shot(tester, key, '${tag}_$plate');
          await tester.tap(find.byKey(const ValueKey('modal-close')).last);
          await _settle(tester, 400);
        }

        await tester.tap(find.byKey(const ValueKey('tool-build')));
        await _settle(tester, 500);
        expect(tester.takeException(), isNull, reason: 'build mode');
        await _shot(tester, key, '${tag}_build');

        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(seconds: 15));
        c.dispose();
        await _setSize(tester, null);
      });
    }
  }

  // A crowded garage: throttling GPUs (heat tint + badges), more GPUs than
  // copper 1G feeds (network meter red) and placement mode with its
  // valid-cell highlights.
  for (final size in sizes) {
    testWidgets('garage scenarios at ${size.width.toInt()}w', (tester) async {
      if (_out != null) await tester.runAsync(_loadFonts);
      SharedPreferences.setMockInitialValues({'intro_seen_v1': true});
      await _setSize(tester, size);
      final c = await GameController.load();
      final garage = <String?>[
        'gpu_v_class', 'gpu_v_class', 'gpu_gamer', null, //
        'gpu_gamer', 'gpu_gamer', 'gpu_old', null,
        'gpu_gamer', null, 'gpu_v_class', null,
        null, 'cool_fan', null, null,
      ];
      c.game = Game(GameState(money: 4000, powerTier: 1, grids: {'garage': garage}));
      final key = GlobalKey();
      await tester.pumpWidget(RepaintBoundary(key: key, child: AiLabTycoonApp(controller: c)));
      await _settle(tester);
      expect(tester.takeException(), isNull);
      final tag = '${size.width.toInt()}_garage';
      await _shot(tester, key, '${tag}_crowded');
      await tester.tap(find.byKey(const ValueKey('tool-build')));
      await _settle(tester, 400);
      await tester.tap(find.byKey(const ValueKey('kind-cooling')));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.byKey(const ValueKey('part-cool_fan')));
      await _settle(tester);
      expect(tester.takeException(), isNull);
      await _shot(tester, key, '${tag}_placing');
      await tester.tapAt(cellOnScreen(tester, 'garage', 1, 1));
      await _settle(tester, 400);
      expect(tester.takeException(), isNull);
      await _shot(tester, key, '${tag}_blocked');
      await tester.tap(find.byKey(const ValueKey('cancel-mode')));
      await _settle(tester, 300);
      await tester.tapAt(cellOnScreen(tester, 'garage', 1, 1));
      await _settle(tester, 800);
      expect(tester.takeException(), isNull);
      await _shot(tester, key, '${tag}_tile_sheet');

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 15));
      c.dispose();
      await _setSize(tester, null);
    });
  }

  // The training modal with the run-setup panel open (garage and a
  // Medium-lab save), then the finished model's benchmark profile and the
  // release card with its benchmark strip.
  for (final size in sizes) {
    for (final stage in ['start', 'mediumlab']) {
      testWidgets('run setup at ${size.width.toInt()}w, $stage', (tester) async {
        if (_out != null) await tester.runAsync(_loadFonts);
        SharedPreferences.setMockInitialValues({'intro_seen_v1': true, 'tutorial_done_v1': true});
        await _setSize(tester, size);
        final c = await GameController.load();
        final st = _stateAt(stage, stages[stage]!.$1, casual: stages[stage]!.$2)
          ..run = null
          ..pendingEffectiveCompute = null
          ..pendingDesign = null;
        c.game = Game(st);
        final key = GlobalKey();
        await tester.pumpWidget(RepaintBoundary(key: key, child: AiLabTycoonApp(controller: c)));
        await _settle(tester);
        final tag = '${size.width.toInt()}_${stage}_design';

        await tester.tap(find.byKey(const ValueKey('tool-train')));
        await _settle(tester, 500);
        await tester.tap(find.byKey(const ValueKey('run-setup-toggle')));
        await _settle(tester, 400);
        expect(find.byKey(const ValueKey('run-setup')), findsOneWidget);
        expect(tester.takeException(), isNull, reason: 'run setup open');
        await _shot(tester, key, '${tag}_0');
        final list = find.descendant(of: find.byType(GameModalCard), matching: find.byType(Scrollable));
        for (var i = 1; i <= 5; i++) {
          await tester.drag(list.first, Offset(0, -size.height * 0.7), warnIfMissed: false);
          await _settle(tester, 200);
          expect(tester.takeException(), isNull, reason: 'run setup scrolled $i');
          await _shot(tester, key, '${tag}_$i');
        }
        await tester.tap(find.byKey(const ValueKey('modal-close')).last);
        await _settle(tester, 400);

        // Train the bot's pick, then look at the finished model.
        final g = c.game;
        c.act((g) => g.startTraining(
              fraction: 0.5,
              durationSeconds: g.runDurations.first,
              spec: ModelSpec.bestGuessFor(g.designContext),
            ));
        c.act((g) => g.advance(g.runDurations.first + 1));
        await tester.tap(find.byKey(const ValueKey('tool-stats')));
        await _settle(tester, 500);
        expect(find.byKey(const ValueKey('pending-benchmark-strip')), findsOneWidget);
        expect(tester.takeException(), isNull, reason: 'pending card');
        await _shot(tester, key, '${tag}_pending');
        await tester.tap(find.byKey(const ValueKey('modal-close')).last);
        await _settle(tester, 400);

        c.act((g) => g.release(open: false, name: 'Parrot-2'));
        unawaited(showReleaseCardDialog(
          tester.element(find.byType(Scaffold).first),
          ReleaseCardData.fromGame(g),
          headline: 'Parrot-2 is live!',
        ));
        await _settle(tester, 800);
        expect(find.byKey(const ValueKey('release-benchmark-strip')), findsOneWidget);
        expect(tester.takeException(), isNull, reason: 'release card');
        await _shot(tester, key, '${tag}_release');

        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(seconds: 15));
        c.dispose();
        await _setSize(tester, null);
      });
    }
  }

  // The live rival feed: a news card over the map, the leaderboard it opens
  // (row highlighted), the News tab and the "while you were away" digest.
  for (final size in sizes) {
    for (final stage in ['mediumlab', 'frontier']) {
      testWidgets('news feed at ${size.width.toInt()}w, $stage', (tester) async {
        if (_out != null) await tester.runAsync(_loadFonts);
        SharedPreferences.setMockInitialValues({'intro_seen_v1': true, 'tutorial_done_v1': true});
        await _setSize(tester, size);
        final c = await GameController.load();
        c.game = Game(_stateAt(stage, stages[stage]!.$1, casual: stages[stage]!.$2));
        final key = GlobalKey();
        await tester.pumpWidget(RepaintBoundary(key: key, child: AiLabTycoonApp(controller: c)));
        await _settle(tester);
        final tag = '${size.width.toInt()}_${stage}_news';
        final g = c.game;
        expect(g.s.news, isNotEmpty, reason: 'the bot run posted news');

        // The newest released rival makes the news again (as if just out).
        final idx = g.releasedCount - 1;
        c.act((g) => g.s.news.add(NewsItem(
              serial: g.lastNewsSerial + 1,
              time: g.s.time,
              kind: NewsKind.rival,
              index: idx,
              playerRating: g.rating,
            )));
        await _settle(tester, 800);
        expect(find.byKey(const ValueKey('news-toast')), findsOneWidget);
        expect(tester.takeException(), isNull, reason: 'news toast');
        await _shot(tester, key, '${tag}_toast');

        await tester.tap(find.byKey(const ValueKey('news-toast')));
        await _settle(tester, 500);
        expect(find.byKey(const ValueKey('leaderboard-highlight')), findsOneWidget);
        expect(tester.takeException(), isNull, reason: 'leaderboard from news');
        await _shot(tester, key, '${tag}_board');

        await tester.tap(find.byKey(const ValueKey('tab-news')));
        await _settle(tester, 400);
        expect(find.byKey(const ValueKey('news-list')), findsOneWidget);
        expect(tester.takeException(), isNull, reason: 'news tab');
        await _shot(tester, key, '${tag}_tab');
        await tester.tap(find.byKey(const ValueKey('modal-close')).last);
        await _settle(tester, 400);

        unawaited(showOfflineDialog(
          tester.element(find.byType(Scaffold).first),
          OfflineReport(
            seconds: 8 * 3600,
            moneyEarned: 1e9,
            usersBefore: g.s.users,
            usersAfter: g.s.users * 1.2,
            trainingFinished: true,
            news: g.s.news.reversed.take(6).toList().reversed.toList(),
          ),
        ));
        await _settle(tester, 600);
        expect(find.byKey(const ValueKey('news-digest')), findsOneWidget);
        expect(tester.takeException(), isNull, reason: 'offline digest');
        await _shot(tester, key, '${tag}_digest');

        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(seconds: 15));
        c.dispose();
        await _setSize(tester, null);
      });
    }
  }

  // The move-to-closet modal: the requirements checklist.
  for (final size in sizes) {
    testWidgets('move modal at ${size.width.toInt()}w', (tester) async {
      if (_out != null) await tester.runAsync(_loadFonts);
      SharedPreferences.setMockInitialValues({'intro_seen_v1': true, 'tutorial_done_v1': true});
      await _setSize(tester, size);
      final c = await GameController.load();
      c.game = Game(GameState(money: 9000, users: 1200, era: Era.garage, powerTier: 1));
      final key = GlobalKey();
      await tester.pumpWidget(RepaintBoundary(key: key, child: AiLabTycoonApp(controller: c)));
      await _settle(tester);
      await tester.tap(find.byKey(const ValueKey('unlock-closet')));
      await _settle(tester, 500);
      expect(tester.takeException(), isNull);
      expect(find.byKey(const ValueKey('move-checklist')), findsOneWidget);
      await _shot(tester, key, '${size.width.toInt()}_move_modal');
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 15));
      c.dispose();
      await _setSize(tester, null);
    });
  }

  // Moving to the closet: truck and fade along the road, the camera follows,
  // the tiles pop in at the new place; a tap skips it.
  for (final size in [const Size(390, 844), const Size(1400, 900)]) {
    testWidgets('move sequence at ${size.width.toInt()}w', (tester) async {
      if (_out != null) await tester.runAsync(_loadFonts);
      SharedPreferences.setMockInitialValues({'intro_seen_v1': true, 'tutorial_done_v1': true});
      await _setSize(tester, size);
      final c = await GameController.load();
      final garage = List<String?>.filled(16, null);
      for (final i in [5, 6, 9, 10]) {
        garage[i] = 'gpu_gamer';
      }
      garage[1] = 'cool_fan';
      c.game = Game(
        GameState(money: 1e5, era: Era.startup, powerTier: 2, grids: {'garage': garage}),
      );
      final key = GlobalKey();
      await tester.pumpWidget(RepaintBoundary(key: key, child: AiLabTycoonApp(controller: c)));
      await _settle(tester);
      final tag = '${size.width.toInt()}_move';
      await _shot(tester, key, '${tag}_0');
      expect(c.act((g) => g.moveTo('closet')), isTrue);
      for (final (i, ms) in [(1, 500), (2, 700), (3, 900)]) {
        await _settle(tester, ms);
        expect(tester.takeException(), isNull);
        await _shot(tester, key, '${tag}_$i');
      }
      expect(find.byKey(const ValueKey('move-banner')), findsOneWidget);
      await _settle(tester, 1400);
      expect(find.byKey(const ValueKey('move-banner')), findsNothing);
      expect(find.byKey(const ValueKey('room-garage')), findsNothing);
      expect(find.byKey(const ValueKey('leaving-garage')), findsNothing);
      expect(find.byKey(const ValueKey('room-closet')), findsOneWidget);
      await _shot(tester, key, '${tag}_closet');

      // Next move (closet → colo) and skip it with a tap.
      c.game.s.era = Era.smallLab;
      c.game.s.powerTier = 3;
      c.game.s.money = 1e8;
      expect(c.act((g) => g.moveTo('colo')), isTrue);
      await _settle(tester, 300);
      expect(find.byKey(const ValueKey('move-skip')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('move-skip')));
      await _settle(tester, 300);
      expect(find.byKey(const ValueKey('move-banner')), findsNothing);
      expect(find.byKey(const ValueKey('room-colo')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await _shot(tester, key, '${tag}_colo_skipped');

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 15));
      c.dispose();
      await _setSize(tester, null);
    });
  }
}
