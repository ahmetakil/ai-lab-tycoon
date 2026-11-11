// Power supply card: current tier, usage meter and the next tier to buy.
import 'package:flutter/material.dart';

import '../../sim/content.dart';
import '../../sim/game.dart';
import '../format.dart';
import '../game_assets.dart';
import '../game_controller.dart';
import '../sound.dart';
import '../theme.dart';
import 'buy.dart';
import 'hud.dart';
import 'meters.dart';
import 'panel.dart';

/// Lives in the Datacenter tab's power sheet.
class PowerCard extends StatelessWidget {
  final GameController controller;
  const PowerCard({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    final g = controller.game;
    final tier = powerTiers[g.s.powerTier];
    final frac = g.powerCapKw <= 0 ? 0.0 : g.powerUsedKw / g.powerCapKw;
    final color =
        frac >= 0.97
            ? AppColors.red
            : frac >= 0.8
            ? AppColors.amber
            : AppColors.cyan;
    final next = g.nextPowerTier;
    return Panel(
      accent: frac >= 0.97 ? AppColors.amber : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              GameImage(GameArt.power(tier.id), size: 52, fallback: Icons.bolt),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('CURRENT SUPPLY', style: labelStyle(size: 10)),
                    Text(
                      tier.name,
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                    ),
                    Text(
                      tier.blurb,
                      style: const TextStyle(color: AppColors.muted, fontSize: 12.5),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Text('In use', style: const TextStyle(color: AppColors.muted, fontSize: 12.5)),
              const Spacer(),
              Text(
                '${formatPower(g.powerUsedKw)} / ${formatPower(g.powerCapKw)}',
                style: numStyle(size: 13, color: color),
              ),
            ],
          ),
          const SizedBox(height: 6),
          MeterBar(value: frac, color: color, height: 10),
          if (frac >= 0.97) ...[
            const SizedBox(height: 6),
            const Text(
              'At the power cap: upgrade your supply or buy more efficient GPUs.',
              style: TextStyle(color: AppColors.amber, fontSize: 12.5),
            ),
          ],
          if (next != null) ...[
            const SizedBox(height: 14),
            const Divider(height: 1),
            const SizedBox(height: 14),
            _nextTier(g, next),
          ],
        ],
      ),
    );
  }

  Widget _nextTier(Game g, PowerDef next) {
    final unlocked = g.isUnlocked(next.era);
    final affordable = g.s.money >= next.cost;
    return Opacity(
      opacity: unlocked ? 1 : 0.55,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              GameImage(GameArt.power(next.id), size: 44, fallback: Icons.electrical_services),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('NEXT', style: labelStyle(size: 10, color: AppColors.neon)),
                    Text(
                      next.name,
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                    ),
                    Text(
                      next.blurb,
                      style: const TextStyle(color: AppColors.muted, fontSize: 12.5),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Tag(
                'cap ${formatPower(next.capacityKw)}',
                color: AppColors.cyan,
                icon: Icons.bolt,
                mono: true,
              ),
              const SizedBox(width: 6),
              Tag(
                '×${formatNumber(next.capacityKw / g.powerCapKw)}',
                color: AppColors.neon,
                mono: true,
              ),
              const Spacer(),
              if (!unlocked)
                Tag(
                  'Unlocks in ${next.era.label}',
                  color: eraColor(next.era),
                  icon: Icons.lock_outline,
                )
              else
                BuyButton(
                  label: 'Upgrade',
                  sublabel: formatMoney(next.cost),
                  icon: Icons.upgrade,
                  enabled: affordable,
                  onBuy: () {
                    final ok = controller.act((g) => g.buyNextPowerTier());
                    Sound.play(ok ? Sfx.upgrade : Sfx.error);
                  },
                ),
            ],
          ),
          if (unlocked && !affordable) ...[
            const SizedBox(height: 8),
            AffordBar(money: g.s.money, cost: next.cost),
          ],
        ],
      ),
    );
  }
}
