import 'package:flutter/material.dart';

import '../../sim/content.dart';
import '../game_controller.dart';
import '../shell/game_modal.dart';
import '../sound.dart';
import '../theme.dart';
import 'effects.dart';

const _eraColors = <Era, Color>{
  Era.garage: AppColors.amber,
  Era.startup: AppColors.cyan,
  Era.smallLab: AppColors.neon,
  Era.mediumLab: Color(0xFF5B8CFF),
  Era.bigLab: AppColors.violet,
  Era.globalLab: Color(0xFFFF6FD8),
};

/// Accent colour per era (falls back for eras without a colour yet).
Color eraColor(Era e) => _eraColors[e] ?? AppColors.neon;

Future<void> showSettingsSheet(BuildContext context, GameController controller) {
  return showGameModal<void>(
    context,
    title: 'Settings',
    icon: Icons.settings_rounded,
    color: AppColors.muted,
    maxWidth: 440,
    child: StatefulBuilder(
      builder:
          (context, setSheet) => Padding(
            padding: const EdgeInsets.fromLTRB(4, 8, 4, 4),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
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
                // Shown in every build for now (playtesting in Chrome).
                const SizedBox(height: 8),
                const Row(
                  children: [
                    Icon(Icons.fast_forward_outlined, color: AppColors.red),
                    SizedBox(width: 16),
                    Expanded(child: Text('Playtest speed')),
                  ],
                ),
                const SizedBox(height: 8),
                SegmentedButton<double>(
                  key: const ValueKey('playtest-speed'),
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(value: 1, label: Text('1×')),
                    ButtonSegment(value: 10, label: Text('10×')),
                    ButtonSegment(value: 60, label: Text('60×')),
                    ButtonSegment(value: 600, label: Text('600×')),
                  ],
                  selected: {controller.speed},
                  onSelectionChanged: (v) {
                    controller.speed = v.first;
                    setSheet(() {});
                  },
                ),
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
  );
}
