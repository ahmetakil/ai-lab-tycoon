// Build mode's bottom drawer: the room you're in with the Power / Network /
// Cooling chips, the training-cluster summary and the parts tray (pick a
// part, then tap glowing floor cells).
import 'package:flutter/material.dart';

import '../../sim/content.dart';
import '../../sim/game.dart';
import '../format.dart';
import '../game_assets.dart';
import '../grid/grid_hints.dart';
import '../theme.dart';
import '../widgets/effects.dart';
import '../widgets/meters.dart';
import '../world/room_grid.dart';

class BuildDrawer extends StatelessWidget {
  final Game game;
  final RoomDef room;
  final TileKind kind;
  final String? placing;
  final VoidCallback onDone;
  final ValueChanged<TileKind> onKind;
  final ValueChanged<TileDef> onPick;
  final VoidCallback onPower;
  final VoidCallback onNetwork;
  final VoidCallback onCooling;

  const BuildDrawer({
    super.key,
    required this.game,
    required this.room,
    required this.kind,
    required this.placing,
    required this.onDone,
    required this.onKind,
    required this.onPick,
    required this.onPower,
    required this.onNetwork,
    required this.onCooling,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xF00A101C),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
        border: Border.all(color: AppColors.neon.withValues(alpha: 0.4), width: 1.5),
        boxShadow: const [
          BoxShadow(color: Color(0xCC000000), blurRadius: 24, offset: Offset(0, -6)),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TierStrip(
              game: game,
              onPower: onPower,
              onNetwork: onNetwork,
              onCooling: onCooling,
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
              child: ClusterSummaryCard(game: game, roomId: room.id, dense: true),
            ),
            PartsTray(
              game: game,
              room: room,
              kind: kind,
              placing: placing,
              modeActive: true,
              onCancel: onDone,
              onKind: onKind,
              onPick: onPick,
            ),
          ],
        ),
      ),
    );
  }
}

// --- Room + tier strip ----------------------------------------------------------

/// The room you're in, then the Power, Network and (from the Medium lab)
/// Cooling chips.
class TierStrip extends StatelessWidget {
  final Game game;
  final VoidCallback onPower;
  final VoidCallback onNetwork;
  final VoidCallback onCooling;

  const TierStrip({
    super.key,
    required this.game,
    required this.onPower,
    required this.onNetwork,
    required this.onCooling,
  });

  @override
  Widget build(BuildContext context) {
    final g = game;
    final room = g.currentRoom;
    return SizedBox(
      height: 50,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
        child: Row(
          children: [
            Expanded(
              child: Column(
                key: const ValueKey('drawer-room'),
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    room.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                  ),
                  Text(
                    '${room.width}×${room.height} · 1 GPU tile = ${room.tileScaleLabel}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: numStyle(size: 10, color: AppColors.muted),
                  ),
                ],
              ),
            ),
            _PowerChip(game: g, onTap: onPower),
            const SizedBox(width: 6),
            _NetworkChip(game: g, onTap: onNetwork),
            if (g.coolingTiersVisible) ...[
              const SizedBox(width: 6),
              _CoolingChip(game: g, onTap: onCooling),
            ],
          ],
        ),
      ),
    );
  }
}

class _NetworkChip extends StatelessWidget {
  final Game game;
  final VoidCallback onTap;
  const _NetworkChip({required this.game, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final g = game;
    final c = g.trainingCluster;
    final color = networkMeterColor(g);
    final frac = c == null ? 0.0 : c.gpus / g.networkCap;
    final canUpgrade = g.nextNetworkTier != null && g.networkBlockReason() == null;
    return _Chip(
      key: const ValueKey('drawer-network'),
      icon: Icons.cable_rounded,
      text: '${formatNumber(c?.gpus ?? 0)}/${formatNumber(g.networkCap)}',
      color: color,
      frac: frac,
      canUpgrade: canUpgrade,
      pulse: canUpgrade && (c?.overCap ?? false),
      onTap: onTap,
    );
  }
}

class _CoolingChip extends StatelessWidget {
  final Game game;
  final VoidCallback onTap;
  const _CoolingChip({required this.game, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final g = game;
    final hot = throttlingTiles(g);
    final canUpgrade = g.nextCoolingTier != null && g.coolingBlockReason() == null;
    return _Chip(
      key: const ValueKey('drawer-cooling'),
      icon: Icons.ac_unit_rounded,
      text: hot > 0 ? '$hot hot' : 'cool',
      color: hot > 0 ? AppColors.red : AppColors.cyan,
      frac: g.s.coolingTier / (coolingTiers.length - 1),
      canUpgrade: canUpgrade,
      pulse: canUpgrade && hot > 0,
      onTap: onTap,
    );
  }
}

class _Chip extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color color;
  final double frac;
  final bool canUpgrade;
  final bool pulse;
  final VoidCallback onTap;
  const _Chip({
    super.key,
    required this.icon,
    required this.text,
    required this.color,
    required this.frac,
    required this.canUpgrade,
    required this.pulse,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Pulse(
      active: pulse,
      child: Container(
        width: 76,
        padding: const EdgeInsets.fromLTRB(7, 5, 6, 6),
        decoration: BoxDecoration(
          color: AppColors.surfaceHi,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: canUpgrade ? AppColors.neon.withValues(alpha: 0.7) : AppColors.border,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(
              children: [
                Icon(icon, size: 14, color: color),
                const SizedBox(width: 2),
                Expanded(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(text, style: numStyle(size: 12, color: color)),
                  ),
                ),
                Icon(
                  canUpgrade ? Icons.arrow_circle_up : Icons.chevron_right,
                  size: 15,
                  color: canUpgrade ? AppColors.neon : AppColors.muted,
                ),
              ],
            ),
            const SizedBox(height: 5),
            MeterBar(value: frac.clamp(0.0, 1.0), color: color, height: 6),
          ],
        ),
      ),
    ),
  );
}

