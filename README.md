# AI Lab Tycoon

An idle tycoon game: grow an AI lab from one gaming GPU in a garage to a gigawatt datacenter,
and race parody versions of the big AI labs through history (2017 → 2026). Every upgrade is a
real technique (quantization, FlashAttention, MoE, RLHF…) with a one-line explanation.

Flutter app for iOS, Android and web.

## Run
```sh
flutter pub get
flutter run -d chrome          # web
flutter run                    # device / simulator
```
Debug builds have a ×10 / ×60 speed toggle in Settings (gear icon).

## Checks
```sh
flutter analyze
flutter test                                 # sim, UI, moments, audio, layout at phone sizes
dart run tool/balance_sim.dart 300           # headless playthrough → pacing table
LAYOUT_PREVIEW_DIR=/tmp/shots flutter test test/ui/layout_test.dart   # PNG screenshots of every tab
flutter build web --release
```

## Layout
- `lib/sim/`: pure-Dart simulation (content, balance knobs, game logic, save state, bot)
- `lib/ui/`: Flutter UI (`screens/`, `widgets/`, `moments/` for releases, celebrations and the share card)
- `assets/`: procedural art, generated audio (`tool/audio/generate_audio.py`), OFL fonts
- `docs/`: DESIGN.md, BALANCE.md, research/rival_labs.md (sourced rival data)

All lab, model and GPU names are parodies. See `assets/CREDITS.md`.
