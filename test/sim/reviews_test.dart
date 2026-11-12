import 'dart:convert';
import 'dart:math' as math;

import 'package:ai_lab_tycoon/sim/balance.dart';
import 'package:ai_lab_tycoon/sim/bot.dart';
import 'package:ai_lab_tycoon/sim/content.dart';
import 'package:ai_lab_tycoon/sim/game.dart';
import 'package:ai_lab_tycoon/sim/game_state.dart';
import 'package:ai_lab_tycoon/sim/model_design.dart';
import 'package:ai_lab_tycoon/sim/reviews.dart';
import 'package:flutter_test/flutter_test.dart';

const _spec = ModelSpec(architecture: Architecture.moe, context: ContextLength.k8, dataMix: DataMix.webCode);

DesignOutcome _design(ModelSpec spec, {List<String> notes = const []}) => DesignOutcome(
  spec: spec,
  ratingAdd: 0,
  serveCostMult: 1,
  demandMult: 1,
  serveCompute: startEffectiveCompute,
  highlights: notes,
);

ReviewInputs _inputs({
  double rating = 1100,
  double previous = 1060,
  ModelSpec spec = _spec,
  List<ModelSpec> history = const [ModelSpec()],
  List<String> notes = const [],
  int seed = 7,
}) => ReviewInputs(
  rating: rating,
  previousRating: previous,
  topRival: rivalLadder.firstWhere((r) => r.rating > 1100),
  design: _design(spec, notes: notes),
  previousSpecs: history,
  designFreedom: 1,
  seed: seed,
);

/// Average over many seeds, so noise doesn't decide a comparison.
double _meanAvg(ReviewInputs Function(int seed) make) {
  var sum = 0.0;
  for (var s = 1; s <= 200; s++) {
    sum += scoreLaunch(make(s)).average;
  }
  return sum / 200;
}

Game _pending({double mult = 8, ModelSpec spec = const ModelSpec()}) {
  final g = Game();
  g.s.pendingEffectiveCompute = startEffectiveCompute * mult;
  g.s.pendingDesign = _design(spec);
  return g;
}

