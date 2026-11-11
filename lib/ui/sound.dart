// Sound contract. UI code calls Sound.play(Sfx.x) and never touches players
// directly. The audio pass implements this file and adds assets/audio/<name>.mp3.
//
// STUB: currently a no-op so the UI can be built in parallel.

enum Sfx {
  click,
  purchase,
  upgrade,
  trainingStart,
  trainingDone,
  release,
  stuntFail,
  eraUp,
  rivalBeaten,
  viralAlarm,
  error,
}

abstract final class Sound {
  static bool muted = false;
  static bool musicOn = true;

  static Future<void> init() async {}
  static void play(Sfx sfx) {}
  static Future<void> startMusic() async {}
  static Future<void> stopMusic() async {}
  static void setMuted(bool value) => muted = value;
}
