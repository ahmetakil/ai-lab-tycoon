// Info card for a placed tile: stats, cluster role, move / sell / upgrade in place.
import 'package:flutter/material.dart';

import '../../sim/content.dart';
import '../../sim/game.dart';
import '../format.dart';
import '../game_assets.dart';
import '../theme.dart';
import '../widgets/buy.dart';
import '../widgets/effects.dart';
import '../widgets/panel.dart';
import '../world/room_grid.dart';

// --- Tile info sheet -----------------------------------------------------------------

class TileSheet extends StatelessWidget {
  final Game game;
  final String roomId;
  final int x, y;
  final VoidCallback onMove;
  final VoidCallback onSell;
  final ValueChanged<TileDef> onReplace;

  const TileSheet({
    super.key,
    required this.game,
    required this.roomId,
    required this.x,
    required this.y,
    required this.onMove,
    required this.onSell,
    required this.onReplace,
  });

  @override
  Widget build(BuildContext context) {
    final g = game;
    final st = g.tileStatus(roomId, x, y);
    if (st == null) return const SizedBox(height: 120);
    final t = st.def;
    final color = kindColor(t.kind);
    final cluster =
        st.clusterId == null
            ? null
            : g.clusters(roomId).where((cl) => cl.id == st.clusterId).firstOrNull;
    final sellBlock = g.sellBlockReason(roomId, x, y);
    final upgrades =
        [
          for (final o in g.tilesForRoom(roomId))
            if (o.kind == t.kind && o.id != t.id && o.cost > t.cost && g.isTileUnlocked(o)) o,
        ].take(3).toList();

    final chips = <Widget>[];
    if (t.isGpu) {
      chips.addAll([
        _Stat(
          label: 'SPEED',
          value: formatPercent(st.speed),
          color: st.throttling ? AppColors.red : AppColors.neon,
        ),
        _Stat(
          label: st.netHeat > 0 ? 'HEAT OVER' : 'HEADROOM',
          value: formatNumber(st.netHeat.abs()),
          color: st.netHeat > 0 ? AppColors.red : AppColors.cyan,
        ),
        _Stat(label: 'TFLOPS', value: formatNumber(st.effectiveTflops), color: AppColors.text),
      ]);
    } else if (t.isCooling) {
      chips.addAll([
        _Stat(label: 'COOLING', value: formatNumber(t.cooling), color: AppColors.cyan),
        _Stat(
          label: 'SHARED BY',
          value: '${st.adjacentGpus} GPU${st.adjacentGpus == 1 ? '' : 's'}',
          color: st.adjacentGpus == 0 ? AppColors.red : AppColors.text,
        ),
        _Stat(label: 'POWER', value: formatPower(t.powerKw), color: AppColors.amber),
      ]);
    } else {
      chips.addAll([
        _Stat(label: 'FEEDS', value: '${formatNumber(t.gpuCap)} GPUs', color: AppColors.amber),
        _Stat(label: 'LINK', value: '${formatNumber(t.linkGbps)} Gbps', color: AppColors.text),
        _Stat(
          label: 'CLUSTER',
          value: cluster == null ? '—' : '${formatNumber(cluster.gpus)} GPUs',
          color: AppColors.cyan,
        ),
      ]);
    }

    final String clusterText;
    final Color clusterColor;
    if (t.isCooling) {
      clusterText =
          st.adjacentGpus == 0
              ? 'Touching no GPU, so this cooling is wasted. Move it next to a GPU.'
              : 'Splits ${formatNumber(t.cooling)} cooling between ${st.adjacentGpus} adjacent GPU tile${st.adjacentGpus == 1 ? '' : 's'}.';
      clusterColor = st.adjacentGpus == 0 ? AppColors.red : AppColors.cyan;
    } else if (cluster == null) {
      clusterText = 'Not connected to any GPU yet. Put GPUs next to it.';
      clusterColor = AppColors.muted;
    } else {
      final role =
          st.inTrainingCluster
              ? 'Part of your training cluster'
              : cluster.networked
              ? 'In a serving cluster'
              : 'Not networked: serves users on its own';
      final size = '${formatNumber(cluster.gpus)} GPUs';
      final eff = cluster.networked ? ', ${formatPercent(cluster.scalingEfficiency)} scaling' : '';
      final bottleneck =
          t.isNetwork && cluster.bottleneckTileId == t.id && cluster.scalingEfficiency < 1
              ? ' This switch is the bottleneck.'
              : '';
      clusterText = '$role ($size$eff).$bottleneck';
      clusterColor = st.inTrainingCluster ? AppColors.neon : AppColors.cyan;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: AppColors.bg,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: color.withValues(alpha: 0.4)),
              ),
              child: Image.asset(GameArt.tile(t.id)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Tag(kindLabel(t.kind).toUpperCase(), color: color, icon: kindIcon(t.kind)),
                  const SizedBox(height: 4),
                  Text(t.name, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700)),
                  if (t.isGpu)
                    Text(
                      '${formatNumber(t.gpusPerTile)} GPU${t.gpusPerTile == 1 ? '' : 's'} · ${formatNumber(t.tflops)} TFLOPS peak · ${formatPower(g.tilePowerKw(t))}',
                      style: numStyle(size: 11, color: AppColors.muted, weight: FontWeight.w500),
                    ),
                ],
              ),
            ),
          ],
        ),
        gap12,
        Text(t.blurb, style: const TextStyle(color: AppColors.text, fontSize: 13.5, height: 1.35)),
        gap12,
        Row(
          children: [
            for (final (i, chip) in chips.indexed) ...[
              if (i > 0) const SizedBox(width: 8),
              Expanded(child: chip),
            ],
          ],
        ),
        gap8,
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: clusterColor.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: clusterColor.withValues(alpha: 0.3)),
          ),
          child: Text(
            clusterText,
            style: TextStyle(color: clusterColor, fontSize: 12.5, height: 1.3),
          ),
        ),
        if (t.isGpu && st.throttling) ...[
          gap8,
          const Text(
            'Too hot: it throttles. Put a cooler on an adjacent cell, or spread GPUs out.',
            style: TextStyle(color: AppColors.red, fontSize: 12.5, height: 1.3),
          ),
        ],
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: NeonButton(
                key: const ValueKey('tile-move'),
                label: 'Move',
                icon: Icons.open_with,
                color: AppColors.cyan,
                filled: false,
                dense: true,
                expand: true,
                onPressed: onMove,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: BuyButton(
                key: const ValueKey('tile-sell'),
                label: 'Sell',
                sublabel: '+${formatMoney(g.sellValue(t.id))}',
                icon: Icons.sell_outlined,
                color: AppColors.amber,
                expand: true,
                enabled: sellBlock == null,
                onBuy: onSell,
              ),
            ),
          ],
        ),
        if (sellBlock != null) ...[
          const SizedBox(height: 6),
          Text(
            sellBlock,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.muted, fontSize: 12),
          ),
        ],
        if (upgrades.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text('UPGRADE IN PLACE', style: labelStyle(size: 10)),
          const SizedBox(height: 6),
          for (final o in upgrades) ...[
            _ReplaceRow(game: g, roomId: roomId, x: x, y: y, to: o, onReplace: onReplace),
            gap8,
          ],
        ],
      ],
    );
  }
}

