// The placement grid drawn on a room's isometric floor: the training-cluster
// glow, overhead cable trays (styled by the network tier), valid-cell
// highlights, tile sprites (depth sorted) with heat tint and speed badges.
// Rebuilt only when what it shows changes.
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../sim/content.dart';
import '../../sim/game.dart';
import '../format.dart';
import '../game_assets.dart';
import '../game_controller.dart';
import '../theme.dart';
import 'world_layout.dart';

/// Tray groups, in display order.
const tileKinds = [TileKind.gpu, TileKind.cooling];

String kindLabel(TileKind k) => switch (k) {
  TileKind.gpu => 'GPU',
  TileKind.cooling => 'Cooling',
};

IconData kindIcon(TileKind k) => switch (k) {
  TileKind.gpu => Icons.memory,
  TileKind.cooling => Icons.ac_unit,
};

Color kindColor(TileKind k) => switch (k) {
  TileKind.gpu => AppColors.neon,
  TileKind.cooling => AppColors.cyan,
};

/// Key stats of a part, short enough for a tray card.
String tileStatsLine(Game g, TileDef t) => switch (t.kind) {
  TileKind.gpu =>
    '${formatTflops(t.tflops)} · ${formatPower(g.tilePowerKw(t))} · heat ${formatNumber(t.heat)}\n'
        '${formatNumber(t.tflops / g.tilePowerKw(t))} TF/kW · ${formatNumber(t.tflops / g.tilePrice(t) * 1000)} TF/\$k',
  TileKind.cooling => 'cools ${formatNumber(t.cooling)} · ${formatPower(t.powerKw)}',
};

/// Look of the overhead cables for a network tier: colour, width (SVG
/// units) and glow. Copper is orange, fiber thin glowing blue, InfiniBand
/// thick bundles, NVLink and optics bright.
(Color, double, double) cableStyle(String tierId) => switch (tierId) {
  'copper1g' => (const Color(0xFFD9822B), 3.0, 0.0),
  'copper10g' => (const Color(0xFFE89A45), 4.0, 0.0),
  'fiber100g' => (const Color(0xFF4FC3FF), 3.0, 3.0),
  'ib400g' => (const Color(0xFF6F8BFF), 7.0, 1.5),
  'ibspine' => (const Color(0xFF9A7CFF), 9.0, 2.0),
  'nvlink' => (const Color(0xFFB6FF6A), 8.0, 4.0),
  _ => (const Color(0xFFE6FFFF), 7.0, 5.0),
};

/// What the build interaction looks like right now (owned by the shell).
class BuildState {
  final bool buildMode;
  final String? activeRoom;
  final String? placing;
  final (String, int, int)? moveFrom;

  /// Planned (not yet bought) tiles in the active room, drawn as ghosts.
  final List<PlannedTile> plan;

  /// The game with [plan] carried out (Game.withPlan), for the heat,
  /// throttle and cluster preview. Null when there's no plan.
  final Game? preview;

  /// Whether a one-finger drag starting on (x, y) paints the selected part
  /// into the plan. When false (or null) the drag pans the map instead.
  final bool Function(String roomId, int x, int y)? canPaintFrom;

  const BuildState({
    this.buildMode = false,
    this.activeRoom,
    this.placing,
    this.moveFrom,
    this.plan = const [],
    this.preview,
    this.canPaintFrom,
  });
}

/// Everything the grid's look depends on. Equal keys reuse the built subtree.
class _GridKey {
  final int revision;
  final bool buildMode;
  final String? placing;
  final (int, int)? moveFrom;
  final String valid; // '1'/'0' per cell: empty and placeable right now
  final int tiers; // network × 100 + cooling: restyles cables, re-tints heat
  final List<PlannedTile> plan; // replaced (not mutated) on every change
  final Game? preview;

  const _GridKey(
    this.revision,
    this.buildMode,
    this.placing,
    this.moveFrom,
    this.valid,
    this.tiers,
    this.plan,
    this.preview,
  );

