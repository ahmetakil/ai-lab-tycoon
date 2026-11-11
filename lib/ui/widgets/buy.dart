import 'package:flutter/material.dart';

import '../sound.dart';
import '../theme.dart';
import 'effects.dart';
import 'meters.dart';

/// A buy button that still reacts when you can't afford it (error sound)
/// instead of being silently dead.
class BuyButton extends StatelessWidget {
  final String label;
  final String? sublabel;
  final bool enabled;
  final VoidCallback onBuy;
  final Color color;
  final IconData? icon;
  final bool expand;
  final bool dense;

  const BuyButton({
    super.key,
    required this.label,
    required this.enabled,
    required this.onBuy,
    this.sublabel,
    this.color = AppColors.neon,
    this.icon,
    this.expand = false,
    this.dense = true,
  });

  @override
  Widget build(BuildContext context) {
    final button = NeonButton(
      label: label,
      sublabel: sublabel,
      icon: icon,
      color: color,
      dense: dense,
      expand: expand,
      onPressed: enabled ? onBuy : null,
    );
    if (enabled) return button;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => Sound.play(Sfx.error),
      child: button,
    );
  }
}

/// "Saving up" bar shown under unaffordable items: money / cost.
class AffordBar extends StatelessWidget {
  final double money;
  final double cost;
  const AffordBar({super.key, required this.money, required this.cost});

  @override
  Widget build(BuildContext context) =>
      MeterBar(value: cost <= 0 ? 1 : money / cost, color: AppColors.faint, height: 4);
}
