// What to do next: the move-to-next-room checklist (each requirement done or
// not, with progress and a button that takes you there), the always-visible
// next-era goal strip, and the "what the next era unlocks" sheet.
import 'package:flutter/material.dart';

import '../../sim/balance.dart';
import '../../sim/content.dart';
import '../../sim/game.dart';
import '../format.dart';
import '../game_controller.dart';
import '../sound.dart';
import '../theme.dart';
import 'effects.dart';
import 'hud.dart';
import 'meters.dart';

// --- Requirement checklist ---------------------------------------------------

/// Rows for Game.moveRequirements: ✓ / ○, title, progress text, a thin bar,
/// a how-to hint and (where there's somewhere to go) a button.
class RequirementList extends StatelessWidget {
  final List<Requirement> requirements;
  final void Function(RequirementAction action) onAction;
  const RequirementList({super.key, required this.requirements, required this.onAction});

  @override
  Widget build(BuildContext context) {
    final need = requirements.where((r) => r.required);
    final nice = requirements.where((r) => !r.required);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final r in need)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _RequirementRow(req: r, onAction: onAction),
          ),
        if (nice.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.only(top: 2, bottom: 6),
            child: Text(
              'GOOD TO KNOW',
              style: labelStyle(size: 9.5, color: AppColors.cyan),
            ),
          ),
          for (final r in nice)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _RequirementRow(req: r, onAction: onAction),
            ),
        ],
      ],
    );
  }
}

class _RequirementRow extends StatelessWidget {
  final Requirement req;
  final void Function(RequirementAction action) onAction;
  const _RequirementRow({required this.req, required this.onAction});

  @override
  Widget build(BuildContext context) {
    final r = req;
    final color =
        r.done
            ? AppColors.neon
            : r.required
            ? AppColors.amber
            : AppColors.cyan;
    final action = r.done ? RequirementAction.none : r.action;
    return Container(
      key: ValueKey('req-${r.kind}'),
      padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: r.done ? 0.35 : 0.55)),
      ),
      child: Row(
        children: [
          Icon(
            r.done
                ? Icons.check_circle_rounded
                : r.required
                ? Icons.radio_button_unchecked_rounded
                : Icons.info_outline_rounded,
            color: color,
            size: 20,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: '${r.title}: ',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      TextSpan(text: r.detail, style: numStyle(size: 12.5, color: color)),
                    ],
                  ),
                  style: const TextStyle(fontSize: 13, color: AppColors.text, height: 1.25),
                ),
                if (!r.done) ...[
                  const SizedBox(height: 4),
                  MeterBar(value: r.progress, color: color, height: 4),
                  if (r.hint != null) ...[
                    const SizedBox(height: 3),
                    Text(
                      r.hint!,
                      style: const TextStyle(color: AppColors.muted, fontSize: 11.5, height: 1.2),
                    ),
                  ],
                ],
              ],
            ),
          ),
          if (action != RequirementAction.none) ...[
            const SizedBox(width: 8),
            TextButton.icon(
              key: ValueKey('req-go-${r.kind}'),
              onPressed: () {
                Sound.play(Sfx.click);
                onAction(action);
              },
              style: TextButton.styleFrom(
                foregroundColor: AppColors.neon,
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 8),
              ),
              icon: Icon(switch (action) {
                RequirementAction.power => Icons.bolt_rounded,
                RequirementAction.research => Icons.science_rounded,
                _ => Icons.model_training_rounded,
              }, size: 16),
              label: Text(switch (action) {
                RequirementAction.power => 'Open power',
                RequirementAction.research => 'Research',
                _ => 'Train',
              }),
            ),
          ],
        ],
      ),
    );
  }
}

// --- Next-era goal -----------------------------------------------------------

/// The goal the strip shows: the next era's gate, or the next rival once
/// you're in the last era. Null when there's nothing left.
class GoalInfo {
  final String title; // "Next era: Small lab"
  final String progress; // "rating 998 / 1,000"
  final String hint;
  final double value; // 0..1
  final bool met;
  final Era? era; // null for a rival goal
  final String? metric;
  const GoalInfo(this.title, this.progress, this.hint, this.value, this.met, this.era, this.metric);

  static GoalInfo? of(Game g) {
    final goal = g.nextEraGoal;
    if (goal != null) {
      final progress = switch (goal.metric) {
        'users' => '${formatNumber(goal.current)} / ${formatNumber(goal.target)} users',
        'rating' => 'rating ${_int(goal.current.floorToDouble())} / ${_int(goal.target)}',
        'compute' => Game.goalProgress(goal),
        _ => '${formatMoney(goal.current)} / ${formatMoney(goal.target)} ARR',
      };
      return GoalInfo(
        'Next era: ${goal.era.label}',
        progress,
        Game.goalHint(goal.metric),
        goal.progress,
        goal.met,
        goal.era,
        goal.metric,
      );
    }
    final r = g.nextRival;
    if (r == null) return null;
    final ratingOk = g.rating >= r.rating;
    final usersOk = g.s.users >= r.users;
    final value = ((g.rating - ratingBase) / (r.rating - ratingBase)).clamp(0.0, 1.0);
    return GoalInfo(
      'Next rival: ${r.model}',
      ratingOk && !usersOk
          ? '${formatNumber(g.s.users)} / ${formatNumber(r.users)} users'
          : 'rating ${_int(g.rating.floorToDouble())} / ${_int(r.rating)}',
      ratingOk && !usersOk
          ? 'release better models and add serving GPUs'
          : 'train & release a better model',
      value,
      ratingOk && usersOk,
      null,
      ratingOk && !usersOk ? 'users' : 'rating',
    );
  }