  factory _GridKey.of(Game g, RoomDef room, BuildState b) {
    final buf = StringBuffer();
    final placing = b.placing;
    final preview = b.preview;
    if (placing != null) {
      for (var y = 0; y < room.height; y++) {
        for (var x = 0; x < room.width; x++) {
          final ok =
              b.plan.isEmpty || preview == null
                  ? g.canPlace(room.id, x, y, placing)
                  : g.planBlockReasonIn(preview, room.id, b.plan, PlannedTile(x, y, placing)) ==
                      null;
          buf.write(ok ? '1' : '0');
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
      g.s.networkTier * 100 + g.s.coolingTier,
      b.plan,
      b.plan.isEmpty ? null : preview,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is _GridKey &&
      other.revision == revision &&
      other.buildMode == buildMode &&
      other.placing == placing &&
      other.moveFrom == moveFrom &&
      other.valid == valid &&
      other.tiers == tiers &&
      identical(other.plan, plan) &&
      identical(other.preview, preview);

  @override
  int get hashCode =>
      Object.hash(revision, buildMode, placing, moveFrom, valid, tiers, identityHashCode(plan));
}

/// Listens to the controller but only rebuilds the grid when its key changes.
class RoomGrid extends StatefulWidget {
  final GameController controller;
  final RoomDef room;
  final BuildState build;
  final void Function(String roomId, int x, int y) onCellTap;

  /// Drag-to-paint while placing: called for every cell the drag crosses
  /// (in order, no gaps), then [onPaintEnd].
  final void Function(String roomId, int x, int y)? onCellPaint;
  final VoidCallback? onPaintEnd;

  const RoomGrid({
    super.key,
    required this.controller,
    required this.room,
    required this.build,
    required this.onCellTap,
    this.onCellPaint,
    this.onPaintEnd,
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

  /// Sprite height of the tile at a cell, for tap hit-testing.
  double _heightOf(int x, int y) {
    // Ghosts count as what they'll be.
    final g = widget.build.plan.isEmpty ? null : widget.build.preview;
    final id = (g ?? widget.controller.game).tileAt(widget.room.id, x, y);
    return id == null ? 0 : tileSpriteHeights[id] ?? 30;
  }

  (int, int)? _lastPaint;
  Offset? _down;
  final _painted = <(int, int)>{};

  /// A drag paints only when it starts on a cell the selected part could
  /// be planned on; otherwise the pan recognizer stays out and the camera
  /// (CameraView's scale recognizer) pans the map.
  bool _paintStartsAt(RoomGeo geo, Offset local) {
    final can = widget.build.canPaintFrom;
    if (widget.build.placing == null || widget.onCellPaint == null || can == null) return false;
    final cell = geo.cellAtLocalTall(local, _heightOf);
    return cell != null && can(widget.room.id, cell.$1, cell.$2);
  }

  void _paintTo(RoomGeo geo, Offset local, {bool start = false}) {
    final cell = geo.cellAtLocal(local);
    if (start) {
      _painted.clear();
      _lastPaint = null;
    }
    if (cell == null) return;
    final from = _lastPaint ?? cell;
    // Every cell on the line from the last one (fast drags skip cells).
    final dx = cell.$1 - from.$1, dy = cell.$2 - from.$2;
    final n = math.max(dx.abs(), dy.abs());
    for (var i = 0; i <= n; i++) {
      final c = n == 0 ? cell : (from.$1 + (dx * i / n).round(), from.$2 + (dy * i / n).round());
      if (_painted.add(c)) widget.onCellPaint!(widget.room.id, c.$1, c.$2);
    }
    _lastPaint = cell;
  }

  void _endPaint() {
    _lastPaint = null;
    _down = null;
    if (_painted.isNotEmpty) widget.onPaintEnd?.call();
    _painted.clear();
  }

  @override
  Widget build(BuildContext context) {
    final g = widget.controller.game;
    final k = _GridKey.of(g, widget.room, widget.build);
    if (k != _key || _child == null) {
      _key = k;
      _child = _GridLayers(
        // With a plan, everything (heat, throttle, cluster) shows as if it
        // were built.
        game: k.preview ?? g,
        room: widget.room,
        geo: geoOf(widget.room.id),
        gridKey: k,
        placingKind: widget.build.placing == null ? null : tileById(widget.build.placing!)!.kind,
      );
    }
    final geo = geoOf(widget.room.id);
    final paint = widget.build.placing != null && widget.onCellPaint != null;
    return Stack(
      fit: StackFit.expand,
      children: [
        RepaintBoundary(child: _child),
        // One tap target for the whole floor; screen → diamond cell maths.
        Positioned.fill(
          child: RawGestureDetector(
            key: ValueKey('room-floor-${widget.room.id}'),
            behavior: HitTestBehavior.deferToChild,
            gestures: {
              TapGestureRecognizer: GestureRecognizerFactoryWithHandlers<TapGestureRecognizer>(
                () => TapGestureRecognizer(debugOwner: this),
                (r) =>
                    r.onTapUp = (d) {
                      final cell = geo.cellAtLocalTall(d.localPosition, _heightOf);
                      if (cell != null) widget.onCellTap(widget.room.id, cell.$1, cell.$2);
                    },
              ),
              // Placing: a drag that starts on a plannable cell paints the
              // part along its path. Any other drag (on a tile, with no part,
              // two fingers) is left to the camera, which pans the map.
              if (paint)
                PaintPanRecognizer: GestureRecognizerFactoryWithHandlers<PaintPanRecognizer>(
                  () => PaintPanRecognizer(debugOwner: this),
                  (r) {
                    r.canStart = (local) => _paintStartsAt(geo, local);
                    r.onDown = (d) => _down = d.localPosition;
                    r.onStart = (d) => _paintTo(geo, _down ?? d.localPosition, start: true);
                    r.onUpdate = (d) => _paintTo(geo, d.localPosition);
                    r.onEnd = (_) => _endPaint();
                    r.onCancel = _endPaint;
                  },
                ),
            },
            child: CustomPaint(painter: _FloorHitArea(geo, _heightOf), size: geo.size),
          ),
        ),
      ],
    );
  }
}

/// A pan recognizer for drag-painting that only joins the gesture arena
/// when the pointer goes down where painting may start ([canStart], in the
/// detector's local coordinates), and backs out as soon as a second finger
/// lands, so the camera gets pinches and pans.
class PaintPanRecognizer extends PanGestureRecognizer {
  PaintPanRecognizer({super.debugOwner});

  bool Function(Offset local)? canStart;
  int _pointers = 0;

  @override
  bool isPointerAllowed(PointerEvent event) {
    if (_pointers > 0) {
      // A second finger: this is a pinch or a two-finger pan, not a paint.
      resolve(GestureDisposition.rejected);
      return false;
    }
    if (!(canStart?.call(event.localPosition) ?? false)) return false;
    return super.isPointerAllowed(event);
  }

  @override
  void addAllowedPointer(PointerDownEvent event) {
    _pointers++;
    super.addAllowedPointer(event);
  }

  @override
  void didStopTrackingLastPointer(int pointer) {
    _pointers = 0;
    super.didStopTrackingLastPointer(pointer);
  }
}

/// Invisible; makes only the floor diamond and the tiles standing on it
/// hit-testable so taps elsewhere
/// (empty void, other rooms' signs) fall through.
class _FloorHitArea extends CustomPainter {
  final RoomGeo geo;
  final double Function(int x, int y) heightOf;
  _FloorHitArea(this.geo, this.heightOf);

  @override
  void paint(Canvas canvas, Size size) {}

  @override
  bool hitTest(Offset position) => geo.cellAtLocalTall(position, heightOf) != null;

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
    final cluster = g.trainingCluster;

    final glows = <(int, int, Color)>[];
    final valid = <(int, int)>[];
    final tilesLayer = <(int, int, TileStatus)>[];
    final planned = {for (final p in gridKey.plan) (p.x, p.y): p};
    // GPU cells per row, for the overhead cable trays.
    final rows = <int, List<int>>{};
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final st = at(x, y);
        final i = y * w + x;
        if (st != null && st.def.isGpu) {
          glows.add((x, y, st.inTrainingCluster ? AppColors.neon : AppColors.cyan));
          (rows[y] ??= []).add(x);
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
          if (planned[(x, y)] case final p?)
            Positioned.fromRect(
              key: ValueKey('plan-$x-$y'),
              rect: geo.tileRect(x, y),
              child: _TileArt(
                key: ValueKey('plan-$x-$y-${st.def.id}'),
                status: st,
                moving: false,
                ghost: true,
                swap: p.replace,
              ),
            )
          else
            Positioned.fromRect(
              key: ValueKey('tile-$x-$y'),
              rect: geo.tileRect(x, y),
              child: _TileArt(
                key: ValueKey('tile-$x-$y-${st.def.id}'),
                status: st,
                moving: mv == (x, y),
              ),
            ),
        // Overhead cable trays above the tiles (decorative; the whole room
        // is one cluster whatever the layout).
        if (rows.values.fold(0, (a, r) => a + r.length) > 1)
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter: _CablePainter(geo, rows, g.network.id, ground: room.width >= 18),
              ),
            ),
          ),
        if (gridKey.buildMode && cluster != null)
          Positioned(
            left: geo.svgToLocal(geo.gridSvg(w / 2, 0, 150)).dx - 90,
            top: geo.svgToLocal(geo.gridSvg(w / 2, 0, 150)).dy - 14,
            width: 180,
            child: IgnorePointer(child: Center(child: _ClusterLabel(game: g, cluster: cluster))),
          ),
      ],
    );
  }
}

/// "96 GPUs · trains · 256 fed": what the network keeps fed, in build mode.
class _ClusterLabel extends StatelessWidget {
  final Game game;
  final Cluster cluster;
  const _ClusterLabel({required this.game, required this.cluster});

