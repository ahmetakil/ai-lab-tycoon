// Network and central-cooling tier cards (like the power card): what you
// have, how much of it you use, and the next tier to buy.
import 'package:flutter/material.dart';

import '../format.dart';
import '../game_assets.dart';
import '../game_controller.dart';
import '../grid/grid_hints.dart';
import '../sound.dart';
import '../theme.dart';
import 'buy.dart';
import 'meters.dart';
import 'panel.dart';

/// The network tier: every GPU in the room is cabled into one cluster; the
/// tier sets how many GPUs it keeps fed.
class NetworkCard extends StatelessWidget {
  final GameController controller;
  const NetworkCard({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    final g = controller.game;
    final net = g.network;
    final c = g.trainingCluster;
    final gpus = c?.gpus ?? 0;
    final color = networkMeterColor(g);
    final frac = g.networkCap <= 0 ? 0.0 : gpus / g.networkCap;
    final String explain;
    if (c == null) {
      explain = 'No GPUs yet.';
    } else if (c.gpuCells.length == 1) {
      explain =
          'One GPU tile: it trains on its own, no network needed yet. Add GPUs and '
          'they\'re cabled together automatically.';
    } else if (c.overCap) {
      explain =
          '${net.name} keeps ${formatNumber(g.networkCap)} GPUs fed, but your cluster has '
          '${formatNumber(gpus)}. GPUs wait on each other to sync, so training runs at '
          '${formatPercent(c.scalingEfficiency)} (√(${formatNumber(g.networkCap)}/${formatNumber(gpus)})).';
    } else {
      explain =
          'All ${formatNumber(gpus)} GPUs train together at full speed. Past '
          '${formatNumber(g.networkCap)} GPUs, runs slow down until you upgrade.';
    }
    final next = g.nextNetworkTier;
    return Panel(
      accent: c != null && c.overCap ? AppColors.red : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Header(
            icon: GameImage(GameArt.networkTier(net.id), size: 52, fallback: Icons.cable),
            label: 'CURRENT NETWORK',
            name: net.name,
            blurb: net.blurb,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Expanded(
                child: Text('GPUs fed', style: TextStyle(color: AppColors.muted, fontSize: 12.5)),
              ),
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: Text(networkMeterText(g), style: numStyle(size: 13, color: color)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          MeterBar(value: frac.clamp(0.0, 1.0), color: color, height: 10),
          const SizedBox(height: 8),
          Text(
            explain,
            key: const ValueKey('network-explain'),
            style: TextStyle(
              color: c != null && c.overCap ? AppColors.red : AppColors.muted,
              fontSize: 12.5,
              height: 1.3,
            ),
          ),
          if (next != null) ...[
            const SizedBox(height: 14),
            const Divider(height: 1),
            const SizedBox(height: 14),
            _NextTier(
              icon: GameImage(GameArt.networkTier(next.id), size: 44, fallback: Icons.cable),
              name: next.name,
              blurb: next.blurb,
              tags: [
                Tag('feeds ${formatNumber(next.gpuCap)} GPUs', color: AppColors.cyan, icon: Icons.hub, mono: true),
                Tag('${formatNumber(next.linkGbps)} Gbps', color: AppColors.neon, mono: true),
              ],
              cost: next.cost,
              reason: g.networkBlockReason(),
              buyKey: const ValueKey('buy-network'),
              onBuy: () {
                final ok = controller.act((g) => g.buyNextNetworkTier());
                Sound.play(ok ? Sfx.upgrade : Sfx.error);
              },
              money: g.s.money,
            ),
          ],
        ],
      ),
    );
  }
}

/// Central cooling: a plant that cools every GPU tile, on top of the room's
/// free cooling and any cooler tiles.
class CoolingCard extends StatelessWidget {
  final GameController controller;
  const CoolingCard({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    final g = controller.game;
    final cur = g.cooling;
    final hot = throttlingTiles(g);
    final next = g.nextCoolingTier;
    return Panel(
      accent: hot > 0 ? AppColors.red : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Header(
            icon: GameImage(GameArt.coolingTier(cur.id), size: 52, fallback: Icons.ac_unit),
            label: 'CENTRAL COOLING',
            name: cur.name,
            blurb: cur.blurb,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Expanded(
                child: Text('Per GPU tile', style: TextStyle(color: AppColors.muted, fontSize: 12.5)),
              ),
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: Text(
                    '−${formatNumber(cur.perGpuTile)} heat',
                    style: numStyle(size: 13, color: AppColors.cyan),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            hot == 0
                ? 'No GPU is throttling.'
                : '$hot GPU tile${hot == 1 ? ' is' : 's are'} throttling from heat.',
            style: TextStyle(color: hot == 0 ? AppColors.neon : AppColors.red, fontSize: 12.5),
          ),
          const SizedBox(height: 4),
          const Text(
            'Coolers still help their neighbours; a plant cools every GPU tile, so big rooms '
            'are about capacity rather than placing coolers.',
            style: TextStyle(color: AppColors.muted, fontSize: 12, height: 1.3),
          ),
          if (next != null) ...[
            const SizedBox(height: 14),
            const Divider(height: 1),
            const SizedBox(height: 14),
            _NextTier(
              icon: GameImage(GameArt.coolingTier(next.id), size: 44, fallback: Icons.ac_unit),
              name: next.name,
              blurb: next.blurb,
              tags: [
                Tag('−${formatNumber(next.perGpuTile)} heat / GPU tile', color: AppColors.cyan, icon: Icons.ac_unit, mono: true),
              ],
              cost: next.cost,
              reason: g.coolingBlockReason(),
              buyKey: const ValueKey('buy-cooling'),
              onBuy: () {
                final ok = controller.act((g) => g.buyNextCoolingTier());
                Sound.play(ok ? Sfx.upgrade : Sfx.error);
              },
              money: g.s.money,
            ),
          ],
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final Widget icon;
  final String label, name, blurb;
  const _Header({required this.icon, required this.label, required this.name, required this.blurb});

  @override
  Widget build(BuildContext context) => Row(
    children: [
      icon,
      const SizedBox(width: 12),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: labelStyle(size: 10)),
            Text(name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            Text(blurb, style: const TextStyle(color: AppColors.muted, fontSize: 12.5)),
          ],
        ),
      ),
    ],
  );
}

/// "NEXT" block: icon, name, tags and a buy button; the lock reason (era
/// gate spelled out, missing research) when it can't be bought yet.
class _NextTier extends StatelessWidget {
  final Widget icon;
  final String name, blurb;
  final List<Widget> tags;
  final double cost;
  final double money;
  final String? reason;
  final Key buyKey;
  final VoidCallback onBuy;

