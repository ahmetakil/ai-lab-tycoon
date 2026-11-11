# Credits

## Fonts

| Family (pubspec) | Files | Source | Licence |
|---|---|---|---|
| `SpaceGrotesk` | `fonts/SpaceGrotesk/SpaceGrotesk-{Regular,Medium,Bold}.ttf` | https://github.com/floriankarsten/space-grotesk (static TTFs) | SIL Open Font License 1.1, see `fonts/SpaceGrotesk/OFL.txt` |
| `JetBrainsMono` | `fonts/JetBrainsMono/JetBrainsMono-{Regular,Bold}.ttf` | https://github.com/JetBrains/JetBrainsMono | SIL Open Font License 1.1, see `fonts/JetBrainsMono/OFL.txt` |

The OFL.txt files are copied from the google/fonts repository (`ofl/spacegrotesk`, `ofl/jetbrainsmono`).

## Images

All images in `images/` (era backgrounds, hardware, power, upgrade, category and
rival icons, logo, player emblem) and the launcher icons in `images/launcher/` were
made for this project by an AI coding assistant (Claude, Anthropic), working in Claude Code.
They are procedurally drawn vector art: Python scripts emit isometric SVG, and
`rsvg-convert` / ImageMagick rasterize it. No image-generation model was used, because
the planned Gemini image API was not available. The logo title is set in Space Grotesk Bold,
converted to outlines.

Rival emblems are original parody marks. They do not reproduce any real company's logo.

## Grid tiles

`images/tile_*.png` (grid tile sprites and the `tile_overlay_heat` / `tile_overlay_link`
overlays), `images/floor_*.png` (128×128 seamless room floors) and `images/room_*.png`
(900×300 room banners) were made the same way as the images above: procedural vector art
drawn by Claude (Anthropic) in Claude Code, with no image-generation model. The generator is
`tool/art/generate_tiles.py` (with `tool/art/iso.py`). Re-run it from the repo root with
`python3 tool/art/generate_tiles.py`; it needs `rsvg-convert` and ImageMagick 7.
`room_garage`, `room_closet` and `room_hall` are crops of `bg_garage`, `bg_startup` and `bg_lab`.

Visual language: every tile is drawn in one fixed isometric view box (light from the top left,
top face lightest, right face darkest). A soft floor glow marks the kind: green for GPUs, cyan
for cooling, amber for network.