class _PowerChip extends StatelessWidget {
  final Game game;
  final VoidCallback onTap;
  const _PowerChip({required this.game, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final g = game;
    final frac = g.powerCapKw <= 0 ? 0.0 : g.powerUsedKw / g.powerCapKw;
    final color =
        frac >= 0.97
            ? AppColors.red
            : frac >= 0.8
            ? AppColors.amber
            : AppColors.cyan;
    final next = g.nextPowerTier;
    final canUpgrade = next != null && g.isUnlocked(next.era) && g.s.money >= next.cost;
    return GestureDetector(
      key: const ValueKey('drawer-power'),
      onTap: onTap,
      child: Pulse(
        active: canUpgrade && frac >= 0.8,
        child: Container(
          width: 72,
          padding: const EdgeInsets.fromLTRB(7, 5, 6, 6),
          decoration: BoxDecoration(
            color: AppColors.surfaceHi,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: canUpgrade ? AppColors.neon.withValues(alpha: 0.7) : AppColors.border,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Row(
                children: [
                  Icon(Icons.bolt, size: 14, color: color),
                  const SizedBox(width: 2),
                  Expanded(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(formatPercent(frac), style: numStyle(size: 12, color: color)),
                    ),
                  ),
                  Icon(
                    canUpgrade ? Icons.arrow_circle_up : Icons.chevron_right,
                    size: 15,
                    color: canUpgrade ? AppColors.neon : AppColors.muted,
                  ),
                ],
              ),
              const SizedBox(height: 5),
              MeterBar(value: frac, color: color, height: 6),
            ],
          ),
        ),
      ),
    );
  }
}

// --- Parts tray -------------------------------------------------------------------

class PartsTray extends StatefulWidget {
  final Game game;
  final RoomDef room;
  final TileKind kind;
  final String? placing;
  final bool modeActive;
  final VoidCallback onCancel;
  final ValueChanged<TileKind> onKind;
  final ValueChanged<TileDef> onPick;

  const PartsTray({
    super.key,
    required this.game,
    required this.room,
    required this.kind,
    required this.placing,
    required this.modeActive,
    required this.onCancel,
    required this.onKind,
    required this.onPick,
  });

  @override
  State<PartsTray> createState() => _PartsTrayState();
}

class _PartsTrayState extends State<PartsTray> {
  /// Parts from earlier rooms still fit but are tucked into one card.
  bool _older = false;

