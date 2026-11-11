# AI Lab Tycoon

Personal side project (Flutter idle tycoon game). Unrelated to Routely — never use Routely names, IDs or accounts here.

- `lib/sim/` is pure Dart (no Flutter imports): content.dart (data), balance.dart (knobs), game.dart (logic), game_state.dart (save state). Keep it deterministic.
- `lib/ui/` is Flutter. Widgets read `controller.game` and mutate only via `controller.act((g) => ...)`.
- Assets: paths come from `lib/ui/game_assets.dart`; sounds via `Sound.play(Sfx.x)` in `lib/ui/sound.dart`.
- Balance: `dart run tool/balance_sim.dart 240` plays headlessly; check pacing after any balance change.
- Checks: `flutter analyze` and `flutter test` must pass. Web build: `flutter build web`.
- Design: docs/DESIGN.md. Rival data and sources: docs/research/rival_labs.md.
- Parody names only for labs, companies and AI models. Real hardware product names (H100, RTX 4090, InfiniBand) are fine; tile ids keep their class names. Upgrade blurbs must be technically accurate.
