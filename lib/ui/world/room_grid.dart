// The placement grid drawn on a room's isometric floor: cluster glows,
// network links, valid-cell highlights, tile sprites (depth sorted) with heat
// tint and speed badges. Rebuilt only when what it shows changes.
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../sim/content.dart';
import '../../sim/game.dart';
import '../format.dart';
import '../game_assets.dart';
import '../game_controller.dart';
import '../theme.dart';
import 'world_layout.dart';

/// Tray groups, in display order.
const tileKinds = [TileKind.gpu, TileKind.cooling, TileKind.network];

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

/// What the build interaction looks like right now (owned by the shell).
class BuildState {
  final bool buildMode;
  final String? activeRoom;
  final String? placing;
  final (String, int, int)? moveFrom;
  const BuildState({this.buildMode = false, this.activeRoom, this.placing, this.moveFrom});
}

/// Everything the grid's look depends on. Equal keys reuse the built subtree.
class _GridKey {
  final int revision;
  final bool buildMode;
  final String? placing;
  final (int, int)? moveFrom;
  final String valid; // '1'/'0' per cell: empty and placeable right now

  const _GridKey(this.revision, this.buildMode, this.placing, this.moveFrom, this.valid);

  factory _GridKey.of(Game g, RoomDef room, BuildState b) {
    final buf = StringBuffer();
    final placing = b.placing;
    if (placing != null && tileById(placing)!.rooms.contains(room.id)) {
      for (var y = 0; y < room.height; y++) {
        for (var x = 0; x < room.width; x++) {
          buf.write(g.canPlace(room.id, x, y, placing) ? '1' : '0');
        }
      }
    }
    final mv = b.moveFrom;
    return _GridKey(
      g.s.gridRevision,
      b.buildMode,
      placing,
      mv != null && mv.$1 == room.id ? (mv.$2, mv.$3) : null,
      buf.toString(),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is _GridKey &&
      other.revision == revision &&
      other.buildMode == buildMode &&
      other.placing == placing &&
      other.moveFrom == moveFrom &&
      other.valid == valid;

  @override
  int get hashCode => Object.hash(revision, buildMode, placing, moveFrom, valid);
}

/// Listens to the controller but only rebuilds the grid when its key changes.
class RoomGrid extends StatefulWidget {
  final GameController controller;
  final RoomDef room;
  final BuildState build;
  final void Function(String roomId, int x, int y) onCellTap;

  const RoomGrid({
    super.key,
    required this.controller,
    required this.room,
    required this.build,
    required this.onCellTap,
  });

  @override
  State<RoomGrid> createState() => _RoomGridState();
}

class _RoomGridState extends State<RoomGrid> {
  _GridKey? _key;
  Widget? _child;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onTick);
  }

  @override
  void didUpdateWidget(RoomGrid old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller.removeListener(_onTick);
      widget.controller.addListener(_onTick);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onTick);
    super.dispose();
  }

  void _onTick() {
    if (!mounted) return;
    final k = _GridKey.of(widget.controller.game, widget.room, widget.build);
    if (k != _key) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final g = widget.controller.game;
    final k = _GridKey.of(g, widget.room, widget.build);
    if (k != _key || _child == null) {
      _key = k;
      _child = _GridLayers(
        game: g,
        room: widget.room,
        geo: geoOf(widget.room.id),
        gridKey: k,
        placingKind: widget.build.placing == null ? null : tileById(widget.build.placing!)!.kind,
      );
    }
    final geo = geoOf(widget.room.id);
    return Stack(
      fit: StackFit.expand,
      children: [
        RepaintBoundary(child: _child),
        // One tap target for the whole floor; screen → diamond cell maths.
        Positioned.fill(
          child: GestureDetector(
            key: ValueKey('room-floor-${widget.room.id}'),
            behavior: HitTestBehavior.deferToChild,
            onTapUp: (d) {
              final cell = geo.cellAtLocal(d.localPosition);
              if (cell != null) widget.onCellTap(widget.room.id, cell.$1, cell.$2);
            },
            child: CustomPaint(painter: _FloorHitArea(geo), size: geo.size),
          ),
        ),
      ],
    );
  }
}