  static String _int(double v) => v.round().toString().replaceAllMapped(
    RegExp(r'(\d)(?=(\d{3})+$)'),
    (m) => '${m[1]},',
  );
}

/// Compact strip under the project bar: "Next era: Small lab · rating 998 /
/// 1,000" with a thin bar and a how-to hint. Tap for details.
class GoalStrip extends StatelessWidget {
  final GameController controller;
  final VoidCallback onTap;
  const GoalStrip({super.key, required this.controller, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final info = GoalInfo.of(controller.game);
    if (info == null) return const SizedBox.shrink();
    final color = info.era == null ? AppColors.amber : eraColor(info.era!);
    return GestureDetector(
      key: const ValueKey('goal-strip'),
      onTap: () {
        Sound.play(Sfx.click);
        onTap();
      },
      child: Container(
        height: 30,
        padding: const EdgeInsets.fromLTRB(10, 3, 10, 4),
        decoration: BoxDecoration(
          color: const Color(0xD90A101C),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.45)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.flag_rounded, size: 12, color: color),
                const SizedBox(width: 4),
                Flexible(
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: info.title,
                          style: TextStyle(color: color, fontWeight: FontWeight.w700),
                        ),
                        TextSpan(text: ' · ${info.progress}', style: numStyle(size: 10.5, color: AppColors.text)),
                        TextSpan(text: ' · ${info.hint}', style: const TextStyle(color: AppColors.muted)),
                      ],
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 10.5, height: 1.1),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 3),
            MeterBar(value: info.value, color: color, height: 3),
          ],
        ),
      ),
    );
  }
}

/// Modal body: how to reach the next era and what it unlocks.
class NextEraSheet extends StatelessWidget {
  final GameController controller;
  final VoidCallback onTrain;
  const NextEraSheet({super.key, required this.controller, required this.onTrain});

  @override
  Widget build(BuildContext context) {
    final g = controller.game;
    final info = GoalInfo.of(g);
    if (info == null) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Text('You beat every rival. You\'re the top lab.'),
      );
    }
    final era = info.era;
    final lines = <(IconData, String)>[];
    if (era != null) {
      for (final r in rooms.where((r) => r.era == era)) {
        lines.add((Icons.home_work_rounded, 'Move to the ${r.name} (${r.width}×${r.height}, ${formatMoney(r.cost)})'));
      }
      final gpus = tiles.where((t) => t.era == era && t.isGpu).map((t) => t.name);
      if (gpus.isNotEmpty) lines.add((Icons.memory, 'GPUs: ${gpus.join(', ')}'));
      final cool = tiles.where((t) => t.era == era && t.isCooling).map((t) => t.name);
      if (cool.isNotEmpty) lines.add((Icons.ac_unit, 'Coolers: ${cool.join(', ')}'));
      for (final p in powerTiers.where((p) => p.era == era)) {
        lines.add((Icons.bolt_rounded, 'Power: ${p.name} (${formatPower(p.capacityKw)})'));
      }
      for (final n in networkTiers.where((n) => n.era == era)) {
        lines.add((Icons.cable, 'Network: ${n.name} (feeds ${formatNumber(n.gpuCap)} GPUs)'));
      }
      for (final c in coolingTiers.where((c) => c.era == era)) {
        lines.add((Icons.water_drop_outlined, 'Central cooling: ${c.name}'));
      }
      final ups = upgrades.where((u) => u.era == era).map((u) => u.name);
      if (ups.isNotEmpty) lines.add((Icons.science_rounded, 'Research: ${ups.join(', ')}'));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 8),
        Text(
          info.title,
          key: const ValueKey('next-era-title'),
          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
        ),
        const SizedBox(height: 6),
        Text(info.progress, style: numStyle(size: 14, color: AppColors.neon)),
        const SizedBox(height: 6),
        MeterBar(value: info.value, color: AppColors.neon, height: 8),
        const SizedBox(height: 8),
        Text(
          'How: ${info.hint}.',
          style: const TextStyle(color: AppColors.text, fontSize: 13.5, height: 1.3),
        ),
        if (lines.isNotEmpty) ...[
          const SizedBox(height: 14),
          Text('IT UNLOCKS', style: labelStyle(size: 10, color: AppColors.neon)),
          const SizedBox(height: 6),
          for (final (icon, text) in lines)
            Padding(
              padding: const EdgeInsets.only(bottom: 5),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(icon, size: 16, color: AppColors.muted),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(text, style: const TextStyle(fontSize: 12.5, height: 1.3)),
                  ),
                ],
              ),
            ),
        ],
        if (info.metric == 'rating' || info.metric == 'users') ...[
          const SizedBox(height: 12),
          FilledButton.icon(
            key: const ValueKey('next-era-train'),
            onPressed: () {
              Sound.play(Sfx.click);
              onTrain();
            },
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.neon,
              foregroundColor: AppColors.bg,
              textStyle: const TextStyle(fontWeight: FontWeight.w800),
            ),
            icon: const Icon(Icons.model_training_rounded, size: 18),
            label: Text(g.s.pendingEffectiveCompute != null ? 'Release your model' : 'Open Training'),
          ),
        ],
      ],
    );
  }
}

/// Gentle nudge: a slow, small pulse (for "no run going").
class Nudge extends StatelessWidget {
  final bool active;
  final Widget child;
  const Nudge({super.key, required this.active, required this.child});

  @override
  Widget build(BuildContext context) =>
      Pulse(active: active, scale: 1.025, period: const Duration(milliseconds: 1800), child: child);
}
