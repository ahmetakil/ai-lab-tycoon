// Game-style HUD drawn over the world map: chunky translucent stat plates
// with big mono numbers and small rates, a Game Dev Tycoon style project bar
// for the training run, a Reactor style vertical toolbar and contextual
// call-to-action buttons.
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../sim/content.dart';
import '../../sim/game.dart';
import '../format.dart';
import '../game_controller.dart';
import '../grid/grid_hints.dart';
import '../moments/release_sheet.dart';
import '../sound.dart';
import '../theme.dart';
import '../widgets/effects.dart';
import '../widgets/game_builder.dart';
import '../widgets/goals.dart';
import '../widgets/hud.dart';

part 'phone_hud.dart';

/// Wide layouts put the stats beside the project bar; narrow ones stack them.
bool isWideHud(double width) => width >= 760;

/// Height of the top HUD (below the safe area, goal strip included), for
/// anything that must sit under it.
double hudHeight(double width) =>
    isWideHud(width)
        ? 110
        : isPhoneHud(width)
        ? PhoneHud.height
        : 170;

const _plate = Color(0xD90A101C);

BoxDecoration plateDecoration(Color accent, {double radius = 12, bool lit = false}) =>
    BoxDecoration(
      color: _plate,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: accent.withValues(alpha: lit ? 0.85 : 0.35), width: 1.6),
      boxShadow: [
        const BoxShadow(color: Color(0xAA000000), offset: Offset(0, 3), blurRadius: 0),
        if (lit) BoxShadow(color: accent.withValues(alpha: 0.35), blurRadius: 14),
      ],
    );

// --- Top bar ----------------------------------------------------------------

