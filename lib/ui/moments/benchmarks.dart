// OWNER: ui-moments agent.
// Fake-but-honest benchmarks for the release card. Every score is derived
// deterministically from the Arena-style rating, so a bigger rating gap really
// does mean bigger bars. The joke is only in which ones get shown.
import 'dart:math' as math;

class BenchmarkDef {
  final String name;

  /// Rating at which a model scores 50% (difficulty).
  final double midpoint;

  /// Rating points per e-fold of the logistic curve (higher = flatter).
  final double spread;

  /// How noisy the benchmark is (max ± points of jitter).
  final double noise;

  const BenchmarkDef(this.name, this.midpoint, this.spread, this.noise);
}

/// The full pool. The card shows 5 of these, cherry-picked.
const benchmarkPool = <BenchmarkDef>[
  BenchmarkDef('MMLU-ish', 950, 120, 3),
  BenchmarkDef('HumanEval-ish', 1050, 110, 4),
  BenchmarkDef('Vibes', 850, 160, 9),
  BenchmarkDef("Counting r's in strawberry", 1200, 90, 12),
  BenchmarkDef('GSM-ish Math', 1000, 100, 4),
  BenchmarkDef('Pelican on a Bicycle (SVG)', 1100, 130, 10),
  BenchmarkDef('Vending Machine Tycoon', 1150, 120, 8),
  BenchmarkDef('Sounding Confident', 750, 150, 6),
];

class BenchmarkResult {
  final String name;
  final double mine; // 0..100
  final double theirs; // 0..100
  const BenchmarkResult(this.name, this.mine, this.theirs);
  bool get win => mine > theirs;
}

class BenchmarkReport {
  final List<BenchmarkResult> shown;
  final int wins;
  const BenchmarkReport(this.shown, this.wins);
}

/// Deterministic jitter in [-1, 1] from a string and a rounded rating.
double _jitter(String key, double rating) {
  var h = 0x811c9dc5;
  for (final c in '$key|${rating.round()}'.codeUnits) {
    h ^= c;
    h = (h * 0x01000193) & 0xffffffff;
  }
  // Extra avalanche so neighbouring ratings differ.
  h ^= h >> 13;
  h = (h * 0x5bd1e995) & 0xffffffff;
  h ^= h >> 15;
  return (h / 0xffffffff) * 2 - 1;
}

/// Score (0..100) of a model with [rating] on [b].
double benchmarkScore(BenchmarkDef b, double rating) {
  final base = 100 / (1 + math.exp(-(rating - b.midpoint) / b.spread));
  return (base + b.noise * _jitter(b.name, rating)).clamp(1.0, 99.5);
}

/// Score every benchmark in the pool, then cherry-pick 5: all our wins first
/// (largest margin first), topped up with our least embarrassing losses.
/// [wins] counts honestly over what is shown.
BenchmarkReport cherryPickedBenchmarks(double myRating, double rivalRating, {int count = 5}) {
  final all = [
    for (final b in benchmarkPool) BenchmarkResult(b.name, benchmarkScore(b, myRating), benchmarkScore(b, rivalRating)),
  ];
  all.sort((a, b) => (b.mine - b.theirs).compareTo(a.mine - a.theirs));
  final shown = all.take(count).toList();
  return BenchmarkReport(shown, shown.where((r) => r.win).length);
}
