// The "Datacenter" tab: the room grid you build on. Pick a part from the tray,
// tap cells to place it; tap a placed tile for its info, move, sell, upgrade.
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../sim/content.dart';
import '../../sim/game.dart';
import '../format.dart';
import '../game_assets.dart';
import '../game_controller.dart';
import '../grid/grid_hints.dart';
import '../sound.dart';
import '../theme.dart';
import '../widgets/buy.dart';
import '../widgets/effects.dart';
import '../widgets/game_builder.dart';
import '../widgets/hud.dart';
import '../widgets/meters.dart';
import '../widgets/panel.dart';
import '../widgets/power_card.dart';

/// Tray groups, in display order.
const _kinds = [TileKind.gpu, TileKind.cooling, TileKind.network];

String kindLabel(TileKind k) => switch (k) {
  TileKind.gpu => 'GPU',
  TileKind.cooling => 'Cooling',
  TileKind.network => 'Network',
};

IconData kindIcon(TileKind k) => switch (k) {
  TileKind.gpu => Icons.memory,
  TileKind.cooling => Icons.ac_unit,
  TileKind.network => Icons.hub,
};

Color kindColor(TileKind k) => switch (k) {
  TileKind.gpu => AppColors.neon,
  TileKind.cooling => AppColors.cyan,
  TileKind.network => AppColors.amber,
};

/// Key stats of a part, short enough for a tray card.
String tileStatsLine(Game g, TileDef t) => switch (t.kind) {
  TileKind.gpu =>
    '${formatNumber(t.tflops)} TFLOPS · ${formatPower(g.tilePowerKw(t))} · heat ${formatNumber(t.heat)}',
  TileKind.cooling => 'cools ${formatNumber(t.cooling)} · ${formatPower(t.powerKw)}',
  TileKind.network => 'feeds ${formatNumber(t.gpuCap)} GPUs · ${formatNumber(t.linkGbps)} Gbps',
};

class DatacenterScreen extends StatefulWidget {
  final GameController controller;
  const DatacenterScreen({super.key, required this.controller});

  @override
  State<DatacenterScreen> createState() => _DatacenterScreenState();
}

class _DatacenterScreenState extends State<DatacenterScreen> {
  String? _room; // null until first build picks the training cluster's room
  String get _roomId => _room!;
  set _roomId(String v) => _room = v;
  String? _placing;
  (int, int)? _moveFrom;
  TileKind _trayKind = TileKind.gpu;

  // The grid's widget subtree is rebuilt only when what it shows changes,
  // not on every 100 ms sim tick.
  _GridKey? _gridKey;
  Widget? _gridChild;

  // Short in-grid toast (a SnackBar would cover the parts tray).
  String? _toastText;
  Color _toastColor = AppColors.amber;
  int _toastId = 0;
  Timer? _toastTimer;

  GameController get c => widget.controller;

  void _toast(String text, {Color color = AppColors.amber}) {
    _toastTimer?.cancel();
    setState(() {
      _toastText = text;
      _toastColor = color;
      _toastId++;
    });
    _toastTimer = Timer(const Duration(milliseconds: 2400), () {
      if (mounted) setState(() => _toastText = null);
    });
  }

  @override
  void dispose() {
    _toastTimer?.cancel();
    super.dispose();
  }

  void _cancelModes() {
    if (_placing == null && _moveFrom == null) return;
    Sound.play(Sfx.click);
    setState(() {
      _placing = null;
      _moveFrom = null;
    });
  }

  void _selectRoom(String id) {
    if (id == _roomId) return;
    Sound.play(Sfx.click);
    setState(() {
      _roomId = id;
      _moveFrom = null;
      final p = _placing == null ? null : tileById(_placing!);
      if (p != null && !p.rooms.contains(id)) _placing = null;
    });
  }

  void _selectPart(TileDef t) {
    final g = c.game;
    final locked = g.tileLockReason(t);
    if (locked != null) {
      Sound.play(Sfx.error);
      _toast('${t.name}: $locked');
      return;
    }
    Sound.play(Sfx.click);
    HapticFeedback.selectionClick();
    setState(() {
      _moveFrom = null;
      _placing = _placing == t.id ? null : t.id;
    });
  }

