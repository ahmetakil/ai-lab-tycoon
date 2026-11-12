// Launch reviews, Game Dev Tycoon style: four parody outlets score every
// release out of 10 with a one-line quip, and the average sets a short
// demand "buzz" multiplier.
//
// Deterministic and pure: scores come from the release's design outcome,
// the rating jump over your previous model, the gap to the best rival on
// the board, novelty (repeating the exact same design scores lower, the way
// GDT punishes repeating a combo) and the launch stunt, plus a little seeded
// noise that never touches the game's RNG. Each quip names the factor that
// moved that outlet's score the most, so the review explains itself.
//
// Balance: the buzz is centred on [reviewPivot], which is what a reasonable
// player (the sim bot) averages, so over a playthrough it nets out to ~×1
// (test/sim/reviews_test.dart checks this).
import 'dart:math' as math;

import 'content.dart';
import 'game.dart';
import 'game_state.dart';
import 'model_design.dart';
import 'news.dart';

/// A parody evaluator.
class ReviewOutlet {
  final String id;
  final String name;

  /// What it cares about, for the UI ("Crowd votes").
  final String tagline;

  /// Weight per factor key (see [ReviewFactors]).
  final Map<String, double> weights;
  const ReviewOutlet(this.id, this.name, this.tagline, this.weights);
}

const reviewOutlets = <ReviewOutlet>[
  ReviewOutlet('arena', 'LLM Arena-ish', 'Crowd votes', {'gap': 1.0, 'jump': 0.6, 'chat': 0.8, 'novelty': 0.4}),
  ReviewOutlet('bench', 'The Benchmarker', 'Eval suites', {'bench': 1.0, 'gap': 0.6, 'jump': 0.5, 'mishap': 1.0}),
  ReviewOutlet('vibes', 'Tech Twitter Vibes', 'The timeline', {'jump': 0.8, 'novelty': 1.2, 'stunt': 0.8, 'gap': 0.4}),
  ReviewOutlet('nooz', 'HackerNooz', 'Top comment', {'open': 1.0, 'serve': 0.8, 'novelty': 0.6, 'mishap': 1.0, 'gap': 0.3}),
];

ReviewOutlet? outletById(String id) {
  for (final o in reviewOutlets) {
    if (o.id == id) return o;
  }
  return null;
}

/// Score before factors and noise.
const reviewBaseScore = 6.0;

/// Noise per outlet score: uniform in ±this.
const reviewNoise = 0.8;

/// Average score that gives a neutral ×1 buzz (what the sim bot averages).
const reviewPivot = 6.6;

/// Buzz range: a 1/10 launch ×[minReviewBuzz], a perfect 10 ×[maxReviewBuzz].
const minReviewBuzz = 0.8;
const maxReviewBuzz = 1.5;

/// Demand buzz multiplier for an average score (piecewise log-linear around
/// [reviewPivot]).
double buzzForAverage(double avg) {
  final a = avg.clamp(1.0, 10.0);
  final x = a >= reviewPivot
      ? math.log(maxReviewBuzz) * (a - reviewPivot) / (10 - reviewPivot)
      : math.log(minReviewBuzz) * (reviewPivot - a) / (reviewPivot - 1);
  return math.exp(x);
}

/// Banner text for an average score.
String verdictFor(double avg) => avg >= 9
    ? 'Universal acclaim'
    : avg >= 7.5
    ? 'Critics love it'
    : avg >= 6
    ? 'Solid launch'
    : avg >= 4.5
    ? 'Mixed reviews'
    : 'Panned';

/// One outlet's score.
class Review {
  final String outletId;
  final int score;
  final String quip;
  const Review(this.outletId, this.score, this.quip);

  ReviewOutlet get outlet => outletById(outletId) ?? reviewOutlets.first;

  Map<String, dynamic> toJson() => {'o': outletId, 's': score, 'q': quip};

  static Review? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final s = (raw['s'] as num?)?.toInt();
    if (s == null) return null;
    return Review(raw['o'] as String? ?? '', s.clamp(1, 10), raw['q'] as String? ?? '');
  }
}

/// The launch reviews, saved on [ModelRelease.review].
class LaunchReview {
  final List<Review> reviews;

  /// Demand multiplier while the buzz lasts (×[minReviewBuzz]..×[maxReviewBuzz]).
  final double buzz;

  /// Game seconds the buzz lasts (it fades out linearly).
  final double buzzSeconds;

  const LaunchReview({required this.reviews, required this.buzz, required this.buzzSeconds});

  double get average =>
      reviews.isEmpty ? reviewPivot : reviews.fold(0.0, (a, r) => a + r.score) / reviews.length;
  String get verdict => verdictFor(average);

