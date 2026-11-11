// Where everything sits on the one world map, and the isometric maths that
// maps grid cells to world/screen points and back.
import 'dart:math' as math;
import 'dart:ui';

import '../../sim/content.dart';
import 'room_art.dart';
import 'room_art.g.dart';

const c30 = 0.8660254037844386;

/// Isometric projection shared with tool/art/iso.py (SVG units).
Offset isoPt(double x, double y, [double z = 0]) => Offset((x - y) * c30, (x + y) * 0.5 - z);

/// Story layout: the garage beside the parents' house, the strip-mall
/// closet, the colo building, then the datacenter plots further out. You
/// only ever see the room you're in and the next one, so each consecutive
/// pair must not overlap. Values are the world position of each floor's
/// centre and world units per SVG unit.
const _placements = <String, (Offset, double)>{
  'house': (Offset(470, 800), 0.62),
  'garage': (Offset(1080, 960), 0.62),
  'closet': (Offset(2000, 820), 0.55),
  'colo': (Offset(3040, 960), 0.5),
  'hall': (Offset(3520, 1880), 0.45),
  'campus': (Offset(2200, 2350), 0.42),
  'gigasite': (Offset(640, 3250), 0.42),
};

/// Geometry of one room (or decor piece) on the world map.
class RoomGeo {
  final String id;
  final RoomArt art;
  final double scale;

  /// World position of the SVG origin (the floor's back corner).
  final Offset origin;
  final int w, h;

  RoomGeo._(this.id, this.art, this.scale, this.origin, this.w, this.h);

  factory RoomGeo(String id) {
    final art = roomArt[id]!;
    final (center, scale) = _placements[id]!;
    final room = roomById(id);
    final w = room?.width ?? 0, h = room?.height ?? 0;
    final side = (math.max(w, h) + art.margin) * 100;
    // The floor centre is isoPt(side/2, side/2) = (0, side/2) in SVG units.
    final origin = center - Offset(0, side / 2) * scale;
    return RoomGeo._(id, art, scale, origin, w, h);
  }

  double get _m => art.margin * 100;
  double get side => (math.max(w, h) + art.margin) * 100;

  /// The image (and the room widget) in world coordinates.
  Rect get rect {
    final (x, y, vw, vh) = art.vb;
    return Rect.fromLTWH(origin.dx + x * scale, origin.dy + y * scale, vw * scale, vh * scale);
  }

  Size get size => rect.size;

  /// SVG units → room-local pixels (relative to [rect]'s top-left).
  Offset svgToLocal(Offset s) {
    final (x, y, _, _) = art.vb;
    return Offset((s.dx - x) * scale, (s.dy - y) * scale);
  }

  Offset localToSvg(Offset l) {
    final (x, y, _, _) = art.vb;
    return Offset(l.dx / scale + x, l.dy / scale + y);
  }

  Offset localToWorld(Offset l) => rect.topLeft + l;

  /// Floor point (SVG units, z = 0) of grid coordinates (fractional cells).
  Offset gridSvg(double gx, double gy, [double z = 0]) => isoPt(_m + gx * 100, _m + gy * 100, z);

  Offset cellCenterLocal(int x, int y, [double z = 0]) => svgToLocal(gridSvg(x + 0.5, y + 0.5, z));

  /// The four floor corners of a cell in local pixels (top, right, bottom, left).
  List<Offset> cellDiamond(int x, int y, {double inset = 0}) {
    final a = inset, b = 1 - inset;
    return [
      svgToLocal(gridSvg(x + a, y + a)),
      svgToLocal(gridSvg(x + b, y + a)),
      svgToLocal(gridSvg(x + b, y + b)),
      svgToLocal(gridSvg(x + a, y + b)),
    ];
  }

  /// Which grid cell a room-local point lands on (floor plane), or null.
  (int, int)? cellAtLocal(Offset l) {
    final s = localToSvg(l);
    final u = s.dx / c30, v = s.dy * 2;
    final gx = ((v + u) / 2 - _m) / 100, gy = ((v - u) / 2 - _m) / 100;
    if (gx < 0 || gy < 0 || gx >= w || gy >= h) return null;
    return (gx.floor(), gy.floor());
  }

  /// Tile sprite rect (tile_*.png: viewBox -100,-84,200,200 with the cell
  /// footprint at [0,100]²) in local pixels.
  Rect tileRect(int x, int y) {
    final corner = svgToLocal(gridSvg(x.toDouble(), y.toDouble()));
    return Rect.fromLTWH(corner.dx - 100 * scale, corner.dy - 84 * scale, 200 * scale, 200 * scale);
  }

  /// Floor centre in world coordinates.
  Offset get worldCenter => origin + Offset(0, side / 2) * scale;

  /// What the camera frames to show this room: floor plus walls.
  Rect get frameRect {
    final halfW = side * c30 * scale;
    return Rect.fromLTRB(
      worldCenter.dx - halfW,
      origin.dy - art.wall * scale,
      worldCenter.dx + halfW,
      origin.dy + side * scale,
    );
  }

  Offset seatLocal() {
    final s = art.seat!;
    return svgToLocal(Offset(s.$1, s.$2));
  }
}

final Map<String, RoomGeo> roomGeos = {
  for (final id in [..._placements.keys]) id: RoomGeo(id),
};

RoomGeo geoOf(String roomId) => roomGeos[roomId]!;

/// The whole world canvas (everything fits inside, with a margin).
final Rect worldRect = () {
  var r = roomGeos.values.first.rect;
  for (final g in roomGeos.values) {
    r = r.expandToInclude(g.rect);
  }
  return Rect.fromLTRB(0, 0, r.right + 400, r.bottom + 400);
}();

/// Public for tests: room-local centre of a cell.
Offset cellCenterLocal(String roomId, int x, int y) => geoOf(roomId).cellCenterLocal(x, y);