  void _onCellTap(int x, int y) {
    final g = c.game;
    final here = g.tileAt(_roomId, x, y);
    final move = _moveFrom;
    if (move != null) {
      if (move == (x, y)) {
        _cancelModes();
        return;
      }
      final ok = c.act((g) => g.moveTile(_roomId, move.$1, move.$2, x, y));
      Sound.play(ok ? Sfx.upgrade : Sfx.error);
      HapticFeedback.lightImpact();
      setState(() => _moveFrom = null);
      return;
    }
    final placing = _placing;
    if (placing != null) {
      final reason = g.placeBlockReason(_roomId, x, y, placing);
      if (reason != null) {
        Sound.play(Sfx.error);
        HapticFeedback.heavyImpact();
        _toast(reason, color: AppColors.red);
        return;
      }
      c.act((g) => g.placeTile(_roomId, x, y, placing));
      Sound.play(Sfx.purchase);
      HapticFeedback.mediumImpact();
      return;
    }
    if (here != null) {
      Sound.play(Sfx.click);
      _openTileSheet(x, y);
    } else {
      Sound.play(Sfx.click);
      _toast('Pick a part in the tray below, then tap a cell to place it.');
    }
  }

  // --- Build -------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return GameBuilder(controller: c, builder: _body);
  }

  Widget _body(BuildContext context) {
    final g = c.game;
    _room ??= g.trainingCluster?.roomId ?? g.ownedRooms.last.id;
    if (!g.isRoomOwned(_roomId)) _roomId = g.ownedRooms.first.id;
    final room = roomById(_roomId)!;
    if (_placing != null && !g.isTileUnlocked(tileById(_placing!)!)) _placing = null;
    if (_moveFrom != null && g.tileAt(_roomId, _moveFrom!.$1, _moveFrom!.$2) == null) {
      _moveFrom = null;
    }
    return Column(
      children: [
        _RoomStrip(
          game: g,
          selected: _roomId,
          onSelect: _selectRoom,
          onNextRoom: (r) => _openRoomSheet(r),
          onPower: _openPowerSheet,
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
          child: ClusterSummaryCard(game: g, roomId: _roomId, dense: true),
        ),
        SizedBox(
          height: 26,
          child: Padding(padding: const EdgeInsets.fromLTRB(12, 4, 12, 0), child: _modeBanner(g)),
        ),
        Expanded(
          child: Stack(
            children: [
              Positioned.fill(child: _gridViewport(g, room)),
              Positioned(
                left: 16,
                right: 16,
                top: 4,
                child: IgnorePointer(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 220),
                    transitionBuilder:
                        (child, a) => FadeTransition(
                          opacity: a,
                          child: ScaleTransition(
                            scale: Tween(
                              begin: 0.85,
                              end: 1.0,
                            ).animate(CurvedAnimation(parent: a, curve: Curves.easeOutBack)),
                            child: child,
                          ),
                        ),
                    child:
                        _toastText == null
                            ? const SizedBox.shrink()
                            : _Toast(
                              key: ValueKey(_toastId),
                              text: _toastText!,
                              color: _toastColor,
                            ),
                  ),
                ),
              ),
              if (_coachText(g) case final text?)
                Positioned(left: 24, right: 24, bottom: 10, child: _CoachMark(text: text)),
            ],
          ),
        ),
        _PartsTray(
          game: g,
          room: room,
          kind: _trayKind,
          placing: _placing,
          modeActive: _placing != null || _moveFrom != null,
          onCancel: _cancelModes,
          onKind: (k) {
            Sound.play(Sfx.click);
            setState(() => _trayKind = k);
          },
          onPick: _selectPart,
        ),
      ],
    );
  }

  String? _coachText(Game g) {
    if (_placing != null || _moveFrom != null) return null;
    final counts = g.s.tileCounts;
    final hasSwitch = counts.keys.any((id) => tileById(id)?.isNetwork ?? false);
    if (hasSwitch) return null;
    if (g.ownedRooms.length > 1 || _roomId != g.ownedRooms.first.id) return null;
    final gpus = counts.entries
        .where((e) => tileById(e.key)?.isGpu ?? false)
        .fold(0, (a, e) => a + e.value);
    return gpus < 2
        ? 'Place a GPU, then a switch next to it.'
        : 'Now put a switch between your GPUs to link them into one training cluster.';
  }

  /// Non-interactive hint over the grid while placing or moving, so it never
  /// blocks taps on the top row. Cancel lives in the tray header.
  Widget _modeBanner(Game g) {
    final move = _moveFrom;
    final String text;
    final Color color;
    final Widget leading;
    if (move == null && _placing == null) {
      final room = roomById(_roomId)!;
      return IgnorePointer(
        child: Center(
          child: Text(
            '1 GPU tile = ${room.tileScaleLabel} · tap a tile for info',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: AppColors.faint, fontSize: 11.5),
          ),
        ),
      );
    }
    if (move != null) {
      final t = tileById(g.tileAt(_roomId, move.$1, move.$2) ?? '');
      text = 'Moving ${t?.name ?? 'tile'}: tap a cell (occupied cells swap)';
      color = AppColors.cyan;
      leading = const Icon(Icons.open_with, color: AppColors.cyan, size: 16);
    } else {
      final t = tileById(_placing!)!;
      text = 'Placing ${t.name} · ${formatMoney(g.tilePrice(t))} · tap glowing cells';
      color = kindColor(t.kind);
      leading = Image.asset(GameArt.tile(t.id), width: 20, height: 20);
    }
    return IgnorePointer(
      child: Center(
        child: Container(
          padding: const EdgeInsets.fromLTRB(8, 4, 10, 4),
          decoration: BoxDecoration(
            color: AppColors.bg.withValues(alpha: 0.82),
            borderRadius: BorderRadius.circular(99),
            border: Border.all(color: color.withValues(alpha: 0.55)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              leading,
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 11.5),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _gridViewport(Game g, RoomDef room) {
    return LayoutBuilder(
      builder: (context, box) {
        const pad = 8.0;
        final fit = math.min(
          (box.maxWidth - pad * 2) / room.width,
          (box.maxHeight - pad * 2) / room.height,
        );
        final cell = fit.clamp(24.0, 120.0).floorToDouble();
        final key = _GridKey.of(g, room, cell, _placing, _moveFrom);
        if (key != _gridKey || _gridChild == null) {
          _gridKey = key;
          _gridChild = _GridLayers(
            game: g,
            room: room,
            cell: cell,
            valid: key.valid,
            moveFrom: _moveFrom,
            placingKind: _placing == null ? null : tileById(_placing!)!.kind,
            onTap: _onCellTap,
          );
        }
        final w = room.width * cell, h = room.height * cell;
        return InteractiveViewer(
          key: ValueKey('viewer-${room.id}-$cell'),
          constrained: false,
          minScale: 0.5,
          maxScale: 3,
          boundaryMargin: const EdgeInsets.all(80),
          child: SizedBox(
            width: math.max(w + pad * 2, box.maxWidth),
            height: math.max(h + pad * 2, box.maxHeight),
            child: Center(child: _gridChild),
          ),
        );
      },
    );
  }

  // --- Sheets -------------------------------------------------------------------

  void _openPowerSheet() {
    Sound.play(Sfx.click);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder:
          (context) => GameBuilder(
            controller: c,
            builder:
                (context) => SafeArea(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: PowerCard(controller: c),
                  ),
                ),
          ),
    );
  }

  void _openRoomSheet(RoomDef room) {
    Sound.play(Sfx.click);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder:
          (sheet) => GameBuilder(
            controller: c,
            builder: (sheet) {
              final g = c.game;
              final reason = g.roomBlockReason(room.id);
              final owned = g.isRoomOwned(room.id);
              return SafeArea(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: AspectRatio(
                          aspectRatio: 3,
                          child: Image.asset(GameArt.roomBanner(room.id), fit: BoxFit.cover),
                        ),
                      ),
                      gap12,
                      Text(
                        room.name,
                        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 2),
                      Text(room.blurb, style: const TextStyle(color: AppColors.muted, height: 1.3)),
                      gap12,
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          Tag(
                            '${room.width}×${room.height} grid',
                            color: AppColors.cyan,
                            mono: true,
                          ),
                          Tag('1 GPU tile = ${room.tileScaleLabel}', color: AppColors.neon),
                          Tag(
                            'free cooling ${formatNumber(room.ambientTotal)}',
                            color: AppColors.cyan,
                            icon: Icons.ac_unit,
                          ),
                          Tag('${room.era.label} era', color: AppColors.violet),
                        ],
                      ),
                      const SizedBox(height: 16),
                      if (!owned)
                        BuyButton(
                          key: const ValueKey('buy-room'),
                          label: 'Buy ${room.name}',
                          sublabel: formatMoney(room.cost),
                          icon: Icons.add_business,
                          expand: true,
                          dense: false,
                          enabled: reason == null,
                          onBuy: () {
                            final ok = c.act((g) => g.buyRoom(room.id));
                            Sound.play(ok ? Sfx.upgrade : Sfx.error);
                            if (ok) {
                              Navigator.of(sheet).pop();
                              setState(() {
                                _roomId = room.id;
                                _placing = null;
                                _moveFrom = null;
                              });
                            }
                          },
                        ),
                      if (reason != null && !owned) ...[
                        gap8,
                        Text(
                          reason,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: AppColors.amber, fontSize: 13),
                        ),
                        if (g.s.money < room.cost) ...[
                          gap8,
                          AffordBar(money: g.s.money, cost: room.cost),
                        ],
                      ],
                    ],
                  ),
                ),
              );
            },
          ),
    );
  }

  void _openTileSheet(int x, int y) {
    final roomId = _roomId;
    _toastTimer?.cancel();
    setState(() => _toastText = null);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder:
          (sheet) => GameBuilder(
            controller: c,
            builder:
                (sheet) => _TileSheet(
                  game: c.game,
                  roomId: roomId,
                  x: x,
                  y: y,
                  onMove: () {
                    Navigator.of(sheet).pop();
                    Sound.play(Sfx.click);
                    setState(() {
                      _placing = null;
                      _moveFrom = (x, y);
                    });
                  },
                  onSell: () {
                    final ok = c.act((g) => g.sellTile(roomId, x, y));
                    Sound.play(ok ? Sfx.purchase : Sfx.error);
                    if (ok) Navigator.of(sheet).pop();
                  },
                  onReplace: (t) {
                    final ok = c.act((g) => g.replaceTile(roomId, x, y, t.id));
                    Sound.play(ok ? Sfx.upgrade : Sfx.error);
                    if (ok) HapticFeedback.mediumImpact();
                  },
                ),
          ),
    );
  }
}