  /// The average with one decimal, e.g. "7.5".
  String get averageText => average.toStringAsFixed(1);

  /// The buzz multiplier [elapsed] game seconds after the launch.
  double buzzAt(double elapsed) {
    if (elapsed < 0 || elapsed >= buzzSeconds || buzzSeconds <= 0) return 1;
    return 1 + (buzz - 1) * (1 - elapsed / buzzSeconds);
  }

  Map<String, dynamic> toJson() => {
    'r': reviews.map((r) => r.toJson()).toList(),
    'buzz': buzz,
    'buzzS': buzzSeconds,
  };

  /// Tolerant: null for anything that isn't a review.
  static LaunchReview? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final list = [
      for (final r in (raw['r'] as List?) ?? const [])
        if (Review.fromJson(r) case final rev?) rev,
    ];
    if (list.isEmpty) return null;
    return LaunchReview(
      reviews: list,
      buzz: ((raw['buzz'] as num?)?.toDouble() ?? 1).clamp(minReviewBuzz, maxReviewBuzz),
      buzzSeconds: (raw['buzzS'] as num?)?.toDouble() ?? 0,
    );
  }
}

/// Everything the reviewers look at, as plain numbers (built by
/// [GameReviews.reviewInputs]; tests build it directly).
class ReviewInputs {
  final double rating;
  final double previousRating;

  /// Best released rival (null before any are out).
  final RivalSnapshot? topRival;
  final DesignOutcome? design;

  /// Specs of the earlier releases, oldest first (the starting model counts
  /// as the default spec).
  final List<ModelSpec> previousSpecs;

  /// 0..1: how much design freedom the lab has (0 in the garage, where
  /// there is nothing worth varying, so repeats aren't punished).
  final double designFreedom;
  final bool open;

  /// 'none' or a launch stunt id, and whether it worked.
  final String stuntId;
  final bool stuntSucceeded;
  final int seed;

  const ReviewInputs({
    required this.rating,
    required this.previousRating,
    this.topRival,
    this.design,
    this.previousSpecs = const [],
    this.designFreedom = 1,
    this.open = false,
    this.stuntId = 'none',
    this.stuntSucceeded = true,
    this.seed = 1,
  });
}

/// Short name for a spec in a quip: "dense 2k", "fine-grained MoE 128k".
String specNickname(ModelSpec s) {
  final arch = switch (s.architecture) {
    Architecture.dense => 'dense',
    Architecture.moe => 'MoE',
    Architecture.fineMoe => 'fine-grained MoE',
  };
  return '$arch ${s.context.label}';
}

/// The factor values (each roughly −2..+2) and what the quips need.
class ReviewFactors {
  final Map<String, double> values;
  final ReviewInputs inputs;
  final double gap;
  final double jump;
  final String bestBench;
  final double bestBenchValue;
  final int repeatStreak;
  final List<String> newOptions;
  final List<String> mishaps;
  const ReviewFactors._(
    this.values,
    this.inputs, {
    required this.gap,
    required this.jump,
    required this.bestBench,
    required this.bestBenchValue,
    required this.repeatStreak,
    required this.newOptions,
    required this.mishaps,
  });

  factory ReviewFactors.of(ReviewInputs i) {
    double c(double v, double lo, double hi) => v.clamp(lo, hi).toDouble();
    final d = i.design;
    final spec = d?.spec ?? const ModelSpec();
    final st = d?.strengths ?? const BenchmarkStrengths();
    final gap = i.topRival == null ? 0.0 : i.rating - i.topRival!.rating;
    final jump = i.rating - i.previousRating;
    final best = st.asMap.entries.reduce((a, b) => b.value > a.value ? b : a);

    // Novelty: the same exact spec as last time (streak), or options this lab
    // has never shipped before.
    var streak = 0;
    for (final p in i.previousSpecs.reversed) {
      if (p != spec) break;
      streak++;
    }
    final seenBefore = i.previousSpecs.contains(spec);
    final newOptions = <String>[
      for (final slot in DesignSlot.values)
        if (slot != DesignSlot.rlStrength &&
            slot.relevant(spec) &&
            !i.previousSpecs.any((p) => slot.of(p) == slot.of(spec)))
          slot.of(spec).label.split(' (').first,
    ];
    final repeatPenalty = streak > 0
        ? math.min(2.5, 1.5 + 0.5 * (streak - 1))
        : seenBefore
        ? 0.5
        : 0.0;
    final novelty = math.min(1.5, 0.7 * newOptions.length) - i.designFreedom * repeatPenalty;

    final mishaps = [
      for (final h in d?.highlights ?? const <String>[])
        if (h.startsWith('Router collapse') || h.startsWith('Bad luck')) h,
    ];
    final stunt = i.stuntId == 'none' ? 0.0 : (i.stuntSucceeded ? 0.8 : -1.5);
    return ReviewFactors._(
      {
        'gap': i.topRival == null ? 0 : c(gap / 40, -2, 1.5),
        'jump': c((jump - 30) / 30, -2, 2),
        'bench': best.value <= 1 ? 0 : c(1.2 * math.log(best.value) / math.ln2, 0, 2),
        'chat': c(2 * (st.chat - 1), -1.5, 1),
        'novelty': novelty,
        'mishap': -1.5 * mishaps.length,
        'open': i.open ? 1.2 : -0.3,
        'serve': d == null ? 0 : c(-0.6 * math.log(d.serveCostMult) / math.ln2, -1.5, 1.2),
        'stunt': stunt,
      },
      i,
      gap: gap,
      jump: jump,
      bestBench: best.key,
      bestBenchValue: best.value,
      repeatStreak: streak,
      newOptions: newOptions,
      mishaps: mishaps,
    );
  }

