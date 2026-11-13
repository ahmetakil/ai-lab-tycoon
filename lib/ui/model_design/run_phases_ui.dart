// Mid-run decisions (lib/sim/run_phases.dart): the checkpoint card, the
// progress bar with phase markers, and the "decisions so far" line.
import 'package:flutter/material.dart';

import '../../sim/game_state.dart';
import '../../sim/run_phases.dart';
import '../game_controller.dart';
import '../sound.dart';
import '../theme.dart';

Color phaseColor(RunPhase p) => switch (p) {
  RunPhase.early => AppColors.cyan,
  RunPhase.anneal => AppColors.violet,
  RunPhase.post => AppColors.amber,
};

/// A run's progress bar with a marker at each checkpoint. A decided
/// checkpoint is filled in its phase colour; the one the run waits at
/// blinks.
class PhaseTrack extends StatelessWidget {
  final TrainingRun run;
  final Color color;
  final double height;
  const PhaseTrack({super.key, required this.run, required this.color, this.height = 6});

  @override
  Widget build(BuildContext context) {
    final waiting = run.awaitingPhase;
    final dot = height + 4;
    return SizedBox(
      height: dot,
      child: LayoutBuilder(
        builder: (context, box) {
          final w = box.maxWidth;
          return Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                left: 0,
                right: 0,
                top: (dot - height) / 2,
                height: height,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(height),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      const ColoredBox(color: Color(0x33FFFFFF)),
                      FractionallySizedBox(
                        alignment: Alignment.centerLeft,
                        widthFactor: run.progress.clamp(0.0, 1.0),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(colors: [color.withValues(alpha: 0.7), color]),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              for (final p in askingPhases)
                Positioned(
                  key: ValueKey('phase-marker-${p.name}'),
                  left: (w * p.checkpoint - dot / 2).clamp(0.0, w - dot),
                  top: 0,
                  width: dot,
                  height: dot,
                  child: _Marker(color: phaseColor(p), done: run.phaseChoices.containsKey(p), waiting: waiting == p),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _Marker extends StatelessWidget {
  final Color color;
  final bool done;
  final bool waiting;
  const _Marker({required this.color, required this.done, required this.waiting});

  @override
  Widget build(BuildContext context) {
    final box = DecoratedBox(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: done || waiting ? color : AppColors.bg,
        border: Border.all(color: done || waiting ? Colors.white : color, width: 1.4),
        boxShadow: waiting ? [BoxShadow(color: color, blurRadius: 8)] : null,
      ),
    );
    if (!waiting) return box;
    return _Blink(child: box);
  }
}

class _Blink extends StatefulWidget {
  final Widget child;
  const _Blink({required this.child});

  @override
  State<_Blink> createState() => _BlinkState();
}

class _BlinkState extends State<_Blink> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 700))
    ..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      FadeTransition(opacity: Tween(begin: 0.35, end: 1.0).animate(_c), child: widget.child);
}

/// "Web → Quality data → ?" : the run's decisions so far.
class PhaseChoicesLine extends StatelessWidget {
  final TrainingRun run;
  const PhaseChoicesLine({super.key, required this.run});

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 6,
    runSpacing: 4,
    children: [
      for (final p in RunPhase.values)
        _Chip(
          key: ValueKey('phase-chip-${p.name}'),
          color: phaseColor(p),
          text:
              run.phaseChoices[p] == null
                  ? '${_short(p)}: …'
                  : '${_short(p)}: ${run.phaseChoices[p]!.shortLabel}${run.autoPhases.contains(p) ? ' (auto)' : ''}',
          filled: run.phaseChoices.containsKey(p),
        ),
    ],
  );

  static String _short(RunPhase p) => switch (p) {
    RunPhase.early => 'Mix',
    RunPhase.anneal => 'Anneal',
    RunPhase.post => 'Post',
  };
}

class _Chip extends StatelessWidget {
  final Color color;
  final String text;
  final bool filled;
  const _Chip({super.key, required this.color, required this.text, required this.filled});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
    decoration: BoxDecoration(
      color: filled ? color.withValues(alpha: 0.14) : null,
      borderRadius: BorderRadius.circular(99),
      border: Border.all(color: color.withValues(alpha: filled ? 0.6 : 0.3)),
    ),
    child: Text(
      text,
      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: filled ? color : AppColors.muted),
    ),
  );
}

