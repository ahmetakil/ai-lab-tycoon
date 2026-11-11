// OWNER: ui-moments agent. Confetti + spark burst, no packages.
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'moments_style.dart';

class _Particle {
  final double angle, speed, spin, size, drift, delay;
  final Color color;
  final int shape; // 0 rect, 1 circle, 2 streamer
  _Particle(math.Random r, List<Color> colors)
    : angle = -math.pi / 2 + (r.nextDouble() - 0.5) * math.pi * 1.4,
      speed = 0.55 + r.nextDouble() * 0.9,
      spin = (r.nextDouble() - 0.5) * 18,
      size = 5 + r.nextDouble() * 9,
      drift = (r.nextDouble() - 0.5) * 0.25,
      delay = r.nextDouble() * 0.15,
      color = colors[r.nextInt(colors.length)],
      shape = r.nextInt(3);
}

/// A looping-free confetti burst driven by [progress] 0..1.
class ConfettiPainter extends CustomPainter {
  final double progress;
  final List<_Particle> _particles;
  final Offset origin; // fraction of size

  ConfettiPainter({
    required this.progress,
    int count = 140,
    int seed = 7,
    this.origin = const Offset(0.5, 0.42),
    List<Color> colors = const [Neon.green, Neon.magenta, Neon.cyan, Neon.yellow, Colors.white],
  }) : _particles = List.generate(count, (_) => _Particle(math.Random(seed++), colors));

  @override
  void paint(Canvas canvas, Size size) {
    final o = Offset(size.width * origin.dx, size.height * origin.dy);
    final scale = math.max(size.width, size.height);
    final paint = Paint();

    // Shockwave ring.
    if (progress < 0.35) {
      final t = progress / 0.35;
      paint
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6 * (1 - t)
        ..color = Neon.green.withValues(alpha: (1 - t) * 0.8);
      canvas.drawCircle(o, scale * 0.45 * Curves.easeOut.transform(t), paint);
    }
    paint.style = PaintingStyle.fill;

    for (final p in _particles) {
      final t = ((progress - p.delay) / (1 - p.delay)).clamp(0.0, 1.0);
      if (t <= 0) continue;
      final time = t * 2.6; // seconds-ish in normalized space
      final v = p.speed * scale * 0.9;
      final x = o.dx + math.cos(p.angle) * v * time * 0.55 + p.drift * scale * time;
      final y = o.dy + math.sin(p.angle) * v * time * 0.55 + 0.5 * scale * 0.55 * time * time;
      final alpha = t < 0.75 ? 1.0 : (1 - (t - 0.75) / 0.25);
      paint.color = p.color.withValues(alpha: alpha.clamp(0.0, 1.0));
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(p.spin * time);
      switch (p.shape) {
        case 0:
          // Fake 3D flutter by squashing one axis.
          final squash = math.cos(p.spin * time * 1.7).abs() * 0.8 + 0.2;
          canvas.drawRect(Rect.fromCenter(center: Offset.zero, width: p.size, height: p.size * 0.6 * squash), paint);
        case 1:
          canvas.drawCircle(Offset.zero, p.size * 0.32, paint);
        default:
          canvas.drawRRect(
            RRect.fromRectAndRadius(
              Rect.fromCenter(center: Offset.zero, width: p.size * 0.35, height: p.size * 1.6),
              const Radius.circular(2),
            ),
            paint,
          );
      }
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(ConfettiPainter old) => old.progress != progress;
}

/// Self-running confetti burst. Ignores pointer events.
class ConfettiBurst extends StatefulWidget {
  final Duration duration;
  final int seed;
  final List<Color>? colors;
  const ConfettiBurst({super.key, this.duration = const Duration(milliseconds: 3200), this.seed = 7, this.colors});

  @override
  State<ConfettiBurst> createState() => _ConfettiBurstState();
}

class _ConfettiBurstState extends State<ConfettiBurst> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: widget.duration)..forward();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _c,
        builder:
            (_, __) => CustomPaint(
              size: Size.infinite,
              painter:
                  widget.colors == null
                      ? ConfettiPainter(progress: _c.value, seed: widget.seed)
                      : ConfettiPainter(progress: _c.value, seed: widget.seed, colors: widget.colors!),
            ),
      ),
    );
  }
}