void main() {
  test('reviews are deterministic and stay in range', () {
    final a = scoreLaunch(_inputs());
    final b = scoreLaunch(_inputs());
    expect(a.toJson(), b.toJson());
    expect(a.reviews.map((r) => r.outletId), reviewOutlets.map((o) => o.id));
    for (final r in a.reviews) {
      expect(r.score, inInclusiveRange(1, 10));
      expect(r.quip, isNotEmpty);
    }
    // Same state, same release → same reviews (and the game RNG is untouched).
    final g1 = _pending(), g2 = _pending();
    final rng = g1.s.rngState;
    final r1 = g1.reviewPending(open: false);
    expect(g1.s.rngState, rng);
    expect(r1.toJson(), g2.reviewPending(open: false).toJson());
  });

  test('repeating the exact same design scores lower (GDT combo penalty)', () {
    final fresh = _meanAvg((s) => _inputs(seed: s));
    final again = _meanAvg((s) => _inputs(seed: s, history: const [ModelSpec(), _spec]));
    final thrice = _meanAvg((s) => _inputs(seed: s, history: const [ModelSpec(), _spec, _spec]));
    expect(again, lessThan(fresh - 0.4));
    expect(thrice, lessThan(again));
    final yawn = scoreLaunch(_inputs(history: const [ModelSpec(), _spec, _spec]));
    expect(yawn.reviews.firstWhere((r) => r.outletId == 'vibes').quip, contains('Yawn'));
    // Without design freedom (the garage) repeats aren't punished.
    final garage = ReviewFactors.of(ReviewInputs(
      rating: 900,
      previousRating: 880,
      previousSpecs: const [ModelSpec(), ModelSpec()],
      designFreedom: 0,
    ));
    expect(garage['novelty'], 0);
  });

  test('better models score higher', () {
    final weak = _meanAvg((s) => _inputs(seed: s, rating: 1070, previous: 1060));
    final strong = _meanAvg((s) => _inputs(seed: s, rating: 1200, previous: 1060));
    expect(strong, greaterThan(weak + 1));
    // Through the game: more compute → higher average and more buzz.
    final small = _pending(mult: 2).reviewPending(open: false);
    final big = _pending(mult: 64).reviewPending(open: false);
    expect(big.average, greaterThan(small.average));
    expect(big.buzz, greaterThan(small.buzz));
    // A mishap costs points and the quip says why.
    final hit = scoreLaunch(_inputs(notes: const ['Router collapse: most tokens went to a few experts']));
    expect(hit.reviews.firstWhere((r) => r.outletId == 'bench').quip, contains('Router collapse'));
    final mishapMean = _meanAvg((s) => _inputs(seed: s, notes: const ['Router collapse: x']));
    expect(mishapMean, lessThan(_meanAvg((s) => _inputs(seed: s))));
  });

  test('quips explain the score', () {
    final beat = scoreLaunch(_inputs(rating: 1600, previous: 1400));
    final rival = rivalLadder.firstWhere((r) => r.rating > 1100).model;
    expect(beat.reviews.first.quip, contains(rival));
    expect(beat.verdict, isNotEmpty);
  });

  test('buzz maps the average onto ×0.8..×1.5 and fades out', () {
    expect(buzzForAverage(reviewPivot), closeTo(1, 1e-9));
    expect(buzzForAverage(10), closeTo(maxReviewBuzz, 1e-9));
    expect(buzzForAverage(1), closeTo(minReviewBuzz, 1e-9));
    const r = LaunchReview(reviews: [Review('arena', 9, 'x')], buzz: 1.4, buzzSeconds: 100);
    expect(r.buzzAt(0), closeTo(1.4, 1e-9));
    expect(r.buzzAt(50), closeTo(1.2, 1e-9));
    expect(r.buzzAt(100), 1);
  });

  test('release() saves the review; it drives demand; old saves still load', () {
    final g = _pending(mult: 64);
    g.release(open: false);
    final m = g.s.currentModel;
    final review = m.review!;
    expect(review.reviews, hasLength(4));
    expect(g.reviewBuzz, closeTo(review.buzz, 1e-9));
    final withBuzz = g.demand;
    g.s.releases.last = ModelRelease(
      name: m.name,
      effectiveCompute: m.effectiveCompute,
      rating: m.rating,
      open: m.open,
      time: m.time,
      design: m.design,
    );
    expect(withBuzz / g.demand, closeTo(review.buzz, 1e-6));
    g.s.releases.last = m;

    final json = jsonDecode(jsonEncode(g.s.toJson())) as Map<String, dynamic>;
    final loaded = GameState.fromJson(json);
    expect(loaded.currentModel.review!.toJson(), review.toJson());

    // A release saved before reviews loads with none (buzz ×1).
    (json['releases'] as List).cast<Map<String, dynamic>>().last.remove('review');
    final old = Game(GameState.fromJson(json));
    expect(old.s.currentModel.review, isNull);
    expect(old.reviewBuzz, 1);
  });

  test('sentiment is neutral-ish over bot playthroughs', () {
    final logs = <double>[];
    void onEvent(Game g, GameEvent e) {
      if (e is ModelReleased) logs.add(math.log(e.release.review!.buzz));
    }

    for (final seed in [12345, 777]) {
      runPlaythrough(maxSeconds: 4 * 3600, seed: seed, onEvent: onEvent);
    }
    // The casual schedule plays the whole ladder, frontier included.
    runSchedule(onEvent: (g, e, _) => onEvent(g, e));
    expect(logs.length, greaterThan(35));
    final geoMean = math.exp(logs.reduce((a, b) => a + b) / logs.length);
    expect(geoMean, inInclusiveRange(0.95, 1.06));
    // ...but not flat: some launches land, some flop.
    expect(logs.reduce(math.max), greaterThan(math.log(1.08)));
    expect(logs.reduce(math.min), lessThan(math.log(0.96)));
  });
}
