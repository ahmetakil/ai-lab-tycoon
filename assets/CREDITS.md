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
