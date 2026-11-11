import 'package:ai_lab_tycoon/ui/moments/benchmarks.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('benchmarks are deterministic', () {
    final a = cherryPickedBenchmarks(912, 920);
    final b = cherryPickedBenchmarks(912, 920);
    expect(
      a.shown.map((r) => (r.name, r.mine, r.theirs)).toList(),
      b.shown.map((r) => (r.name, r.mine, r.theirs)).toList(),
    );
    expect(a.wins, b.wins);
  });

  test('shows 5 distinct benchmarks from the pool with sane scores', () {
    final r = cherryPickedBenchmarks(1000, 1100);
    expect(r.shown, hasLength(5));
    expect(r.shown.map((e) => e.name).toSet(), hasLength(5));
    for (final e in r.shown) {
      expect(e.mine, inInclusiveRange(1, 99.5));
      expect(e.theirs, inInclusiveRange(1, 99.5));
    }
  });

  test('wins are counted honestly and follow the rating gap', () {
    final crushing = cherryPickedBenchmarks(1300, 900);
    final crushed = cherryPickedBenchmarks(900, 1300);
    expect(crushing.wins, 5);
    expect(crushed.wins, 0);
    final even = cherryPickedBenchmarks(1000, 1000);
    expect(even.wins, 0, reason: 'identical ratings score identically');
    for (final r in [crushing, crushed, even]) {
      expect(r.wins, r.shown.where((e) => e.mine > e.theirs).length);
    }
  });

  test('cherry-picking: wins are shown first', () {
    final r = cherryPickedBenchmarks(1040, 1050);
    final firstLoss = r.shown.indexWhere((e) => !e.win);
    if (firstLoss >= 0) {
      expect(r.shown.skip(firstLoss).every((e) => !e.win), isTrue);
    }
  });

  test('higher rating never scores lower on the noise-free curve', () {
    for (final b in benchmarkPool) {
      final lo = benchmarkScore(b, 800);
      final hi = benchmarkScore(b, 1400);
      expect(hi, greaterThan(lo), reason: b.name);
    }
  });
}
