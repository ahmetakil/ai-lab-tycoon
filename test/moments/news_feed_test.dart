// The live rival feed in the UI: the news ticker (one at a time, tap opens
// the leaderboard on that row), the News tab and the offline digest.
import 'package:ai_lab_tycoon/sim/content.dart';
import 'package:ai_lab_tycoon/sim/game.dart';
import 'package:ai_lab_tycoon/sim/game_state.dart';
import 'package:ai_lab_tycoon/sim/news.dart';
import 'package:ai_lab_tycoon/ui/game_controller.dart';
import 'package:ai_lab_tycoon/ui/moments/event_presenter.dart';
import 'package:ai_lab_tycoon/ui/moments/news_feed.dart';
import 'package:ai_lab_tycoon/ui/moments/rivals_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _run(WidgetTester tester, Future<void> Function(GameController c) body) async {
  SharedPreferences.setMockInitialValues({kIntroSeenKey: true});
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

Future<void> _pumpFor(WidgetTester tester, Duration d) async {
  for (var t = Duration.zero; t < d; t += const Duration(milliseconds: 200)) {
    await tester.pump(const Duration(milliseconds: 200));
  }
}

ThemeData get _theme => ThemeData(brightness: Brightness.dark, colorSchemeSeed: const Color(0xFF39FF9F));

Widget _app(GameController c) => MaterialApp(
  theme: _theme,
  home: EventPresenter(controller: c, child: const Scaffold(body: Text('game'))),
);

void main() {
  testWidgets('a rival release becomes a news toast; tapping it highlights the row', (tester) async {
    await _run(tester, (c) async {
      await tester.pumpWidget(_app(c));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(NewsTicker), findsNothing, reason: 'a new game starts quiet');

      // GPT-ish-1 drips out after a few minutes; the gossip line soon after.
      c.act((g) => g.advance(rivalDripSeconds(Era.garage) + 1));
      c.act((g) => g.advance(flavourNewsSeconds(Era.garage)));
      expect(c.game.s.news, hasLength(2));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byKey(const ValueKey('news-toast')), findsOneWidget, reason: 'one at a time');
      expect(find.text('ClosedAI released GPT-ish-1'), findsOneWidget);
      expect(find.textContaining('796 rating'), findsOneWidget);
      expect(find.textContaining('Overtook you'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('news-toast')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byKey(const ValueKey('leaderboard')), findsOneWidget);
      final row = find.byKey(const ValueKey('leaderboard-highlight'));
      expect(row, findsOneWidget);
      expect(find.descendant(of: row, matching: find.textContaining('GPT-ish-1')), findsOneWidget);
      // Only released rivals are on the board: Tiny-Transformer, GPT-ish-1, you.
      expect(find.text('#3 of 3'), findsOneWidget);

      // The queued gossip shows once the first card is gone.
      await tester.pump(const Duration(milliseconds: 900));
      expect(find.textContaining('10,000 uploaded models'), findsOneWidget);
    });
  });

  testWidgets('news cards queue and expire one by one', (tester) async {
    await _run(tester, (c) async {
      await tester.pumpWidget(_app(c));
      await tester.pump(const Duration(milliseconds: 300));
      c.act((g) => g.advance(rivalDripSeconds(Era.garage) + 1));
      c.act((g) => g.advance(flavourNewsSeconds(Era.garage)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(NewsTicker), findsOneWidget);
      expect(find.text('ClosedAI released GPT-ish-1'), findsOneWidget);
      // ~5 s on screen, slide out, a short gap, then the next card.
      await _pumpFor(tester, const Duration(seconds: 7));
      expect(find.text('ClosedAI released GPT-ish-1'), findsNothing);
      expect(find.byType(NewsTicker), findsOneWidget);
      expect(find.textContaining('10,000 uploaded models'), findsOneWidget);
      await _pumpFor(tester, const Duration(seconds: 7));
      expect(find.byType(NewsTicker), findsNothing);
    });
  });

  testWidgets('offline releases go to the digest, not toasts', (tester) async {
    await _run(tester, (c) async {
      c.offlineReport = c.game.catchUp(3600);
      expect(c.offlineReport!.news, isNotEmpty);
      await tester.pumpWidget(_app(c));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('While you were away'), findsOneWidget);
      expect(find.byKey(const ValueKey('news-digest')), findsOneWidget);
      expect(find.textContaining('ClosedAI released GPT-ish-1'), findsOneWidget);
      await tester.tap(find.text('Collect'));
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.byType(NewsTicker), findsNothing);
    });
  });

  testWidgets('the News tab lists releases newest first with game time', (tester) async {
    await _run(tester, (c) async {
      c.game = Game(GameState(era: Era.bigLab, rivalIndex: 8, users: 1e7));
      c.game.advance(3 * 3600, step: 10);
      final news = c.game.s.news;
      expect(news.where((n) => n.kind == NewsKind.rival).length, greaterThanOrEqualTo(2));
      await tester.binding.setSurfaceSize(const Size(420, 2400));
      await tester.pumpWidget(
        MaterialApp(theme: _theme, home: Scaffold(body: RivalsScreen(controller: c))),
      );
      // The board shows released rivals ahead of you by name.
      expect(find.text(rivalLadder[9].model), findsWidgets);
      expect(find.byKey(const ValueKey('news-list')), findsNothing);

      await tester.tap(find.byKey(const ValueKey('tab-news')));
      await tester.pump();
      expect(find.byKey(const ValueKey('news-list')), findsOneWidget);
      final newest = find.byKey(ValueKey('news-row-${news.last.serial}'));
      final oldest = find.byKey(ValueKey('news-row-${news.first.serial}'));
      expect(tester.getTopLeft(newest).dy, lessThan(tester.getTopLeft(oldest).dy));
      expect(find.textContaining('ago'), findsWidgets);
      expect(find.textContaining('2h ago'), findsWidgets);

      // Tapping a release goes back to the board with that row highlighted.
      final rival = news.lastWhere((n) => n.kind == NewsKind.rival);
      await tester.tap(find.byKey(ValueKey('news-row-${rival.serial}')));
      await tester.pump();
      expect(find.byKey(const ValueKey('news-list')), findsNothing);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('leaderboard-highlight')),
          matching: find.textContaining(rival.rival!.model),
        ),
        findsOneWidget,
      );
    });
  });

  test('news text: detail rotates, verdict and relative time', () {
    final r = rivalLadder[13]; // yAI Grokk 3
    final item = NewsItem(serial: 1, time: 0, kind: NewsKind.rival, index: 13, playerRating: 1480);
    expect(newsHeadline(item), 'yAI released Grokk 3');
    expect(newsDetail(item), startsWith('1,503 rating, '));
    expect(newsVerdict(item), contains('Overtook you'));
    expect(
      newsVerdict(NewsItem(serial: 1, time: 0, kind: NewsKind.rival, index: 13, playerRating: 1600)),
      'You\'re still ahead',
    );
    expect(rivalDetail(12, rivalLadder[12]), contains('H100s'));
    expect(rivalDetail(13, r), contains('users'));
    expect(rivalDetail(14, rivalLadder[14]), rivalLadder[14].quip);
    final quip = NewsItem(serial: 2, time: 0, kind: NewsKind.rival, index: 14);
    expect(newsDetail(quip), '1,506 rating. ${rivalLadder[14].quip}');
    expect(newsAgo(30), 'just now');
    expect(newsAgo(125), '2m ago');
    expect(newsAgo(3 * 3600 + 10), '3h ago');
  });
}
