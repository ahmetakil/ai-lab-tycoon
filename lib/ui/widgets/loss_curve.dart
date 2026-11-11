import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme.dart';

/// Deterministic fake-but-plausible training loss: power-law decay toward an
/// irreducible floor, warm-up shoulder, step noise that shrinks over time and
/// the occasional spike. Same [seed] → same curve, so it doesn't jitter.
class LossCurveModel {
  static const samples = 160;
  final List<double> noisy;
  final List<double> smooth;
  final double minY;
  final double maxY;

  LossCurveModel._(this.noisy, this.smooth, this.minY, this.maxY);

  factory LossCurveModel(int seed) {
    final rnd = math.Random(seed);
    final floor = 1.7 + rnd.nextDouble() * 0.4;
    final scale = 2.4 + rnd.nextDouble() * 0.6;
    final k = 25 + rnd.nextDouble() * 20;
    final alpha = 0.5 + rnd.nextDouble() * 0.15;
    final smooth = <double>[];
    final noisy = <double>[];
    var walk = 0.0;
    var spike = 0.0;
    for (var i = 0; i < samples; i++) {
      final x = i / (samples - 1);
      final warm = 1 - math.exp(-x * 60); // short plateau at the start
      final base = floor + scale * math.pow(1 + k * x * warm, -alpha);
      smooth.add(base.toDouble());
      walk = walk * 0.6 + (rnd.nextDouble() - 0.5) * 0.18;
      if (spike > 0.001) {
        spike *= 0.55;
      } else if (x > 0.1 && rnd.nextDouble() < 0.025) {
        spike = 0.2 + rnd.nextDouble() * 0.25;
      }
      final amp = 0.35 + 0.65 * (1 - x);
      noisy.add(base + (walk + (rnd.nextDouble() - 0.5) * 0.08) * amp + spike);
    }
    final all = [...noisy, ...smooth];
    return LossCurveModel._(noisy, smooth, all.reduce(math.min) - 0.1, all.reduce(math.max) + 0.1);
  }

  double lossAt(double progress) => noisy[(progress.clamp(0.0, 1.0) * (samples - 1)).round()];
}

class LossCurve extends StatelessWidget {
  final LossCurveModel model;
  final double progress;
  final bool paused;
  const LossCurve({super.key, required this.model, required this.progress, this.paused = false});

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    child: CustomPaint(
      painter: _LossPainter(model, progress, paused ? AppColors.amber : AppColors.neon),
      size: Size.infinite,
    ),
  );
}

class _LossPainter extends CustomPainter {
  final LossCurveModel m;
  final double progress;
  final Color color;
  _LossPainter(this.m, this.progress, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    const padL = 4.0, padR = 6.0, padT = 6.0, padB = 6.0;
    final w = size.width - padL - padR;
    final h = size.height - padT - padB;
    Offset pt(int i, List<double> ys) {
      final x = padL + w * i / (LossCurveModel.samples - 1);
      final y = padT + h * (1 - (ys[i] - m.minY) / (m.maxY - m.minY));
      return Offset(x, y);
    }

    // Grid.
    final grid =
        Paint()
          ..color = AppColors.border
          ..strokeWidth = 1;
    for (var i = 0; i <= 4; i++) {
      final y = padT + h * i / 4;
      for (var x = padL; x < padL + w; x += 6) {
        canvas.drawLine(Offset(x, y), Offset(x + 2, y), grid);
      }
    }
    for (var i = 1; i < 4; i++) {
      final x = padL + w * i / 4;
      canvas.drawLine(
        Offset(x, padT),
        Offset(x, padT + h),
        grid..color = AppColors.border.withValues(alpha: 0.5),
      );
    }

    // Ghost: the smooth expected curve for the rest of the run.
    final last = (progress.clamp(0.0, 1.0) * (LossCurveModel.samples - 1)).round();
    final ghost = Path()..moveTo(pt(last, m.smooth).dx, pt(last, m.smooth).dy);
    for (var i = last + 1; i < LossCurveModel.samples; i++) {
      final p = pt(i, m.smooth);
      ghost.lineTo(p.dx, p.dy);
    }
    canvas.drawPath(
      ghost,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = AppColors.faint,
    );
    if (last < 1) return;

    // Revealed noisy curve.
    final path = Path()..moveTo(pt(0, m.noisy).dx, pt(0, m.noisy).dy);
    for (var i = 1; i <= last; i++) {
      final p = pt(i, m.noisy);
      path.lineTo(p.dx, p.dy);
    }
    final head = pt(last, m.noisy);
    final fill =
        Path.from(path)
          ..lineTo(head.dx, padT + h)
          ..lineTo(padL, padT + h)
          ..close();
    canvas.drawPath(
      fill,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [color.withValues(alpha: 0.22), color.withValues(alpha: 0)],
        ).createShader(Offset.zero & size),
    );
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..color = color.withValues(alpha: 0.18)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..strokeJoin = StrokeJoin.round
        ..color = color,
    );
    canvas.drawCircle(head, 6, Paint()..color = color.withValues(alpha: 0.25));
    canvas.drawCircle(head, 3, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_LossPainter old) =>
      old.progress != progress || old.m != m || old.color != color;
}