// --- Grid ---------------------------------------------------------------------

/// Everything the grid's look depends on. Equal keys reuse the built subtree.
class _GridKey {
  final String roomId;
  final int revision;
  final double cell;
  final String? placing;
  final (int, int)? moveFrom;
  final String valid; // '1'/'0' per cell: empty and placeable right now

  const _GridKey(this.roomId, this.revision, this.cell, this.placing, this.moveFrom, this.valid);

  factory _GridKey.of(Game g, RoomDef room, double cell, String? placing, (int, int)? moveFrom) {
    final buf = StringBuffer();
    if (placing != null) {
      for (var y = 0; y < room.height; y++) {
        for (var x = 0; x < room.width; x++) {
          buf.write(g.canPlace(room.id, x, y, placing) ? '1' : '0');
        }
      }
    }
    return _GridKey(room.id, g.s.gridRevision, cell, placing, moveFrom, buf.toString());
  }

  @override
  bool operator ==(Object other) =>
      other is _GridKey &&
      other.roomId == roomId &&
      other.revision == revision &&
      other.cell == cell &&
      other.placing == placing &&
      other.moveFrom == moveFrom &&
      other.valid == valid;

  @override
  int get hashCode => Object.hash(roomId, revision, cell, placing, moveFrom, valid);
}