  double operator [](String k) => values[k] ?? 0;
}

/// Deterministic 32-bit xorshift (web-safe: only 32-bit ops).
class _Rng {
  int _x;
  _Rng(int seed) : _x = (seed & 0x7fffffff) | 1;
  double next() {
    _x ^= (_x << 13) & 0xffffffff;
    _x ^= _x >> 17;
    _x ^= (_x << 5) & 0xffffffff;
    _x &= 0xffffffff;
    return (_x & 0xffffff) / 0x1000000;
  }
}

/// Scores [i] with every outlet.
LaunchReview scoreLaunch(ReviewInputs i, {double buzzSeconds = 0}) {
  final f = ReviewFactors.of(i);
  final rng = _Rng(i.seed);
  // Warm up so close seeds diverge.
  for (var k = 0; k < 4; k++) {
    rng.next();
  }
  final reviews = <Review>[];
  for (final o in reviewOutlets) {
    var raw = reviewBaseScore;
    String? top;
    var topMag = 0.0;
    for (final MapEntry(:key, :value) in o.weights.entries) {
      final contrib = value * f[key];
      raw += contrib;
      if (contrib.abs() > topMag) {
        topMag = contrib.abs();
        top = key;
      }
    }
    raw += (rng.next() * 2 - 1) * reviewNoise;
    final score = raw.round().clamp(1, 10);
    final quip = topMag < 0.35 ? _neutralQuip(o.id) : _quip(o.id, top!, f, i);
    reviews.add(Review(o.id, score, quip));
  }
  final avg = reviews.fold(0.0, (a, r) => a + r.score) / reviews.length;
  return LaunchReview(reviews: reviews, buzz: buzzForAverage(avg), buzzSeconds: buzzSeconds);
}

String _neutralQuip(String outlet) => switch (outlet) {
  'arena' => 'Mid-table on the leaderboard. Respectable.',
  'bench' => 'Solid numbers, no surprises.',
  'vibes' => 'Nobody asked, nobody noticed.',
  _ => '42 points, 17 comments. Mostly about the name.',
};

