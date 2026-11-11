// Build mode's bottom drawer: room picker, the training-cluster summary and
// the parts tray (pick a part, then tap glowing floor cells).
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
  final ValueChanged<String> onSelectRoom;
  final ValueChanged<RoomDef> onNextRoom;
  final VoidCallback onPower;

  const BuildDrawer({
    super.key,
    required this.game,
    required this.room,
    required this.kind,
    required this.placing,
    required this.onDone,
    required this.onKind,
    required this.onPick,
    required this.onSelectRoom,
    required this.onNextRoom,
    required this.onPower,
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
            RoomStrip(
              game: game,
              selected: room.id,
              onSelect: onSelectRoom,
              onNextRoom: onNextRoom,
              onPower: onPower,
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

// --- Room strip -------------------------------------------------------------------

class RoomStrip extends StatelessWidget {
  final Game game;
  final String selected;
  final ValueChanged<String> onSelect;
  final ValueChanged<RoomDef> onNextRoom;
  final VoidCallback onPower;

  const RoomStrip({
    super.key,
    required this.game,
    required this.selected,
    required this.onSelect,
    required this.onNextRoom,
    required this.onPower,
  });

  @override
  Widget build(BuildContext context) {
    final g = game;
    final owned = g.ownedRooms;
    final next = rooms.where((r) => !g.isRoomOwned(r.id)).firstOrNull;
    return SizedBox(
      height: 50,
      child: Row(
        children: [
          Expanded(
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(12, 8, 6, 0),
              children: [
                for (final r in owned)
                  _RoomChip(
                    key: ValueKey('room-${r.id}'),
                    room: r,
                    selected: r.id == selected,
                    onTap: () => onSelect(r.id),
                  ),
                if (next != null)
                  _RoomChip(
                    key: ValueKey('room-${next.id}'),
                    room: next,
                    selected: false,
                    locked: true,
                    buyable: g.canBuyRoom(next.id),
                    price: next.cost,
                    onTap: () => onNextRoom(next),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(0, 8, 12, 0),
            child: _PowerChip(game: g, onTap: onPower),
          ),
        ],
      ),
    );
  }
}

class _RoomChip extends StatelessWidget {
  final RoomDef room;
  final bool selected;
  final bool locked;
  final bool buyable;
  final double? price;
  final VoidCallback onTap;

  const _RoomChip({
    super.key,
    required this.room,
    required this.selected,
    required this.onTap,
    this.locked = false,
    this.buyable = false,
    this.price,
  });

  @override
  Widget build(BuildContext context) {
    final accent =
        selected
            ? AppColors.neon
            : buyable
            ? AppColors.amber
            : AppColors.border;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: onTap,
        child: Pulse(
          active: buyable,
          scale: 1.04,
          child: Container(
            width: 116,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: accent, width: selected ? 2 : 1),
              boxShadow: [
                if (selected || buyable)
                  BoxShadow(color: accent.withValues(alpha: 0.3), blurRadius: 10),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(11),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Opacity(
                    opacity: locked && !buyable ? 0.35 : 1,
                    child: Image.asset(
                      GameArt.roomBanner(room.id),
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const ColoredBox(color: AppColors.surfaceHi),
                    ),
                  ),
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Color(0x22000000), Color(0xDD060A12)],
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 4, 6, 4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Text(
                          room.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                            color: selected ? AppColors.neon : AppColors.text,
                          ),
                        ),
                        if (locked)
                          Row(
                            children: [
                              Icon(
                                buyable ? Icons.add_circle : Icons.lock,
                                size: 11,
                                color: buyable ? AppColors.amber : AppColors.muted,
                              ),
                              const SizedBox(width: 3),
                              Flexible(
                                child: Text(
                                  formatMoney(price ?? 0),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: numStyle(
                                    size: 10.5,
                                    color: buyable ? AppColors.amber : AppColors.muted,
                                  ),
                                ),
                              ),
                            ],
                          )
                        else
                          Text(
                            '${room.width}×${room.height}',
                            style: numStyle(size: 10.5, color: AppColors.muted),
                          ),
                      ],
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
      key: const ValueKey('power-chip'),
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

class PartsTray extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final g = game;
    final all = g.tilesForRoom(room.id);
    final parts = all.where((t) => t.kind == kind).toList();
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
                if (parts.isEmpty)
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
