import 'dart:io';

import 'package:ai_lab_tycoon/ui/sound.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('audio assets', () {
    test('every Sfx has a non-empty mp3 in assets/audio', () {
      for (final sfx in Sfx.values) {
        final file = File('assets/${Sound.assetFor(sfx)}');
        expect(file.existsSync(), isTrue, reason: '${file.path} is missing');
        expect(file.lengthSync(), greaterThan(500), reason: file.path);
      }
    });

    test('music loop exists and stays under 1.5 MB', () {
      final file = File('assets/${Sound.musicAsset}');
      expect(file.existsSync(), isTrue);
      expect(file.lengthSync(), lessThan(1536 * 1024));
    });

    test('credits file exists', () {
      expect(File('assets/audio/CREDITS.md').existsSync(), isTrue);
    });
  });

  group('Sound', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('init, play, music calls never throw in tests', () async {
      await Sound.init();
      for (final sfx in Sfx.values) {
        Sound.play(sfx);
      }
      await Sound.startMusic();
      await Sound.stopMusic();
      Sound.setMusicOn(false);
      Sound.setMusicOn(true);
      Sound.setMuted(true);
      Sound.setMuted(false);
      await Future<void>.delayed(const Duration(milliseconds: 10));
    });

    test('same sound is throttled, different sounds are not', () async {
      await Sound.init();
      await Future<void>.delayed(const Duration(milliseconds: 80));
      final before = Sound.debugAccepted;
      Sound.play(Sfx.click);
      Sound.play(Sfx.click);
      Sound.play(Sfx.click);
      Sound.play(Sfx.purchase);
      expect(Sound.debugAccepted - before, 2);
      await Future<void>.delayed(const Duration(milliseconds: 80));
      Sound.play(Sfx.click);
      expect(Sound.debugAccepted - before, 3);
    });

    test('muted blocks playback and persists', () async {
      await Sound.init();
      await Future<void>.delayed(const Duration(milliseconds: 80));
      Sound.setMuted(true);
      expect(Sound.muted, isTrue);
      final before = Sound.debugAccepted;
      Sound.play(Sfx.eraUp);
      expect(Sound.debugAccepted, before);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('sound.muted'), isTrue);
      Sound.setMuted(false);
      expect(Sound.muted, isFalse);
    });

    test('musicOn toggles and persists', () async {
      await Sound.init();
      Sound.setMusicOn(false);
      expect(Sound.musicOn, isFalse);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('sound.musicOn'), isFalse);
      Sound.musicOn = true;
      expect(Sound.musicOn, isTrue);
    });
  });
}