class _ReplaceRow extends StatelessWidget {
  final Game game;
  final String roomId;
  final int x, y;
  final TileDef to;
  final ValueChanged<TileDef> onReplace;
  const _ReplaceRow({
    required this.game,
    required this.roomId,
    required this.x,
    required this.y,
    required this.to,
    required this.onReplace,
  });

  @override
  Widget build(BuildContext context) {
    final g = game;
    final old = tileById(g.tileAt(roomId, x, y)!)!;
    final reason = g.replaceBlockReason(roomId, x, y, to.id);
    final price = g.tilePrice(to) - g.sellValue(old.id);
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 6, 6, 6),
      decoration: BoxDecoration(
        color: AppColors.bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          SizedBox(width: 38, height: 38, child: Image.asset(GameArt.tile(to.id))),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  to.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                ),
                Text(
                  reason ?? tileStatsLine(g, to),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: reason == null ? AppColors.muted : AppColors.amber,
                    fontSize: 11,
                    height: 1.2,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          BuyButton(
            label: 'Swap',
            sublabel: formatMoney(price),
            icon: Icons.upgrade,
            enabled: reason == null,
            onBuy: () => onReplace(to),
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _Stat({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    decoration: BoxDecoration(
      color: AppColors.bg,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: AppColors.border),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, maxLines: 1, overflow: TextOverflow.clip, style: labelStyle(size: 9.5)),
        const SizedBox(height: 3),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(value, style: numStyle(size: 16, weight: FontWeight.w800, color: color)),
        ),
      ],
    ),
  );
}