class _GridLayers extends StatelessWidget {
  final Game game;
  final RoomDef room;
  final double cell;
  final String valid;
  final (int, int)? moveFrom;
  final TileKind? placingKind;
  final void Function(int x, int y) onTap;

  const _GridLayers({
    required this.game,
    required this.room,
    required this.cell,
    required this.valid,
    required this.moveFrom,
    required this.placingKind,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final g = game;
    final w = room.width, h = room.height;
    final statuses = [
      for (var y = 0; y < h; y++)
        for (var x = 0; x < w; x++) g.tileStatus(room.id, x, y),
    ];
    TileStatus? at(int x, int y) => x < 0 || y < 0 || x >= w || y >= h ? null : statuses[y * w + x];
    final clusters = {for (final cl in g.clusters(room.id)) cl.id: cl};

    // Keyed so a Stack child keeps its element (and the tile its state) when
    // other layers gain or lose children, e.g. entering placement mode.
    Positioned cellBox(String layer, int x, int y, Widget child) => Positioned(
      key: ValueKey('$layer-$x-$y'),
      left: x * cell,
      top: y * cell,
      width: cell,
      height: cell,
      child: child,
    );

    final glows = <Widget>[];
    final links = <Widget>[];
    final tilesLayer = <Widget>[];
    final hints = <Widget>[];
    final taps = <Widget>[];

    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final st = at(x, y);
        final i = y * w + x;

        // Cluster glow: training green, other networked clusters cyan.
        if (st != null && st.clusterId != null && !st.def.isCooling) {
          final cl = clusters[st.clusterId];
          final color =
              st.inTrainingCluster
                  ? AppColors.neon
                  : (cl?.networked ?? false)
                  ? AppColors.cyan
                  : null;
          if (color != null) glows.add(cellBox('glow', x, y, _ClusterGlow(color: color)));
        }

        // Network links to the right and below (each pair once).
        for (final (dx, dy) in const [(1, 0), (0, 1)]) {
          final o = at(x + dx, y + dy);
          if (st == null || o == null) continue;
          final linked =
              (st.def.isNetwork && (o.def.isNetwork || o.def.isGpu)) ||
              (o.def.isNetwork && st.def.isGpu);
          if (!linked) continue;
          final training = st.inTrainingCluster && o.inTrainingCluster;
          links.add(
            dx == 1
                ? Positioned(
                  key: ValueKey('link-h-$x-$y'),
                  left: x * cell + cell / 2,
                  top: y * cell,
                  width: cell,
                  height: cell,
                  child: _Link(vertical: false, training: training),
                )
                : Positioned(
                  key: ValueKey('link-v-$x-$y'),
                  left: x * cell,
                  top: y * cell + cell / 2,
                  width: cell,
                  height: cell,
                  child: _Link(vertical: true, training: training),
                ),
          );
        }

        if (st != null) {
          tilesLayer.add(
            cellBox(
              'tile-${st.def.id}',
              x,
              y,
              _TileArt(
                key: ValueKey('tile-$x-$y-${st.def.id}'),
                status: st,
                cell: cell,
                moving: moveFrom == (x, y),
              ),
            ),
          );
        } else if (valid.isNotEmpty && valid[i] == '1') {
          hints.add(cellBox('hint', x, y, _ValidCell(color: kindColor(placingKind!))));
        } else if (moveFrom != null) {
          hints.add(cellBox('hint', x, y, const _ValidCell(color: AppColors.cyan)));
        }

        taps.add(
          cellBox(
            'tap',
            x,
            y,
            GestureDetector(
              key: ValueKey('cell-$x-$y'),
              behavior: HitTestBehavior.opaque,
              onTap: () => onTap(x, y),
            ),
          ),
        );
      }
    }

