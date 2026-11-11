// Renders every tab at real phone sizes with early/mid/late-game saves and
// fails on any layout exception (overflows etc.).
// Set LAYOUT_PREVIEW_DIR=/some/dir to also write PNG screenshots.
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
    for (final w in ['Regular', 'Medium', 'Bold'])
      'assets/fonts/SpaceGrotesk/SpaceGrotesk-$w.ttf',
  ]);
  await _font('JetBrainsMono', [
    for (final w in ['Regular', 'Bold']) 'assets/fonts/JetBrainsMono/JetBrainsMono-$w.ttf',
  ]);
}

GameState _stateAt(double seconds) {
  if (seconds == 0) return GameState();
  final r = runPlaythrough(maxSeconds: seconds, stopWhenDone: false);
  r.game.events.clear();
  // Round-trip through JSON like a real save.
  return GameState.fromJson(r.game.s.toJson());
}

void main() {
  const sizes = [Size(360, 740), Size(390, 844)];
  const stages = {'start': 0.0, 'startup': 20 * 60.0, 'lab': 100 * 60.0};
  const tabs = ['Lab', 'Hardware', 'Research', 'Rivals'];

  for (final size in sizes) {
    for (final stage in stages.entries) {
      testWidgets('no layout errors at ${size.width.toInt()}w, ${stage.key}', (tester) async {
        if (_out != null) await tester.runAsync(_loadFonts);
        SharedPreferences.setMockInitialValues({'intro_seen_v1': true});
        await tester.binding.setSurfaceSize(size);
        final c = await GameController.load();
        c.game = Game(_stateAt(stage.value));
        final key = GlobalKey();
        await tester.pumpWidget(RepaintBoundary(key: key, child: AiLabTycoonApp(controller: c)));
        await tester.pump(const Duration(milliseconds: 500));

        for (final tab in tabs) {
          await tester.tap(find.descendant(
              of: find.byType(NavigationBar), matching: find.text(tab)));
          await tester.pump(const Duration(milliseconds: 500));
          expect(tester.takeException(), isNull, reason: '$tab tab');
          if (_out != null) {
            await tester.runAsync(() async {
              final b = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
              final img = await b.toImage(pixelRatio: 1);
              final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
              File('$_out/${size.width.toInt()}_${stage.key}_$tab.png')
                  .writeAsBytesSync(bytes!.buffer.asUint8List());
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
}
