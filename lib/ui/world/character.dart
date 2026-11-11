// "You": a tiny procedural founder at the desk. Three states, animated in
// code on the shared world clock: typing while a run trains, cheering after
// a release or a rival falls, otherwise an idle bob.
import 'dart:math' as math;

import 'package:flutter/material.dart';

enum FounderMood { idle, typing, cheering }

class Founder extends StatelessWidget {
  final FounderMood mood;
  final Animation<double> clock;
  final double scale; // world units per SVG unit of the room
  const Founder({super.key, required this.mood, required this.clock, required this.scale});

  static const box = Size(90, 130); // SVG units

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: RepaintBoundary(
      child: CustomPaint(
        size: Size(box.width * scale, box.height * scale),
        painter: _FounderPainter(mood, clock, scale),
      ),
    ),
  );
}

class _FounderPainter extends CustomPainter {
  final FounderMood mood;
  final Animation<double> clock;
  final double k;
  _FounderPainter(this.mood, this.clock, this.k) : super(repaint: clock);

  static const _ink = Color(0xFF0B0F1C);
  static const _hoodie = Color(0xFF2F7D5B);
  static const _hoodieDark = Color(0xFF225A43);
  static const _skin = Color(0xFFE8B98F);
  static const _hair = Color(0xFF3A2618);
  static const _jeans = Color(0xFF34466E);

  @override
  void paint(Canvas canvas, Size size) {
    final t = clock.value;
    canvas.save();
    // Anchor: seat point is the bottom-centre of the box.
    canvas.translate(size.width / 2, size.height);
    canvas.scale(k);
    final ink =
        Paint()
          ..color = _ink
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.4
          ..strokeJoin = StrokeJoin.round
          ..strokeCap = StrokeCap.round;

    void blob(Path p, Color c) {
      canvas.drawPath(p, Paint()..color = c);
      canvas.drawPath(p, ink);
    }

    void limb(Offset a, Offset b, Color c, double w) {
      canvas.drawLine(
        a,
        b,
        Paint()
          ..color = _ink
          ..strokeWidth = w + 3
          ..strokeCap = StrokeCap.round,
      );
      canvas.drawLine(
        a,
        b,
        Paint()
          ..color = c
          ..strokeWidth = w
          ..strokeCap = StrokeCap.round,
      );
    }

    final cheering = mood == FounderMood.cheering;
    final typing = mood == FounderMood.typing;
    // Body motion.
    final bob =
        cheering
            ? -(math.sin(t * 9).abs()) * 22 - 16
            : typing
            ? math.sin(t * 14) * 1.2
            : math.sin(t * 2.2) * 2.2;
    canvas.translate(0, bob);

    // Seat/legs (sitting unless cheering).
    if (cheering) {
      limb(const Offset(-8, -38), const Offset(-12, 0), _jeans, 9);
      limb(const Offset(8, -38), const Offset(12, 0), _jeans, 9);
    } else {
      limb(const Offset(-8, -30), const Offset(-22, -24), _jeans, 10);
      limb(const Offset(8, -30), const Offset(-2, -22), _jeans, 10);
    }
    final hip = cheering ? -40.0 : -30.0;
    // Torso (hoodie), seen from behind-left.
    final torso =
        Path()
          ..moveTo(-17, hip)
          ..quadraticBezierTo(-21, hip - 30, -12, hip - 44)
          ..lineTo(12, hip - 44)
          ..quadraticBezierTo(21, hip - 30, 17, hip)
          ..close();
    blob(torso, _hoodie);
    canvas.drawLine(
      Offset(0, hip - 40),
      Offset(0, hip - 6),
      Paint()
        ..color = _hoodieDark
        ..strokeWidth = 2,
    );
    final shoulderL = Offset(-13, hip - 38), shoulderR = Offset(13, hip - 38);

    // Arms.
    if (cheering) {
      final wave = math.sin(t * 12) * 8;
      limb(shoulderL, Offset(-26 + wave * 0.3, hip - 72 + wave), _hoodie, 8);
      limb(shoulderR, Offset(26 - wave * 0.3, hip - 72 - wave), _hoodie, 8);
      canvas.drawCircle(Offset(-26 + wave * 0.3, hip - 74 + wave), 4.5, Paint()..color = _skin);
      canvas.drawCircle(Offset(26 - wave * 0.3, hip - 74 - wave), 4.5, Paint()..color = _skin);
    } else if (typing) {
      final a = math.sin(t * 22) * 3, b = math.sin(t * 22 + 2.4) * 3;
      limb(shoulderL, Offset(-10, hip - 22 + a), _hoodie, 8);
      limb(shoulderR, Offset(18, hip - 26 + b), _hoodie, 8);
    } else {
      final sip = math.sin(t * 0.8) > 0.85;
      limb(shoulderL, const Offset(-16, -36), _hoodie, 8);
      limb(shoulderR, sip ? Offset(10, hip - 50) : const Offset(16, -34), _hoodie, 8);
      if (sip) {
        canvas.drawRect(
          Rect.fromCenter(center: Offset(10, hip - 54), width: 8, height: 10),
          Paint()..color = const Color(0xFFB4362F),
        );
      }
    }

    // Head: back of the head mostly, a bit of cheek, messy hair.
    final head = Offset(cheering ? 0 : 2, hip - 58 + (typing ? math.sin(t * 7) * 0.8 : 0));
    canvas.drawCircle(head, 14, Paint()..color = _skin);
    canvas.drawCircle(head, 14, ink);
    final hair =
        Path()
          ..moveTo(head.dx - 14, head.dy + 2)
          ..quadraticBezierTo(head.dx - 16, head.dy - 16, head.dx, head.dy - 16)
          ..quadraticBezierTo(head.dx + 16, head.dy - 16, head.dx + 13, head.dy + 4)
          ..quadraticBezierTo(head.dx + 6, head.dy - 2, head.dx + 1, head.dy + 6)
          ..quadraticBezierTo(head.dx - 6, head.dy - 2, head.dx - 14, head.dy + 2)
          ..close();
    blob(hair, _hair);
    // Headphones.
    canvas.drawArc(
      Rect.fromCircle(center: head, radius: 16),
      math.pi * 1.05,
      math.pi * 0.9,
      false,
      Paint()
        ..color = const Color(0xFF1A1E28)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4,
    );
    canvas.drawCircle(head + const Offset(-15, 2), 5, Paint()..color = const Color(0xFF39FF9F));

    if (cheering) {
      // Little burst of joy.
      for (var i = 0; i < 5; i++) {
        final a = i * 2 * math.pi / 5 + t * 2;
        final r = 34 + math.sin(t * 6 + i) * 4;
        canvas.drawCircle(
          head + Offset(math.cos(a) * r, math.sin(a) * r * 0.7 - 10),
          3,
          Paint()
            ..color =
                [const Color(0xFFFFD447), const Color(0xFF39FF9F), const Color(0xFF3DD6FF)][i % 3],
        );
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_FounderPainter old) => old.mood != mood || old.k != k;
}
