import 'package:ai_lab_tycoon/sim/content.dart';
import 'package:ai_lab_tycoon/sim/game.dart';
import 'package:ai_lab_tycoon/ui/game_controller.dart';
import 'package:ai_lab_tycoon/ui/moments/event_presenter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _run(WidgetTester tester, Map<String, Object> prefs, Future<void> Function(GameController c) body) async {
  SharedPreferences.setMockInitialValues(prefs);
  await tester.binding.setSurfaceSize(const Size(430, 932));
  final c = await GameController.load();
  try {
    await body(c);
  } finally {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 15));
    c.dispose();
    await tester.binding.setSurfaceSize(null);
  }
}

Widget _app(GameController c) => MaterialApp(
  theme: ThemeData(brightness: Brightness.dark, colorSchemeSeed: const Color(0xFF39FF9F)),
  home: EventPresenter(controller: c, child: const Scaffold(body: Text('game'))),
);

void main() {
  testWidgets('first launch shows the intro and names the lab', (tester) async {
    await _run(tester, {}, (c) async {
      await tester.pumpWidget(_app(c));
      await tester.pumpAndSettle();
      expect(find.text('AI LAB TYCOON'), findsOneWidget);
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Tensor Shack');
      await tester.tap(find.text('Open the garage'));
      await tester.pumpAndSettle();
      expect(c.game.s.labName, 'Tensor Shack');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(kIntroSeenKey), isTrue);
    });
  });

  testWidgets('offline report shows once, then clears', (tester) async {
    await _run(tester, {kIntroSeenKey: true}, (c) async {
      c.offlineReport = const OfflineReport(
        seconds: 3600,
        moneyEarned: 1234,
        usersBefore: 10,
        usersAfter: 50,
        trainingFinished: true,
      );
      await tester.pumpWidget(_app(c));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('While you were away'), findsOneWidget);
      expect(find.textContaining('Training finished'), findsOneWidget);
      await tester.tap(find.text('Collect'));
      await tester.pump(const Duration(milliseconds: 400));
      expect(c.offlineReport, isNull);
    });
  });

  testWidgets('events become toasts and queued celebrations', (tester) async {
    await _run(tester, {kIntroSeenKey: true}, (c) async {
      await tester.pumpWidget(_app(c));
      await tester.pump();
      c.act((g) {
        g.events.add(const TrainingFinished(1e19, 900));
        g.events.add(RivalBeaten(rivalLadder[0]));
        g.events.add(const EraUnlocked(Era.startup));
      });
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.text('Training done'), findsOneWidget);
      expect(find.text('RIVAL PASSED'), findsOneWidget);
      expect(find.text('ERA UNLOCKED'), findsNothing, reason: 'queued, not stacked');
      await tester.tap(find.text('Continue'));
      await tester.pump(const Duration(milliseconds: 300));
      // The era moment waits for the world map's reveal fly-over.
      await tester.pump(kEraRevealDelay);
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.text('ERA UNLOCKED'), findsOneWidget);
    });
  });
}