  @override
  Widget build(BuildContext context) {
    final c = cluster;
    final color =
        c.overCap
            ? AppColors.red
            : c.gpus >= 0.8 * c.gpuCap
            ? AppColors.amber
            : AppColors.neon;
    return Container(
      key: const ValueKey('cluster-label'),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xE60B1220),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: color, width: 1.4),
      ),
      child: Text(
        '${formatNumber(c.gpus)} GPUs · trains · ${formatNumber(game.networkCap)} fed'
        '${c.overCap ? ' → ${formatPercent(c.scalingEfficiency)}' : ''}',
        maxLines: 1,
        style: numStyle(size: 10.5, color: color, weight: FontWeight.w700),
      ),
    );
  }
}

/// Cable trays hung above the GPU rows: one run per row over its GPUs, drops
/// down to each tile, and a trunk joining the rows. Style follows the tier.
/// On campus-sized sites ([ground]) every tile is a whole pod or building,
/// so the runs are buried fiber trenches on the ground instead: thin, dim
/// and without drops (overhead trays there floated far above the floor).
class _CablePainter extends CustomPainter {
  final RoomGeo geo;
  final Map<int, List<int>> rows;
  final String tierId;
  final bool ground;
  _CablePainter(this.geo, this.rows, this.tierId, {this.ground = false});

