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

/// Lives in the Power sheet. When the next tier needs a bigger building, it
/// shows why and a button that calls [onMove] with the room to move to.
class PowerCard extends StatelessWidget {
  final GameController controller;
  final void Function(RoomDef room)? onMove;
  const PowerCard({super.key, required this.controller, this.onMove});

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
              const Expanded(
                child: Text('In use', style: TextStyle(color: AppColors.muted, fontSize: 12.5)),
              ),
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: Text(
                    '${formatPower(g.powerUsedKw)} / ${formatPower(g.powerCapKw)}',
                    style: numStyle(size: 13, color: color),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          MeterBar(value: frac, color: color, height: 10),
          if (frac >= 0.97) ...[
            const SizedBox(height: 6),
            Text(
              g.powerNeedsMove
                  ? 'At the power cap: this building can\'t take more. Move, or buy more efficient GPUs.'
                  : 'At the power cap: upgrade your supply or buy more efficient GPUs.',
              style: const TextStyle(color: AppColors.amber, fontSize: 12.5),
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
    final needsMove = g.powerNeedsMove;
    final moveTo = Game.roomForPowerTier(g.s.powerTier + 1);
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
              Expanded(
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    Tag(
                      'cap ${formatPower(next.capacityKw)}',
                      color: AppColors.cyan,
                      icon: Icons.bolt,
                      mono: true,
                    ),
                    Tag(
                      '×${formatNumber(next.capacityKw / g.powerCapKw)}',
                      color: AppColors.neon,
                      mono: true,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (!unlocked)
                Tag(
                  'Locked',
                  color: eraColor(next.era),
                  icon: Icons.lock_outline,
                )
              else if (needsMove)
                BuyButton(
                  key: const ValueKey('power-move'),
                  label: 'Move',
                  sublabel: moveTo.name,
                  icon: Icons.add_business_rounded,
                  color: AppColors.amber,
                  enabled: onMove != null,
                  onBuy: () => onMove?.call(moveTo),
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
          if (needsMove) ...[
            const SizedBox(height: 8),
            Text(
              g.powerBlockReason()!,
              key: const ValueKey('power-block-reason'),
              style: const TextStyle(color: AppColors.amber, fontSize: 12.5, height: 1.3),
            ),
          ] else if (unlocked && !affordable) ...[
            const SizedBox(height: 8),
            AffordBar(money: g.s.money, cost: next.cost),
          ],
          if (!unlocked) ...[
            const SizedBox(height: 8),
            Text(
              g.eraLockReason(next.era),
              style: const TextStyle(color: AppColors.amber, fontSize: 12.5, height: 1.3),
            ),
          ],
        ],
      ),
    );
  }
}