/// Invisible; makes only the floor diamond hit-testable so taps elsewhere
/// (empty void, other rooms' signs) fall through.
class _FloorHitArea extends CustomPainter {
  final RoomGeo geo;
  _FloorHitArea(this.geo);

  @override
  void paint(Canvas canvas, Size size) {}

  @override
  bool hitTest(Offset position) => geo.cellAtLocal(position) != null;

  @override
  bool shouldRepaint(_FloorHitArea old) => old.geo != geo;
}

class _GridLayers extends StatelessWidget {
  final Game game;
  final RoomDef room;
  final RoomGeo geo;
  final _GridKey gridKey;
  final TileKind? placingKind;

  const _GridLayers({
    required this.game,
    required this.room,
    required this.geo,
    required this.gridKey,
    required this.placingKind,
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

    final glows = <(int, int, Color)>[];
    final links = <(int, int, int, int, bool)>[];
    final valid = <(int, int)>[];
    final tilesLayer = <(int, int, TileStatus)>[];
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final st = at(x, y);
        final i = y * w + x;
        if (st != null && st.clusterId != null && !st.def.isCooling) {
          final cl = clusters[st.clusterId];
          final color =
              st.inTrainingCluster
                  ? AppColors.neon
                  : (cl?.networked ?? false)
                  ? AppColors.cyan
                  : null;
          if (color != null) glows.add((x, y, color));
        }
        for (final (dx, dy) in const [(1, 0), (0, 1)]) {
          final o = at(x + dx, y + dy);
          if (st == null || o == null) continue;
          final linked =
              (st.def.isNetwork && (o.def.isNetwork || o.def.isGpu)) ||
              (o.def.isNetwork && st.def.isGpu);
          if (linked) {
            links.add((x, y, x + dx, y + dy, st.inTrainingCluster && o.inTrainingCluster));
          }
        }
        if (st != null) {
          tilesLayer.add((x, y, st));
        } else if (gridKey.valid.isNotEmpty && gridKey.valid[i] == '1') {
          valid.add((x, y));
        }
      }
    }
    // Back to front: smaller x+y is further away.
    tilesLayer.sort((a, b) => (a.$1 + a.$2).compareTo(b.$1 + b.$2));
    final mv = gridKey.moveFrom;
    final moveTargets =
        mv == null
            ? const <(int, int)>[]
            : [
              for (var y = 0; y < h; y++)
                for (var x = 0; x < w; x++)
                  if ((x, y) != mv) (x, y),
            ];

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned.fill(
          child: CustomPaint(
            painter: _FloorPainter(
              geo: geo,
              buildMode: gridKey.buildMode || gridKey.placing != null || mv != null,
              glows: glows,
              links: links,
              moveFrom: mv,
            ),
          ),
        ),
        if (valid.isNotEmpty || moveTargets.isNotEmpty)
          Positioned.fill(
            child: _ValidCells(
              geo: geo,
              cells: valid.isNotEmpty ? valid : moveTargets,
              color: valid.isNotEmpty ? kindColor(placingKind!) : AppColors.cyan,
            ),
          ),
        for (final (x, y, st) in tilesLayer)
          Positioned.fromRect(
            key: ValueKey('tile-$x-$y'),
            rect: geo.tileRect(x, y),
            child: _TileArt(
              key: ValueKey('tile-$x-$y-${st.def.id}'),
              status: st,
              moving: mv == (x, y),
            ),
          ),
      ],
    );
  }
}

class _FloorPainter extends CustomPainter {
  final RoomGeo geo;
  final bool buildMode;
  final List<(int, int, Color)> glows;
  final List<(int, int, int, int, bool)> links;
  final (int, int)? moveFrom;

