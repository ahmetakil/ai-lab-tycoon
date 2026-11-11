// Plain-language summaries of the grid that teach the two placement lessons:
// the network bottleneck (slowest switch caps the cluster) and heat.
import 'package:flutter/material.dart';

import '../../sim/content.dart';
import '../../sim/game.dart';
import '../format.dart';
import '../theme.dart';

class ClusterSummary {
  /// "Training cluster: 24 GPUs on 5 Gbit switch (feeds 8) → 58% scaling".
  final String line;

  /// What to do about it, if anything.
  final String? hint;

  /// True when the cluster is network-bound (scaling efficiency < 1).
  final bool bottlenecked;
  final double efficiency;

  const ClusterSummary(this.line, this.hint, this.bottlenecked, this.efficiency);
}

String _gpus(double n) => '${formatNumber(n)} GPU${n == 1 ? '' : 's'}';

/// The training cluster, explained.
ClusterSummary trainingSummary(Game g) {
  final c = g.trainingCluster;
  if (c == null) {
    return const ClusterSummary('No GPUs yet: place one to start training.', null, false, 1);
  }
  final eff = c.scalingEfficiency;
  if (!c.networked) {
    return ClusterSummary(
      'Training cluster: ${_gpus(c.gpus)}, no switch.',
      'Put a switch between GPUs so they train together.',
      false,
      eff,
    );
  }
  final sw = tileById(c.bottleneckTileId ?? '');
  final swName = sw?.name ?? 'switch';
  final line =
      'Training cluster: ${_gpus(c.gpus)} on $swName (feeds ${formatNumber(c.gpuCap)}) '
      '→ ${formatPercent(eff)} scaling efficiency';
  if (eff >= 1) return ClusterSummary(line, null, false, eff);
  // Suggest the cheapest faster switch the player could use in that room.
  final faster = [
    for (final t in g.tilesForRoom(c.roomId))
      if (t.isNetwork && t.gpuCap > c.gpuCap && g.isTileUnlocked(t)) t,
  ];
  final next = faster.isEmpty ? null : faster.first;
  final hint =
      next == null
          ? 'Your $swName can only keep ${formatNumber(c.gpuCap)} GPUs fed. '
              'Research faster networking.'
          : 'Your $swName can only keep ${formatNumber(c.gpuCap)} GPUs fed. '
              'Swap it for a ${next.name} (feeds ${formatNumber(next.gpuCap)}).';
  return ClusterSummary(line, hint, true, eff);
}

/// GPU tiles throttling from heat, in one room (or every owned room).
int throttlingTiles(Game g, {String? roomId}) {
  var n = 0;
  for (final room in g.ownedRooms) {
    if (roomId != null && room.id != roomId) continue;
    for (var y = 0; y < room.height; y++) {
      for (var x = 0; x < room.width; x++) {
        final st = g.tileStatus(room.id, x, y);
        if (st != null && st.def.isGpu && st.throttling) n++;
      }
    }
  }
  return n;
}

String? heatHint(Game g, {String? roomId}) {
  final n = throttlingTiles(g, roomId: roomId);
  if (n == 0) return null;
  final what = n == 1 ? '1 GPU is' : '$n GPUs are';
  return '$what throttling: put a cooler next to ${n == 1 ? 'it' : 'them'}.';
}

/// Compact card with the cluster line and the hints; used on the Lab tab and
/// above the grid.
class ClusterSummaryCard extends StatelessWidget {
  final Game game;
  final String? roomId;
  final bool dense;
  const ClusterSummaryCard({super.key, required this.game, this.roomId, this.dense = false});

  @override
  Widget build(BuildContext context) {
    final sum = trainingSummary(game);
    final heat = heatHint(game, roomId: roomId);
    final color = sum.bottlenecked ? AppColors.amber : AppColors.neon;
    final size = dense ? 12.0 : 13.0;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: dense ? 7 : 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 1),
                child: Icon(Icons.hub, size: size + 3, color: color),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  sum.line,
                  maxLines: dense ? 2 : 3,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppColors.text,
                    fontSize: size,
                    fontWeight: FontWeight.w600,
                    height: 1.25,
                  ),
                ),
              ),
            ],
          ),
          if (sum.hint != null)
            _HintLine(
              icon: Icons.lightbulb_outline,
              color: color,
              text: sum.hint!,
              size: size,
              dense: dense,
            ),
          if (heat != null)
            _HintLine(
              icon: Icons.local_fire_department,
              color: AppColors.red,
              text: heat,
              size: size,
              dense: dense,
            ),
        ],
      ),
    );
  }
}

class _HintLine extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String text;
  final double size;
  final bool dense;
  const _HintLine({
    required this.icon,
    required this.color,
    required this.text,
    required this.size,
    required this.dense,
  });

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 4),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Icon(icon, size: size + 2, color: color),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            maxLines: dense ? 2 : 3,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: color, fontSize: size - 0.5, height: 1.25),
          ),
        ),
      ],
    ),
  );
}
