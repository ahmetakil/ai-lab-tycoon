// The live rival feed (lib/sim/news.dart): release order, the next rival is
// always released, offline digest, save round trip, and parody-only text.
import 'dart:convert';

import 'package:ai_lab_tycoon/sim/bot.dart';
import 'package:ai_lab_tycoon/sim/content.dart';
import 'package:ai_lab_tycoon/sim/game.dart';
import 'package:ai_lab_tycoon/sim/game_state.dart';
import 'package:ai_lab_tycoon/sim/news.dart';
import 'package:flutter_test/flutter_test.dart';

GameState _roundTrip(GameState s) =>
    GameState.fromJson(jsonDecode(jsonEncode(s.toJson())) as Map<String, dynamic>);

void main() {
  test('a new game starts with only the first rival out and no news', () {
    final g = Game();
    expect(g.releasedCount, 1);
    expect(g.isReleased(0), isTrue);
    expect(g.isReleased(1), isFalse);
    g.advance(10);
    expect(g.s.news, isEmpty);
  });

  test('the drip releases one rival at a time, only from reached eras', () {
    final g = Game();
    g.advance(rivalDripSeconds(Era.garage) + 1);
    expect(g.releasedCount, 2, reason: 'GPT-ish-1 drips out in the garage');
    final item = g.s.news.firstWhere((n) => n.kind == NewsKind.rival);
    expect(item.rival, rivalLadder[1]);
    expect(item.overtookYou, isTrue, reason: '${rivalLadder[1].rating} > ${g.rating}');
    // Index 2 is a Startup rival: nothing more until the Startup era.
    g.advance(3 * 3600);
    expect(g.releasedCount, 2);
    g.s.era = Era.startup;
    g.advance(rivalDripSeconds(Era.startup) + 1);
    expect(g.releasedCount, 3);
    // Lookahead: at most rivalLookahead past the next rival.
    g.s.era = Era.globalLab;
    g.advance(20 * 3600, step: 10);
    expect(g.releasedCount, g.s.rivalIndex + 1 + rivalLookahead);
  });

  test('passing a rival releases the next one at once, before it can be beaten', () {
    final g = Game(GameState(era: Era.globalLab));
    // A huge model passes the whole ladder in one tick (canBeat is
    // unchanged); each rival is released just before it's beaten.
    g.s.users = 1e10;
    g.s.releases.add(const ModelRelease(name: 'Big', effectiveCompute: 1e36, rating: 2000, open: false, time: 0));
    final order = <int>[];
    for (var t = 0; t < 5 && g.nextRival != null; t++) {
      g.s.users = 1e10;
      g.tick(1);
      for (final e in g.events) {
        if (e is RivalBeaten) order.add(rivalLadder.indexOf(e.rival));
      }
      g.events.clear();
    }
    expect(order, List.generate(rivalLadder.length, (i) => i));
    expect(g.releasedCount, rivalLadder.length);
    final released = [for (final n in g.s.news) if (n.kind == NewsKind.rival) n.index];
    expect(released, List.generate(rivalLadder.length - 1, (i) => i + 1), reason: 'ladder order, each once');
  });

  test('casual playthrough: the next rival is always released, releases in order', () {
    var lastSerial = 0;
    final released = <int>[];
    final r = runSchedule(
      dt: 3,
      thinkEvery: 6,
      onTick: (g, _) {
        expect(g.isReleased(g.s.rivalIndex) || g.nextRival == null, isTrue);
        expect(g.s.rivalsReleased, greaterThanOrEqualTo(g.s.rivalIndex));
        for (final n in g.s.news) {
          if (n.serial <= lastSerial) continue;
          if (n.kind == NewsKind.rival) {
            released.add(n.index);
            // Scheduled releases only come from reached eras; the next
            // rival is the exception (it's always out).
            expect(g.isUnlocked(n.rival!.era) || n.index <= g.s.rivalIndex, isTrue, reason: n.rival!.model);
          }
        }
        lastSerial = g.lastNewsSerial;
      },
      onEvent: (g, e, _) {
        if (e is RivalBeaten) {
          final i = rivalLadder.indexOf(e.rival);
          expect(g.isReleased(i), isTrue);
          if (i > 0) {
            expect(
              g.s.news.any((n) => n.kind == NewsKind.rival && n.index == i),
              isTrue,
              reason: 'released (with news) before ${e.rival.model} was beaten',
            );
          }
        }
      },
    );
    expect(r.ladderDone, isTrue);
    expect(released, List.generate(rivalLadder.length - 1, (i) => i + 1));
    expect(r.game.s.flavourShown, greaterThan(flavourNews.length ~/ 2));
  });

  test('releases while offline land in the digest', () {
    final g = Game();
    final before = g.lastNewsSerial;
    final report = g.catchUp(3600);
    expect(report.news, isNotEmpty);
    expect(report.news.every((n) => n.serial > before), isTrue);
    expect(report.news.map((n) => n.serial), g.s.news.map((n) => n.serial));
    expect(report.news.where((n) => n.kind == NewsKind.rival).single.rival, rivalLadder[1]);
    expect(report.news.where((n) => n.kind == NewsKind.flavour), isNotEmpty);
    // The digest doesn't change the offline catch-up itself.
    final plain = Game()..applyOffline(3600);
    expect(g.s.money, plain.s.money);
    expect(g.s.users, plain.s.users);
    // A second, short absence with nothing due has an empty digest.
    expect(g.catchUp(30).news, isEmpty);
  });

  test('the feed round-trips through a save', () {
    final g = Game(GameState(era: Era.bigLab, rivalIndex: 9));
    g.advance(4 * 3600, step: 10);
    expect(g.s.news, isNotEmpty);
    final s2 = _roundTrip(g.s);
    expect(s2.rivalsReleased, g.s.rivalsReleased);
    expect(s2.lastRivalReleaseAt, g.s.lastRivalReleaseAt);
    expect(s2.flavourShown, g.s.flavourShown);
    expect(s2.lastFlavourAt, g.s.lastFlavourAt);
    expect(s2.news.map((n) => n.toJson()), g.s.news.map((n) => n.toJson()));
    // Same future after loading.
    final g2 = Game(s2);
    g.advance(3 * 3600, step: 10);
    g2.advance(3 * 3600, step: 10);
    expect(g2.s.news.map((n) => n.toJson()), g.s.news.map((n) => n.toJson()));
  });

  test('a save from before the feed derives it from progress', () {
    final json = GameState(era: Era.mediumLab, rivalIndex: 6, time: 5000).toJson()
      ..remove('rivalsReleased')
      ..remove('rivalReleaseAt')
      ..remove('flavourShown')
      ..remove('flavourAt')
      ..remove('news');
    final s = GameState.fromJson(jsonDecode(jsonEncode(json)) as Map<String, dynamic>);
    expect(s.rivalsReleased, 7, reason: 'everything up to the next rival');
    expect(s.lastRivalReleaseAt, 5000);
    expect(s.flavourShown, flavourBefore(Era.mediumLab));
    expect(s.news, isEmpty);
    final g = Game(s)..tick(1);
    expect(g.s.news, isEmpty, reason: 'loading posts nothing');
    expect(g.isReleased(6), isTrue);
    expect(g.isReleased(7), isFalse);
  });

  test('bad news entries are dropped on load and the log is capped', () {
    final json = GameState().toJson()
      ..['news'] = [
        {'n': 1, 't': 0, 'k': 'rival', 'i': 999},
        {'n': 2, 't': 0, 'k': 'nope', 'i': 0},
        'junk',
        {'n': 3, 't': 5, 'k': 'flavour', 'i': 0},
      ];
    final s = GameState.fromJson(jsonDecode(jsonEncode(json)) as Map<String, dynamic>);
    expect(s.news.map((n) => n.serial), [3]);

    final g = Game(GameState(era: Era.globalLab));
    g.s.users = 1e10;
    g.s.releases.add(const ModelRelease(name: 'Big', effectiveCompute: 1e36, rating: 2000, open: false, time: 0));
    g.advance(400 * 3600, step: 60);
    expect(g.s.news.length, lessThanOrEqualTo(newsLogCap));
  });

  test('flavour news is parody only', () {
    const real = [
      'OpenAI', 'Anthropic', 'Google', 'DeepMind', 'Meta ', 'Meta\'', 'xAI', 'Mistral ', 'DeepSeek',
      'Grok', 'Claude', 'Gemini', 'ChatGPT', 'Hugging Face', 'Microsoft', 'Nvidia', 'NVIDIA',
    ];
    for (final f in flavourNews) {
      for (final name in real) {
        expect(f.text.contains(name), isFalse, reason: '"$name" in: ${f.text}');
      }
      expect(rivalLadder.any((r) => r.lab == f.lab), isTrue, reason: 'unknown lab ${f.lab}');
      expect(f.text, contains(f.lab));
    }
    // In era order, so "the next line" is always the earliest era left.
    for (var i = 1; i < flavourNews.length; i++) {
      expect(flavourNews[i].era.index, greaterThanOrEqualTo(flavourNews[i - 1].era.index));
    }
  });
}
