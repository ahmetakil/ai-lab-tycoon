import 'package:flutter/material.dart';

import '../sim/content.dart';

/// Single source of truth for asset paths. The art pass fills assets/images/
/// using exactly these file names. Missing files fall back to an icon, so the
/// UI never breaks while art is in progress.
abstract final class GameArt {
  static String eraBackground(Era era) => 'assets/images/bg_${era.name}.png';
  static String tile(String tileId) => 'assets/images/tile_$tileId.png';
  static String floor(String roomId) => 'assets/images/floor_$roomId.png';
  static String roomBanner(String roomId) => 'assets/images/room_$roomId.png';

  /// Cutaway isometric room (floor, back walls, props) for the world map, or
  /// decor ('house'). Made by tool/art/generate_rooms.py.
  static String world(String id) => 'assets/images/world_$id.webp';
  static const tileHeatOverlay = 'assets/images/tile_overlay_heat.png';
  static const tileLinkOverlay = 'assets/images/tile_overlay_link.png';
  static String power(String id) => 'assets/images/power_$id.png';
  static String upgrade(String id) => 'assets/images/up_$id.png';
  static String upgradeCategory(UpgradeCategory c) => 'assets/images/cat_${c.name}.png';
  static String rivalLogo(String lab) =>
      'assets/images/rival_${lab.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_')}.png';
  static const logo = 'assets/images/logo.png';
  static const logoIcon = 'assets/images/logo_icon.png'; // icon-only, for small sizes
  static const playerLab = 'assets/images/player_lab.png';
}

/// Image.asset with a graceful icon fallback while art is missing.
class GameImage extends StatelessWidget {
  final String path;
  final IconData fallback;
  final double size;
  final BoxFit fit;

  const GameImage(
    this.path, {
    super.key,
    this.fallback = Icons.memory,
    this.size = 48,
    this.fit = BoxFit.contain,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Image.asset(
        path,
        fit: fit,
        filterQuality: FilterQuality.medium,
        errorBuilder: (context, _, __) => Icon(
          fallback,
          size: size * 0.6,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }
}
