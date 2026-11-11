import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../sim/content.dart';
import '../format.dart';
import '../game_assets.dart';
import '../game_controller.dart';
import '../sound.dart';
import '../theme.dart';
import 'effects.dart';
import 'game_builder.dart';
import 'meters.dart';
import 'panel.dart';

const _eraColors = <Era, Color>{
  Era.garage: AppColors.amber,
  Era.startup: AppColors.cyan,
  Era.lab: AppColors.violet,
};

/// Accent colour per era (falls back for eras without a colour yet).
Color eraColor(Era e) => _eraColors[e] ?? AppColors.neon;

/// Always-visible header: lab, era, money, users, rating, power.
class Hud extends StatelessWidget {
  final GameController controller;
  const Hud({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: ContentFrame(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 8, 12),
          child: GameBuilder(controller: controller, builder: (context) => _content(context)),
        ),
      ),
    );
  }

  Widget _content(BuildContext context) {
    final g = controller.game;
    final s = g.s;
    final over = g.overloaded;
    final powerFrac = g.powerCapKw <= 0 ? 0.0 : g.powerUsedKw / g.powerCapKw;
    final powerColor =
        powerFrac >= 0.97
            ? AppColors.red
            : powerFrac >= 0.8
            ? AppColors.amber
            : AppColors.cyan;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            const GameImage(GameArt.logoIcon, size: 26, fallback: Icons.hub_outlined),
            const SizedBox(width: 8),
            Expanded(
              child: Row(
                children: [
                  Flexible(
                    child: Text(
                      s.labName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.2,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Tag(s.era.label.toUpperCase(), color: eraColor(s.era)),
                  if (controller.speed != 1) ...[
                    const SizedBox(width: 6),
                    Tag('×${formatNumber(controller.speed)}', color: AppColors.red, mono: true),
                  ],
                ],
              ),
            ),
            IconButton(
              tooltip: 'Settings',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.settings_outlined, color: AppColors.muted, size: 21),
              onPressed: () {
                Sound.play(Sfx.click);
                showSettingsSheet(context, controller);
              },
            ),
          ],
        ),
        const SizedBox(height: 6),
        Padding(
          padding: const EdgeInsets.only(right: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 5,
                child: _Stat(
                  label: 'CASH',
                  main: AnimatedNumber(
                    value: s.money,
                    format: formatMoney,
                    style: numStyle(size: 19, color: AppColors.neon, weight: FontWeight.w800),
                  ),
                  sub: '+${formatMoney(g.revenuePerSecond)}/s',
                ),
              ),
              Expanded(
                flex: 5,
                child: _Stat(
                  label: over ? 'USERS · OVERLOAD' : 'USERS',
                  labelColor: over ? AppColors.red : AppColors.muted,
                  main: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (over)
                        Blink(
                          builder:
                              (context, t) => Container(
                                width: 8,
                                height: 8,
                                margin: const EdgeInsets.only(right: 5),
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: AppColors.red.withValues(alpha: 0.35 + 0.65 * t),
                                ),
                              ),
                        ),
                      Text(
                        formatNumber(s.users),
                        maxLines: 1,
                        style: numStyle(
                          size: 19,
                          weight: FontWeight.w800,
                          color: over ? AppColors.red : AppColors.text,
                        ),
                      ),
                    ],
                  ),
                  sub: '${formatNumber(g.servedUsers)} served',
                  subColor: over ? AppColors.red : AppColors.muted,
                ),
              ),
              Expanded(
                flex: 4,
                child: _Stat(
                  label: 'RATING',
                  main: Text(
                    g.rating.toStringAsFixed(0),
                    style: numStyle(size: 19, weight: FontWeight.w800, color: AppColors.cyan),
                  ),
                  sub: 'arena elo',
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Padding(
          padding: const EdgeInsets.only(right: 8),
          child: Row(
            children: [
              Icon(Icons.bolt, size: 15, color: powerColor),
              const SizedBox(width: 4),
              Expanded(child: MeterBar(value: powerFrac, color: powerColor, height: 7)),
              const SizedBox(width: 10),
              Text(
                '${formatPower(g.powerUsedKw)} / ${formatPower(g.powerCapKw)}',
                style: numStyle(size: 11.5, color: AppColors.muted, weight: FontWeight.w500),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  final String label;
  final Color labelColor;
  final Widget main;
  final String sub;
  final Color subColor;

  const _Stat({
    required this.label,
    required this.main,
    required this.sub,
    this.labelColor = AppColors.muted,
    this.subColor = AppColors.muted,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.fade,
          softWrap: false,
          style: labelStyle(color: labelColor, size: 10),
        ),
        const SizedBox(height: 2),
        FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: main),
        Text(
          sub,
          maxLines: 1,
          overflow: TextOverflow.fade,
          softWrap: false,
          style: numStyle(size: 11, color: subColor, weight: FontWeight.w500),
        ),
      ],
    );
  }
}

Future<void> showSettingsSheet(BuildContext context, GameController controller) {
  return showModalBottomSheet<void>(
    context: context,
    builder:
        (context) => StatefulBuilder(
          builder:
              (context, setSheet) => SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text('SETTINGS', style: labelStyle()),
                      const SizedBox(height: 8),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        secondary: const Icon(Icons.volume_up_outlined),
                        title: const Text('Sound effects'),
                        value: !Sound.muted,
                        onChanged: (v) {
                          Sound.setMuted(!v);
                          Sound.play(Sfx.click);
                          setSheet(() {});
                        },
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        secondary: const Icon(Icons.music_note_outlined),
                        title: const Text('Music'),
                        value: Sound.musicOn,
                        onChanged: (v) {
                          Sound.musicOn = v;
                          v ? Sound.startMusic() : Sound.stopMusic();
                          setSheet(() {});
                        },
                      ),
                      if (kDebugMode) ...[
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            const Icon(Icons.fast_forward_outlined, color: AppColors.red),
                            const SizedBox(width: 16),
                            const Expanded(child: Text('Debug speed')),
                            SegmentedButton<double>(
                              showSelectedIcon: false,
                              segments: const [
                                ButtonSegment(value: 1, label: Text('×1')),
                                ButtonSegment(value: 10, label: Text('×10')),
                                ButtonSegment(value: 60, label: Text('×60')),
                              ],
                              selected: {controller.speed},
                              onSelectionChanged: (v) {
                                controller.speed = v.first;
                                setSheet(() {});
                              },
                            ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 20),
                      NeonButton(
                        label: 'Reset game',
                        icon: Icons.restart_alt,
                        color: AppColors.red,
                        filled: false,
                        expand: true,
                        onPressed: () async {
                          final ok = await showDialog<bool>(
                            context: context,
                            builder:
                                (context) => AlertDialog(
                                  title: const Text('Reset everything?'),
                                  content: const Text(
                                    'Your lab, GPUs, research and models will be wiped. This cannot be undone.',
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.pop(context, false),
                                      child: const Text('Cancel'),
                                    ),
                                    TextButton(
                                      onPressed: () => Navigator.pop(context, true),
                                      style: TextButton.styleFrom(foregroundColor: AppColors.red),
                                      child: const Text('Reset'),
                                    ),
                                  ],
                                ),
                          );
                          if (ok == true) {
                            await controller.resetGame();
                            if (context.mounted) Navigator.pop(context);
                          }
                        },
                      ),
                    ],
                  ),
                ),
              ),
        ),
  );
}