    final era = eraColor(room.era);
    return RepaintBoundary(
      child: Container(
        width: w * cell,
        height: h * cell,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: era.withValues(alpha: 0.55), width: 2),
          boxShadow: [
            BoxShadow(color: era.withValues(alpha: 0.22), blurRadius: 24, spreadRadius: 1),
            const BoxShadow(color: Color(0xAA000000), blurRadius: 30, offset: Offset(0, 12)),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(child: _Floor(roomId: room.id, cell: cell)),
              Positioned.fill(
                child: CustomPaint(painter: _GridLinesPainter(cell: cell, w: w, h: h)),
              ),
              ...glows,
              ...links,
              ...hints,
              ...tilesLayer,
              ...taps,
            ],
          ),
        ),
      ),
    );
  }
}

class _Floor extends StatelessWidget {
  final String roomId;
  final double cell;
  const _Floor({required this.roomId, required this.cell});

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: AppColors.surface,
      image: DecorationImage(
        image: AssetImage(GameArt.floor(roomId)),
        repeat: ImageRepeat.repeat,
        alignment: Alignment.topLeft,
        scale: 128 / cell,
        filterQuality: FilterQuality.medium,

        onError: (_, __) {},
      ),
    ),
  );
}

class _GridLinesPainter extends CustomPainter {
  final double cell;
  final int w, h;
  _GridLinesPainter({required this.cell, required this.w, required this.h});