  double get _z => ground ? 1.0 : 105.0;

  @override
  void paint(Canvas canvas, Size size) {
    var (color, width, glow) = cableStyle(tierId);
    if (ground) {
      color = color.withValues(alpha: 0.45);
      width *= 0.45;
      glow = 0;
    }
    final sw = width * geo.scale * 1.6;
    final shadow =
        Paint()
          ..color = const Color(0xAA05070D)
          ..strokeWidth = sw + 3
          ..strokeCap = StrokeCap.round
          ..style = PaintingStyle.stroke;
    final cable =
        Paint()
          ..color = color
          ..strokeWidth = sw
          ..strokeCap = StrokeCap.round
          ..style = PaintingStyle.stroke;
    if (glow > 0) cable.maskFilter = MaskFilter.blur(BlurStyle.solid, glow);
    final drop =
        Paint()
          ..color = color.withValues(alpha: 0.55)
          ..strokeWidth = math.max(1, sw * 0.45);
    Offset p(double gx, double gy, [double? z]) => geo.svgToLocal(geo.gridSvg(gx, gy, z ?? _z));
    final ys = rows.keys.toList()..sort();
    final path = Path();
    var trunkX = double.infinity;
    for (final y in ys) {
      final xs = rows[y]!..sort();
      trunkX = math.min(trunkX, xs.first.toDouble());
    }
    for (final y in ys) {
      final xs = rows[y]!;
      final a = p(trunkX + 0.5, y + 0.5), b = p(xs.last + 0.5, y + 0.5);
      path
        ..moveTo(a.dx, a.dy)
        ..lineTo(b.dx, b.dy);
      if (!ground) {
        for (final x in xs) {
          canvas.drawLine(p(x + 0.5, y + 0.5), p(x + 0.5, y + 0.5, 70), drop);
        }
      }
    }
    if (ys.length > 1) {
      final a = p(trunkX + 0.5, ys.first + 0.5), b = p(trunkX + 0.5, ys.last + 0.5);
      path
        ..moveTo(a.dx, a.dy)
        ..lineTo(b.dx, b.dy);
    }
    canvas.drawPath(path, shadow);
    canvas.drawPath(path, cable);
  }

  @override
  bool shouldRepaint(_CablePainter old) =>
      old.tierId != tierId || old.rows != rows || old.ground != ground;
}

class _FloorPainter extends CustomPainter {
  final RoomGeo geo;
  final bool buildMode;
  final List<(int, int, Color)> glows;
  final (int, int)? moveFrom;

  _FloorPainter({
    required this.geo,
    required this.buildMode,
    required this.glows,
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
    // Training-cluster glow under every GPU.
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

  /// Planned, not bought: drawn see-through (with an arrow for a swap).
  final bool ghost;
  final bool swap;
  const _TileArt({
    super.key,
    required this.status,
    required this.moving,
    this.ghost = false,
    this.swap = false,
  });

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
    final heat =
        st.def.isGpu && st.throttling ? ((1 - st.speed) / (1 - minThrottleSpeed)).clamp(0.0, 1.0) : 0.0;
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
                if (widget.ghost) Opacity(opacity: 0.5, child: art) else art,
                if (widget.swap)
                  Positioned(
                    left: 0,
                    right: 0,
                    top: s * 0.3,
                    child: Center(
                      child: Icon(
                        Icons.arrow_circle_up_rounded,
                        color: AppColors.neon,
                        size: math.max(12.0, s * 0.16),
                      ),
                    ),
                  ),
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
