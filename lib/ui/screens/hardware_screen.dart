// OWNER: ui-core agent. The "Hardware" tab: power first, then GPUs.
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../sim/content.dart';
import '../../sim/game.dart';
import '../format.dart';
import '../game_assets.dart';
import '../game_controller.dart';
import '../sound.dart';
import '../theme.dart';
import '../widgets/buy.dart';
import '../widgets/effects.dart';
import '../widgets/game_builder.dart';
import '../widgets/hud.dart';
import '../widgets/meters.dart';
import '../widgets/panel.dart';

class HardwareScreen extends StatelessWidget {
  final GameController controller;
  const HardwareScreen({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return GameBuilder(
      controller: controller,
      builder: (context) {
        final g = controller.game;
        final unlocked = hardware.where((h) => g.isUnlocked(h.era)).toList();
        final bestEff = unlocked.map((h) => h.tflopsPerKw).fold(0.0, math.max);
        return TabScroll(
          children: [
            const SectionTitle(
              'Power',
              subtitle: 'Every GPU draws power. The cap decides how many you can run.',
            ),
            _PowerCard(controller: controller),
            const SectionTitle(
              'GPUs',
              subtitle: 'Raw compute. Compare TFLOPS per kW when power is tight.',
            ),
            for (final h in hardware) ...[
              _GpuCard(controller: controller, h: h, bestEfficiency: h.tflopsPerKw >= bestEff),
              gap12,
            ],
          ],
        );
      },
    );
  }
}

class _PowerCard extends StatelessWidget {
  final GameController controller;
  const _PowerCard({required this.controller});

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

class _GpuCard extends StatelessWidget {
  final GameController controller;
  final HardwareDef h;
  final bool bestEfficiency;
  const _GpuCard({required this.controller, required this.h, required this.bestEfficiency});

  @override
  Widget build(BuildContext context) {
    final g = controller.game;
    final unlocked = g.isUnlocked(h.era);
    final owned = g.s.hardwareCounts[h.id] ?? 0;
    final maxBuy = g.maxBuyable(h);
    final headroom = g.powerCapKw - g.powerUsedKw;
    final byPower = (headroom / (h.powerKw * g.powerMult) + 1e-9).floor();
    final powerBlocked = unlocked && byPower < 1;
    final affordable = g.s.money >= h.cost;

    final header = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 68,
          height: 68,
          decoration: BoxDecoration(
            color: AppColors.bg,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.border),
          ),
          child: Center(child: GameImage(GameArt.hardware(h.id), size: 60, fallback: Icons.memory)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      h.name,
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15.5),
                    ),
                  ),
                  if (unlocked)
                    PopOnChange(
                      trigger: owned,
                      scale: 1.4,
                      child: Text(
                        '×$owned',
                        style: numStyle(
                          size: 18,
                          weight: FontWeight.w800,
                          color: owned > 0 ? AppColors.neon : AppColors.faint,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                h.blurb,
                style: const TextStyle(color: AppColors.muted, fontSize: 12.5, height: 1.3),
              ),
            ],
          ),
        ),
      ],
    );

    final stats = Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        Tag('${formatNumber(h.tflops)} TFLOPS', color: AppColors.cyan, mono: true),
        Tag(
          formatPower(h.powerKw * g.powerMult),
          color: AppColors.amber,
          icon: Icons.bolt,
          mono: true,
        ),
        Tag(
          '${formatNumber(h.tflops / (h.powerKw * g.powerMult))} TFLOPS/kW',
          color: bestEfficiency && unlocked ? AppColors.neon : AppColors.muted,
          icon: bestEfficiency && unlocked ? Icons.eco_outlined : null,
          mono: true,
        ),
      ],
    );

    if (!unlocked) {
      return Panel(
        opacity: 0.5,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            header,
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(child: stats),
                Tag('Unlocks in ${h.era.label}', color: eraColor(h.era), icon: Icons.lock_outline),
              ],
            ),
          ],
        ),
      );
    }

    void buy(int n) {
      final ok = controller.act((g) => g.buyHardware(h.id, n));
      Sound.play(ok ? Sfx.purchase : Sfx.error);
    }

    Widget actions;
    if (!g.isHardwareAvailable(h)) {
      // Era is unlocked but prerequisites (cooling upgrade / power tier) aren't.
      final missing = [
        for (final id in h.requires)
          if (!g.s.ownedUpgrades.contains(id))
            upgrades.firstWhere((u) => u.id == id).name,
        if (g.s.powerTier < h.minPowerTier) powerTiers[h.minPowerTier].name,
      ];
      actions = BuyButton(
        label: 'Requires: ${missing.join(' + ')}',
        sublabel: 'this hardware needs serious cooling and power',
        icon: Icons.lock_outline,
        color: AppColors.amber,
        enabled: false,
        expand: true,
        onBuy: () {},
      );
    } else if (powerBlocked) {
      actions = BuyButton(
        label: 'Needs more power',
        sublabel: 'upgrade your supply above',
        icon: Icons.power_off_outlined,
        color: AppColors.amber,
        enabled: false,
        expand: true,
        onBuy: () {},
      );
    } else {
      actions = Row(
        children: [
          Expanded(
            flex: 4,
            child: BuyButton(
              label: 'Buy',
              sublabel: formatMoney(h.cost),
              enabled: maxBuy >= 1,
              expand: true,
              onBuy: () => buy(1),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 3,
            child: BuyButton(
              label: '×10',
              sublabel: formatMoney(h.cost * 10),
              enabled: maxBuy >= 10,
              color: AppColors.cyan,
              expand: true,
              onBuy: () => buy(10),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 3,
            child: BuyButton(
              label: 'Max',
              sublabel: maxBuy > 0 ? '×$maxBuy' : '—',
              enabled: maxBuy >= 1,
              color: AppColors.cyan,
              expand: true,
              onBuy: () => buy(maxBuy),
            ),
          ),
        ],
      );
    }

    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          header,
          const SizedBox(height: 10),
          stats,
          const SizedBox(height: 12),
          actions,
          if (!powerBlocked && !affordable) ...[
            const SizedBox(height: 8),
            AffordBar(money: g.s.money, cost: h.cost),
          ],
          if (!powerBlocked &&
              affordable &&
              byPower < 10 &&
              byPower < (g.s.money / h.cost).floor()) ...[
            const SizedBox(height: 6),
            Text(
              'Power for only $byPower more',
              style: const TextStyle(color: AppColors.amber, fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }
}