  _FloorPainter({
    required this.geo,
    required this.buildMode,
    required this.glows,
    required this.links,
    required this.moveFrom,
  });

  Path _diamond(int x, int y, {double inset = 0}) {
    final d = geo.cellDiamond(x, y, inset: inset);
    return Path()..addPolygon(d, true);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final w = geo.w, h = geo.h;
    // Grid lines: faint always, clearer while building.
    final line =
        Paint()
          ..color = (buildMode ? const Color(0x66A9C8FF) : const Color(0x22A9C8FF))
          ..strokeWidth = buildMode ? 1.4 : 1;
    for (var x = 0; x <= w; x++) {
      canvas.drawLine(
        geo.svgToLocal(geo.gridSvg(x.toDouble(), 0)),
        geo.svgToLocal(geo.gridSvg(x.toDouble(), h.toDouble())),
        line,
      );
    }
    for (var y = 0; y <= h; y++) {
      canvas.drawLine(
        geo.svgToLocal(geo.gridSvg(0, y.toDouble())),
        geo.svgToLocal(geo.gridSvg(w.toDouble(), y.toDouble())),
        line,
      );
    }
    // Cluster glows: training green, other networked clusters cyan.
    for (final (x, y, color) in glows) {
      final p = _diamond(x, y, inset: 0.05);
      canvas.drawPath(p, Paint()..color = color.withValues(alpha: 0.16));
      canvas.drawPath(
        p,
        Paint()
          ..color = color.withValues(alpha: 0.75)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2 * geo.scale * 2.2
          ..maskFilter = const MaskFilter.blur(BlurStyle.solid, 3),
      );
    }
    // Network links between cell centres, just above the floor.
    for (final (x0, y0, x1, y1, training) in links) {
      final a = geo.cellCenterLocal(x0, y0, 6), b = geo.cellCenterLocal(x1, y1, 6);
      final color = training ? const Color(0xFFB6FF6A) : AppColors.amber;
      canvas.drawLine(
        a,
        b,
        Paint()
          ..color = const Color(0xCC080C1A)
          ..strokeWidth = 9 * geo.scale * 1.6
          ..strokeCap = StrokeCap.round,
      );
      canvas.drawLine(
        a,
        b,
        Paint()
          ..color = color
          ..strokeWidth = 4.5 * geo.scale * 1.6
          ..strokeCap = StrokeCap.round
          ..maskFilter = const MaskFilter.blur(BlurStyle.solid, 2.5),
      );
    }
    final mv = moveFrom;
    if (mv != null) {
      canvas.drawPath(
        _diamond(mv.$1, mv.$2),
        Paint()
          ..color = AppColors.cyan
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3,
      );
    }
  }

  @override
  bool shouldRepaint(_FloorPainter old) => true; // only rebuilt when the grid key changes
}

/// Blinking diamonds on the cells you can place on (or move to).
class _ValidCells extends StatefulWidget {
  final RoomGeo geo;
  final List<(int, int)> cells;
  final Color color;
  const _ValidCells({required this.geo, required this.cells, required this.color});

  @override
  State<_ValidCells> createState() => _ValidCellsState();
}

class _ValidCellsState extends State<_ValidCells> with SingleTickerProviderStateMixin {
  late final AnimationController _t = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _t.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: RepaintBoundary(
      child: CustomPaint(painter: _ValidPainter(widget.geo, widget.cells, widget.color, _t)),
    ),
  );
}

class _ValidPainter extends CustomPainter {
  final RoomGeo geo;
  final List<(int, int)> cells;
  final Color color;
  final Animation<double> t;
  _ValidPainter(this.geo, this.cells, this.color, this.t) : super(repaint: t);

