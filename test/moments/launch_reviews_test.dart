import 'package:ai_lab_tycoon/sim/balance.dart';
import 'package:ai_lab_tycoon/sim/reviews.dart';
import 'package:ai_lab_tycoon/ui/game_controller.dart';
import 'package:ai_lab_tycoon/ui/moments/launch_reviews.dart';
import 'package:ai_lab_tycoon/ui/moments/release_card.dart';
import 'package:ai_lab_tycoon/ui/moments/release_sheet.dart';
import 'package:ai_lab_tycoon/ui/sound.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _review = LaunchReview(
  reviews: [
    Review('arena', 8, 'Beats GPT-ish-3 by 24 points. New #1.'),
    Review('bench', 9, 'Coding scores are top-tier (×2.4).'),
    Review('vibes', 4, 'Another dense 2k model? Yawn.'),
    Review('nooz', 7, 'Open weights! Top comment: "runs on my 4090".'),
  ],
  buzz: 1.2,
  buzzSeconds: 300,
);

Widget _host(Widget child) => MaterialApp(
  theme: ThemeData(useMaterial3: true, brightness: Brightness.dark, colorSchemeSeed: const Color(0xFF39FF9F)),
  home: Scaffold(body: child),
);

Finder _shown(String id) => find.byKey(ValueKey('review-$id-shown'));

void main() {
  testWidgets('scores flip in one at a time with sounds, then the verdict', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    var done = 0;
    final sounds = <Sfx>[];
    await tester.pumpWidget(_host(LaunchReviewsView(
      modelName: 'GL-7',
      review: _review,
      onDone: () => done++,
      playSound: sounds.add,
    )));

    expect(find.text('GL-7'), findsOneWidget);
    for (final id in ['arena', 'bench', 'vibes', 'nooz']) {
      expect(_shown(id), findsNothing);
    }
    // First flip lands at ~0.29 s + half a flip.
    await tester.pump(const Duration(milliseconds: 600));
    expect(_shown('arena'), findsOneWidget);
    expect(_shown('bench'), findsNothing);
    expect(sounds, [Sfx.purchase]); // a score of 8
    await tester.pump(const Duration(milliseconds: 450));
    expect(_shown('bench'), findsOneWidget);
    expect(_shown('nooz'), findsNothing);
    await tester.pump(kReviewRevealDuration);
    for (final id in ['arena', 'bench', 'vibes', 'nooz']) {
      expect(_shown(id), findsOneWidget);
    }
    expect(find.text('Another dense 2k model? Yawn.'), findsOneWidget);
    expect(find.text('SOLID LAUNCH'), findsOneWidget); // (8 + 9 + 4 + 7) / 4 = 7.0
    expect(find.text('7.0'), findsOneWidget);
    expect(find.textContaining('demand +20%'), findsOneWidget);
    expect(find.text('Tap to continue'), findsOneWidget);
    // One sound per flip (by score), then the banner's (by verdict).
    expect(sounds, [Sfx.purchase, Sfx.purchase, Sfx.click, Sfx.purchase, Sfx.upgrade]);
    expect(done, 0);

    await tester.tap(find.byKey(const ValueKey('reviews-tap')));
    expect(done, 1);
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('a tap skips the animation; the next tap continues', (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 740));
    var done = 0;
    final sounds = <Sfx>[];
    await tester.pumpWidget(_host(LaunchReviewsView(
      modelName: 'GL-7',
      review: _review,
      onDone: () => done++,
      playSound: sounds.add,
    )));
    await tester.pump(const Duration(milliseconds: 100));
    expect(_shown('arena'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('reviews-tap')));
    await tester.pump();
    for (final id in ['arena', 'bench', 'vibes', 'nooz']) {
      expect(_shown(id), findsOneWidget);
    }
    expect(find.byKey(const ValueKey('reviews-verdict')), findsOneWidget);
    expect(done, 0, reason: 'the skip tap must not also close it');
    expect(sounds, [Sfx.upgrade], reason: 'a skip plays only the verdict sound');

    await tester.tap(find.byKey(const ValueKey('reviews-tap')));
    expect(done, 1);
    expect(tester.takeException(), isNull);
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('release flow: sheet → reviews → share card with the score', (tester) async {
    SharedPreferences.setMockInitialValues({'intro_seen_v1': true});
    await tester.binding.setSurfaceSize(const Size(420, 1600));
    final c = await GameController.load();
    c.game.s.pendingEffectiveCompute = startEffectiveCompute * 8;
    try {
      await tester.pumpWidget(_host(Builder(
        builder: (context) => TextButton(onPressed: () => showReleaseSheet(context, c), child: const Text('go')),
      )));
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Release'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      final review = c.game.s.currentModel.review!;
      expect(find.byKey(const ValueKey('launch-reviews')), findsOneWidget);

      // Release → share card in about 3 s without touching anything...
      await tester.pump(kReviewRevealDuration);
      expect(find.text('Tap to continue'), findsOneWidget);
      // ...or skip right away.
      await tester.tap(find.byKey(const ValueKey('reviews-tap')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('launch-reviews')), findsNothing);
      expect(find.text('CRITICS ${review.averageText}/10'), findsOneWidget);
      final data = ReleaseCardData.fromGame(c.game);
      expect(data.postText, contains('Critics: ${review.averageText}/10'));
    } finally {
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 15));
      c.dispose();
      await tester.binding.setSurfaceSize(null);
    }
  });
}
