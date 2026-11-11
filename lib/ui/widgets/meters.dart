import 'package:flutter/material.dart';

import '../theme.dart';

/// Animated horizontal meter with a glowing fill.
class MeterBar extends StatelessWidget {
  final double value; // 0..1
  final Color color;
  final double height;
  final Duration duration;

  const MeterBar({
    super.key,
    required this.value,
    this.color = AppColors.neon,
    this.height = 8,
    this.duration = const Duration(milliseconds: 350),
  });

  @override
  Widget build(BuildContext context) {
    final v = value.isFinite ? value.clamp(0.0, 1.0) : 0.0;
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: AppColors.bg,
        borderRadius: BorderRadius.circular(height),
        border: Border.all(color: AppColors.border),
      ),
      child: TweenAnimationBuilder<double>(
        tween: Tween(end: v),
        duration: duration,
        curve: Curves.easeOutCubic,
        builder:
            (context, t, _) => FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: t,
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(height),
                  gradient: LinearGradient(colors: [color.withValues(alpha: 0.65), color]),
                  boxShadow: [BoxShadow(color: color.withValues(alpha: 0.45), blurRadius: 8)],
                ),
              ),
            ),
      ),
    );
  }
}

class SplitSegment {
  final String label;
  final double value;
  final Color color;
  const SplitSegment(this.label, this.value, this.color);
}

/// Stacked bar showing shares of a whole (e.g. training vs serving compute).
class SplitBar extends StatelessWidget {
  final List<SplitSegment> segments;
  final double height;
  const SplitBar({super.key, required this.segments, this.height = 14});

  @override
  Widget build(BuildContext context) {
    final total = segments.fold(0.0, (a, s) => a + s.value);
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: AppColors.bg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: LayoutBuilder(
        builder:
            (context, box) => Row(
              children: [
                for (final s in segments)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 400),
                    curve: Curves.easeOutCubic,
                    width: total <= 0 ? 0 : box.maxWidth * s.value / total,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [s.color, s.color.withValues(alpha: 0.7)],
                      ),
                      border: const Border(right: BorderSide(color: AppColors.bg, width: 1.5)),
                    ),
                  ),
              ],
            ),
      ),
    );
  }
}

/// Coloured dot + label + value, used under split bars.
class LegendItem extends StatelessWidget {
  final Color color;
  final String label;
  final String value;
  const LegendItem({super.key, required this.color, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            boxShadow: [BoxShadow(color: color.withValues(alpha: 0.6), blurRadius: 6)],
          ),
        ),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(fontSize: 12, color: AppColors.muted)),
        const SizedBox(width: 5),
        Text(value, style: numStyle(size: 12, color: AppColors.text)),
      ],
    );
  }
}