  @override
  void paint(Canvas canvas, Size size) {
    final v = Curves.easeInOut.transform(t.value);
    final fill = Paint()..color = color.withValues(alpha: 0.07 + 0.12 * v);
    final edge =
        Paint()
          ..color = color.withValues(alpha: 0.35 + 0.4 * v)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6;
    for (final (x, y) in cells) {
      final p = Path()..addPolygon(geo.cellDiamond(x, y, inset: 0.1), true);
      canvas.drawPath(p, fill);
      canvas.drawPath(p, edge);
      final c = geo.cellCenterLocal(x, y);
      final s = 9 * geo.scale * 1.6;
      final plus =
          Paint()
            ..color = color.withValues(alpha: 0.4 + 0.35 * v)
            ..strokeWidth = 2;
      canvas.drawLine(c - Offset(s, 0), c + Offset(s, 0), plus);
      canvas.drawLine(c - Offset(0, s * 0.6), c + Offset(0, s * 0.6), plus);
    }
  }

  @override
  bool shouldRepaint(_ValidPainter old) => old.cells != cells || old.color != color;
}

/// One placed tile: art, heat glow, throttle badge. Pops in when placed.
class _TileArt extends StatefulWidget {
  final TileStatus status;
  final bool moving;
  const _TileArt({super.key, required this.status, required this.moving});

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
    final heat = st.def.isGpu && st.throttling ? ((1 - st.speed) / 0.7).clamp(0.0, 1.0) : 0.0;
    final art = Image.asset(
      GameArt.tile(st.def.id),
      fit: BoxFit.fill,
      gaplessPlayback: true,
      filterQuality: FilterQuality.medium,
      errorBuilder:
          (_, __, ___) => Center(child: Icon(kindIcon(st.def.kind), color: kindColor(st.def.kind))),
    );
    return IgnorePointer(
      child: LayoutBuilder(
        builder: (context, box) {
          final s = box.maxWidth;
          return ScaleTransition(
            // Pop from the footprint centre (y = 134/200 of the sprite).
            alignment: const Alignment(0, 0.34),
            scale: CurvedAnimation(parent: _pop, curve: Curves.elasticOut),
            child: Stack(
              fit: StackFit.expand,
              clipBehavior: Clip.none,
              children: [
                if (heat > 0)
                  Opacity(
                    opacity: 0.45 + 0.55 * heat,
                    child: Image.asset(GameArt.tileHeatOverlay, fit: BoxFit.fill),
                  ),
                art,
                if (heat > 0)
                  Opacity(
                    opacity: 0.25 + 0.35 * heat,
                    child: Image.asset(
                      GameArt.tile(st.def.id),
                      fit: BoxFit.fill,
                      color: AppColors.red,
                      colorBlendMode: BlendMode.srcATop,
                      errorBuilder: (_, __, ___) => const SizedBox(),
                    ),
                  ),
                if (widget.moving)
                  Positioned(
                    left: s * 0.2,
                    right: s * 0.2,
                    top: s * 0.4,
                    bottom: s * 0.1,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(99),
                        border: Border.all(color: AppColors.cyan, width: 2),
                      ),
                    ),
                  ),
                if (heat > 0)
                  Positioned(
                    left: 0,
                    right: 0,
                    top: s * 0.18,
                    child: Center(
                      child: _Badge(
                        text: formatPercent(st.speed),
                        color: AppColors.red,
                        size: math.max(7.0, s * 0.075),
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final String text;
  final Color color;
  final double size;
  const _Badge({required this.text, required this.color, required this.size});

  @override
  Widget build(BuildContext context) => Container(
    padding: EdgeInsets.symmetric(horizontal: size * 0.45, vertical: size * 0.12),
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(99),
      border: Border.all(color: const Color(0xFF080C1A), width: 1.2),
      boxShadow: [BoxShadow(color: color.withValues(alpha: 0.5), blurRadius: 6)],
    ),
    child: Text(text, style: numStyle(size: size, color: Colors.white, weight: FontWeight.w800)),
  );
}