/// The checkpoint card: one question and the phase's options. Options the
/// lab hasn't researched yet show greyed with a lock and the reason, and
/// ignore taps. Shown while the run waits (Game.awaitingPhase); renders
/// nothing otherwise.
class PhaseDecisionCard extends StatelessWidget {
  final GameController controller;
  const PhaseDecisionCard({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    final run = controller.game.s.run;
    final phase = run?.awaitingPhase;
    if (run == null || phase == null) return const SizedBox.shrink();
    final g = controller.game;
    final color = phaseColor(phase);
    final def = defaultPhaseOption(phase, run.spec, g.phaseContext);
    // Unlocked options first, locked ones after (each in content order).
    final locks = {for (final o in phase.options) o: g.phaseLockReason(o)};
    final ordered = [
      ...phase.options.where((o) => locks[o] == null),
      ...phase.options.where((o) => locks[o] != null),
    ];
    return Container(
      key: ValueKey('phase-decision-${phase.name}'),
      constraints: const BoxConstraints(maxWidth: 560),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.97),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color, width: 1.4),
        boxShadow: [BoxShadow(color: color.withValues(alpha: 0.3), blurRadius: 18)],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.flag_circle_rounded, color: color, size: 18),
              const SizedBox(width: 6),
              Expanded(
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(text: '${phase.label.toUpperCase()}  ', style: labelStyle(color: color, size: 10.5)),
                      TextSpan(
                        text: phase.question,
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5, color: AppColors.text),
                      ),
                    ],
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          LayoutBuilder(
            builder: (context, box) {
              final narrow = box.maxWidth < 420;
              final buttons = [
                for (final o in ordered)
                  _OptionButton(
                    option: o,
                    color: color,
                    isDefault: o == def,
                    narrow: narrow,
                    lockReason: locks[o],
                    onTap: () {
                      Sound.play(Sfx.click);
                      controller.act((g) => g.choosePhase(o));
                    },
                  ),
              ];
              if (narrow) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [for (final b in buttons) Padding(padding: const EdgeInsets.only(bottom: 6), child: b)],
                );
              }
              // Up to 3 side by side; 4 or more in rows of 2.
              final perRow = buttons.length <= 3 ? buttons.length : 2;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var r = 0; r < buttons.length; r += perRow)
                    Padding(
                      padding: EdgeInsets.only(bottom: r + perRow < buttons.length ? 8 : 0),
                      child: IntrinsicHeight(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            for (var i = r; i < r + perRow; i++) ...[
                              if (i > r) const SizedBox(width: 8),
                              Expanded(child: i < buttons.length ? buttons[i] : const SizedBox.shrink()),
                            ],
                          ],
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
          const SizedBox(height: 2),
          Text(
            'Training waits for your call. Not sure? ${def.label} is the safe default.',
            key: const ValueKey('phase-hint'),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: numStyle(size: 10.5, color: AppColors.muted, weight: FontWeight.w500),
          ),
        ],
      ),
    );
  }
}

class _OptionButton extends StatelessWidget {
  final PhaseOption option;
  final Color color;
  final bool isDefault;
  final bool narrow;

  /// Why it can't be picked yet ("Research RLHF to unlock"), or null.
  final String? lockReason;
  final VoidCallback onTap;
  const _OptionButton({
    required this.option,
    required this.color,
    required this.isDefault,
    required this.narrow,
    required this.onTap,
    this.lockReason,
  });