  @override
  void paint(Canvas canvas, Size size) {
    final p =
        Paint()
          ..color = const Color(0x2E8FB5FF)
          ..strokeWidth = 1;
    for (var x = 1; x < w; x++) {
      canvas.drawLine(Offset(x * cell, 0), Offset(x * cell, size.height), p);
    }
    for (var y = 1; y < h; y++) {
      canvas.drawLine(Offset(0, y * cell), Offset(size.width, y * cell), p);
    }
    // Small corner ticks at each intersection read as floor tiles.
    final dot = Paint()..color = const Color(0x558FB5FF);
    for (var x = 1; x < w; x++) {
      for (var y = 1; y < h; y++) {
        canvas.drawCircle(Offset(x * cell, y * cell), 1.6, dot);
      }
    }
  }

  @override
  bool shouldRepaint(_GridLinesPainter old) => old.cell != cell || old.w != w || old.h != h;
}

class _ClusterGlow extends StatelessWidget {
  final Color color;
  const _ClusterGlow({required this.color});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(2),
    child: DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        color: color.withValues(alpha: 0.13),
        border: Border.all(color: color.withValues(alpha: 0.7), width: 1.5),
        boxShadow: [BoxShadow(color: color.withValues(alpha: 0.35), blurRadius: 10)],
      ),
    ),
  );
}

class _ValidCell extends StatelessWidget {
  final Color color;
  const _ValidCell({required this.color});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(5),
    child: Blink(
      period: const Duration(milliseconds: 1200),
      builder:
          (context, t) => DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              color: color.withValues(alpha: 0.06 + 0.08 * t),
              border: Border.all(color: color.withValues(alpha: 0.3 + 0.35 * t), width: 1.5),
            ),
            child: Center(
              child: Icon(Icons.add, size: 18, color: color.withValues(alpha: 0.35 + 0.3 * t)),
            ),
          ),
    ),
  );
}

class _Link extends StatelessWidget {
  final bool vertical;
  final bool training;
  const _Link({required this.vertical, required this.training});

  @override
  Widget build(BuildContext context) {
    Widget img = Image.asset(
      GameArt.tileLinkOverlay,
      fit: BoxFit.fill,
      gaplessPlayback: true,
      errorBuilder:
          (_, __, ___) =>
              Center(child: Container(height: 4, color: AppColors.amber.withValues(alpha: 0.8))),
    );
    if (training) {
      // Training links glow green-gold.
      img = ColorFiltered(
        colorFilter: const ColorFilter.matrix([
          0.55, 0.25, 0, 0, 0, //
          0.35, 0.75, 0, 0, 40,
          0.1, 0.1, 0.25, 0, 0,
          0, 0, 0, 1, 0,
        ]),
        child: img,
      );
    }
    return IgnorePointer(child: vertical ? RotatedBox(quarterTurns: 1, child: img) : img);
  }
}

/// One placed tile: art, heat glow, throttle badge. Pops in when placed.
class _TileArt extends StatefulWidget {
  final TileStatus status;
  final double cell;
  final bool moving;
  const _TileArt({super.key, required this.status, required this.cell, required this.moving});

  @override
  State<_TileArt> createState() => _TileArtState();
}

