// Renders the release card and celebration overlays to PNG for a visual check.
// Skipped unless MOMENTS_PREVIEW_DIR is set:
//   MOMENTS_PREVIEW_DIR=/tmp/x flutter test test/moments/card_preview_test.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:ai_lab_tycoon/sim/content.dart';
import 'package:ai_lab_tycoon/ui/moments/event_presenter.dart';
import 'package:ai_lab_tycoon/sim/balance.dart';
import 'package:ai_lab_tycoon/ui/game_controller.dart';
import 'package:ai_lab_tycoon/ui/moments/release_card.dart';
import 'package:ai_lab_tycoon/ui/moments/release_sheet.dart';
import 'package:ai_lab_tycoon/ui/moments/rivals_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

final _out = Platform.environment['MOMENTS_PREVIEW_DIR'];

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
  await _font('Roboto', ['$sdk/Roboto-Regular.ttf', '$sdk/Roboto-Bold.ttf', '$sdk/Roboto-Medium.ttf']);
  await _font('MaterialIcons', ['$sdk/MaterialIcons-Regular.otf']);
  await _font('SpaceGrotesk', [
    'assets/fonts/SpaceGrotesk/SpaceGrotesk-Regular.ttf',
    'assets/fonts/SpaceGrotesk/SpaceGrotesk-Medium.ttf',
    'assets/fonts/SpaceGrotesk/SpaceGrotesk-Bold.ttf',
  ]);
  await _font('JetBrainsMono', [
    'assets/fonts/JetBrainsMono/JetBrainsMono-Regular.ttf',
    'assets/fonts/JetBrainsMono/JetBrainsMono-Bold.ttf',
  ]);
}

Future<void> _snap(WidgetTester tester, GlobalKey key, String name) async {
  await tester.runAsync(() async {
    final b = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final img = await b.toImage(pixelRatio: 1);
    final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
    File('$_out/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
  });
}

final _theme = ThemeData(
  useMaterial3: true,
  brightness: Brightness.dark,
  colorSchemeSeed: const Color(0xFF39FF9F),
  fontFamily: 'Roboto',
);

void main() {
  testWidgets('preview release card', (tester) async {
    await _loadFonts();
    const data = ReleaseCardData(
      labName: 'Garage Labs',
      modelName: 'GL-3-turbo-preview',
      open: true,
      year: 2019,
      rating: 968,
      users: 412000,
      arr: 3.4e6,
      rivalLab: 'ClosedAI',
      rivalModel: 'GPT-ish-2',
      rivalRating: 980,
      era: Era.startup,
    );
    await tester.binding.setSurfaceSize(const Size(kCardWidth, kCardHeight));
    final key = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        theme: _theme,
        debugShowCheckedModeBanner: false,
        home: RepaintBoundary(key: key, child: const ReleaseCard(data: data)),
      ),
    );
    await _snap(tester, key, 'release_card');
  }, skip: _out == null);

  testWidgets('preview overlays', (tester) async {
    await _loadFonts();
    await tester.binding.setSurfaceSize(const Size(430, 932));
    final key = GlobalKey();
    Future<void> shot(Widget w, String name, Duration at) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: _theme,
          debugShowCheckedModeBanner: false,
          home: RepaintBoundary(key: key, child: Scaffold(body: w)),
        ),
      );
      await tester.pump(at);
      await _snap(tester, key, name);
    }

    await shot(
      RivalBeatenOverlay(rival: rivalLadder[1], next: rivalLadder[2], onDone: () {}, onShare: () {}),
      'rival_beaten',
      const Duration(milliseconds: 1500),
    );
    await shot(EraOverlay(era: Era.startup, onDone: () {}), 'era', const Duration(milliseconds: 1500));
    await shot(
      const Align(alignment: Alignment.topCenter, child: ViralBanner(secondsLeft: 74)),
      'viral',
      const Duration(milliseconds: 300),
    );
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 12));
  }, skip: _out == null);

  testWidgets('preview rivals + release sheet', (tester) async {
    await _loadFonts();
    SharedPreferences.setMockInitialValues({'intro_seen_v1': true});
    final c = await GameController.load();
    c.game.s
      ..rivalIndex = 2
      ..users = 6200
      ..pendingEffectiveCompute = startEffectiveCompute * 300;
    final key = GlobalKey();
    Future<void> shot(Widget w, String name, Size size) async {
      await tester.binding.setSurfaceSize(size);
      await tester.pumpWidget(
        MaterialApp(
          theme: _theme,
          debugShowCheckedModeBanner: false,
          home: RepaintBoundary(key: key, child: Scaffold(body: w)),
        ),
      );
      await tester.pump(const Duration(milliseconds: 800));
      await _snap(tester, key, name);
    }

    await shot(RivalsScreen(controller: c), 'rivals', const Size(430, 1500));
    await shot(SingleChildScrollView(child: ReleaseSheet(controller: c)), 'release_sheet', const Size(430, 1300));
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 2));
    c.dispose();
  }, skip: _out == null);
}