  @override
  Widget build(BuildContext context) {
    final w = widget;
    final g = w.game;
    final room = w.room, kind = w.kind, placing = w.placing;
    // Current era's parts (and anything newer) first; older unlocked parts
    // in a collapsed group, still placeable.
    final all = [
      for (final t in g.tilesForRoom(room.id))
        if (!g.isOlderPart(t, room.id)) t,
    ];
    final parts = all.where((t) => t.kind == kind).toList();
    final older = [
      for (final t in g.tilesForRoom(room.id))
        if (t.kind == kind && g.isOlderPart(t, room.id) && g.isTileUnlocked(t)) t,
    ];
    final onKind = w.onKind, onPick = w.onPick, onCancel = w.onCancel;
    final modeActive = w.modeActive;
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: 32,
            child: Row(
              children: [
                const SizedBox(width: 8),
                for (final k in tileKinds)
                  Expanded(
                    child: _KindTab(
                      kind: k,
                      selected: k == kind,
                      count: all.where((t) => t.kind == k && g.isTileUnlocked(t)).length,
                      onTap: () => onKind(k),
                    ),
                  ),
                if (modeActive)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 5, 0, 1),
                    child: GestureDetector(
                      key: const ValueKey('cancel-mode'),
                      onTap: onCancel,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        decoration: BoxDecoration(
                          color: AppColors.red.withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(99),
                          border: Border.all(color: AppColors.red.withValues(alpha: 0.6)),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.close, size: 14, color: AppColors.red),
                            SizedBox(width: 3),
                            Text(
                              'Done',
                              style: TextStyle(
                                color: AppColors.red,
                                fontWeight: FontWeight.w700,
                                fontSize: 12.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                const SizedBox(width: 8),
              ],
            ),
          ),
          SizedBox(
            height: 96,
            child: ListView(
              key: ValueKey('tray-${room.id}-${kind.name}'),
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(12, 2, 12, 8),
              children: [
                for (final t in parts)
                  _PartCard(
                    key: ValueKey('part-${t.id}'),
                    game: g,
                    tile: t,
                    selected: placing == t.id,
                    onTap: () => onPick(t),
                  ),
                if (older.isNotEmpty)
                  _OlderToggle(
                    count: older.length,
                    open: _older || older.any((t) => t.id == placing),
                    onTap: () => setState(() => _older = !_older),
                  ),
                if (_older || older.any((t) => t.id == placing))
                  for (final t in older)
                    _PartCard(
                      key: ValueKey('part-${t.id}'),
                      game: g,
                      tile: t,
                      selected: placing == t.id,
                      onTap: () => onPick(t),
                    ),
                if (parts.isEmpty && older.isEmpty)
                  const Center(
                    child: Text(
                      'Nothing of this kind fits in this room.',
                      style: TextStyle(color: AppColors.muted, fontSize: 12.5),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// "Older parts (3)": expands the earlier rooms' parts in the tray.
class _OlderToggle extends StatelessWidget {
  final int count;
  final bool open;
  final VoidCallback onTap;
  const _OlderToggle({required this.count, required this.open, required this.onTap});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(right: 8),
    child: GestureDetector(
      key: const ValueKey('tray-older'),
      onTap: onTap,
      child: Container(
        width: 76,
        decoration: BoxDecoration(
          color: AppColors.bg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(open ? Icons.chevron_left : Icons.inventory_2_outlined, color: AppColors.muted, size: 20),
            const SizedBox(height: 4),
            Text(
              open ? 'Hide older' : 'Older parts ($count)',
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.muted, fontSize: 11, height: 1.15),
            ),
          ],
        ),
      ),
    ),
  );
}

class _KindTab extends StatelessWidget {
  final TileKind kind;
  final bool selected;
  final int count;
  final VoidCallback onTap;
  const _KindTab({
    required this.kind,
    required this.selected,
    required this.count,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = selected ? kindColor(kind) : AppColors.muted;
    return GestureDetector(
      key: ValueKey('kind-${kind.name}'),
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        margin: const EdgeInsets.fromLTRB(4, 5, 4, 1),
        decoration: BoxDecoration(
          color: selected ? color.withValues(alpha: 0.12) : Colors.transparent,
          borderRadius: BorderRadius.circular(99),
          border: Border.all(color: selected ? color.withValues(alpha: 0.5) : AppColors.border),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(kindIcon(kind), size: 14, color: color),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                kindLabel(kind),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 12.5),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PartCard extends StatelessWidget {
  final Game game;
  final TileDef tile;
  final bool selected;
  final VoidCallback onTap;
  const _PartCard({
    super.key,
    required this.game,
    required this.tile,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final g = game;
    final t = tile;
    final locked = g.tileLockReason(t);
    final price = g.tilePrice(t);
    final affordable = g.s.money >= price;
    final color = kindColor(t.kind);
    final border =
        selected
            ? color
            : locked != null
            ? AppColors.border
            : AppColors.borderHi;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedScale(
          duration: const Duration(milliseconds: 160),
          scale: selected ? 1.0 : 0.97,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            width: 140,
            padding: const EdgeInsets.fromLTRB(7, 6, 7, 5),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  selected
                      ? Color.alphaBlend(color.withValues(alpha: 0.16), AppColors.surfaceHi)
                      : AppColors.surfaceHi,
                  AppColors.bg,
                ],
              ),
              border: Border.all(color: border, width: selected ? 2 : 1),
              boxShadow: [
                if (selected) BoxShadow(color: color.withValues(alpha: 0.35), blurRadius: 12),
              ],
            ),
            child: Opacity(
              opacity: locked != null ? 0.5 : 1,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      SizedBox(
                        width: 34,
                        height: 34,
                        child: Image.asset(
                          GameArt.tile(t.id),
                          errorBuilder:
                              (_, __, ___) => Icon(kindIcon(t.kind), color: color, size: 24),
                        ),
                      ),
                      const SizedBox(width: 5),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              t.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
                            ),
                            const SizedBox(height: 1),
                            if (locked != null)
                              const Icon(Icons.lock, size: 14, color: AppColors.muted)
                            else
                              FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  formatMoney(price),
                                  style: numStyle(
                                    size: 12.5,
                                    weight: FontWeight.w800,
                                    color: affordable ? AppColors.neon : AppColors.red,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Expanded(
                    child: Text(
                      locked ?? tileStatsLine(g, t),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style:
                          locked != null
                              ? const TextStyle(color: AppColors.amber, fontSize: 10, height: 1.2)
                              : numStyle(
                                size: 9.5,
                                color: AppColors.muted,
                                weight: FontWeight.w500,
                              ).copyWith(height: 1.25),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
