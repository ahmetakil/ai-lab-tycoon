// OWNER: ui-moments agent.
// Wraps the app: listens to controller.events and shows toasts, banners,
// full-screen celebrations (queued, never stacked), the rival news ticker
// (one card at a time), the offline "while you were away" dialog and the
// first-launch intro.
import 'dart:async';
import 'dart:collection';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../sim/balance.dart';
import '../../sim/content.dart';
import '../../sim/game.dart';
import '../../sim/news.dart';
import '../shell/hud_overlay.dart' show hudHeight;
import '../format.dart';
import '../game_controller.dart';
import '../sound.dart';
import 'confetti.dart';
import 'intro.dart';
import 'moments_style.dart';
import 'news_feed.dart';
import 'launch_reviews.dart';
import 'release_card.dart';
import 'release_sheet.dart';
import 'rivals_screen.dart';

const kIntroSeenKey = 'intro_seen_v1';

/// How long the world map's reveal fly-over gets before the era moment.
const kEraRevealDelay = Duration(milliseconds: 1900);

class EventPresenter extends StatefulWidget {
  final GameController controller;
  final Widget child;
  const EventPresenter({
    super.key,
    required this.controller,
    required this.child,
  });

  @override
  State<EventPresenter> createState() => _EventPresenterState();
}

class _ToastData {
  final int id;
  final IconData icon;
  final Color color;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final Duration duration;
  _ToastData({
    required this.id,
    required this.icon,
    required this.color,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
    this.duration = const Duration(milliseconds: 4200),
  });
}

class _EventPresenterState extends State<EventPresenter> {
  StreamSubscription<GameEvent>? _sub;
  OverlayEntry? _layer;
  final _changed = ValueNotifier(0);
  final _toasts = <_ToastData>[];
  final _queue = Queue<GameEvent>();
  GameEvent? _current;
  int _nextId = 0;

  /// Rival feed: news items not shown yet, the one on screen, and the
  /// newest serial already queued (or put in the offline digest).
  final _newsQueue = Queue<NewsItem>();
  NewsItem? _newsCurrent;
  int _newsSeen = 0;

  /// True while the intro or offline dialog is up; celebrations wait.
  bool _blocked = true;

  /// Toasts held while the launch reviews play (launchReviewsActive).
  final _heldToasts = <VoidCallback>[];
  bool _offlineShowing = false;

  GameController get c => widget.controller;

  @override
  void initState() {
    super.initState();
    _sub = c.events.listen(_onEvent);
    c.addListener(_onController);
    launchReviewsActive.addListener(_onReviews);
    // News from before this screen (last session, or offline) isn't toasted.
    _newsSeen = c.game.lastNewsSerial;
    WidgetsBinding.instance.addPostFrameCallback((_) => _startup());
  }

  @override
  void didUpdateWidget(EventPresenter old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller.removeListener(_onController);
      _sub?.cancel();
      _sub = c.events.listen(_onEvent);
      c.addListener(_onController);
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    c.removeListener(_onController);
    launchReviewsActive.removeListener(_onReviews);
    _layer?.remove();
    _layer?.dispose();
    _changed.dispose();
    super.dispose();
  }

  void _bump() => _changed.value++;

  /// The reviews closed: show what waited.
  void _onReviews() {
    if (!mounted) return;
    _bump(); // hides / shows the bottom toasts
    if (launchReviewsActive.value) return;
    final held = List.of(_heldToasts);
    _heldToasts.clear();
    for (final t in held) {
      t();
    }
    _advanceQueue();
    _advanceNews();
  }

  Future<void> _startup() async {
    if (!mounted) return;
    final overlay = Overlay.maybeOf(context);
    if (overlay != null) {
      _layer = OverlayEntry(builder: (_) => _buildLayer());
      overlay.insert(_layer!);
    }
    await _maybeShowIntro();
    await _maybeShowOffline();
    _blocked = false;
    _advanceQueue();
    _advanceNews();
  }

  Future<void> _maybeShowIntro() async {
    SharedPreferences? prefs;
    try {
      prefs = await SharedPreferences.getInstance();
    } catch (_) {
      return;
    }
    if (prefs.getBool(kIntroSeenKey) ?? false) return;
    final s = c.game.s;
    // Existing players (save from before the intro existed) skip it.
    if (s.releases.length > 1 || s.time > 600) {
      await prefs.setBool(kIntroSeenKey, true);
      return;
    }
    if (!mounted) return;
    await showIntro(context, c);
    await prefs.setBool(kIntroSeenKey, true);
  }

