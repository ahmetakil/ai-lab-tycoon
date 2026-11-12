// The live rival feed: rival models appear on the leaderboard over time
// ("yAI released Grokk 3") and the industry posts small flavour news.
//
// Release schedule (deterministic, no RNG, offline-safe):
// - Rivals release in ladder order, so the released set is a prefix of
//   rivalLadder ([GameState.rivalsReleased]). A new game starts with the
//   first one (your first target) already out.
// - The next rival to beat (rivalIndex) is always released: passing one
//   releases the next in the same tick. So a rival is always on the board
//   before you can beat it, and the HUD's "next rival" is always released.
// - On top of that, up to [rivalLookahead] more rivals drip out ahead of you,
//   one every [rivalDripSeconds] of game time (by your era), but only rivals
//   of an era you've reached. The board moves while you idle, and offline.
// The release schedule only adds news; gates, rival ratings and the win
// condition are untouched (Game.canBeat doesn't look at it).
import 'dart:math' as math;

import 'content.dart';
import 'game.dart';

/// How many unbeaten rivals past the next one may be on the board.
const rivalLookahead = 2;

/// Game seconds between two scheduled rival releases, by your era. Active
/// play: the board moves every few minutes (an era lasts ~5 min in the
/// garage, ~1–2 h later).
double rivalDripSeconds(Era era) => switch (era) {
  Era.garage => 60,
  Era.startup => 3 * 60,
  Era.smallLab => 10 * 60,
  Era.mediumLab => 20 * 60,
  Era.bigLab => 8 * 60,
  Era.globalLab => 12 * 60,
};

/// Game seconds between two flavour news items, by your era.
double flavourNewsSeconds(Era era) => switch (era) {
  Era.garage => 2 * 60,
  Era.startup => 4 * 60,
  Era.smallLab => 12 * 60,
  Era.mediumLab => 20 * 60,
  Era.bigLab => 12 * 60,
  Era.globalLab => 15 * 60,
};

/// News log entries kept in the save (newest kept).
const newsLogCap = 60;

/// Industry gossip that doesn't touch the game. Parody labs only. In era
/// order: the next one posts once its era is reached.
class FlavourNews {
  final Era era;
  final String lab;
  final String text;
  const FlavourNews(this.era, this.lab, this.text);
}

const flavourNews = <FlavourNews>[
  FlavourNews(Era.garage, 'Hugging Hands Collective',
      'Hugging Hands Collective passed 10,000 uploaded models. Most are fine-tunes of the same one.'),
  FlavourNews(Era.startup, 'Gogol DeepThought',
      'Gogol DeepThought published a paper with "All You Need" in the title. Citations: yes.'),
  FlavourNews(Era.startup, 'ClosedAI',
      'ClosedAI is now a "capped-profit" company. The cap is 100× your money.'),
  FlavourNews(Era.smallLab, 'ClosedAI',
      'ClosedAI opened an API waitlist. The waitlist has a waitlist.'),
  FlavourNews(Era.smallLab, 'Gogol DeepThought',
      'A Gogol DeepThought engineer says the chatbot has feelings. HR says it has a policy.'),
  FlavourNews(Era.smallLab, 'Anthropomorphic',
      'Ex-ClosedAI researchers founded Anthropomorphic to build it more safely. Raised \$124M.'),
  FlavourNews(Era.mediumLab, 'Mistrawl',
      'Mistrawl raised €385M six months after founding. The pitch deck was seven pages.'),
  FlavourNews(Era.mediumLab, 'MetaMind Labs',
      'MetaMind Labs\' model weights leaked on a forum. MetaMind: "that was the plan all along."'),
  FlavourNews(Era.mediumLab, 'ClosedAI',
      'ClosedAI\'s board fired its CEO on Friday. He was back by Wednesday.'),
  FlavourNews(Era.bigLab, 'Anthropomorphic',
      'Anthropomorphic raised \$4B. The investor also rents it the GPUs.'),
  FlavourNews(Era.bigLab, 'ClosedAI',
      'ClosedAI cut API prices 50%. Again.'),
  FlavourNews(Era.bigLab, 'DeepSleep',
      'DeepSleep\'s app tops the store charts. Chip stocks lose \$600B in a day.'),
  FlavourNews(Era.bigLab, 'yAI',
      'yAI says its 200k-GPU cluster is the biggest on Earth. Gogol DeepThought disagrees in a blog post.'),
  FlavourNews(Era.globalLab, 'MetaMind Labs',
      'MetaMind Labs offers researchers \$100M signing bonuses. Several accept.'),
  FlavourNews(Era.globalLab, 'Gogol DeepThought',
      'Gogol DeepThought said "coming soon" for the 40th time this year.'),
  FlavourNews(Era.globalLab, 'ClosedAI',
      'ClosedAI "secured" 10 GW of power. Construction starts any day now.'),
  FlavourNews(Era.globalLab, 'Anthropomorphic',
      'Anthropomorphic\'s revenue run-rate passed ClosedAI\'s, depending on who you ask.'),
  FlavourNews(Era.globalLab, 'yAI',
      'yAI told its chatbot to be edgier. It was. The apology was also edgy.'),
];

