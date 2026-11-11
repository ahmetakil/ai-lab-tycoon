// Shared number formatting. Idle games live and die by readable big numbers.

String formatNumber(double v, {int decimals = 1}) {
  final a = v.abs();
  const units = [
    (1e15, 'Q'),
    (1e12, 'T'),
    (1e9, 'B'),
    (1e6, 'M'),
    (1e3, 'k'),
  ];
  for (final (scale, suffix) in units) {
    if (a >= scale) return '${(v / scale).toStringAsFixed(decimals)}$suffix';
  }
  if (a > 0 && a < 1) return v.toStringAsPrecision(2); // e.g. 0.034
  return a < 10 && a != a.roundToDouble()
      ? v.toStringAsFixed(1)
      : v.toStringAsFixed(0);
}

String formatMoney(double v) => '\$${formatNumber(v)}';

/// FLOPs in scientific form, e.g. "3.2e21 FLOP".
String formatFlops(double v) => '${v.toStringAsExponential(1)} FLOP';

String formatPower(double kw) =>
    kw >= 1000 ? '${formatNumber(kw / 1000)} MW' : '${formatNumber(kw)} kW';

String formatDuration(double seconds) {
  final s = seconds.round();
  if (s < 60) return '${s}s';
  if (s < 3600) return '${s ~/ 60}m ${(s % 60).toString().padLeft(2, '0')}s';
  return '${s ~/ 3600}h ${((s % 3600) ~/ 60).toString().padLeft(2, '0')}m';
}

String formatPercent(double fraction) => '${(fraction * 100).round()}%';

/// Ratings live around 700–1500; never abbreviate them ("1.1k" reads wrong).
String formatRating(double rating) => rating.round().toString();