  void _onController() {
    if (!_blocked && !_offlineShowing && c.offlineReport != null) {
      _maybeShowOffline();
    }
    _checkNews();
  }

  /// Queue news posted since the last look. Offline news goes to the
  /// "while you were away" digest instead; a reset game starts over.
  void _checkNews() {
    final g = c.game;
    final last = g.lastNewsSerial;
    if (last == _newsSeen) return;
    if (last < _newsSeen || c.offlineReport != null) {
      _newsSeen = last;
      return;
    }
    for (final n in g.s.news) {
      if (n.serial > _newsSeen) _newsQueue.add(n);
    }
    _newsSeen = last;
    // Keep it light: a burst (several rivals passed at once) shows the
    // newest few.
    while (_newsQueue.length > 3) {
      _newsQueue.removeFirst();
    }
    _advanceNews();
  }

  void _advanceNews() {
    if (_blocked || launchReviewsActive.value || _newsCurrent != null || _current != null || _newsQueue.isEmpty || !mounted) {
      return;
    }
    _newsCurrent = _newsQueue.removeFirst();
    _bump();
  }

  void _dismissNews() {
    _newsCurrent = null;
    _bump();
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) _advanceNews();
    });
  }

  /// How many action buttons ContextButtons (hud_overlay.dart) shows in the
  /// bottom-right corner right now.
  static int _ctaCount(Game g) {
    final s = g.s;
    var n = 0;
    if (s.viralSecondsLeft > 0 || g.overloaded) {
      n++;
      if (s.run != null && !s.run!.paused) n++;
    }
    if (s.pendingEffectiveCompute != null) n++;
    return n;
  }

  void _openNews(NewsItem n) {
    Sound.play(Sfx.click);
    showLeaderboard(
      context,
      c,
      highlight: n.kind == NewsKind.rival ? n.index : null,
      news: n.kind == NewsKind.flavour,
    );
  }

  Future<void> _maybeShowOffline() async {
    final report = c.offlineReport;
    if (report == null || _offlineShowing || !mounted) return;
    _offlineShowing = true;
    await showOfflineDialog(context, report);
    _offlineShowing = false;
    c.clearOfflineReport();
  }

  // ---------------------------------------------------------------------------
  // Events
  // ---------------------------------------------------------------------------

  void _onEvent(GameEvent e) {
    switch (e) {
      case TrainingFinished(:final predictedRating, :final mishaps):
        Sound.play(Sfx.trainingDone);
        final delta = predictedRating - c.game.rating;
        _toast(
          icon: Icons.model_training_rounded,
          color: mishaps.isEmpty ? Neon.green : Neon.yellow,
          title:
              mishaps.isEmpty
                  ? 'Training done'
                  : 'Training done, with a mishap',
          message:
              '${mishaps.isEmpty ? '' : '${mishaps.first}. '}'
              'Predicted rating ${predictedRating.round()} '
              '(${delta >= 0 ? '+' : '−'}${delta.abs().round()}). Release it!',
          actionLabel: 'Release',
          onAction: () => showReleaseSheet(context, c),
          duration: const Duration(seconds: 7),
        );
      case ModelReleased(:final release, :final stunt, :final stuntSucceeded):
        Sound.play(stuntSucceeded ? Sfx.release : Sfx.stuntFail);
        final hold = launchReviewsActive.value;
        void show() => _toast(
          icon:
              stuntSucceeded
                  ? Icons.rocket_launch_rounded
                  : Icons.local_fire_department_rounded,
          color: stuntSucceeded ? Neon.cyan : Neon.red,
          title: '${release.name} is live',
          message:
              '${stuntResultText(stunt, stuntSucceeded)}'
              '${release.review == null ? '' : ' Critics: ${release.review!.averageText}/10.'}',
        );
        hold ? _heldToasts.add(show) : show();
      case ViralSpikeStarted():
        Sound.play(Sfx.viralAlarm);
        _bump();
      case RivalBeaten():
        _queue.add(e);
        _advanceQueue();
      case RoomMoved():
        // The world map plays the move (truck, fade, tiles pop in).
        Sound.play(Sfx.upgrade);
      case EraUnlocked():
        // Let the world map push the darkness back and pull the camera out
        // to the new plot first; then the era moment plays.
        Future.delayed(kEraRevealDelay, () {
          if (!mounted) return;
          _queue.add(e);
          _advanceQueue();
        });
    }
  }

  void _toast({
    required IconData icon,
    required Color color,
    required String title,
    required String message,
    String? actionLabel,
    VoidCallback? onAction,
    Duration duration = const Duration(milliseconds: 4200),
  }) {
    _toasts.add(
      _ToastData(
        id: _nextId++,
        icon: icon,
        color: color,
        title: title,
        message: message,
        actionLabel: actionLabel,
        onAction: onAction,
        duration: duration,
      ),
    );
    while (_toasts.length > 3) {
      _toasts.removeAt(0);
    }
    _bump();
  }

  void _removeToast(int id) {
    _toasts.removeWhere((t) => t.id == id);
    _bump();
  }

  void _advanceQueue() {
    if (_blocked || launchReviewsActive.value || _current != null || _queue.isEmpty) return;
    _current = _queue.removeFirst();
    switch (_current) {
      case RivalBeaten():
        Sound.play(Sfx.rivalBeaten);
      case EraUnlocked():
        Sound.play(Sfx.eraUp);
      default:
    }
    _bump();
  }

  void _dismissCurrent() {
    _current = null;
    _bump();
    // Small breather between back-to-back celebrations.
    Future.delayed(const Duration(milliseconds: 250), () {
      if (mounted) {
        _advanceQueue();
        _advanceNews();
      }
    });
  }

  // ---------------------------------------------------------------------------
  // Overlay layer (above every route, so it also covers dialogs/sheets)
  // ---------------------------------------------------------------------------

  Widget _buildLayer() {
    return ValueListenableBuilder<int>(
      valueListenable: _changed,
      builder: (ctx, _, __) {
        final current = _current;
        return Stack(
          children: [
            // Viral banner (top).
            Positioned(
              top: hudHeight(MediaQuery.sizeOf(ctx).width) + 4,
              left: 0,
              right: 0,
              child: SafeArea(
                bottom: false,
                child: IgnorePointer(
                  child: ListenableBuilder(
                    listenable: c,
                    builder: (_, __) {
                      final left = c.game.s.viralSecondsLeft;
                      return AnimatedSwitcher(
                        duration: const Duration(milliseconds: 300),
                        transitionBuilder:
                            (child, a) => SizeTransition(
                              sizeFactor: a,
                              axisAlignment: -1,
                              child: FadeTransition(opacity: a, child: child),
                            ),
                        child:
                            left > 0
                                ? ViralBanner(
                                  key: const ValueKey('viral'),
                                  secondsLeft: left,
                                )
                                : const SizedBox(
                                  key: ValueKey('none'),
                                  width: double.infinity,
                                ),
                      );
                    },
                  ),
                ),
              ),
            ),
            // Rival news ticker (one at a time) and toasts (bottom, where
            // the map is open; the HUD, toolbar and move sign live up top).
            // Hidden while the launch reviews play; they come back after.
            if (!launchReviewsActive.value)
              Positioned(
                left: 12,
                right: 12,
                bottom: 24,
                child: SafeArea(
                  top: false,
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 480),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (_newsCurrent case final n?)
                            // On narrow screens, sit above the bottom-right
                            // action buttons (release, rent cloud...).
                            ListenableBuilder(
                              listenable: c,
                              builder:
                                  (ctx, child) => Padding(
                                    padding: EdgeInsets.only(
                                      bottom: MediaQuery.sizeOf(ctx).width < 950 ? _ctaCount(c.game) * 60.0 : 0,
                                    ),
                                    child: child,
                                  ),
                              child: NewsTicker(
                                key: ValueKey('news-${n.serial}'),
                                item: n,
                                onTap: () => _openNews(n),
                                onDone: _dismissNews,
                              ),
                            ),
                          for (final t in _toasts)
                            _ToastView(
                              key: ValueKey(t.id),
                              data: t,
                              onDone: () => _removeToast(t.id),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            // Full-screen celebration.
            if (current != null)
              Positioned.fill(
                child: switch (current) {
                  RivalBeaten(:final rival) => RivalBeatenOverlay(
                    key: ValueKey(current),
                    rival: rival,
                    next: c.game.nextRival,
                    onDone: _dismissCurrent,
                    onShare: () {
                      _dismissCurrent();
                      showReleaseCardDialog(
                        context,
                        ReleaseCardData.fromGame(c.game),
                        headline: 'You passed ${rival.lab} ${rival.model}',
                      );
                    },
                  ),
                  EraUnlocked(:final era) => EraOverlay(
                    key: ValueKey(current),
                    era: era,
                    onDone: _dismissCurrent,
                  ),
                  _ => const SizedBox.shrink(),
                },
              ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Toast text for a release's launch stunt.
String stuntResultText(LaunchStunt stunt, bool success) {
  String pct(double m) =>
      '${m >= 1 ? '+' : '−'}${((m - 1).abs() * 100).round()}%';
  if (!success) {
    return stunt.id == 'live_demo'
        ? 'Live demo FAILED on stage. Hype ${pct(stunt.hypeOnFail)}.'
        : '${stunt.name} backfired. Hype ${pct(stunt.hypeOnFail)}.';
  }
  return switch (stunt.id) {
    'none' => 'Shipped quietly. The changelog says "improvements".',
    'cryptic_tweet' =>
      'The cryptic tweet worked. Timeline is losing it. Hype ${pct(stunt.hypeOnSuccess)}.',
    'live_demo' =>
      'Live demo crushed it on stage. Hype ${pct(stunt.hypeOnSuccess)}.',
    _ => '${stunt.name} landed. Hype ${pct(stunt.hypeOnSuccess)}.',
  };
}

// -----------------------------------------------------------------------------
// Toast
// -----------------------------------------------------------------------------

class _ToastView extends StatefulWidget {
  final _ToastData data;
  final VoidCallback onDone;
  const _ToastView({super.key, required this.data, required this.onDone});

  @override
  State<_ToastView> createState() => _ToastViewState();
}

class _ToastViewState extends State<_ToastView>
    with SingleTickerProviderStateMixin {
  late final _a = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 380),
  )..forward();
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer(widget.data.duration, _close);
  }

  Future<void> _close() async {
    _timer?.cancel();
    if (!mounted) return;
    await _a.reverse();
    if (mounted) widget.onDone();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _a.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.data;
    final theme = Theme.of(context);
    final curved = CurvedAnimation(
      parent: _a,
      curve: Curves.easeOutBack,
      reverseCurve: Curves.easeIn,
    );
    return SizeTransition(
      sizeFactor: CurvedAnimation(parent: _a, curve: Curves.easeOut),
      axisAlignment: 1,
      child: FadeTransition(
        opacity: _a,
        child: SlideTransition(
          position: Tween(
            begin: const Offset(0, 0.6),
            end: Offset.zero,
          ).animate(curved),
          child: Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Material(
              color: Colors.transparent,
              child: Dismissible(
                key: ValueKey('dismiss-${d.id}'),
                onDismissed: (_) => widget.onDone(),
                child: Container(
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHigh.withValues(
                      alpha: 0.97,
                    ),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: d.color.withValues(alpha: 0.6)),
                    boxShadow: [
                      BoxShadow(
                        color: d.color.withValues(alpha: 0.22),
                        blurRadius: 18,
                      ),
                      const BoxShadow(
                        color: Colors.black54,
                        blurRadius: 12,
                        offset: Offset(0, 4),
                      ),
                    ],
                  ),
                  padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
                  child: Row(
                    children: [
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: d.color.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(d.icon, color: d.color),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              d.title,
                              style: display(context, 15, color: d.color),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              d.message,
                              style: theme.textTheme.bodySmall?.copyWith(
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (d.actionLabel != null)
                        TextButton(
                          onPressed: () {
                            d.onAction?.call();
                            _close();
                          },
                          child: Text(
                            d.actionLabel!,
                            style: TextStyle(
                              color: d.color,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Viral banner
// -----------------------------------------------------------------------------

class ViralBanner extends StatefulWidget {
  final double secondsLeft;
  const ViralBanner({super.key, required this.secondsLeft});

  @override
  State<ViralBanner> createState() => _ViralBannerState();
}

class _ViralBannerState extends State<ViralBanner>
    with SingleTickerProviderStateMixin {
  late final _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _pulse,
      builder: (context, _) {
        final t = _pulse.value;
        // Material gives the banner a text style; without it Flutter draws
        // the debug yellow double underline under every word.
        return Material(
          type: MaterialType.transparency,
          child: Container(
            margin: const EdgeInsets.fromLTRB(10, 6, 10, 0),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Color.lerp(const Color(0xFFB0121C), Neon.red, t)!,
                  Color.lerp(Neon.red, const Color(0xFFFF2E63), t)!,
                ],
              ),
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Neon.red.withValues(alpha: 0.35 + 0.35 * t),
                  blurRadius: 12 + 14 * t,
                ),
              ],
            ),
            child: Row(
              children: [
                Transform.rotate(
                  angle: (t - 0.5) * 0.3,
                  child: const Icon(
                    Icons.warning_amber_rounded,
                    color: Colors.white,
                    size: 26,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'VIRAL! Demand x${viralDemandMult.round()}',
                        style: const TextStyle(
                          fontFamily: kDisplayFont,
                          fontWeight: FontWeight.w800,
                          fontSize: 17,
                          color: Colors.white,
                          letterSpacing: 1,
                        ),
                      ),
                      const Text(
                        'Demand is way above your serving capacity. Tap "Rent cloud" '
                        '(bottom right) for ×2 serving, or pause training to free GPUs.',
                        style: TextStyle(color: Colors.white, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                Text(
                  formatDuration(widget.secondsLeft),
                  style: const TextStyle(
                    fontFamily: kMonoFont,
                    fontWeight: FontWeight.w700,
                    fontSize: 18,
                    color: Colors.white,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// -----------------------------------------------------------------------------
// Celebrations
// -----------------------------------------------------------------------------

/// Shared shell: blurred dim backdrop, staged entrance, tap to continue,
/// auto-dismiss so idle players don't get stuck behind it.
class _CelebrationShell extends StatefulWidget {
  final Widget Function(BuildContext context, Animation<double> a) builder;
  final Widget? background;
  final VoidCallback onDone;
  final int confettiSeed;
  const _CelebrationShell({
    required this.builder,
    required this.onDone,
    this.background,
    this.confettiSeed = 7,
  });

  @override
  State<_CelebrationShell> createState() => _CelebrationShellState();
}

class _CelebrationShellState extends State<_CelebrationShell>
    with SingleTickerProviderStateMixin {
  late final _a = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..forward();
  Timer? _auto;
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    _auto = Timer(const Duration(seconds: 9), _close);
  }

  Future<void> _close() async {
    if (_closing) return;
    _closing = true;
    _auto?.cancel();
    await _a.animateBack(
      0,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeIn,
    );
    widget.onDone();
  }

  @override
  void dispose() {
    _auto?.cancel();
    _a.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final fade = CurvedAnimation(parent: _a, curve: const Interval(0, 0.25));
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _close,
      child: FadeTransition(
        opacity: fade,
        child: Material(
          type: MaterialType.transparency,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (widget.background != null)
                widget.background!
              else
                BackdropFilter(
                  filter: ui.ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                  child: Container(
                    decoration: const BoxDecoration(
                      gradient: RadialGradient(
                        radius: 1.1,
                        colors: [Color(0xE60F2A20), Color(0xF2050809)],
                      ),
                    ),
                  ),
                ),
              ConfettiBurst(seed: widget.confettiSeed),
              SafeArea(
                child: Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 520),
                      child: widget.builder(context, _a),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Staggered entrance helper: [begin]..[end] are fractions of the timeline.
Widget _stagger(
  Animation<double> a,
  double begin,
  double end,
  Widget child, {
  double dy = 24,
}) {
  final t = CurvedAnimation(
    parent: a,
    curve: Interval(begin, end, curve: Curves.easeOutCubic),
  );
  return AnimatedBuilder(
    animation: t,
    builder:
        (_, c) => Opacity(
          opacity: t.value.clamp(0.0, 1.0),
          child: Transform.translate(
            offset: Offset(0, dy * (1 - t.value)),
            child: c,
          ),
        ),
    child: child,
  );
}

class RivalBeatenOverlay extends StatelessWidget {
  final RivalSnapshot rival;
  final RivalSnapshot? next;
  final VoidCallback onDone;
  final VoidCallback? onShare;
  const RivalBeatenOverlay({
    super.key,
    required this.rival,
    this.next,
    required this.onDone,
    this.onShare,
  });

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return _CelebrationShell(
      onDone: onDone,
      confettiSeed: rival.year * 31 + rival.model.length,
      builder: (context, a) {
        final logoScale = CurvedAnimation(
          parent: a,
          curve: const Interval(0.05, 0.55, curve: Curves.elasticOut),
        );
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _stagger(a, 0.0, 0.3, _Tag('RIVAL PASSED', color: accent)),
            const SizedBox(height: 22),
            ScaleTransition(
              scale: logoScale,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  RivalLogo(rival.lab, size: 128),
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: accent,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.check_rounded,
                        color: Neon.ink,
                        size: 26,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 22),
            _stagger(
              a,
              0.2,
              0.5,
              Text(
                'You passed',
                style: display(context, 20, color: Colors.white70),
              ),
            ),
            const SizedBox(height: 4),
            _stagger(
              a,
              0.25,
              0.6,
              Text(
                '${rival.lab} ${rival.model}',
                textAlign: TextAlign.center,
                style: display(
                  context,
                  38,
                  color: Colors.white,
                  height: 1.1,
                ).copyWith(
                  shadows: [
                    Shadow(
                      color: accent.withValues(alpha: 0.6),
                      blurRadius: 24,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            _stagger(a, 0.3, 0.65, _Tag('${rival.year}', color: Colors.white)),
            if (rival.quip.isNotEmpty) ...[
              const SizedBox(height: 18),
              _stagger(
                a,
                0.4,
                0.75,
                Text(
                  '“${rival.quip}”',
                  textAlign: TextAlign.center,
                  style: display(
                    context,
                    17,
                    color: Colors.white70,
                    weight: FontWeight.w500,
                  ).copyWith(fontStyle: FontStyle.italic),
                ),
              ),
            ],
            const SizedBox(height: 22),
            _stagger(
              a,
              0.5,
              0.85,
              Text(
                next == null
                    ? 'Nobody left to chase. You are the frontier. For now.'
                    : 'Next up: ${next!.lab} (${next!.year})',
                textAlign: TextAlign.center,
                style: mono(context, 14, color: accent),
              ),
            ),
            const SizedBox(height: 22),
            _stagger(
              a,
              0.6,
              0.95,
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 12,
                runSpacing: 8,
                children: [
                  if (onShare != null)
                    OutlinedButton.icon(
                      onPressed: onShare,
                      icon: const Icon(Icons.ios_share_rounded),
                      label: const Text('Brag'),
                    ),
                  FilledButton(
                    onPressed: onDone,
                    child: const Text('Continue'),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

String eraTagline(Era era) =>
    {
      Era.garage: 'One GPU, one dream, one very warm room.',
      Era.startup:
          '${formatNumber(startupUnlockUsers, decimals: 0)} users. Investors are suddenly returning your emails.',
      Era.smallLab:
          'Your model writes passable poetry. Time to rent a cage in a real datacenter.',
      Era.mediumLab:
          'A GPT-ish-3-class model, built by you. Your own datacenter hall is next.',
      Era.bigLab:
          'Chatbots are a product category now, and you\'re in the big leagues. Pour the concrete.',
      Era.globalLab:
          'A reasoning model at the frontier. Now it\'s gigawatts, power plants and the last few rungs.',
    }[era] ??
    'A bigger room, a bigger cluster, a bigger model.';

class EraOverlay extends StatelessWidget {
  final Era era;
  final VoidCallback onDone;
  const EraOverlay({super.key, required this.era, required this.onDone});

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    final unlocks = unlocksFor(era);
    return _CelebrationShell(
      onDone: onDone,
      confettiSeed: era.index * 97 + 3,
      background: Stack(
        fit: StackFit.expand,
        children: [
          EraBackdrop(era),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0x99000000),
                  Color(0xCC000000),
                  Color(0xF2000000),
                ],
              ),
            ),
          ),
        ],
      ),
      builder:
          (context, a) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _stagger(a, 0.0, 0.3, _Tag('ERA UNLOCKED', color: accent)),
              const SizedBox(height: 18),
              _stagger(
                a,
                0.1,
                0.45,
                Text(
                  'Welcome to the',
                  style: display(context, 22, color: Colors.white70),
                ),
                dy: 40,
              ),
              _stagger(
                a,
                0.15,
                0.55,
                ShaderMask(
                  shaderCallback:
                      (r) => LinearGradient(
                        colors: [accent, Neon.cyan],
                      ).createShader(r),
                  child: Text(
                    '${era.label} era',
                    textAlign: TextAlign.center,
                    style: display(
                      context,
                      54,
                      color: Colors.white,
                      height: 1.05,
                      weight: FontWeight.w800,
                    ),
                  ),
                ),
                dy: 40,
              ),
              const SizedBox(height: 12),
              _stagger(
                a,
                0.3,
                0.65,
                Text(
                  eraTagline(era),
                  textAlign: TextAlign.center,
                  style: display(
                    context,
                    16,
                    color: Colors.white70,
                    weight: FontWeight.w500,
                  ),
                ),
              ),
              if (unlocks.isNotEmpty) ...[
                const SizedBox(height: 24),
                _stagger(
                  a,
                  0.4,
                  0.7,
                  Text(
                    'NOW AVAILABLE',
                    style: mono(context, 12, color: Colors.white54),
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final (i, u) in unlocks.take(8).indexed)
                      _stagger(
                        a,
                        (0.45 + i * 0.05).clamp(0.0, 0.85),
                        (0.7 + i * 0.05).clamp(0.0, 1.0),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 7,
                          ),
                          decoration: BoxDecoration(
                            color: accent.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: accent.withValues(alpha: 0.5),
                            ),
                          ),
                          child: Text(
                            u,
                            style: mono(context, 12.5, color: Colors.white),
                          ),
                        ),
                        dy: 12,
                      ),
                    if (unlocks.length > 8)
                      _stagger(
                        a,
                        0.8,
                        1.0,
                        Text(
                          '+${unlocks.length - 8} more',
                          style: mono(context, 12.5, color: Colors.white54),
                        ),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 28),
              _stagger(
                a,
                0.7,
                1.0,
                FilledButton(onPressed: onDone, child: const Text("Let's go")),
              ),
            ],
          ),
    );
  }
}

class _Tag extends StatelessWidget {
  final String text;
  final Color color;
  const _Tag(this.text, {required this.color});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(6),
      border: Border.all(color: color.withValues(alpha: 0.7), width: 1.5),
      color: color.withValues(alpha: 0.1),
    ),
    child: Text(
      text,
      style: mono(
        context,
        13,
        color: color,
        weight: FontWeight.w700,
      ).copyWith(letterSpacing: 3),
    ),
  );
}

// -----------------------------------------------------------------------------
// Offline dialog
// -----------------------------------------------------------------------------

Future<void> showOfflineDialog(BuildContext context, OfflineReport r) {
  Sound.play(Sfx.click);
  return showDialog<void>(
    context: context,
    builder: (ctx) => OfflineReportDialog(report: r),
  );
}

class OfflineReportDialog extends StatelessWidget {
  final OfflineReport report;
  const OfflineReportDialog({super.key, required this.report});

  @override
  Widget build(BuildContext context) {
    final r = report;
    final scheme = Theme.of(context).colorScheme;
    final userDelta = r.usersAfter - r.usersBefore;
    final capped = r.seconds >= offlineCapSeconds;
    Widget row(IconData icon, String label, String value, {Color? color}) =>
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: [
              Icon(icon, size: 20, color: scheme.onSurfaceVariant),
              const SizedBox(width: 10),
              Text(label),
              const SizedBox(width: 8),
              // Big late-game numbers ("394.4M → 473.3M") shrink on phones.
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: Text(
                    value,
                    style: mono(context, 16, color: color, weight: FontWeight.w700),
                  ),
                ),
              ),
            ],
          ),
        );
    return AlertDialog(
      scrollable: true,
      icon: Icon(Icons.nightlight_round, color: scheme.primary, size: 36),
      title: Text('While you were away', style: display(context, 24)),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Your GPUs kept humming for ${formatDuration(r.seconds)}${capped ? ' (offline time caps at 8h)' : ''}.',
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            row(
              Icons.payments_outlined,
              'Money earned',
              '+${formatMoney(r.moneyEarned)}',
              color: scheme.primary,
            ),
            row(
              Icons.people_alt_outlined,
              'Users',
              '${formatNumber(r.usersBefore)} → ${formatNumber(r.usersAfter)}',
              color: userDelta >= 0 ? scheme.primary : Neon.red,
            ),
            if (r.trainingFinished)
              Container(
                margin: const EdgeInsets.only(top: 10),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: scheme.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    Icon(Icons.model_training_rounded, color: scheme.primary),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        'Training finished. A new model is waiting to be released!',
                      ),
                    ),
                  ],
                ),
              ),
            if (r.news.isNotEmpty) NewsDigest(news: r.news),
          ],
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Collect'),
        ),
      ],
    );
  }
}
