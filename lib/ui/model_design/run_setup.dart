// Run setup: pick the model design (architecture, attention, context, size vs
// training length, data mix, post-training, RL strength, serving precision)
// as chunky option chips, with a live preview of what the choices do.
import 'package:flutter/material.dart';

import '../../sim/model_design.dart';
import '../theme.dart';
import '../widgets/panel.dart';
import 'benchmark_strip.dart';

/// Widths at or above this show the slots and the preview side by side.
const runSetupWideBreakpoint = 900.0;

class RunSetupPanel extends StatelessWidget {
  final ModelSpec spec;
  final DesignContext ctx;
  final ValueChanged<ModelSpec> onChanged;

  const RunSetupPanel({super.key, required this.spec, required this.ctx, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final effects = evaluate(spec, ctx);
    final slots = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final slot in DesignSlot.values)
          if (slot.relevant(spec)) _SlotPicker(slot: slot, spec: spec, ctx: ctx, onChanged: onChanged),
      ],
    );
    final preview = DesignPreview(spec: spec, effects: effects);
    return LayoutBuilder(
      builder: (context, box) {
        if (box.maxWidth >= runSetupWideBreakpoint) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 3, child: slots),
              const SizedBox(width: 16),
              Expanded(flex: 2, child: preview),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [slots, gap8, preview],
        );
      },
    );
  }
}

class _SlotPicker extends StatelessWidget {
  final DesignSlot slot;
  final ModelSpec spec;
  final DesignContext ctx;
  final ValueChanged<ModelSpec> onChanged;

  const _SlotPicker({required this.slot, required this.spec, required this.ctx, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final selected = slot.of(spec);
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(slot.label.toUpperCase(), style: labelStyle()),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final c in slot.options)
                OptionChip(
                  key: ValueKey('design-${slot.name}-${c.id}'),
                  label: c.label,
                  selected: c == selected,
                  lockReason: ctx.lockReason(c),
                  onTap: () => onChanged(slot.set(spec, c)),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(selected.blurb, style: const TextStyle(color: AppColors.muted, fontSize: 12.5, height: 1.3)),
        ],
      ),
    );
  }
}

/// A chunky selectable chip. Locked chips are dimmed, show why, and ignore taps.
class OptionChip extends StatelessWidget {
  final String label;
  final bool selected;
  final String? lockReason;
  final VoidCallback onTap;

  const OptionChip({super.key, required this.label, required this.selected, required this.onTap, this.lockReason});

  @override
  Widget build(BuildContext context) {
    final locked = lockReason != null;
    final color =
        locked
            ? AppColors.faint
            : selected
            ? AppColors.neon
            : AppColors.text;
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 44, maxWidth: 260),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: locked ? null : onTap,
          child: Ink(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            decoration: BoxDecoration(
              color:
                  selected
                      ? AppColors.neon.withValues(alpha: 0.14)
                      : locked
                      ? AppColors.surface
                      : AppColors.surfaceHi,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: selected ? AppColors.neon : (locked ? AppColors.border : AppColors.borderHi),
                width: selected ? 2 : 1,
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (locked) ...[const Icon(Icons.lock_outline, size: 14, color: AppColors.faint), const SizedBox(width: 5)],
                    if (selected) ...[const Icon(Icons.check_circle, size: 15, color: AppColors.neon), const SizedBox(width: 5)],
                    Flexible(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5, color: color),
                      ),
                    ),
                  ],
                ),
                if (locked)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      lockReason!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11, color: AppColors.faint),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Live preview: predicted rating change, cost and demand multipliers, risks,
/// explanation lines (good/bad) and the benchmark profile.
class DesignPreview extends StatelessWidget {
  final ModelSpec spec;
  final DesignEffects effects;
  const DesignPreview({super.key, required this.spec, required this.effects});

  static String mult(double m) => '×${m.toStringAsFixed(m >= 10 ? 0 : 2)}';

  @override
  Widget build(BuildContext context) {
    final e = effects;
    final dr = e.ratingDelta;
    final ratingColor =
        dr > 0.5
            ? AppColors.neon
            : dr < -0.5
            ? AppColors.red
            : AppColors.muted;
    // Lower is better for costs, higher for demand.
    Color cost(double m) =>
        m < 0.98
            ? AppColors.neon
            : m > 1.02
            ? AppColors.amber
            : AppColors.muted;
    Color gain(double m) =>
        m > 1.02
            ? AppColors.neon
            : m < 0.98
            ? AppColors.red
            : AppColors.muted;
    return Panel(
      accent: ratingColor == AppColors.muted ? null : ratingColor,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          const PanelHeader('Predicted effect', icon: Icons.insights),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _Stat(
                key: const ValueKey('preview-rating'),
                label: 'Rating',
                value: '${dr >= 0 ? '+' : '−'}${dr.abs().toStringAsFixed(1)}',
                color: ratingColor,
              ),
              _Stat(label: 'Training cost', value: mult(e.trainCostMult), color: cost(e.trainCostMult)),
              _Stat(label: 'Serving cost', value: mult(e.serveCostMult), color: cost(e.serveCostMult)),
              _Stat(label: 'Demand', value: mult(e.demandMult), color: gain(e.demandMult)),
            ],
          ),
          if (e.risks.isNotEmpty || e.notes.isNotEmpty) gap12,
          for (final r in e.risks) _NoteLine(text: r.text, ref: r.ref, color: AppColors.amber, icon: Icons.casino_outlined),
          for (final n in e.notes)
            _NoteLine(
              text: n.text,
              ref: n.ref,
              color: switch (n.tone) {
                NoteTone.good => AppColors.neon,
                NoteTone.bad => AppColors.red,
                NoteTone.neutral => AppColors.cyan,
              },
              icon: switch (n.tone) {
                NoteTone.good => Icons.arrow_upward,
                NoteTone.bad => Icons.arrow_downward,
                NoteTone.neutral => Icons.swap_vert,
              },
            ),
          gap12,
          Text('BENCHMARK PROFILE', style: labelStyle()),
          gap8,
          BenchmarkStrip(strengths: e.strengths, headline: strengthHeadline(spec, e.strengths)),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _Stat({super.key, required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 120),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label.toUpperCase(), style: labelStyle(size: 10)),
          const SizedBox(height: 3),
          Text(value, style: numStyle(size: 18, color: color, weight: FontWeight.w700)),
        ],
      ),
    );
  }
}

class _NoteLine extends StatelessWidget {
  final String text;
  final String ref;
  final Color color;
  final IconData icon;
  const _NoteLine({required this.text, required this.ref, required this.color, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(padding: const EdgeInsets.only(top: 2), child: Icon(icon, size: 14, color: color)),
          const SizedBox(width: 6),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(text: text, style: TextStyle(color: color, fontSize: 12.5, height: 1.3)),
                  TextSpan(
                    text: '  $ref',
                    style: const TextStyle(color: AppColors.faint, fontSize: 11, fontStyle: FontStyle.italic),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
