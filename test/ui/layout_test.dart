// Renders every tab at real phone sizes with early/mid/late-game saves and
// fails on any layout exception (overflows etc.).
// Set LAYOUT_PREVIEW_DIR=/some/dir to also write PNG screenshots.
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:ai_lab_tycoon/sim/bot.dart';
import 'package:ai_lab_tycoon/sim/game.dart';
import 'package:ai_lab_tycoon/sim/game_state.dart';
import 'package:ai_lab_tycoon/ui/app.dart';
import 'package:ai_lab_tycoon/ui/game_controller.dart';
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
            ? runSchedule(maxWallSeconds: seconds, stopWhenDone: false, dt: 3, thinkEvery: 6)
            : runPlaythrough(maxSeconds: seconds, stopWhenDone: false);
    r.game.events.clear();
    return jsonEncode(r.game.s.toJson());
  });
  // Round-trip through JSON like a real save.
  return GameState.fromJson(jsonDecode(json) as Map<String, dynamic>);
}

void main() {
  const sizes = [Size(360, 740), Size(390, 844)];
  // (seconds, casual schedule?): Garage, Startup, Small lab, Medium lab
  // (casual, day 1 evening), Frontier lab (casual, day 2 evening).
  const stages = {
    'start': (0.0, false),
    'startup': (20 * 60.0, false),
    'smalllab': (100 * 60.0, false),
    'mediumlab': (12 * 3600.0, true),
    'frontier': (36 * 3600.0, true),
  };
  const tabs = ['Lab', 'Datacenter', 'Research', 'Rivals'];

  for (final size in sizes) {
    for (final stage in stages.entries) {
      testWidgets('no layout errors at ${size.width.toInt()}w, ${stage.key}', (tester) async {
        if (_out != null) await tester.runAsync(_loadFonts);
        SharedPreferences.setMockInitialValues({'intro_seen_v1': true});
        await tester.binding.setSurfaceSize(size);
        final c = await GameController.load();
        c.game = Game(_stateAt(stage.key, stage.value.$1, casual: stage.value.$2));
        final key = GlobalKey();
        await tester.pumpWidget(RepaintBoundary(key: key, child: AiLabTycoonApp(controller: c)));
        await tester.pump(const Duration(milliseconds: 500));

        for (final tab in tabs) {
          await tester.tap(
            find.descendant(of: find.byType(NavigationBar), matching: find.text(tab)),
          );
          await tester.pump(const Duration(milliseconds: 500));
          expect(tester.takeException(), isNull, reason: '$tab tab');
          if (_out != null) {
            await tester.runAsync(() async {
              final b = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
              final img = await b.toImage(pixelRatio: 1);
              final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
              File(
                '$_out/${size.width.toInt()}_${stage.key}_$tab.png',
              ).writeAsBytesSync(bytes!.buffer.asUint8List());
            });
          }
          // Scroll the whole tab to surface overflows further down.
          final scrollable = find.byType(Scrollable);
          if (scrollable.evaluate().isNotEmpty) {
            for (var i = 0; i < 8; i++) {
              await tester.drag(scrollable.first, const Offset(0, -500), warnIfMissed: false);
              await tester.pump(const Duration(milliseconds: 100));
            }
            expect(tester.takeException(), isNull, reason: '$tab tab (scrolled)');
          }
        }

        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(seconds: 15));
        c.dispose();
        await tester.binding.setSurfaceSize(null);
      });
    }
  }

  // A crowded garage: throttling GPUs (heat tint + badges), a too-slow switch
  // (bottleneck hint) and placement mode with its valid-cell highlights.
  for (final size in sizes) {
    testWidgets('datacenter scenarios at ${size.width.toInt()}w', (tester) async {
      if (_out != null) await tester.runAsync(_loadFonts);
      SharedPreferences.setMockInitialValues({'intro_seen_v1': true});
      await tester.binding.setSurfaceSize(size);
      final c = await GameController.load();
      final garage = <String?>[
        'gpu_v_class', 'gpu_v_class', 'gpu_gamer', null, //
        'gpu_gamer', 'net_home', 'gpu_old', null,
        'gpu_gamer', 'net_home', 'gpu_v_class', null,
        null, 'cool_fan', null, null,
      ];
      c.game = Game(GameState(money: 4000, powerTier: 1, grids: {'garage': garage}));
      final key = GlobalKey();
      await tester.pumpWidget(RepaintBoundary(key: key, child: AiLabTycoonApp(controller: c)));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.tap(
        find.descendant(of: find.byType(NavigationBar), matching: find.text('Datacenter')),
      );
      await tester.pump(const Duration(milliseconds: 600));
      expect(tester.takeException(), isNull);
      Future<void> shot(String name) async {
        if (_out == null) return;
        await tester.runAsync(() async {
          final b = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
          final img = await b.toImage(pixelRatio: 1);
          final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
          File(
            '$_out/${size.width.toInt()}_grid_$name.png',
          ).writeAsBytesSync(bytes!.buffer.asUint8List());
        });
      }

      await shot('crowded');
      await tester.tap(find.byKey(const ValueKey('kind-cooling')));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.byKey(const ValueKey('part-cool_fan')));
      await tester.pump(const Duration(milliseconds: 600));
      expect(tester.takeException(), isNull);
      await shot('placing');
      await tester.tap(find.byKey(const ValueKey('cell-1-1')));
      await tester.pump(const Duration(milliseconds: 400));
      expect(tester.takeException(), isNull);
      await shot('blocked');
      await tester.tap(find.byKey(const ValueKey('cancel-mode')));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.byKey(const ValueKey('cell-1-1')));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));
      expect(tester.takeException(), isNull);
      await shot('switch_sheet');

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 15));
      c.dispose();
      await tester.binding.setSurfaceSize(null);
    });
  }
}
