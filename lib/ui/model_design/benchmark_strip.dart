// Benchmark profile of a designed model (coding, math, chat, long context),
// for the release card and the run-setup preview.
import 'package:flutter/material.dart';

import '../../sim/model_design.dart';
import '../../sim/run_phases.dart';
import '../theme.dart';
import 'run_phases_ui.dart' show phaseColor;

class BenchmarkStrip extends StatelessWidget {
  final BenchmarkStrengths strengths;

  /// Optional one-liner on top, e.g. strengthHeadline(spec, strengths).
  final String? headline;

  /// Strength that fills a bar completely.
  final double fullScale;

  /// The run's phase decisions, listed under the bars ("Annealed on math &
  /// code: math ×1.2").
  final List<PhaseOption> phases;

  const BenchmarkStrip({super.key, required this.strengths, this.headline, this.fullScale = 3, this.phases = const []});

  static Color colorFor(double v) =>
      v >= 1.15
          ? AppColors.neon
          : v <= 0.85
          ? AppColors.red
          : AppColors.cyan;

  @override
  Widget build(BuildContext context) {
    final entries = strengths.asMap.entries.toList();
    final best = entries.reduce((a, b) => b.value > a.value ? b : a).key;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (headline != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                const Icon(Icons.emoji_events_outlined, size: 16, color: AppColors.amber),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    headline!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: AppColors.text),
                  ),
                ),
              ],
            ),
          ),
        for (final e in entries)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: _Bar(
              key: ValueKey('bench-${e.key}'),
              label: e.key,
              value: e.value,
              fraction: (e.value / fullScale).clamp(0.03, 1.0),
              highlight: e.key == best && e.value >= 1.15,
            ),
          ),
        if (phases.isNotEmpty) ...[
          const SizedBox(height: 6),
          for (final p in phases)
            Padding(
              key: ValueKey('phase-line-${p.name}'),
              padding: const EdgeInsets.only(top: 2),
              child: Row(
                children: [
                  Icon(Icons.flag_circle_rounded, size: 12, color: phaseColor(p.phase)),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(
                      p.summary,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11.5, color: AppColors.muted),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ],
    );
  }
}

class _Bar extends StatelessWidget {
  final String label;
  final double value;
  final double fraction;
  final bool highlight;
  const _Bar({super.key, required this.label, required this.value, required this.fraction, required this.highlight});

  @override
  Widget build(BuildContext context) {
    final color = BenchmarkStrip.colorFor(value);
    return Row(
      children: [
        SizedBox(
          width: 92,
          child: Text(
            label.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: labelStyle(size: 10, color: highlight ? AppColors.amber : AppColors.muted),
          ),
        ),
        Expanded(
          child: Container(
            height: 10,
            decoration: BoxDecoration(color: AppColors.surfaceHi, borderRadius: BorderRadius.circular(99)),
            alignment: Alignment.centerLeft,
            child: FractionallySizedBox(
              widthFactor: fraction,
              child: Container(
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(99),
                  boxShadow: [if (highlight) BoxShadow(color: color.withValues(alpha: 0.5), blurRadius: 8)],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 44,
          child: Text(
            '×${value.toStringAsFixed(1)}',
            textAlign: TextAlign.right,
            maxLines: 1,
            style: numStyle(size: 12, color: color),
          ),
        ),
      ],
    );
  }
}
