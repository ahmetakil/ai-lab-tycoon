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
          Row(
            children: [
              Flexible(child: Text(slot.label.toUpperCase(), style: labelStyle())),
              const SizedBox(width: 6),
              HelpDot(
                key: ValueKey('design-help-${slot.name}'),
                title: slot.label,
                body: slotHelp[slot] ?? '',
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final c in slot.options)
                OptionChip(
                  key: ValueKey('design-${slot.name}-${c.id}'),
                  label: c.label,
                  blurb: c.blurb,
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
  final String? blurb;
  final bool selected;
  final String? lockReason;
  final VoidCallback onTap;

  const OptionChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.lockReason,
    this.blurb,
  });

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
      constraints: const BoxConstraints(minHeight: 40, maxWidth: 260),
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
                    if (blurb != null || locked) ...[
                      const SizedBox(width: 6),
                      HelpDot(
                        title: label,
                        body: blurb ?? '',
                        footer: lockReason,
                      ),
                    ],
                  ],
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
          const PanelHeader('Effect of these choices', icon: Icons.insights),
          const Text(
            'Compared with a plain model trained on the same compute. '
            'It is already included in the predicted rating below.',
            style: TextStyle(color: AppColors.muted, fontSize: 12, height: 1.3),
          ),
          gap12,
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _Stat(
                key: const ValueKey('preview-rating'),
                label: 'Design rating',
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

/// What each run-setup slot means, in one or two plain sentences.
const slotHelp = <DesignSlot, String>{
  DesignSlot.architecture:
      'How the network is wired. Dense uses every weight for every token. '
      'Mixture of Experts routes each token to a few expert blocks: more '
      'quality per FLOP, but experts talk across GPUs, so it wants a fast network.',
  DesignSlot.attention:
      'How tokens look at each other. Full attention keeps keys and values '
      'for every head; cheaper variants share or limit them so serving uses '
      'less memory, at a small quality cost.',
  DesignSlot.context:
      'How much text the model can read at once. Longer context attracts more '
      'users but costs training compute and memory per user when serving.',
  DesignSlot.sizing:
      'Split a fixed compute budget between model size and training tokens. '
      'Chinchilla found ~20 tokens per parameter is compute-optimal; smaller, '
      'longer-trained models cost less to serve.',
  DesignSlot.dataMix:
      'What the model reads. Code-heavy mixes win coding benchmarks, books and '
      'papers help reasoning, and synthetic data stretches a limited supply.',
  DesignSlot.postTraining:
      'Training after pre-training that turns a text predictor into an '
      'assistant: supervised examples (SFT), human preferences (RLHF, DPO) or '
      'reinforcement learning on checkable answers (reasoning).',
  DesignSlot.rlStrength:
      'How hard to push RL. A little helps a lot; too much over-optimises the '
      'reward and quality falls off.',
  DesignSlot.quantization:
      'Number format used when serving. Fewer bits per weight means less '
      'memory and faster serving, with a small quality loss.',
};

/// A small "?" that explains something. Hover on web/desktop, tap on touch.
class HelpDot extends StatelessWidget {
  final String title;
  final String body;
  final String? footer;
  const HelpDot({super.key, required this.title, required this.body, this.footer});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      triggerMode: TooltipTriggerMode.tap,
      showDuration: const Duration(seconds: 8),
      waitDuration: const Duration(milliseconds: 150),
      preferBelow: false,
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.symmetric(horizontal: 24),
      decoration: BoxDecoration(
        color: AppColors.surfaceHi,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.borderHi),
      ),
      richMessage: TextSpan(
        children: [
          TextSpan(
            text: '$title\n',
            style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.text, fontSize: 13),
          ),
          if (body.isNotEmpty)
            TextSpan(text: body, style: const TextStyle(color: AppColors.muted, fontSize: 12.5, height: 1.35)),
          if (footer != null)
            TextSpan(
              text: '\n\n🔒 $footer',
              style: const TextStyle(color: AppColors.amber, fontSize: 12, height: 1.35),
            ),
        ],
      ),
      child: Container(
        width: 18,
        height: 18,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: AppColors.borderHi),
        ),
        child: const Text(
          '?',
          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: AppColors.muted),
        ),
      ),
    );
  }
}
