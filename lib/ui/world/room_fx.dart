// Cheap per-room animation on top of the static room art: the garage's
// flickering bare bulb, screen glow, blinking rack LEDs, steam. One painter
// per room driven by one shared ticker; nothing here rebuilds widgets.
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'world_layout.dart';

class RoomFx extends StatelessWidget {
  final RoomGeo geo;
  final Animation<double> clock; // seconds, wraps every few minutes

  /// Draw the soft light pools under tiles (true) or the bright bits on top.
  final bool under;
  const RoomFx({super.key, required this.geo, required this.clock, required this.under});

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: RepaintBoundary(
      child: CustomPaint(size: geo.size, painter: _FxPainter(geo, clock, under)),
    ),
  );
}

double _hash(int i) {
  final s = math.sin(i * 12.9898 + 78.233) * 43758.5453;
  return s - s.floorToDouble();
}

/// 0..1 brightness of a dodgy bulb: mostly on, with stutters.
double bulbFlicker(double t) {
  final slot = (t * 9).floor();
  final r = _hash(slot);
  if (r < 0.06) return 0.15; // brief dropout
  if (r < 0.14) return 0.6;
  return 0.92 + 0.08 * math.sin(t * 31);
}

class _FxPainter extends CustomPainter {
  final RoomGeo geo;
  final Animation<double> clock;
  final bool under;
  _FxPainter(this.geo, this.clock, this.under) : super(repaint: clock);

  @override
  void paint(Canvas canvas, Size size) {
    final t = clock.value;
    final s = geo.scale;
    for (final (i, l) in geo.art.lights.indexed) {
      final p = geo.svgToLocal(Offset(l.x, l.y));
      final c = Color(l.color);
      switch (l.kind) {
        case 'bulb':
          _bulb(canvas, size, p, c, t, s);
        case 'tube':
          if (under) {
            final f = _hash((t * 4).floor() + 3) < 0.04 ? 0.5 : 1.0;
            _pool(canvas, p + Offset(0, 220 * s), 520 * s, c.withValues(alpha: 0.10 * f), 0.5);
          } else {
            canvas.drawRRect(
              RRect.fromRectAndRadius(
                Rect.fromCenter(center: p, width: 120 * s, height: 10 * s),
                Radius.circular(5 * s),
              ),
              Paint()
                ..color = c
                ..maskFilter = MaskFilter.blur(BlurStyle.solid, 6 * s),
            );
          }
        case 'screen':
          if (!under) {
            final a = 0.22 + 0.08 * math.sin(t * 2.1 + i);
            _glow(canvas, p, 46 * s, c.withValues(alpha: a));
          }
        case 'led':
          if (!under) _led(canvas, p, c, t, i, s);
        case 'window':
          if (!under) {
            _glow(canvas, p, 90 * s, c.withValues(alpha: 0.18 + 0.03 * math.sin(t * 0.7 + i)));
          }
        case 'steam':
          if (!under) _steam(canvas, p, t, i, s);
      }
    }
  }

  void _bulb(Canvas canvas, Size size, Offset p, Color c, double t, double s) {
    final f = bulbFlicker(t);
    if (under) {
      // Warm pool of light on the floor, and the dark corners around it.
      _pool(canvas, p + Offset(0, 260 * s), 520 * s, c.withValues(alpha: 0.20 * f), 0.55);
      return;
    }
    // Swinging slightly on its cord.
    final sway = Offset(math.sin(t * 1.3) * 3 * s, 0);
    final b = p + sway;
    _glow(canvas, b, 70 * s, c.withValues(alpha: 0.35 * f));
    canvas.drawCircle(b, 8 * s, Paint()..color = Color.lerp(const Color(0xFF6B5A3A), c, f)!);
    canvas.drawCircle(
      b + Offset(-2 * s, -2 * s),
      3 * s,
      Paint()..color = Colors.white.withValues(alpha: 0.8 * f),
    );
    // Whole-room dimming when it stutters.
    if (f < 0.7) {
      canvas.drawRect(
        Offset.zero & size,
        Paint()..color = Colors.black.withValues(alpha: (0.7 - f) * 0.35),
      );
    }
  }

  void _pool(Canvas canvas, Offset center, double r, Color c, double squash) {
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.scale(1, squash);
    canvas.drawCircle(
      Offset.zero,
      r,
      Paint()
        ..shader = RadialGradient(
          colors: [c, c.withValues(alpha: 0)],
        ).createShader(Rect.fromCircle(center: Offset.zero, radius: r)),
    );
    canvas.restore();
  }

  void _glow(Canvas canvas, Offset p, double r, Color c) {
    canvas.drawCircle(
      p,
      r,
      Paint()
        ..shader = RadialGradient(
          colors: [c, c.withValues(alpha: 0)],
        ).createShader(Rect.fromCircle(center: p, radius: r)),
    );
  }

  void _led(Canvas canvas, Offset p, Color c, double t, int i, double s) {
    final speed = 0.6 + _hash(i) * 2.4;
    final phase = _hash(i + 99) * 10;
    final on =
        math.sin(t * speed * 3 + phase) > -0.2 || _hash((t * speed * 2).floor() + i * 7) > 0.85;
    if (!on) return;
    canvas.drawCircle(p, 6 * s, Paint()..color = c.withValues(alpha: 0.25));
    canvas.drawCircle(p, 2.6 * s, Paint()..color = c);
  }

  void _steam(Canvas canvas, Offset p, double t, int i, double s) {
    for (var k = 0; k < 4; k++) {
      final life = ((t * 0.25 + k / 4 + _hash(i) * 0.3) % 1.0);
      final c = p + Offset(math.sin(life * 4 + k) * 10 * s, -life * 160 * s);
      canvas.drawCircle(
        c,
        (24 + life * 50) * s,
        Paint()..color = const Color(0xFFDDE6F2).withValues(alpha: 0.16 * (1 - life)),
      );
    }
  }

  @override
  bool shouldRepaint(_FxPainter old) => old.geo != geo || old.under != under;
}