  const _NextTier({
    required this.icon,
    required this.name,
    required this.blurb,
    required this.tags,
    required this.cost,
    required this.money,
    required this.reason,
    required this.buyKey,
    required this.onBuy,
  });

  @override
  Widget build(BuildContext context) {
    final onlyMoney = reason == null || reason!.startsWith('Costs');
    return Opacity(
      opacity: onlyMoney ? 1 : 0.75,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              icon,
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('NEXT', style: labelStyle(size: 10, color: AppColors.neon)),
                    Text(name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                    Text(blurb, style: const TextStyle(color: AppColors.muted, fontSize: 12.5)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: Wrap(spacing: 6, runSpacing: 6, children: tags)),
              const SizedBox(width: 8),
              BuyButton(
                key: buyKey,
                label: 'Upgrade',
                sublabel: formatMoney(cost),
                icon: Icons.upgrade,
                enabled: reason == null,
                onBuy: onBuy,
              ),
            ],
          ),
          if (reason != null && !onlyMoney) ...[
            const SizedBox(height: 8),
            Text(reason!, style: const TextStyle(color: AppColors.amber, fontSize: 12.5, height: 1.3)),
          ],
          if (reason != null && onlyMoney) ...[
            const SizedBox(height: 8),
            AffordBar(money: money, cost: cost),
          ],
        ],
      ),
    );
  }
}