class TopHud extends StatelessWidget {
  final GameController controller;
  final VoidCallback onPower;
  final VoidCallback onNetwork;
  final VoidCallback onCooling;
  final VoidCallback onProject;
  final VoidCallback onGoal;
  final VoidCallback onRivals;
  const TopHud({
    super.key,
    required this.controller,
    required this.onPower,
    required this.onNetwork,
    required this.onCooling,
    required this.onProject,
    required this.onGoal,
    required this.onRivals,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final wide = isWideHud(box.maxWidth);
        if (isPhoneHud(box.maxWidth)) {
          return GameBuilder(
            controller: controller,
            builder:
                (context) => PhoneHud(
                  controller: controller,
                  onPower: onPower,
                  onNetwork: onNetwork,
                  onCooling: onCooling,
                  onProject: onProject,
                  onGoal: onGoal,
                  onRivals: onRivals,
                ),
          );
        }
        return GameBuilder(
          controller: controller,
          builder: (context) {
            final money = _MoneyStat(controller: controller);
            final users = _UsersStat(controller: controller);
            final rating = _RatingStat(controller: controller, onTap: onRivals);
            final power = _PowerStat(controller: controller, onTap: onPower);
            final network = _NetworkStat(controller: controller, onTap: onNetwork);
            final cooling =
                controller.game.coolingTiersVisible
                    ? _CoolingStat(controller: controller, onTap: onCooling)
                    : null;
            final project = Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ProjectBar(controller: controller, onTap: onProject),
                const SizedBox(height: 4),
                GoalStrip(controller: controller, onTap: onGoal),
              ],
            );
            if (wide) {
              return Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Flexible(child: SizedBox(width: 190, child: money)),
                          const SizedBox(width: 8),
                          Flexible(child: SizedBox(width: 170, child: users)),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    SizedBox(width: 340, child: project),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(child: SizedBox(width: 130, child: rating)),
                              const SizedBox(width: 8),
                              Flexible(child: SizedBox(width: 160, child: power)),
                              const SizedBox(width: 8),
                              Flexible(child: SizedBox(width: 160, child: network)),
                            ],
                          ),
                          if (cooling != null) ...[
                            const SizedBox(height: 4),
                            SizedBox(width: 160, height: 40, child: cooling),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              );
            }
            return Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Expanded(flex: 11, child: money),
                      const SizedBox(width: 5),
                      Expanded(flex: 9, child: users),
                      const SizedBox(width: 5),
                      Expanded(flex: 8, child: rating),
                      const SizedBox(width: 5),
                      Expanded(flex: 9, child: power),
                      const SizedBox(width: 5),
                      Expanded(flex: 9, child: network),
                    ],
                  ),
                  const SizedBox(height: 6),
                  ConstrainedBox(constraints: const BoxConstraints(maxWidth: 360), child: project),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class _StatPlate extends StatelessWidget {
  final IconData icon;
  final Color color;
  final Widget value;
  final String sub;
  final Color? subColor;
  final bool lit;
  final Widget? extra;

  /// Tiny caption above the value ("RATING").
  final String? label;
  const _StatPlate({
    super.key,
    required this.icon,
    required this.color,
    required this.value,
    required this.sub,
    this.subColor,
    this.lit = false,
    this.extra,
    this.label,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final tight = box.maxWidth < 110;
        return Container(
          height: tight ? 54 : 60,
          padding: EdgeInsets.fromLTRB(tight ? 5 : 7, 5, tight ? 6 : 10, 5),
          decoration: plateDecoration(color, lit: lit),
          child: Row(
            children: [
              if (!tight || box.maxWidth > 84) ...[
                Container(
                  width: tight ? 20 : 30,
                  height: tight ? 20 : 30,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: color.withValues(alpha: 0.5)),
                  ),
                  child: Icon(icon, size: tight ? 13 : 18, color: color),
                ),
                SizedBox(width: tight ? 4 : 7),
              ],
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (label != null)
                      Text(
                        label!,
                        maxLines: 1,
                        style: labelStyle(size: tight ? 8 : 8.5, color: color).copyWith(height: 1),
                      ),
                    Flexible(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: value,
                      ),
                    ),
                    if (extra != null) extra!,
                    Text(
                      sub,
                      maxLines: 1,
                      overflow: TextOverflow.fade,
                      softWrap: false,
                      style: numStyle(
                        size: tight ? 9.5 : 11,
                        color: subColor ?? color,
                        weight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

TextStyle _big(Color c) => numStyle(
  size: 20,
  color: c,
  weight: FontWeight.w800,
).copyWith(shadows: const [Shadow(color: Color(0xFF000000), offset: Offset(0, 2))]);

class _MoneyStat extends StatelessWidget {
  final GameController controller;
  const _MoneyStat({required this.controller});

  @override
  Widget build(BuildContext context) {
    final g = controller.game;
    return _StatPlate(
      key: const ValueKey('hud-money'),
      icon: Icons.attach_money_rounded,
      color: AppColors.neon,
      value: AnimatedNumber(value: g.s.money, format: formatMoney, style: _big(AppColors.neon)),
      sub: '+${formatMoney(g.revenuePerSecond)}/s',
    );
  }
}

class _UsersStat extends StatelessWidget {
  final GameController controller;
  const _UsersStat({required this.controller});

  @override
  Widget build(BuildContext context) {
    final g = controller.game;
    final over = g.overloaded;
    return _StatPlate(
      icon: over ? Icons.warning_amber_rounded : Icons.people_alt_rounded,
      color: over ? AppColors.red : AppColors.cyan,
      lit: over,
      value: Text(formatNumber(g.s.users), style: _big(over ? AppColors.red : AppColors.text)),
      sub: over ? 'OVERLOADED' : 'cap ${formatNumber(g.capacity)}',
      subColor: over ? AppColors.red : AppColors.cyan,
    );
  }
}

/// "RATING 1293 · beat GPT-ish-4: 1339". Tap for the leaderboard.
class _RatingStat extends StatelessWidget {
  final GameController controller;
  final VoidCallback onTap;
  const _RatingStat({required this.controller, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final g = controller.game;
    final next = g.nextRival;
    return Tooltip(
      message:
          next == null
              ? 'Your model rating: ${formatRating(g.rating)}. You top the leaderboard.'
              : 'Your model rating: ${formatRating(g.rating)}. Next rival to beat: '
                  '${next.lab} ${next.model} at ${formatRating(next.rating)}. Tap for the leaderboard.',
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          key: const ValueKey('rating-chip'),
          onTap: () {
            Sound.play(Sfx.click);
            onTap();
          },
          child: _StatPlate(
            icon: Icons.emoji_events_rounded,
            color: AppColors.amber,
            label: 'RATING',
            value: Text(formatRating(g.rating), style: _big(AppColors.amber)),
            sub: next == null ? 'top lab' : 'beat ${next.model}: ${formatRating(next.rating)}',
            subColor: AppColors.muted,
          ),
        ),
      ),
    );
  }
}

/// Is the next power tier worth a nudge: affordable and needed (power
/// nearly full, or the next room needs it)?
bool powerNudge(Game g) {
  final next = g.nextPowerTier;
  if (next == null || !g.isUnlocked(next.era)) return false;
  final frac = g.powerCapKw <= 0 ? 0.0 : g.powerUsedKw / g.powerCapKw;
  final room = g.nextRoom;
  final roomNeeds = room != null && g.isUnlocked(room.era) && g.s.powerTier < room.minPowerTier;
  return g.s.money >= next.cost && (frac >= 0.8 || roomNeeds);
}

class _PowerStat extends StatelessWidget {
  final GameController controller;
  final VoidCallback onTap;
  const _PowerStat({required this.controller, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final g = controller.game;
    final frac = g.powerCapKw <= 0 ? 0.0 : g.powerUsedKw / g.powerCapKw;
    final color =
        frac >= 0.97
            ? AppColors.red
            : frac >= 0.8
            ? AppColors.amber
            : const Color(0xFFFFE066);
    final next = g.nextPowerTier;
    final canUpgrade = next != null && g.isUnlocked(next.era) && g.s.money >= next.cost;
    final nudge = powerNudge(g);
    return Tooltip(
      message:
          'Power: ${formatPower(g.powerUsedKw)} of ${formatPower(g.powerCapKw)}. '
          '${next == null ? 'Top tier.' : 'Tap to see or buy ${next.name} (${formatMoney(next.cost)}).'}',
      child: GestureDetector(
        key: const ValueKey('power-chip'),
        onTap: onTap,
        child: _TapPlate(
          nudge: nudge,
          badge: canUpgrade,
          child: _StatPlate(
            icon: Icons.bolt_rounded,
            color: color,
            lit: nudge,
            value: Text(formatPower(g.powerUsedKw), style: _big(color)),
            sub: canUpgrade ? 'upgrade ▲' : '/ ${formatPower(g.powerCapKw)}',
            subColor: canUpgrade ? AppColors.neon : AppColors.muted,
            extra: _MiniBar(frac: frac, color: color),
          ),
        ),
      ),
    );
  }
}

/// "96 / 256 GPUs fed": the network tier meter. Tap for the Network panel.
class _NetworkStat extends StatelessWidget {
  final GameController controller;
  final VoidCallback onTap;
  const _NetworkStat({required this.controller, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final g = controller.game;
    final c = g.trainingCluster;
    final color = networkMeterColor(g);
    final gpus = c?.gpus ?? 0;
    final frac = g.networkCap <= 0 ? 0.0 : gpus / g.networkCap;
    final next = g.nextNetworkTier;
    final canUpgrade = next != null && g.networkBlockReason() == null;
    final over = c != null && c.overCap;
    return Tooltip(
      message:
          'Network: ${networkMeterText(g)} on ${g.network.name}'
          '${over ? ', training at ${formatPercent(c.scalingEfficiency)}' : ''}. Tap for Network.',
      child: GestureDetector(
        key: const ValueKey('network-chip'),
        onTap: onTap,
        child: _TapPlate(
          nudge: over && canUpgrade,
          badge: canUpgrade && (over || frac >= 0.8),
          child: _StatPlate(
            icon: Icons.cable_rounded,
            color: color,
            lit: over,
            value: Text('${formatNumber(gpus)}/${formatNumber(g.networkCap)}', style: _big(color)),
            sub: over ? '→ ${formatPercent(c.scalingEfficiency)} scaling' : 'GPUs fed',
            subColor: over ? AppColors.red : AppColors.muted,
            extra: _MiniBar(frac: frac, color: color),
          ),
        ),
      ),
    );
  }
}

/// Central cooling plate (Medium lab on): throttling tiles and the tier.
class _CoolingStat extends StatelessWidget {
  final GameController controller;
  final VoidCallback onTap;
  const _CoolingStat({required this.controller, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final g = controller.game;
    final hot = throttlingTiles(g);
    final color = hot > 0 ? AppColors.red : AppColors.cyan;
    final canUpgrade = g.nextCoolingTier != null && g.coolingBlockReason() == null;
    return Tooltip(
      message: 'Central cooling: ${g.cooling.name}. Tap for Cooling.',
      child: GestureDetector(
        key: const ValueKey('cooling-chip'),
        onTap: onTap,
        child: _TapPlate(
          nudge: hot > 0 && canUpgrade,
          badge: canUpgrade,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: plateDecoration(color, lit: hot > 0),
            child: Row(
              children: [
                Icon(Icons.ac_unit_rounded, size: 16, color: color),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    // Hot GPUs first; else what the central plant removes
                    // per GPU tile (none before the first plant: all cool).
                    hot > 0
                        ? '$hot hot'
                        : g.cooling.perGpuTile > 0
                        ? '−${formatNumber(g.cooling.perGpuTile)}/GPU'
                        : 'All cool',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: numStyle(size: 13, color: color, weight: FontWeight.w800),
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

/// A plate that reads as a button: optional gentle pulse and an "▲" badge.
class _TapPlate extends StatelessWidget {
  final bool nudge;
  final bool badge;
  final Widget child;
  const _TapPlate({required this.nudge, required this.badge, required this.child});

  @override
  Widget build(BuildContext context) => MouseRegion(
    cursor: SystemMouseCursors.click,
    child: Nudge(
      active: nudge,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          child,
          if (badge)
            Positioned(
              right: -3,
              top: -4,
              child: Container(
                width: 16,
                height: 16,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.neon,
                  border: Border.all(color: Colors.black, width: 1.5),
                ),
                child: const Icon(Icons.arrow_upward_rounded, size: 11, color: Colors.black),
              ),
            ),
        ],
      ),
    ),
  );
}

class _MiniBar extends StatelessWidget {
  final double frac;
  final Color color;
  const _MiniBar({required this.frac, required this.color});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 2, top: 1),
    child: ClipRRect(
      borderRadius: BorderRadius.circular(3),
      child: SizedBox(
        height: 4,
        child: Stack(
          fit: StackFit.expand,
          children: [
            const ColoredBox(color: Color(0x33FFFFFF)),
            FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: frac.clamp(0.0, 1.0),
              child: ColoredBox(color: color),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Top-centre project bar: the current run, or what to do next.
class ProjectBar extends StatelessWidget {
  final GameController controller;
  final VoidCallback onTap;
  const ProjectBar({super.key, required this.controller, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final g = controller.game;
    final s = g.s;
    final run = s.run;
    final pending = s.pendingEffectiveCompute != null;
    final String title;
    final String sub;
    final double? progress;
    final Color color;
    final IconData icon;
    if (pending) {
      title = 'Release ready: ${defaultModelName(g)}';
      sub = 'rating ${formatRating(g.pendingRating!)} · tap to ship';
      progress = 1;
      color = AppColors.neon;
      icon = Icons.rocket_launch_rounded;
    } else if (run != null) {
      final left = math.max(0.0, (run.durationSeconds - run.elapsedSeconds) / controller.speed);
      title = 'Training ${defaultModelName(g)}';
      sub =
          run.paused
              ? 'paused · tap to resume'
              : '${formatPercent(run.progress)} · ETA ${formatDuration(left)}';
      progress = run.progress;
      color = run.paused ? AppColors.amber : AppColors.cyan;
      icon = Icons.model_training_rounded;
    } else {
      title = 'No training run';
      sub = 'idle GPUs · tap to train a model';
      progress = null;
      color = AppColors.amber;
      icon = Icons.play_arrow_rounded;
    }
    final bar = GestureDetector(
      key: const ValueKey('project-bar'),
      onTap: () {
        Sound.play(Sfx.click);
        onTap();
      },
      child: Container(
        height: 60,
        padding: const EdgeInsets.fromLTRB(6, 5, 14, 5),
        decoration: plateDecoration(color, radius: 28, lit: pending),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color.withValues(alpha: 0.2),
                border: Border.all(color: color, width: 2),
              ),
              child: Icon(icon, color: color, size: 22),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                            height: 1.1,
                          ),
                        ),
                      ),
                      Text(
                        s.era.shortLabel.toUpperCase(),
                        style: labelStyle(color: eraColor(s.era), size: 9.5),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: SizedBox(
                      height: 6,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          const ColoredBox(color: Color(0x33FFFFFF)),
                          if (progress != null)
                            FractionallySizedBox(
                              alignment: Alignment.centerLeft,
                              widthFactor: progress.clamp(0.0, 1.0),
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [color.withValues(alpha: 0.7), color],
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    sub,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: numStyle(size: 10.5, color: AppColors.muted, weight: FontWeight.w500),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    if (pending) return Pulse(scale: 1.03, child: bar);
    // Nothing training and nothing to ship: a gentle nudge.
    return Nudge(active: run == null, child: bar);
  }
}

// --- Toolbar ------------------------------------------------------------------

class ToolSpec {
  final String id;
  final String label;
  final String tooltip;
  final IconData icon;
  final Color color;
  final bool active;
  final bool badge;
  final bool pulse;

  /// Gentler than [pulse]: a slow, small breathe (e.g. idle GPUs).
  final bool nudge;

  /// The main action (Train / Release): drawn filled on the phone rail.
  final bool primary;

  /// Rarely used: tucked behind the "More" button on phones.
  final bool overflow;

  /// Small corner tag (e.g. the debug "×10" speed).
  final String? tag;
  final VoidCallback onTap;
  const ToolSpec({
    required this.id,
    required this.label,
    required this.tooltip,
    required this.icon,
    required this.color,
    required this.onTap,
    this.active = false,
    this.badge = false,
    this.pulse = false,
    this.nudge = false,
    this.primary = false,
    this.overflow = false,
    this.tag,
  });
}

/// Width of the left tool rail.
double toolbarWidth({required bool phone, required bool compact}) =>
    phone
        ? 46
        : compact
        ? 50
        : 60;

class GameToolbar extends StatefulWidget {
  final List<ToolSpec> tools;
  final bool compact;

  /// Phone rail: slim icon-first buttons, [ToolSpec.overflow] items behind
  /// a "More" toggle.
  final bool phone;
  const GameToolbar({super.key, required this.tools, this.compact = false, this.phone = false});

  @override
  State<GameToolbar> createState() => _GameToolbarState();
}

class _GameToolbarState extends State<GameToolbar> {
  bool _more = false;

  @override
  Widget build(BuildContext context) {
    final phone = widget.phone;
    final size = toolbarWidth(phone: phone, compact: widget.compact);
    final gap = phone ? 6.0 : (widget.compact ? 6.0 : 8.0);
    final shown = <ToolSpec>[
      for (final t in widget.tools)
        if (!phone || !t.overflow || _more) t,
    ];
    if (phone && widget.tools.any((t) => t.overflow)) {
      final hidden = widget.tools.where((t) => t.overflow).toList();
      shown.add(
        ToolSpec(
          id: 'more',
          label: _more ? 'Less' : 'More',
          tooltip: _more ? 'Hide extra tools' : 'More: ${hidden.map((t) => t.label).join(', ')}',
          icon: _more ? Icons.expand_less_rounded : Icons.more_horiz_rounded,
          color: AppColors.muted,
          badge: !_more && hidden.any((t) => t.badge),
          tag: _more ? null : hidden.map((t) => t.tag).whereType<String>().firstOrNull,
          onTap: () => setState(() => _more = !_more),
        ),
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final t in shown)
          Padding(
            padding: EdgeInsets.only(bottom: gap),
            child: _ToolButton(spec: t, size: size, phone: phone),
          ),
      ],
    );
  }
}

class _ToolButton extends StatefulWidget {
  final ToolSpec spec;
  final double size;
  final bool phone;
  const _ToolButton({required this.spec, required this.size, this.phone = false});

  @override
  State<_ToolButton> createState() => _ToolButtonState();
}

class _ToolButtonState extends State<_ToolButton> {
  bool _down = false;
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final t = widget.spec;
    final s = widget.size;
    final c = t.color;
    final phone = widget.phone;
    // On phones the primary action is drawn filled so it stands out.
    final filled = t.active || (phone && t.primary);
    final h = phone && t.primary ? s + 8 : s;
    const ink = Color(0xFF06100A);
    final face = Container(
      width: s,
      height: h,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(phone ? 12 : 14),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors:
              filled
                  ? [c, Color.lerp(c, Colors.black, 0.35)!]
                  : [
                    Color.lerp(const Color(0xFF1A2540), c, _hover ? 0.25 : 0.1)!,
                    const Color(0xFF0C1322),
                  ],
        ),
        border: Border.all(
          color: t.active ? Colors.white.withValues(alpha: 0.7) : c.withValues(alpha: 0.6),
          width: phone ? 1.6 : 2,
        ),
        boxShadow: [
          BoxShadow(color: const Color(0xFF000000), offset: Offset(0, _down ? 1 : (phone ? 3 : 4))),
          if (t.active || t.pulse) BoxShadow(color: c.withValues(alpha: 0.4), blurRadius: 14),
        ],
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(t.icon, size: phone ? 20 : s * 0.44, color: filled ? ink : c),
                SizedBox(height: phone ? 2 : s * 0.02),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      t.label,
                      maxLines: 1,
                      style: TextStyle(
                        fontSize: phone ? 8.5 : s * 0.17,
                        fontWeight: FontWeight.w700,
                        height: 1,
                        color: filled ? ink : (phone ? AppColors.muted : AppColors.text),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (t.badge)
            Positioned(
              right: phone ? 3 : 5,
              top: phone ? 3 : 5,
              child: Container(
                width: phone ? 8 : 10,
                height: phone ? 8 : 10,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.red,
                  border: Border.all(color: Colors.white, width: 1.5),
                ),
              ),
            ),
          if (t.tag != null)
            Positioned(
              right: -5,
              bottom: -5,
              child: Container(
                key: ValueKey('tool-${t.id}-tag'),
                padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
                decoration: BoxDecoration(
                  color: AppColors.red,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Colors.black),
                ),
                child: Text(
                  t.tag!,
                  style: numStyle(size: 8.5, color: Colors.white, weight: FontWeight.w800),
                ),
              ),
            ),
        ],
      ),
    );
    final btn = Tooltip(
      message: t.tooltip,
      preferBelow: false,
      waitDuration: const Duration(milliseconds: 350),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          key: ValueKey('tool-${t.id}'),
          onTapDown: (_) => setState(() => _down = true),
          onTapCancel: () => setState(() => _down = false),
          onTapUp: (_) => setState(() => _down = false),
          onTap: () {
            Sound.play(Sfx.click);
            t.onTap();
          },
          child: AnimatedSlide(
            duration: const Duration(milliseconds: 60),
            offset: Offset(0, _down ? 0.05 : 0),
            child: face,
          ),
        ),
      ),
    );
    if (t.pulse) return Pulse(scale: 1.06, child: btn);
    return Nudge(active: t.nudge, child: btn);
  }
}

// --- Contextual call-to-action buttons -------------------------------------

class ContextButtons extends StatelessWidget {
  final GameController controller;
  final VoidCallback onRelease;
  const ContextButtons({super.key, required this.controller, required this.onRelease});

  @override
  Widget build(BuildContext context) {
    return GameBuilder(
      controller: controller,
      builder: (context) {
        final g = controller.game;
        final s = g.s;
        final items = <Widget>[];
        final viral = s.viralSecondsLeft > 0;
        if (viral || g.overloaded) {
          final cloudLeft = s.cloudSecondsLeft;
          final canRent = cloudLeft <= 0 && s.money >= g.cloudRentCost;
          items.add(
            _CtaButton(
              key: const ValueKey('ctx-rent-cloud'),
              icon: viral ? Icons.local_fire_department_rounded : Icons.cloud_upload_rounded,
              color: AppColors.violet,
              title: viral ? 'VIRAL! Rent cloud' : 'Overloaded: rent cloud',
              sub:
                  cloudLeft > 0
                      ? 'cloud active · ${formatDuration(cloudLeft / controller.speed)}'
                      : '${formatMoney(g.cloudRentCost)} · serving ×2',
              pulse: canRent,
              onTap:
                  canRent
                      ? () {
                        final ok = controller.act((g) => g.rentCloud());
                        Sound.play(ok ? Sfx.purchase : Sfx.error);
                      }
                      : null,
            ),
          );
          if (s.run != null && !s.run!.paused) {
            items.add(
              _CtaButton(
                key: const ValueKey('ctx-pause'),
                icon: Icons.pause_rounded,
                color: AppColors.amber,
                title: 'Pause training',
                sub: 'free compute for users',
                onTap: () {
                  Sound.play(Sfx.click);
                  controller.act((g) => g.togglePauseTraining());
                },
              ),
            );
          }
        }
        if (s.pendingEffectiveCompute != null) {
          items.add(
            _CtaButton(
              key: const ValueKey('ctx-release'),
              icon: Icons.rocket_launch_rounded,
              color: AppColors.neon,
              title: 'Run done: release!',
              sub: 'rating ${formatRating(g.pendingRating!)}',
              pulse: true,
              onTap: onRelease,
            ),
          );
        }
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (final w in items) Padding(padding: const EdgeInsets.only(top: 8), child: w),
          ],
        );
      },
    );
  }
}

class _CtaButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String sub;
  final bool pulse;
  final VoidCallback? onTap;
  const _CtaButton({
    super.key,
    required this.icon,
    required this.color,
    required this.title,
    required this.sub,
    this.pulse = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    final btn = GestureDetector(
      onTap: onTap,
      child: Opacity(
        opacity: enabled ? 1 : 0.6,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 230),
          padding: const EdgeInsets.fromLTRB(8, 7, 14, 7),
          decoration: BoxDecoration(
            color: Color.alphaBlend(color.withValues(alpha: 0.22), _plate),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: color, width: 2),
            boxShadow: [
              const BoxShadow(color: Color(0xFF000000), offset: Offset(0, 4)),
              BoxShadow(color: color.withValues(alpha: 0.45), blurRadius: 16),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(10)),
                child: Icon(icon, color: const Color(0xFF080C1A), size: 20),
              ),
              const SizedBox(width: 9),
              Flexible(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5),
                    ),
                    Text(
                      sub,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: numStyle(size: 10.5, color: color, weight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
    return pulse ? Pulse(scale: 1.05, child: btn) : btn;
  }
}