class _TileArtState extends State<_TileArt> with SingleTickerProviderStateMixin {
  late final AnimationController _pop = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  )..forward();

  @override
  void dispose() {
    _pop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final st = widget.status;
    final cell = widget.cell;
    final heat = st.def.isGpu && st.throttling ? ((1 - st.speed) / 0.7).clamp(0.0, 1.0) : 0.0;
    final art = Image.asset(
      GameArt.tile(st.def.id),
      fit: BoxFit.contain,
      gaplessPlayback: true,
      filterQuality: FilterQuality.medium,
      errorBuilder:
          (_, __, ___) =>
              Icon(kindIcon(st.def.kind), color: kindColor(st.def.kind), size: cell * 0.5),
    );
    return IgnorePointer(
      child: ScaleTransition(
        scale: CurvedAnimation(parent: _pop, curve: Curves.elasticOut),
        child: Stack(
          fit: StackFit.expand,
          clipBehavior: Clip.none,
          children: [
            if (heat > 0)
              Opacity(
                opacity: 0.45 + 0.55 * heat,
                child: Image.asset(GameArt.tileHeatOverlay, fit: BoxFit.contain),
              ),
            Padding(padding: EdgeInsets.all(cell * 0.02), child: art),
            if (heat > 0)
              // Red wash over the art itself.
              Padding(
                padding: EdgeInsets.all(cell * 0.02),
                child: Opacity(
                  opacity: 0.25 + 0.35 * heat,
                  child: Image.asset(
                    GameArt.tile(st.def.id),
                    fit: BoxFit.contain,
                    color: AppColors.red,
                    colorBlendMode: BlendMode.srcATop,
                    errorBuilder: (_, __, ___) => const SizedBox(),
                  ),
                ),
              ),
            if (widget.moving)
              DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.cyan, width: 2),
                ),
              ),
            if (heat > 0)
              Positioned(
                right: 2,
                top: 2,
                child: _Badge(
                  text: formatPercent(st.speed),
                  color: AppColors.red,
                  size: (cell * 0.13).clamp(8.0, 12.0),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Toast extends StatelessWidget {
  final String text;
  final Color color;
  const _Toast({super.key, required this.text, required this.color});

  @override
  Widget build(BuildContext context) => Center(
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Color.alphaBlend(color.withValues(alpha: 0.16), AppColors.surface),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.7)),
        boxShadow: const [BoxShadow(color: Color(0x99000000), blurRadius: 14)],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.info_outline, size: 16, color: color),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              text,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: AppColors.text, fontSize: 12.5, height: 1.3),
            ),
          ),
        ],
      ),
    ),
  );
}

class _Badge extends StatelessWidget {
  final String text;
  final Color color;
  final double size;
  const _Badge({required this.text, required this.color, required this.size});

  @override
  Widget build(BuildContext context) => Container(
    padding: EdgeInsets.symmetric(horizontal: size * 0.4, vertical: size * 0.1),
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(99),
      boxShadow: [BoxShadow(color: color.withValues(alpha: 0.5), blurRadius: 6)],
    ),
    child: Text(text, style: numStyle(size: size, color: Colors.white, weight: FontWeight.w800)),
  );
}

class _CoachMark extends StatelessWidget {
  final String text;
  const _CoachMark({required this.text});

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: Pulse(
      scale: 1.03,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            decoration: BoxDecoration(
              color: AppColors.neon,
              borderRadius: BorderRadius.circular(14),
              boxShadow: [BoxShadow(color: AppColors.neon.withValues(alpha: 0.4), blurRadius: 18)],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.touch_app, size: 18, color: AppColors.bg),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    text,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: AppColors.bg,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      height: 1.25,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Icon(Icons.arrow_drop_down, size: 26, color: AppColors.neon),
        ],
      ),
    ),
  );
}

// --- Room strip -------------------------------------------------------------------

class _RoomStrip extends StatelessWidget {
  final Game game;
  final String selected;
  final ValueChanged<String> onSelect;
  final ValueChanged<RoomDef> onNextRoom;
  final VoidCallback onPower;

  const _RoomStrip({
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

class _PartsTray extends StatelessWidget {
  final Game game;
  final RoomDef room;
  final TileKind kind;
  final String? placing;
  final bool modeActive;
  final VoidCallback onCancel;
  final ValueChanged<TileKind> onKind;
  final ValueChanged<TileDef> onPick;

  const _PartsTray({
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
                for (final k in _kinds)
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

// --- Tile info sheet -----------------------------------------------------------------

class _TileSheet extends StatelessWidget {
  final Game game;
  final String roomId;
  final int x, y;
  final VoidCallback onMove;
  final VoidCallback onSell;
  final ValueChanged<TileDef> onReplace;

  const _TileSheet({
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

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
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
                      Text(
                        t.name,
                        style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
                      ),
                      if (t.isGpu)
                        Text(
                          '${formatNumber(t.gpusPerTile)} GPU${t.gpusPerTile == 1 ? '' : 's'} · ${formatNumber(t.tflops)} TFLOPS peak · ${formatPower(g.tilePowerKw(t))}',
                          style: numStyle(
                            size: 11,
                            color: AppColors.muted,
                            weight: FontWeight.w500,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            gap12,
            Text(
              t.blurb,
              style: const TextStyle(color: AppColors.text, fontSize: 13.5, height: 1.35),
            ),
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
        ),
      ),
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
