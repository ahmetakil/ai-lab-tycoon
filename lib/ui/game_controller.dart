import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../sim/game.dart';
import '../sim/game_state.dart';
import '../sim/news.dart';

/// Owns the Game, drives the real-time loop, saves/loads, and broadcasts
/// sim events to the UI. Widgets listen via ListenableBuilder / AnimatedBuilder.
class GameController extends ChangeNotifier with WidgetsBindingObserver {
  static const _saveKey = 'save_v1';
  static const _savedAtKey = 'saved_at_v1';

  Game game;
  Timer? _loop;
  Timer? _autosave;
  DateTime _lastTick = DateTime.now();
  final _events = StreamController<GameEvent>.broadcast();

  /// Debug speed multiplier (1 = normal).
  double speed = 1;

  /// Bumped by [resetGame]; the app rebuilds the whole shell on it.
  final resets = ValueNotifier<int>(0);

  /// Set after load if the player was away; the UI shows it once and clears it.
  OfflineReport? offlineReport;

  GameController._(this.game);

  /// Sim events (releases, rival beaten, viral spikes…) for toasts/sounds.
  Stream<GameEvent> get events => _events.stream;

  static Future<GameController> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_saveKey);
    Game game;
    OfflineReport? report;
    if (raw != null) {
      try {
        game = Game(GameState.fromJson(jsonDecode(raw) as Map<String, dynamic>));
        final savedAt = prefs.getInt(_savedAtKey);
        // An old, incompatible save loads as a fresh game: it gets no
        // offline progress (it would hand a brand-new lab up to 2 h of
        // earnings, enough for a garage full of V100s at once).
        if (savedAt != null && !game.s.startedFromOldSave) {
          final away = DateTime.now()
                  .difference(DateTime.fromMillisecondsSinceEpoch(savedAt))
                  .inMilliseconds /
              1000.0;
          if (away > 60) report = game.catchUp(away);
          game.events.clear();
        }
      } catch (_) {
        game = Game(); // corrupt save → fresh start
      }
    } else {
      game = Game();
    }
    final c = GameController._(game)..offlineReport = report;
    c._start();
    return c;
  }

  void _start() {
    WidgetsBinding.instance.addObserver(this);
    _lastTick = DateTime.now();
    _loop = Timer.periodic(const Duration(milliseconds: 100), (_) => _onTick());
    _autosave = Timer.periodic(const Duration(seconds: 10), (_) => save());
  }

  void _onTick() {
    final now = DateTime.now();
    var dt = now.difference(_lastTick).inMilliseconds / 1000.0;
    _lastTick = now;
    // Long gaps (tab hidden, app suspended) are handled as offline progress.
    if (dt > 5) {
      final report = game.catchUp(dt);
      if (dt > 60) offlineReport = report;
      game.events.clear();
      dt = 0;
    }
    if (dt > 0) game.advance(dt * speed);
    _flushEvents();
    notifyListeners();
  }

  void _flushEvents() {
    for (final e in game.events) {
      _events.add(e);
    }
    game.events.clear();
  }

  /// Wrap every player action so the UI updates and events fire immediately.
  T act<T>(T Function(Game g) action) {
    final result = action(game);
    _flushEvents();
    notifyListeners();
    return result;
  }

  void clearOfflineReport() {
    offlineReport = null;
    notifyListeners();
  }

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_saveKey, jsonEncode(game.s.toJson()));
    await prefs.setInt(_savedAtKey, DateTime.now().millisecondsSinceEpoch);
  }

  Future<void> resetGame() async {
    game = Game();
    offlineReport = null;
    // A fresh game starts at normal speed, not at the last playtest speed.
    speed = 1;
    await save();
    // A full restart: the intro and the tutorial play again too. (Sound
    // settings and the analytics id are kept.)
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('intro_seen_v1'); // kIntroSeenKey
    await prefs.remove('tutorial_done_v1'); // GameShell._tutorialKey
    resets.value++;
    notifyListeners();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden) {
      save();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _loop?.cancel();
    _autosave?.cancel();
    _events.close();
    super.dispose();
  }
}
