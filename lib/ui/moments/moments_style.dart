// OWNER: ui-moments agent. Shared look for the moments (overlays, cards).
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../sim/content.dart';
import '../game_assets.dart';

const kDisplayFont = 'SpaceGrotesk';
const kMonoFont = 'JetBrainsMono';

/// Fallback neon palette, used next to the theme colours for juicy accents.
abstract final class Neon {
  static const green = Color(0xFF39FF9F);
  static const magenta = Color(0xFFFF3D9A);
  static const cyan = Color(0xFF3DD8FF);
  static const yellow = Color(0xFFFFD23D);
  static const red = Color(0xFFFF4D4D);
  static const ink = Color(0xFF0A0F14);
  static const panel = Color(0xFF111A22);
}

TextStyle display(
  BuildContext context,
  double size, {
  Color? color,
  FontWeight weight = FontWeight.w700,
  double? height,
}) => TextStyle(
  fontFamily: kDisplayFont,
  fontSize: size,
  fontWeight: weight,
  height: height,
  letterSpacing: -0.3,
  color: color ?? Theme.of(context).colorScheme.onSurface,
);

TextStyle mono(BuildContext context, double size, {Color? color, FontWeight weight = FontWeight.w500}) => TextStyle(
  fontFamily: kMonoFont,
  fontSize: size,
  fontWeight: weight,
  color: color ?? Theme.of(context).colorScheme.onSurface,
  fontFeatures: const [FontFeature.tabularFigures()],
);

/// A stable colour per lab name, so monogram fallbacks look intentional.
Color labColor(String lab) {
  const palette = [Neon.green, Neon.magenta, Neon.cyan, Neon.yellow, Color(0xFFB57CFF), Color(0xFFFF8A3D)];
  var h = 0;
  for (final c in lab.codeUnits) {
    h = (h * 31 + c) & 0x7fffffff;
  }
  return palette[h % palette.length];
}

String labInitials(String lab) {
  final words = lab.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
  if (words.isEmpty) return '?';
  if (words.length == 1) return words.first.substring(0, math.min(2, words.first.length)).toUpperCase();
  return (words[0][0] + words[1][0]).toUpperCase();
}

/// Rival logo with a monogram fallback while art is missing.
class RivalLogo extends StatelessWidget {
  final String lab;
  final double size;
  final bool dimmed;
  const RivalLogo(this.lab, {super.key, this.size = 48, this.dimmed = false});

  @override
  Widget build(BuildContext context) {
    final color = labColor(lab);
    final fallback = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(colors: [color.withValues(alpha: 0.35), color.withValues(alpha: 0.08)]),
        border: Border.all(color: color, width: math.max(1.5, size / 28)),
        boxShadow: [BoxShadow(color: color.withValues(alpha: 0.35), blurRadius: size / 4)],
      ),
      alignment: Alignment.center,
      child: Text(
        labInitials(lab),
        style: TextStyle(fontFamily: kDisplayFont, fontWeight: FontWeight.w800, fontSize: size * 0.38, color: color),
      ),
    );
    final img = SizedBox(
      width: size,
      height: size,
      child: Image.asset(GameArt.rivalLogo(lab), fit: BoxFit.contain, errorBuilder: (_, __, ___) => fallback),
    );
    if (!dimmed) return img;
    return Opacity(opacity: 0.45, child: ColorFiltered(colorFilter: _greyscale, child: img));
  }
}

const _greyscale = ColorFilter.matrix(<double>[
  0.2126, 0.7152, 0.0722, 0, 0, //
  0.2126, 0.7152, 0.0722, 0, 0, //
  0.2126, 0.7152, 0.0722, 0, 0, //
  0, 0, 0, 1, 0,
]);

/// Full-bleed era background with a gradient fallback.
class EraBackdrop extends StatelessWidget {
  final Era era;
  const EraBackdrop(this.era, {super.key});

  static const _colors = <Era, List<Color>>{
    Era.garage: [Color(0xFF1B1209), Color(0xFF3A2410), Color(0xFF0A0F14)],
    Era.startup: [Color(0xFF071A24), Color(0xFF0E3B4A), Color(0xFF0A0F14)],
    Era.smallLab: [Color(0xFF06180F), Color(0xFF0E3A26), Color(0xFF0A0F14)],
    Era.mediumLab: [Color(0xFF070F24), Color(0xFF12265A), Color(0xFF0A0F14)],
    Era.bigLab: [Color(0xFF0D0820), Color(0xFF26124A), Color(0xFF0A0F14)],
    Era.globalLab: [Color(0xFF1A0718), Color(0xFF4A1240), Color(0xFF0A0F14)],
  };

  static List<Color> colorsFor(Era era) =>
      _colors[era] ?? const [Color(0xFF0D0820), Color(0xFF26124A), Color(0xFF0A0F14)];

  @override
  Widget build(BuildContext context) {
    final gradient = DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: colorsFor(era)),
      ),
    );
    return Image.asset(
      GameArt.eraBackground(era),
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
      errorBuilder: (_, __, ___) => gradient,
    );
  }
}

/// What a newly unlocked era brings, for the era overlay.
List<String> unlocksFor(Era era) => [
  for (final r in rooms.where((r) => r.era == era)) r.name,
  for (final t in tiles.where((t) => t.era == era)) t.name,
  for (final p in powerTiers.where((p) => p.era == era)) p.name,
  for (final u in upgrades.where((u) => u.era == era)) u.name,
];
