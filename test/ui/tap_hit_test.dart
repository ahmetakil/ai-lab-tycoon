import 'package:ai_lab_tycoon/ui/world/world_layout.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final geo = roomGeos['colo']!;
  // A GPU (24 tall) at (3,3) in front of a tall cooler (71) at (2,2).
  double heights(int x, int y) => switch ((x, y)) {
    (3, 3) => 24,
    (2, 2) => 71,
    _ => 0,
  };

  test(
    'a tap on a low GPU\'s top face picks the GPU, not the cooler behind it',
    () {
      final top = geo.svgToLocal(geo.gridSvg(3.1, 3.1, 22));
      expect(
        geo.cellAtLocal(top),
        (2, 2),
        reason: 'the floor maths alone picks the cell behind',
      );
      expect(geo.cellAtLocalTall(top, heights), (3, 3));
    },
  );

  test('a tap on a tall cooler\'s upper body picks the cooler', () {
    final side = geo.svgToLocal(geo.gridSvg(2.5, 2.5, 65));
    expect(geo.cellAtLocalTall(side, heights), (2, 2));
  });

  test('empty floor still maps to its own cell', () {
    final floor = geo.svgToLocal(geo.gridSvg(5.5, 1.5));
    expect(geo.cellAtLocalTall(floor, heights), (5, 1));
  });
}