  @override
  Widget build(BuildContext context) {
    final locked = lockReason != null;
    final c = locked ? AppColors.faint : color;
    return Material(
      color: locked ? AppColors.surface : color.withValues(alpha: isDefault ? 0.16 : 0.07),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        key: ValueKey('phase-option-${option.name}'),
        borderRadius: BorderRadius.circular(10),
        onTap: locked ? null : onTap,
        child: Container(
          padding: narrow ? const EdgeInsets.fromLTRB(9, 5, 9, 5) : const EdgeInsets.fromLTRB(9, 7, 9, 7),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: locked ? AppColors.border : color.withValues(alpha: isDefault ? 0.8 : 0.35)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  if (locked) ...[
                    Icon(Icons.lock_outline, key: ValueKey('phase-lock-${option.name}'), size: 13, color: c),
                    const SizedBox(width: 4),
                  ],
                  Flexible(
                    child: Text(
                      option.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5, color: c),
                    ),
                  ),
                ],
              ),
              // On a phone a locked option keeps just its name and why, so
              // the card stays short.
              if (!(locked && narrow)) ...[
                const SizedBox(height: 2),
                Text(
                  option.effectsText,
                  style: numStyle(size: 10.5, color: locked ? AppColors.faint : AppColors.text, weight: FontWeight.w600),
                ),
              ],
              SizedBox(height: locked && narrow ? 1 : 3),
              if (locked)
                Text(
                  lockReason!,
                  key: ValueKey('phase-lock-reason-${option.name}'),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11, color: AppColors.muted, fontWeight: FontWeight.w600, height: 1.25),
                )
              else
                Text(
                  option.blurb,
                  maxLines: narrow ? 1 : 4,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11, color: AppColors.muted, height: 1.25),
                ),
              if (!narrow) ...[
                const SizedBox(height: 3),
                Text(
                  option.ref,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 9.5, color: AppColors.faint, fontStyle: FontStyle.italic),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Picker for the early-phase data emphasis in the run setup: every mix
/// holds web, code and math; a segment says which one is upweighted (or,
/// once researched, a tuned blend). Locked emphases are disabled, with a
/// lock and the reason in the tooltip. Segments use [PhaseOption.shortLabel]
/// and tight padding so all of them fit a 360 px phone.
class EarlyFocusPicker extends StatelessWidget {
  final PhaseOption selected;
  final ValueChanged<PhaseOption> onChanged;

  /// Why an option can't be picked yet, or null (default: all unlocked).
  final String? Function(PhaseOption)? lockReason;
  const EarlyFocusPicker({super.key, required this.selected, required this.onChanged, this.lockReason});

  @override
  Widget build(BuildContext context) => SegmentedButton<PhaseOption>(
    key: const ValueKey('early-focus'),
    showSelectedIcon: false,
    style: const ButtonStyle(
      visualDensity: VisualDensity.compact,
      padding: WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 4)),
    ),
    segments: [
      for (final o in RunPhase.early.options)
        if (lockReason?.call(o) case final why?)
          ButtonSegment(
            value: o,
            enabled: false,
            // The lock sits in the scaled label so 4 segments fit a phone.
            label: FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.lock_outline, size: 13, key: ValueKey('early-lock-${o.name}')),
                  const SizedBox(width: 3),
                  Text(o.shortLabel),
                ],
              ),
            ),
            tooltip: '${_tip(o)} $why.',
          )
        else
          ButtonSegment(
            value: o,
            label: FittedBox(
              key: ValueKey('early-option-${o.name}'),
              fit: BoxFit.scaleDown,
              child: Text(o.shortLabel),
            ),
            tooltip: _tip(o),
          ),
    ],
    selected: {selected},
    onSelectionChanged: (v) => onChanged(v.first),
  );

  static String _tip(PhaseOption o) =>
      o == PhaseOption.tunedMix
          ? 'Tuned mix: ${o.blurb} (${o.ref})'
          : '${o.label} emphasis (the mix still has web, code and math): ${o.blurb} (${o.ref})';
}