enum NewsKind { rival, flavour }

/// One entry in the news log (saved). Text is derived from content.
class NewsItem {
  /// Increases by one per item over the whole game (the UI uses it to know
  /// which items it has already shown).
  final int serial;
  final double time;
  final NewsKind kind;

  /// Index into rivalLadder or flavourNews.
  final int index;

  /// Your rating when it was posted (for "overtook you").
  final double playerRating;

  const NewsItem({
    required this.serial,
    required this.time,
    required this.kind,
    required this.index,
    this.playerRating = 0,
  });

  RivalSnapshot? get rival => kind == NewsKind.rival ? rivalLadder[index] : null;
  FlavourNews? get flavour => kind == NewsKind.flavour ? flavourNews[index] : null;
  String get lab => rival?.lab ?? flavour!.lab;

  /// True if the released model rated above you when it came out.
  bool get overtookYou => kind == NewsKind.rival && rival!.rating > playerRating;

  Map<String, dynamic> toJson() => {
    'n': serial,
    't': time,
    'k': kind.name,
    'i': index,
    'r': playerRating,
  };

  /// Null for entries that no longer fit the content (dropped on load).
  static NewsItem? fromJson(Object? j) {
    if (j is! Map) return null;
    final kind = NewsKind.values.asNameMap()[j['k']];
    final index = (j['i'] as num?)?.toInt();
    if (kind == null || index == null || index < 0) return null;
    if (index >= (kind == NewsKind.rival ? rivalLadder.length : flavourNews.length)) return null;
    return NewsItem(
      serial: (j['n'] as num?)?.toInt() ?? 0,
      time: (j['t'] as num?)?.toDouble() ?? 0,
      kind: kind,
      index: index,
      playerRating: (j['r'] as num?)?.toDouble() ?? 0,
    );
  }
}

/// Number of flavour lines from eras before [era] (an old save skips them).
int flavourBefore(Era era) => flavourNews.where((f) => f.era.index < era.index).length;

extension NewsFeed on Game {
  /// Is ladder rival [i] on the leaderboard yet? The next rival always is.
  bool isReleased(int i) => i < s.rivalsReleased || i <= s.rivalIndex;

  /// Rivals on the leaderboard (a prefix of rivalLadder).
  int get releasedCount =>
      (s.rivalIndex + 1 > s.rivalsReleased ? s.rivalIndex + 1 : s.rivalsReleased)
          .clamp(0, rivalLadder.length);

  /// Newest serial in the log (0 if empty).
  int get lastNewsSerial => s.news.isEmpty ? 0 : s.news.last.serial;

  /// Items posted after [serial], oldest first.
  List<NewsItem> newsSince(int serial) => [
    for (final n in s.news)
      if (n.serial > serial) n,
  ];

  /// [Game.applyOffline] plus the "while you were away" news digest.
  OfflineReport catchUp(double seconds) {
    final before = lastNewsSerial;
    return applyOffline(seconds).withNews(newsSince(before));
  }

  /// Release due rivals and post due flavour news. Called every tick.
  void updateNews() {
    // Play passes one rival at a time, so the feed is at most one behind.
    // A state that jumped further (built by hand) catches up quietly.
    if (s.rivalsReleased < s.rivalIndex) {
      s.rivalsReleased = math.min(s.rivalIndex + 1, rivalLadder.length);
      s.lastRivalReleaseAt = s.time;
    }
    // Forced: the next rival is always released.
    if (s.rivalsReleased < rivalLadder.length && s.rivalsReleased <= s.rivalIndex) {
      _releaseNext();
    }
    // Scheduled drip, a lookahead window past the next rival.
    final drip = rivalDripSeconds(s.era);
    if (s.rivalsReleased < rivalLadder.length &&
        s.rivalsReleased <= s.rivalIndex + rivalLookahead &&
        isUnlocked(rivalLadder[s.rivalsReleased].era) &&
        s.time >= s.lastRivalReleaseAt + drip) {
      _releaseNext();
    }
    // Flavour.
    if (s.flavourShown < flavourNews.length &&
        isUnlocked(flavourNews[s.flavourShown].era) &&
        s.time >= s.lastFlavourAt + flavourNewsSeconds(s.era)) {
      _post(NewsKind.flavour, s.flavourShown);
      s.flavourShown++;
      s.lastFlavourAt = s.time;
    }
  }

  void _releaseNext() {
    _post(NewsKind.rival, s.rivalsReleased);
    s.rivalsReleased++;
    s.lastRivalReleaseAt = s.time;
  }

  void _post(NewsKind kind, int index) {
    s.news.add(NewsItem(
      serial: lastNewsSerial + 1,
      time: s.time,
      kind: kind,
      index: index,
      playerRating: rating,
    ));
    if (s.news.length > newsLogCap) s.news.removeRange(0, s.news.length - newsLogCap);
  }
}
