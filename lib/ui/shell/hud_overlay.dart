// Game-style HUD drawn over the world map: chunky translucent stat plates
// with big mono numbers and small rates, a Game Dev Tycoon style project bar
// for the training run, a Reactor style vertical toolbar and contextual
// call-to-action buttons.
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../sim/content.dart';
import '../format.dart';
import '../game_controller.dart';
import '../moments/release_sheet.dart';
import '../sound.dart';
import '../theme.dart';
import '../widgets/effects.dart';
import '../widgets/game_builder.dart';
import '../widgets/hud.dart';

/// Wide layouts put the stats beside the project bar; narrow ones stack them.
bool isWideHud(double width) => width >= 760;

/// Height of the top HUD (below the safe area), for anything that must sit under it.
double hudHeight(double width) => isWideHud(width) ? 76 : 136;

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
  final VoidCallback onProject;
  const TopHud({
    super.key,
    required this.controller,
    required this.onPower,
    required this.onProject,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final wide = isWideHud(box.maxWidth);
        return GameBuilder(
          controller: controller,
          builder: (context) {
            final money = _MoneyStat(controller: controller);
            final users = _UsersStat(controller: controller);
            final rating = _RatingStat(controller: controller);
            final power = _PowerStat(controller: controller, onTap: onPower);
            final project = ProjectBar(controller: controller, onTap: onProject);
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
                      child: Row(
                        children: [
                          Flexible(child: SizedBox(width: 160, child: rating)),
                          const SizedBox(width: 8),
                          Flexible(child: SizedBox(width: 190, child: power)),
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
  const _StatPlate({
    super.key,
    required this.icon,
    required this.color,
    required this.value,
    required this.sub,
    this.subColor,
    this.lit = false,
    this.extra,
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
                    FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: value),
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

class _RatingStat extends StatelessWidget {
  final GameController controller;
  const _RatingStat({required this.controller});

  @override
  Widget build(BuildContext context) {
    final g = controller.game;
    final next = g.nextRival;
    return _StatPlate(
      icon: Icons.emoji_events_rounded,
      color: AppColors.amber,
      value: Text(formatRating(g.rating), style: _big(AppColors.amber)),
      sub: next == null ? 'top lab' : 'vs ${formatRating(next.rating)}',
    );
  }
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
    return GestureDetector(
      key: const ValueKey('power-chip'),
      onTap: onTap,
      child: Tooltip(
        message: 'Power: ${formatPower(g.powerUsedKw)} of ${formatPower(g.powerCapKw)}',
        child: _StatPlate(
          icon: Icons.bolt_rounded,
          color: color,
          lit: canUpgrade && frac >= 0.8,
          value: Text(formatPower(g.powerUsedKw), style: _big(color)),
          sub: canUpgrade ? 'upgrade ▲' : '/ ${formatPower(g.powerCapKw)}',
          subColor: canUpgrade ? AppColors.neon : AppColors.muted,
          extra: Padding(
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
          ),
        ),
      ),
    );
  }
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
      sub = 'rating ${formatRating(g.ratingOf(s.pendingEffectiveCompute!))} · tap to ship';
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
      title = 'No run';
      sub = 'tap to train a model';
      progress = null;
      color = AppColors.muted;
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
    return pending ? Pulse(scale: 1.03, child: bar) : bar;
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
  });
}

class GameToolbar extends StatelessWidget {
  final List<ToolSpec> tools;
  final bool compact;
  const GameToolbar({super.key, required this.tools, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final size = compact ? 50.0 : 60.0;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final t in tools)
          Padding(
            padding: EdgeInsets.only(bottom: compact ? 6 : 8),
            child: _ToolButton(spec: t, size: size),
          ),
      ],
    );
  }
}

class _ToolButton extends StatefulWidget {
  final ToolSpec spec;
  final double size;
  const _ToolButton({required this.spec, required this.size});

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
    final face = Container(
      width: s,
      height: s,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors:
              t.active
                  ? [c, Color.lerp(c, Colors.black, 0.35)!]
                  : [
                    Color.lerp(const Color(0xFF1A2540), c, _hover ? 0.25 : 0.1)!,
                    const Color(0xFF0C1322),
                  ],
        ),
        border: Border.all(
          color: t.active ? Colors.white.withValues(alpha: 0.7) : c.withValues(alpha: 0.6),
          width: 2,
        ),
        boxShadow: [
          BoxShadow(color: const Color(0xFF000000), offset: Offset(0, _down ? 1 : 4)),
          if (t.active || t.pulse) BoxShadow(color: c.withValues(alpha: 0.4), blurRadius: 14),
        ],
      ),
      child: Stack(
        children: [
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(t.icon, size: s * 0.44, color: t.active ? const Color(0xFF06100A) : c),
                SizedBox(height: s * 0.02),
                Text(
                  t.label,
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: s * 0.17,
                    fontWeight: FontWeight.w700,
                    height: 1,
                    color: t.active ? const Color(0xFF06100A) : AppColors.text,
                  ),
                ),
              ],
            ),
          ),
          if (t.badge)
            Positioned(
              right: 5,
              top: 5,
              child: Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.red,
                  border: Border.all(color: Colors.white, width: 1.5),
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
    return t.pulse ? Pulse(scale: 1.06, child: btn) : btn;
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
              sub: 'rating ${formatRating(g.ratingOf(s.pendingEffectiveCompute!))}',
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
