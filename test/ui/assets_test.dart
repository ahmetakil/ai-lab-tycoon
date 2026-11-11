// Every asset path the UI asks GameArt for must exist for the core content.
import 'dart:io';

import 'package:ai_lab_tycoon/sim/content.dart';
import 'package:ai_lab_tycoon/ui/game_assets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('every era has a background', () {
    for (final era in Era.values) {
      expect(File(GameArt.eraBackground(era)).existsSync(), isTrue, reason: era.name);
    }
  });

  test('every tile, room, power tier and upgrade has art', () {
    for (final t in tiles) {
      expect(File(GameArt.tile(t.id)).existsSync(), isTrue, reason: t.id);
    }
    for (final r in rooms) {
      expect(File(GameArt.floor(r.id)).existsSync(), isTrue, reason: r.id);
      expect(File(GameArt.roomBanner(r.id)).existsSync(), isTrue, reason: r.id);
    }
    for (final p in powerTiers) {
      expect(File(GameArt.power(p.id)).existsSync(), isTrue, reason: p.id);
    }
    for (final u in upgrades) {
      expect(File(GameArt.upgrade(u.id)).existsSync(), isTrue, reason: u.id);
    }
  });
}
