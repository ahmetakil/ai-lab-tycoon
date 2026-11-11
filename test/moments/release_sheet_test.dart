import 'package:ai_lab_tycoon/sim/balance.dart';
import 'package:ai_lab_tycoon/sim/game.dart';
import 'package:ai_lab_tycoon/ui/game_controller.dart';
import 'package:ai_lab_tycoon/ui/moments/release_card.dart';
import 'package:ai_lab_tycoon/ui/moments/release_sheet.dart';
import 'package:ai_lab_tycoon/ui/moments/rivals_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Runs [body] with a fresh controller that has a trained model pending,
/// and disposes it (and its periodic timers) before the test ends.
Future<void> withController(
  WidgetTester tester,
  Future<void> Function(GameController c) body, {
  double pendingMultiplier = 8,
  Size size = const Size(420, 1600),
}) async {
  SharedPreferences.setMockInitialValues({'intro_seen_v1': true});
  await tester.binding.setSurfaceSize(size);
  final c = await GameController.load();
  c.game.s.pendingEffectiveCompute = startEffectiveCompute * pendingMultiplier;
  try {
    await body(c);
  } finally {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 2));
    c.dispose();
    await tester.binding.setSurfaceSize(null);
  }
}

Widget _host(Widget child) => MaterialApp(
  theme: ThemeData(useMaterial3: true, brightness: Brightness.dark, colorSchemeSeed: const Color(0xFF39FF9F)),
  home: Scaffold(body: child),
);

void main() {
  testWidgets('release sheet builds and releases', (tester) async {
    await withController(tester, (c) async {
      await tester.pumpWidget(_host(ReleaseSheet(controller: c)));
      expect(find.text('Ship it?'), findsOneWidget);
      expect(find.text('Closed API'), findsOneWidget);
      expect(find.text('Open weights'), findsOneWidget);
      expect(find.text('Live demo'), findsOneWidget);
      expect(find.text(defaultModelName(c.game)), findsOneWidget);

      // Naming joke appears after enough suffixes.
      await tester.enterText(find.byType(TextField), 'GL-1-turbo-preview-0613');
      await tester.pump();
      expect(find.text('Users are confused by your naming scheme.'), findsOneWidget);

      await tester.tap(find.text('Open weights'));
      await tester.pump();
      await tester.tap(find.text('Release'));
      await tester.pump();
      expect(c.game.s.pendingEffectiveCompute, isNull);
      expect(c.game.s.currentModel.name, 'GL-1-turbo-preview-0613');
      expect(c.game.s.currentModel.open, isTrue);
    });
  });

  testWidgets('worse model shows a warning', (tester) async {
    await withController(tester, pendingMultiplier: 0.25, (c) async {
      await tester.pumpWidget(_host(ReleaseSheet(controller: c)));
      expect(find.textContaining('WORSE'), findsOneWidget);
    });
  });

  testWidgets('release card and rivals screen build', (tester) async {
    await withController(tester, size: const Size(420, 2400), (c) async {
      final data = ReleaseCardData.fromGame(Game());
      expect(data.postText, contains(kGameUrl));
      expect(data.benchmarkLine, contains('cherry-picked'));
      await tester.pumpWidget(_host(ScaledReleaseCard(data: data, boundaryKey: GlobalKey())));
      expect(find.text('AI LAB TYCOON'), findsOneWidget);

      await tester.pumpWidget(_host(RivalsScreen(controller: c)));
      expect(find.text('Share your latest model'), findsOneWidget);
      expect(find.text('CURRENT TARGET'), findsOneWidget);
      expect(find.textContaining('All names are parodies'), findsOneWidget);
    });
  });
}
