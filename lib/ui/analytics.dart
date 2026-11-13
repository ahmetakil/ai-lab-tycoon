import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../sim/game.dart';
import 'game_controller.dart';

/// Anonymous product analytics and crash reports (PostHog, plain HTTP so it
/// works the same on web and mobile).
///
/// Off unless the build passes a project key:
///   flutter build web --dart-define=POSTHOG_KEY=phc_... \
///     [--dart-define=POSTHOG_HOST=https://eu.i.posthog.com] \
///     [--dart-define=APP_BUILD=<git sha>]
///
/// Sends only a random per-install id and game facts (era, room, playtime,
/// ratings); no names, emails or save contents. Person profiles are off
/// (`$process_person_profile: false`), which is enough for daily users.
class Analytics {
  static const _key = String.fromEnvironment('POSTHOG_KEY');
  static const _host = String.fromEnvironment('POSTHOG_HOST', defaultValue: 'https://us.i.posthog.com');
  static const _build = String.fromEnvironment('APP_BUILD', defaultValue: 'dev');
  static const _idKey = 'analytics_id_v1';

  /// At most this many crash reports per app session (a broken frame can
  /// throw every tick).
  static const _maxErrors = 20;

  static bool get enabled => _key.isNotEmpty;

  static String? _id;
  static final _session = _randomId();
  static final _queue = <Map<String, Object?>>[];
  static Timer? _flushTimer;
  static int _errors = 0;
  static GameController? _controller;

  static String _randomId() {
    final r = math.Random.secure();
    return List.generate(16, (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
  }

  static String get _platform {
    if (kIsWeb) return 'web';
    return defaultTargetPlatform.name;
  }

  /// Call once before runApp: hooks crash handlers. Safe when disabled.
  static Future<void> init() async {
    if (!enabled) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      _id = prefs.getString(_idKey);
      if (_id == null) {
        _id = _randomId();
        await prefs.setString(_idKey, _id!);
      }
    } catch (_) {
      _id = _randomId();
    }
    final previousFlutter = FlutterError.onError;
    FlutterError.onError = (details) {
      captureError(details.exception, details.stack, fatal: false, context: details.context?.toString());
      previousFlutter?.call(details);
    };
    final dispatcher = PlatformDispatcher.instance;
    final previous = dispatcher.onError;
    dispatcher.onError = (error, stack) {
      captureError(error, stack, fatal: true);
      return previous?.call(error, stack) ?? false;
    };
    _flushTimer = Timer.periodic(const Duration(seconds: 30), (_) => flush());
  }

  /// Start following [controller]: app open, game milestones, heartbeats.
  static void attach(GameController controller) {
    if (!enabled) return;
    _controller = controller;
    capture(kIsWeb ? r'$pageview' : 'app_opened', {
      if (kIsWeb) r'$current_url': Uri.base.toString(),
      'returning': controller.game.s.time > 0,
      'offline_minutes': controller.offlineReport == null ? null : (controller.offlineReport!.seconds / 60).round(),
    });
    controller.events.listen(_onGameEvent);
    // Active play time: one heartbeat a minute while the app is open.
    Timer.periodic(const Duration(minutes: 1), (_) {
      if (WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
        capture('heartbeat');
      }
    });
  }

  static void _onGameEvent(GameEvent e) {
    switch (e) {
      case EraUnlocked(:final era):
        capture('era_unlocked', {'unlocked_era': era.name});
      case RoomMoved(:final from, :final to):
        capture('room_moved', {'from_room': from.id, 'to_room': to.id});
      case RivalBeaten(:final rival):
        capture('rival_beaten', {'rival': '${rival.lab} ${rival.model}'});
      case ModelReleased(:final release, :final stunt):
        capture('model_released', {
          'rating': release.rating.round(),
          'open_weights': release.open,
          'stunt': stunt.id,
          if (release.review != null) 'review_average': release.review!.average,
        });
      default:
        break;
    }
  }

  /// Game facts sent with every event.
  static Map<String, Object?> _gameProps() {
    final g = _controller?.game;
    if (g == null) return const {};
    return {
      'era': g.s.era.name,
      'room': g.s.roomId,
      'playtime_min': (g.s.time / 60).round(),
      'rating': g.s.currentModel.rating.round(),
      'speed': _controller!.speed,
    };
  }

  static void capture(String event, [Map<String, Object?> props = const {}]) {
    if (!enabled || _id == null) return;
    _queue.add({
      'event': event,
      'timestamp': DateTime.now().toUtc().toIso8601String(),
      'properties': {
        'distinct_id': _id,
        r'$session_id': _session,
        r'$process_person_profile': false,
        r'$lib': 'ai_lab_tycoon',
        'platform': _platform,
        'app_build': _build,
        ..._gameProps(),
        for (final p in props.entries)
          if (p.value != null) p.key: p.value,
      },
    });
    if (_queue.length >= 20) flush();
  }

  /// A crash or error in PostHog's error-tracking shape (`$exception`).
  static void captureError(Object error, StackTrace? stack, {bool fatal = false, String? context}) {
    if (!enabled || _errors >= _maxErrors) return;
    _errors++;
    final trace = stack?.toString() ?? '';
    capture(r'$exception', {
      r'$exception_list': [
        {
          'type': error.runtimeType.toString(),
          'value': _clip(error.toString(), 1000),
          'mechanism': {'handled': !fatal, 'synthetic': false},
        },
      ],
      r'$exception_level': fatal ? 'fatal' : 'error',
      'stack': _clip(trace, 6000),
      'context': context,
    });
    flush(); // a crash may be the last thing this session does
  }

  static String _clip(String s, int n) => s.length <= n ? s : s.substring(0, n);

  /// Send what's queued. Failures drop the batch (analytics never blocks
  /// or retries into a loop).
  static Future<void> flush() async {
    if (_queue.isEmpty) return;
    final batch = List.of(_queue);
    _queue.clear();
    try {
      await http
          .post(
            Uri.parse('$_host/batch/'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'api_key': _key, 'batch': batch}),
          )
          .timeout(const Duration(seconds: 10));
    } catch (_) {
      // Offline or blocked by an ad blocker: fine.
    }
  }

  @visibleForTesting
  static void dispose() => _flushTimer?.cancel();
}