String _quip(String outlet, String factor, ReviewFactors f, ReviewInputs i) {
  final v = f[factor];
  final up = v >= 0;
  final rival = i.topRival?.model ?? 'the field';
  final gap = f.gap.abs().round();
  final jump = f.jump.abs().round();
  final bench = f.bestBench;
  final spec = i.design?.spec ?? const ModelSpec();
  final fresh = f.newOptions.isEmpty ? specNickname(spec) : f.newOptions.first;
  return switch ((outlet, factor, up)) {
    ('arena', 'gap', true) => 'Beats $rival by $gap points. New #1.',
    ('arena', 'gap', false) => 'Still $gap points behind $rival. Voters noticed.',
    ('arena', 'jump', true) => '+$jump Elo over your last model. Big climb.',
    ('arena', 'jump', false) =>
      f.jump < 0 ? 'Voters prefer your previous model. Awkward.' : 'Only +$jump over your last model. Barely moved.',
    ('arena', 'chat', true) => 'Chats beautifully. Users keep voting for it.',
    ('arena', 'chat', false) => 'Chat answers read like compiler errors.',
    ('arena', 'novelty', true) => 'Something new on the board. Votes are pouring in.',
    ('arena', 'novelty', false) => 'Same model, new name? Voters can tell.',
    ('bench', 'bench', _) =>
      f.gap > 0 && i.topRival != null
          ? 'Beats $rival on ${bench.toLowerCase()} (×${f.bestBenchValue.toStringAsFixed(1)}).'
          : '$bench scores are top-tier (×${f.bestBenchValue.toStringAsFixed(1)}).',
    ('bench', 'gap', true) => 'New SOTA on our suite. Pending a contamination check.',
    ('bench', 'gap', false) => 'Trails $rival on most evals by a wide margin.',
    ('bench', 'jump', true) => 'Up across the board vs your last release.',
    ('bench', 'jump', false) => f.jump < 0 ? 'Regressed on half the suite.' : 'Within noise of your last release.',
    ('bench', 'mishap', _) => '${_mishapShort(f)} shows up in every eval.',
    ('vibes', 'novelty', true) => 'First $fresh model from this lab. Timeline is excited.',
    ('vibes', 'novelty', false) => 'Another ${specNickname(spec)} model? Yawn.',
    ('vibes', 'jump', true) => '+$jump rating overnight. Timeline is melting.',
    ('vibes', 'jump', false) => f.jump < 0 ? 'Worse than the last one? Ratio\'d.' : 'A +$jump bump. Scrolled past it.',
    ('vibes', 'stunt', true) => i.stuntId == 'live_demo'
        ? 'The live demo slapped. Clip is everywhere.'
        : 'Everyone is decoding the launch tweet. Peak hype.',
    ('vibes', 'stunt', false) => 'The launch stunt flopped. The clip has 2M views.',
    ('vibes', 'gap', true) => '"$rival is cooked" threads everywhere.',
    ('vibes', 'gap', false) => 'Quote tweets: "cool, but $rival exists".',
    ('nooz', 'open', true) => 'Open weights! Top comment: "runs on my 4090".',
    ('nooz', 'open', false) => 'Closed API, no paper. Flagged.',
    ('nooz', 'serve', true) => 'Cheap to serve. Someone already measured tokens/sec.',
    ('nooz', 'serve', false) => 'Inference costs look brutal. "Who pays for this?"',
    ('nooz', 'novelty', true) => 'Finally trying $fresh. Upvoted.',
    ('nooz', 'novelty', false) => 'Same recipe as last time. "What\'s new here?"',
    ('nooz', 'mishap', _) => 'Long thread on why: ${_mishapShort(f).toLowerCase()}.',
    ('nooz', 'gap', true) => 'Beats $rival. Top comment: "show me the evals".',
    ('nooz', 'gap', false) => 'Top comment: "just use $rival".',
    _ => _neutralQuip(outlet),
  };
}

String _mishapShort(ReviewFactors f) {
  final m = f.mishaps.isEmpty ? 'A training mishap' : f.mishaps.first;
  final cut = m.indexOf(':');
  return cut > 0 ? m.substring(0, cut) : m;
}

extension GameReviews on Game {
  /// Best rival on the leaderboard right now (null if none are out).
  RivalSnapshot? get topReleasedRival {
    RivalSnapshot? top;
    for (var i = 0; i < releasedCount; i++) {
      final r = rivalLadder[i];
      if (top == null || r.rating > top.rating) top = r;
    }
    return top;
  }

  /// 0..1: unlocked design options beyond the garage's handful.
  double get designFreedom {
    final ctx = designContext;
    var extra = 0;
    for (final slot in DesignSlot.values) {
      if (slot == DesignSlot.rlStrength) continue;
      extra += slot.options.where(ctx.isUnlocked).length - 1;
    }
    return ((extra - 2) / 6).clamp(0.0, 1.0);
  }

  /// The reviewers' view of the pending model, released [open] with [stuntId].
  ReviewInputs reviewInputs({required bool open, String stuntId = 'none', bool stuntSucceeded = true}) {
    final rating = pendingRating!;
    return ReviewInputs(
      rating: rating,
      previousRating: this.rating,
      topRival: topReleasedRival,
      design: s.pendingDesign,
      previousSpecs: [for (final r in s.releases) r.design?.spec ?? const ModelSpec()],
      designFreedom: designFreedom,
      open: open,
      stuntId: stuntId,
      stuntSucceeded: stuntSucceeded,
      seed: s.releases.length * 7919 ^ (rating * 10).round() ^ s.rngState,
    );
  }

  /// Reviews for the pending model (called by [Game.release]).
  LaunchReview reviewPending({required bool open, String stuntId = 'none', bool stuntSucceeded = true}) =>
      scoreLaunch(
        reviewInputs(open: open, stuntId: stuntId, stuntSucceeded: stuntSucceeded),
        // Half the era's middle run (30 s in the garage, 90 s later): about
        // as long as a release's hype lasts (hypeHalfLifeSeconds is 40 s).
        buzzSeconds: s.era.runDurations[1] / 2,
      );

  /// Demand multiplier from the current model's launch reviews (fading).
  double get reviewBuzz {
    final m = s.currentModel;
    return m.review?.buzzAt(s.time - m.time) ?? 1;
  }
}
