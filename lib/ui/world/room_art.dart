// Shapes of the generated room art metadata (see room_art.g.dart, written by
// tool/art/generate_rooms.py). All coordinates are SVG units: one grid cell
// is 100 units and the room floor's back corner is the origin.

/// A point the game animates on top of the room art.
/// Kinds: bulb, tube, screen, led, steam, window.
class RoomLight {
  final String kind;
  final double x, y;
  final int color;
  const RoomLight(this.kind, this.x, this.y, this.color);
}

class RoomArt {
  /// The image's viewBox: (left, top, width, height).
  final (double, double, double, double) vb;

  /// Prop strip along the back walls, in cells; the grid starts at (margin, margin).
  final double margin;
  final double wall;

  /// Where "you" sit, if this room has a desk.
  final (double, double)? seat;
  final List<RoomLight> lights;

  const RoomArt({
    required this.vb,
    required this.margin,
    required this.wall,
    required this.seat,
    required this.lights,
  });
}
