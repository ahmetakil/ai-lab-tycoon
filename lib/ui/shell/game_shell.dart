// The game screen: one full-screen world map with HUD overlays on top, a
// vertical toolbar on the left, contextual call-to-action buttons, and
// centered modal cards for everything else. Build mode slides up the parts
// tray; tap glowing floor cells to place.
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../sim/content.dart';
import '../../sim/game.dart';
import '../format.dart';
import '../game_assets.dart';
import '../game_controller.dart';
import '../grid/grid_hints.dart';
import '../moments/event_presenter.dart';
import '../moments/release_sheet.dart';
import '../moments/rivals_screen.dart';
import '../screens/overview_screen.dart';
import '../screens/research_screen.dart';
import '../sound.dart';
import '../theme.dart';
import '../widgets/buy.dart';
import '../widgets/effects.dart';
import '../widgets/game_builder.dart';
import '../widgets/goals.dart';
import '../widgets/hud.dart';
import '../widgets/panel.dart';
import '../widgets/power_card.dart';
import '../widgets/tier_cards.dart';
import '../world/room_grid.dart';
import '../world/world_map.dart';
import 'build_drawer.dart';
import 'game_modal.dart';
import 'hud_overlay.dart';
import 'tile_sheet.dart';

class GameShell extends StatefulWidget {
  final GameController controller;
  const GameShell({super.key, required this.controller});

  @override
  State<GameShell> createState() => _GameShellState();
}

class _GameShellState extends State<GameShell> {
  final _world = GlobalKey<WorldMapState>();

  bool _build = false;
  String? _placing;
  (String, int, int)? _moveFrom;
  TileKind _trayKind = TileKind.gpu;

  String? _toastText;
  Color _toastColor = AppColors.amber;
  int _toastId = 0;
  Timer? _toastTimer;

  double _drawerH = 250; // measured once the drawer lays out
  bool _cheering = false;
  Timer? _cheerTimer;
  StreamSubscription<GameEvent>? _sub;

  GameController get c => widget.controller;
  Game get g => c.game;

  String get _roomId => g.currentRoom.id;

  @override
  void initState() {
    super.initState();
    _sub = c.events.listen(_onEvent);
    _loadTutorialFlag();
  }

  @override
  void dispose() {
    _toastTimer?.cancel();
    _cheerTimer?.cancel();
    _sub?.cancel();
    super.dispose();
  }

  void _onEvent(GameEvent e) {
    if (e is ModelReleased || e is RivalBeaten) {
      _cheerTimer?.cancel();
      setState(() => _cheering = true);
      _cheerTimer = Timer(const Duration(seconds: 5), () {
        if (mounted) setState(() => _cheering = false);
      });
    }
  }

  // --- Feedback -------------------------------------------------------------

  void _toast(String text, {Color color = AppColors.amber}) {
    _toastTimer?.cancel();
    setState(() {
      _toastText = text;
      _toastColor = color;
      _toastId++;
    });
    _toastTimer = Timer(const Duration(milliseconds: 2400), () {
      if (mounted) setState(() => _toastText = null);
    });
  }

  // --- Build mode -------------------------------------------------------------

  void _toggleBuild() {
    setState(() {
      _build = !_build;
      _placing = null;
      _moveFrom = null;
    });
  }

  void _exitModes() {
    Sound.play(Sfx.click);
    setState(() {
      _build = false;
      _placing = null;
      _moveFrom = null;
    });
  }

  void _selectPart(TileDef t) {
    final locked = g.tileLockReason(t);
    if (locked != null) {
      Sound.play(Sfx.error);
      _toast('${t.name}: $locked');
      return;
    }
    Sound.play(Sfx.click);
    HapticFeedback.selectionClick();
    setState(() {
      _moveFrom = null;
      _placing = _placing == t.id ? null : t.id;
    });
  }

  void _onCellTap(String roomId, int x, int y) {
    final here = g.tileAt(roomId, x, y);
    final move = _moveFrom;
    if (move != null) {
      if ((move.$2, move.$3) == (x, y)) {
        Sound.play(Sfx.click);
        setState(() => _moveFrom = null);
        return;
      }
      final ok = c.act((g) => g.moveTile(roomId, move.$2, move.$3, x, y));
      Sound.play(ok ? Sfx.upgrade : Sfx.error);
      HapticFeedback.lightImpact();
      setState(() => _moveFrom = null);
      return;
    }
    final placing = _placing;
    if (placing != null) {
      final reason = g.placeBlockReason(roomId, x, y, placing);
      if (reason != null) {
        Sound.play(Sfx.error);
        HapticFeedback.heavyImpact();
        _toast(reason, color: AppColors.red);
        return;
      }
      c.act((g) => g.placeTile(roomId, x, y, placing));
      Sound.play(Sfx.purchase);
      HapticFeedback.mediumImpact();
      return;
    }
    Sound.play(Sfx.click);
    if (here != null) {
      _openTileSheet(roomId, x, y);
    } else {
      _toast(
        _build
            ? 'Pick a part in the tray below, then tap a cell to place it.'
            : 'Tap Build to place parts on the floor.',
      );
    }
  }

  /// Drag-to-paint: place the selected part on every crossed cell that
  /// allows it (blocked cells are skipped quietly); one toast at the end.
  int _painted = 0;

  void _onCellPaint(String roomId, int x, int y) {
    final placing = _placing;
    if (placing == null || g.placeBlockReason(roomId, x, y, placing) != null) return;
    if (c.act((g) => g.placeTile(roomId, x, y, placing))) {
      _painted++;
      if (_painted == 1) Sound.play(Sfx.purchase);
      HapticFeedback.selectionClick();
    }
  }

  void _onPaintEnd() {
    final n = _painted;
    _painted = 0;
    if (n > 1 && _placing != null) {
      Sound.play(Sfx.purchase);
      _toast('Placed $n × ${tileById(_placing!)!.name}.', color: AppColors.neon);
    }
  }

  // --- Tutorial -------------------------------------------------------------
  // A short guided path, derived from game state: train → add a GPU →
  // release. Each step says why and has a "do it" button. (Every GPU in the
  // room is cabled into one cluster, so there's no linking step; the garage
  // network already feeds the first 4 GPUs.)

  static const _tutorialKey = 'tutorial_done_v1';
  static const _tutorialSteps = 3;
  bool _tutorialDone = false;

  void _loadTutorialFlag() {
    SharedPreferences.getInstance().then((p) {
      if (mounted && (p.getBool(_tutorialKey) ?? false)) {
        setState(() => _tutorialDone = true);
      }
    });
  }

  void _finishTutorial() {
    if (_tutorialDone) return;
    _tutorialDone = true;
    SharedPreferences.getInstance().then((p) => p.setBool(_tutorialKey, true));
  }

  void _skipTutorial() {
    Sound.play(Sfx.click);
    setState(_finishTutorial);
  }

  /// Opens build mode on [kind] and selects [tileId] (if unlocked & affordable).
  void _guideToPart(TileKind kind, String tileId) {
    final t = tileById(tileId)!;
    setState(() {
      _build = true;
      _moveFrom = null;
      _trayKind = kind;
    });
    if (_placing != t.id) _selectPart(t);
  }

  _TutorialStep? _tutorialStep() {
    if (_tutorialDone || _moveFrom != null) return null;
    final s = g.s;
    final gpus = s.tileCounts.entries
        .where((e) => tileById(e.key)?.isGpu ?? false)
        .fold(0, (a, e) => a + e.value);
    final released = s.releases.length > 1;
    if (released || s.roomId != 'garage') {
      // Finished (or clearly past the basics, e.g. moved out): never again.
      WidgetsBinding.instance.addPostFrameCallback((_) => _finishTutorial());
      return null;
    }
    final run = s.run;

    if (s.pendingEffectiveCompute != null) {
      return _TutorialStep(
        step: 3,
        title: 'Your model is trained!',
        body: 'Release it: a better model raises your rating, which brings more users and money.',
        action: 'Release',
        onAction: () => showReleaseSheet(context, c),
      );
    }
    if (run == null) {
      return _TutorialStep(
        step: 1,
        title: 'Train your first model',
        body:
            'Your GPU is already serving a few users. Training a model raises your '
            'rating, and better models attract more users.',
        action: 'Set up a training run',
        onAction: _openTrain,
      );
    }
    final pct = formatPercent(run.progress);
    if (gpus < 2) {
      final gpu = tileById('gpu_old')!;
      if (_placing != null && tileById(_placing!)!.isGpu) {
        return _TutorialStep(
          step: 2,
          title: 'Tap a glowing floor cell',
          body:
              'Anywhere works: every GPU in the room is cabled into one training cluster. '
              'Leave room for a cooler next to it if it gets hot.',
        );
      }
      final short = gpu.cost - s.money;
      return _TutorialStep(
        step: 2,
        title: 'Training… $pct. Add a second GPU',
        body:
            short > 0
                ? 'More GPUs train faster. A ${gpu.name} costs ${formatMoney(gpu.cost)}; '
                    'you\'ll have it in about ${formatDuration(short / g.revenuePerSecond.clamp(1e-6, double.infinity))}.'
                : 'More GPUs train faster, and you can afford a ${gpu.name} now.',
        action: short > 0 ? null : 'Pick ${gpu.name}',
        onAction: short > 0 ? null : () => _guideToPart(TileKind.gpu, gpu.id),
      );
    }
    return _TutorialStep(
      step: 3,
      title: 'Cabled! Training… $pct',
      body:
          'Your GPUs train together now. When the run finishes, release the model. '
          'Hot GPUs throttle: a fan next to one cools it. Tap any tile to learn more.',
    );
  }

  // --- Modals -----------------------------------------------------------------

  void _openResearch() => showGameModal<void>(
    context,
    title: 'Research',
    icon: Icons.science_rounded,
    color: AppColors.violet,
    maxWidth: 680,
    selfScrolling: true,
    child: ResearchScreen(controller: c),
  );

  void _openRivals() => showGameModal<void>(
    context,
    title: 'Leaderboard',
    icon: Icons.leaderboard_rounded,
    color: AppColors.amber,
    maxWidth: 680,
    selfScrolling: true,
    child: RivalsScreen(controller: c),
  );

  void _openStats() => showGameModal<void>(
    context,
    title: g.s.labName,
    icon: Icons.insights_rounded,
    color: AppColors.cyan,
    maxWidth: 640,
    selfScrolling: true,
    child: OverviewScreen(controller: c),
  );

  void _openTrain() {
    if (g.s.pendingEffectiveCompute != null) {
      showReleaseSheet(context, c);
      return;
    }
    showGameModal<void>(
      context,
      title: 'Training',
      icon: Icons.model_training_rounded,
      color: AppColors.neon,
      maxWidth: 520,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 8),
          TrainingPanel(controller: c),
          gap8,
          GameBuilder(controller: c, builder: (context) => ClusterSummaryCard(game: c.game)),
        ],
      ),
    );
  }

  void _openSettings() => showSettingsSheet(context, c).then((_) {
    if (mounted) setState(() {}); // speed tag
  });

  void _openPower() {
    Sound.play(Sfx.click);
    showGameModal<void>(
      context,
      title: 'Power',
      icon: Icons.bolt_rounded,
      color: AppColors.amber,
      maxWidth: 520,
      child: GameBuilder(controller: c, builder: (context) => PowerCard(controller: c)),
    );
  }

  void _openNetwork() {
    Sound.play(Sfx.click);
    showGameModal<void>(
      context,
      title: 'Network',
      icon: Icons.cable_rounded,
      color: AppColors.cyan,
      maxWidth: 520,
      child: GameBuilder(controller: c, builder: (context) => NetworkCard(controller: c)),
    );
  }

  void _openCooling() {
    Sound.play(Sfx.click);
    showGameModal<void>(
      context,
      title: 'Cooling',
      icon: Icons.ac_unit_rounded,
      color: AppColors.cyan,
      maxWidth: 520,
      child: GameBuilder(controller: c, builder: (context) => CoolingCard(controller: c)),
    );
  }

  void _openGoal() {
    showGameModal<void>(
      context,
      title: 'What\'s next',
      icon: Icons.flag_rounded,
      color: AppColors.neon,
      maxWidth: 520,
      child: Builder(
        builder:
            (sheet) => GameBuilder(
              controller: c,
              builder:
                  (_) => NextEraSheet(
                    controller: c,
                    onTrain: () {
                      Navigator.of(sheet).pop();
                      _openTrain();
                    },
                  ),
            ),
      ),
    );
  }

  void _onRequirement(BuildContext sheet, RequirementAction a) {
    Navigator.of(sheet).pop();
    switch (a) {
      case RequirementAction.power:
        _openPower();
      case RequirementAction.train:
        _openTrain();
      case RequirementAction.none:
        break;
    }
  }

  void _openRoom(RoomDef room) {
    Sound.play(Sfx.click);
    showGameModal<void>(
      context,
      title: room.name,
      icon: Icons.add_business_rounded,
      color: AppColors.amber,
      maxWidth: 520,
      child: Builder(
        builder:
            (sheet) => GameBuilder(
              controller: c,
              builder: (_) {
                final reason = g.roomBlockReason(room.id);
                final owned = g.isRoomOwned(room.id);
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: AspectRatio(
                        aspectRatio: 3,
                        child: Image.asset(
                          GameArt.roomBanner(room.id),
                          fit: BoxFit.cover,
                          errorBuilder:
                              (_, __, ___) => const ColoredBox(color: AppColors.surfaceHi),
                        ),
                      ),
                    ),
                    gap12,
                    Text(room.blurb, style: const TextStyle(color: AppColors.muted, height: 1.3)),
                    gap12,
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        Tag('${room.width}×${room.height} grid', color: AppColors.cyan, mono: true),
                        Tag('1 GPU tile = ${room.tileScaleLabel}', color: AppColors.neon),
                        Tag(
                          'free cooling ${formatNumber(room.ambientTotal)}',
                          color: AppColors.cyan,
                          icon: Icons.ac_unit,
                        ),
                        Tag('${room.era.label} era', color: AppColors.violet),
                      ],
                    ),
                    const SizedBox(height: 16),
                    if (!owned) ...[
                      Text(
                        'Everything you\'ve built comes with you: same layout, centred in the bigger floor. '
                        'Moving only takes the cash; the ${room.era.label} era still unlocks the new parts.',
                        style: const TextStyle(color: AppColors.muted, fontSize: 12.5, height: 1.3),
                      ),
                      const SizedBox(height: 10),
                      Text('TO MOVE HERE', style: labelStyle(size: 10, color: AppColors.neon)),
                      const SizedBox(height: 6),
                      RequirementList(
                        key: const ValueKey('move-checklist'),
                        requirements: g.moveRequirements(room.id),
                        onAction: (a) => _onRequirement(sheet, a),
                      ),
                      if (reason != null && g.moveRequirements(room.id).isEmpty)
                        Text(reason, style: const TextStyle(color: AppColors.amber, fontSize: 13)),
                      const SizedBox(height: 4),
                      BuyButton(
                        key: const ValueKey('buy-room'),
                        label: 'Move to ${room.name}',
                        sublabel: formatMoney(room.cost),
                        icon: Icons.local_shipping_rounded,
                        expand: true,
                        dense: false,
                        enabled: reason == null,
                        onBuy: () {
                          final ok = c.act((g) => g.moveTo(room.id));
                          Sound.play(ok ? Sfx.upgrade : Sfx.error);
                          if (ok) {
                            Navigator.of(sheet).pop();
                            setState(() {
                              _build = false;
                              _placing = null;
                              _moveFrom = null;
                            });
                          }
                        },
                      ),
                    ],
                  ],
                );
              },
            ),
      ),
    );
  }

  void _openTileSheet(String roomId, int x, int y) {
    _toastTimer?.cancel();
    setState(() => _toastText = null);
    final t = tileById(g.tileAt(roomId, x, y)!)!;
    showGameModal<void>(
      context,
      title: '${roomById(roomId)!.name} · ${kindLabel(t.kind)}',
      icon: kindIcon(t.kind),
      color: kindColor(t.kind),
      maxWidth: 520,
      child: Builder(
        builder:
            (sheet) => GameBuilder(
              controller: c,
              builder:
                  (_) => Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: TileSheet(
                      game: c.game,
                      roomId: roomId,
                      x: x,
                      y: y,
                      onMove: () {
                        Navigator.of(sheet).pop();
                        Sound.play(Sfx.click);
                        setState(() {
                          _placing = null;
                          _moveFrom = (roomId, x, y);
                        });
                      },
                      onSell: () {
                        final ok = c.act((g) => g.sellTile(roomId, x, y));
                        Sound.play(ok ? Sfx.purchase : Sfx.error);
                        if (ok) Navigator.of(sheet).pop();
                      },
                      onReplace: (t) {
                        final ok = c.act((g) => g.replaceTile(roomId, x, y, t.id));
                        Sound.play(ok ? Sfx.upgrade : Sfx.error);
                        if (ok) HapticFeedback.mediumImpact();
                      },
                    ),
                  ),
            ),
      ),
    );
  }

  // --- Layout -------------------------------------------------------------------

  List<ToolSpec> _tools(Game g) {
    final pending = g.s.pendingEffectiveCompute != null;
    final affordable = upgrades.any((u) => g.canBuyUpgrade(u));
    return [
      ToolSpec(
        id: 'build',
        label: 'Build',
        tooltip: 'Build: place GPUs, cooling and network (B)',
        icon: Icons.construction_rounded,
        color: AppColors.neon,
        active: _build,
        pulse: !_build && (_tutorialStep()?.pulseBuild ?? false),
        onTap: _toggleBuild,
      ),
      ToolSpec(
        id: 'research',
        label: 'Research',
        tooltip: 'Research upgrades (R)',
        icon: Icons.science_rounded,
        color: AppColors.violet,
        badge: affordable,
        onTap: _openResearch,
      ),
      ToolSpec(
        id: 'train',
        label: pending ? 'Release' : 'Train',
        tooltip: pending ? 'Release your new model (T)' : 'Training run (T)',
        icon: pending ? Icons.rocket_launch_rounded : Icons.model_training_rounded,
        color: pending ? AppColors.neon : AppColors.cyan,
        pulse: pending,
        // Idle GPUs: a gentle nudge (no run, nothing to ship).
        nudge: !pending && g.s.run == null,
        onTap: _openTrain,
      ),
      ToolSpec(
        id: 'power',
        label: 'Power',
        tooltip: 'Power supply: see and buy the next tier (P)',
        icon: Icons.bolt_rounded,
        color: const Color(0xFFFFE066),
        badge: powerNudge(g),
        onTap: _openPower,
      ),
      ToolSpec(
        id: 'rivals',
        label: 'Rivals',
        tooltip: 'Leaderboard: you vs the rival labs',
        icon: Icons.leaderboard_rounded,
        color: AppColors.amber,
        onTap: _openRivals,
      ),
      ToolSpec(
        id: 'stats',
        label: 'Lab',
        tooltip: 'Lab stats: serving, compute, model',
        icon: Icons.insights_rounded,
        color: AppColors.cyan,
        onTap: _openStats,
      ),
      ToolSpec(
        id: 'settings',
        label: 'Settings',
        tooltip: 'Sound and playtest speed',
        icon: Icons.settings_rounded,
        color: AppColors.muted,
        onTap: _openSettings,
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return EventPresenter(
      controller: c,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.keyB): _toggleBuild,
            const SingleActivator(LogicalKeyboardKey.keyR): _openResearch,
            const SingleActivator(LogicalKeyboardKey.keyT): _openTrain,
            const SingleActivator(LogicalKeyboardKey.keyP): _openPower,
            const SingleActivator(LogicalKeyboardKey.escape): () {
              if (_build || _placing != null || _moveFrom != null) _exitModes();
            },
          },
          child: Focus(autofocus: true, child: LayoutBuilder(builder: _layout)),
        ),
      ),
    );
  }

  Widget _layout(BuildContext context, BoxConstraints box) {
    final mq = MediaQuery.of(context);
    final w = box.maxWidth, h = box.maxHeight;
    final compact = w < 600 || h < 640;
    final top = mq.padding.top + hudHeight(w);
    final toolW = compact ? 50.0 : 60.0;
    final drawerH = _build ? _drawerH : 0.0;
    // The tutorial card sits above the drawer: keep the room clear of it.
    final coachH = _tutorialStep() == null ? 0.0 : 150.0;
    final safe = EdgeInsets.fromLTRB(
      toolW + 16,
      top + 6,
      8,
      drawerH + 8 + (_build ? coachH : math.max(0.0, coachH - 80)),
    );
    final room = roomById(_roomId)!;
    if (_placing != null && !g.isTileUnlocked(tileById(_placing!)!)) _placing = null;
    final mv = _moveFrom;
    if (mv != null && g.tileAt(mv.$1, mv.$2, mv.$3) == null) _moveFrom = null;

    return Stack(
      children: [
        Positioned.fill(
          child: WorldMap(
            key: _world,
            controller: c,
            safe: safe,
            cheering: _cheering,
            build: BuildState(
              buildMode: _build,
              activeRoom: room.id,
              placing: _placing,
              moveFrom: _moveFrom,
            ),
            onCellTap: _onCellTap,
            onCellPaint: _onCellPaint,
            onPaintEnd: _onPaintEnd,
            onPlotTap: _openRoom,
          ),
        ),
        // Vignette: the world fades into darkness at the screen edges.
        const Positioned.fill(
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  radius: 1.0,
                  colors: [Color(0x00000000), Color(0x00000000), Color(0xB0000000)],
                  stops: [0, 0.6, 1],
                ),
              ),
            ),
          ),
        ),
        // Top shade so the HUD reads over bright rooms.
        Positioned(
          left: 0,
          right: 0,
          top: 0,
          height: top + 30,
          child: const IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xCC000000), Color(0x00000000)],
                ),
              ),
            ),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          top: mq.padding.top,
          child: TopHud(
            controller: c,
            onPower: _openPower,
            onNetwork: _openNetwork,
            onCooling: _openCooling,
            onProject: _openTrain,
            onGoal: _openGoal,
            onRivals: _openRivals,
          ),
        ),
        if (c.speed != 1)
          Positioned(
            right: 10,
            top: top + 4,
            child: Tag(
              '×${formatNumber(c.speed)} speed',
              color: AppColors.red,
              mono: true,
              filled: true,
            ),
          ),
        Positioned(
          left: mq.padding.left + 8,
          top: top + 8,
          bottom: drawerH + 8,
          child: SingleChildScrollView(
            child: GameBuilder(
              controller: c,
              builder: (context) => GameToolbar(tools: _tools(g), compact: compact),
            ),
          ),
        ),
        Positioned(
          right: 10,
          bottom: drawerH + 14,
          child: ContextButtons(controller: c, onRelease: () => showReleaseSheet(context, c)),
        ),
        if (_moveFrom case final mv?)
          Positioned(left: toolW + 20, right: 12, top: top + 8, child: _moveBanner(mv)),
        Positioned(
          left: toolW + 20,
          right: 12,
          top: top + (_moveFrom != null || _placing != null ? 48 : 8),
          child: IgnorePointer(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              transitionBuilder:
                  (child, a) => FadeTransition(
                    opacity: a,
                    child: ScaleTransition(
                      scale: Tween(
                        begin: 0.85,
                        end: 1.0,
                      ).animate(CurvedAnimation(parent: a, curve: Curves.easeOutBack)),
                      child: child,
                    ),
                  ),
              child:
                  _toastText == null
                      ? const SizedBox.shrink()
                      : _Toast(key: ValueKey(_toastId), text: _toastText!, color: _toastColor),
            ),
          ),
        ),
        Positioned(
          left: toolW + 24,
          right: 24,
          bottom: drawerH + (_build ? 10 : 90),
          child: GameBuilder(
            controller: c,
            builder: (context) {
              final step = _tutorialStep();
              return step == null
                  ? const SizedBox.shrink()
                  : _CoachMark(step: step, onSkip: _skipTutorial);
            },
          ),
        ),
        if (_placing != null)
          Positioned(left: toolW + 20, right: 12, top: top + 8, child: _placingBanner()),
        AnimatedPositioned(
          duration: const Duration(milliseconds: 240),
          curve: Curves.easeOutCubic,
          left: 0,
          right: 0,
          bottom: _build ? 0 : -drawerH - 300,
          child:
              _build
                  ? Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 980),
                      child: SizeReporter(
                        onSize: (sz) {
                          if ((sz.height - _drawerH).abs() > 1) {
                            setState(() => _drawerH = sz.height);
                          }
                        },
                        child: GameBuilder(
                          controller: c,
                          builder:
                              (context) => BuildDrawer(
                                game: g,
                                room: room,
                                kind: _trayKind,
                                placing: _placing,
                                onDone: _exitModes,
                                onKind: (k) {
                                  Sound.play(Sfx.click);
                                  setState(() => _trayKind = k);
                                },
                                onPick: _selectPart,
                                onPower: _openPower,
                                onNetwork: _openNetwork,
                                onCooling: _openCooling,
                              ),
                        ),
                      ),
                    ),
                  )
                  : const SizedBox.shrink(),
        ),
      ],
    );
  }

  Widget _placingBanner() {
    final t = tileById(_placing!)!;
    final color = kindColor(t.kind);
    return IgnorePointer(
      child: Center(
        child: Container(
          padding: const EdgeInsets.fromLTRB(8, 5, 12, 5),
          decoration: plateDecoration(color, radius: 99),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Image.asset(GameArt.tile(t.id), width: 22, height: 22),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  'Placing ${t.name} · ${formatMoney(g.tilePrice(t))} · tap or drag across cells',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 12),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _moveBanner((String, int, int) mv) {
    final t = tileById(g.tileAt(mv.$1, mv.$2, mv.$3) ?? '');
    return Center(
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 4, 4, 4),
        decoration: plateDecoration(AppColors.cyan, radius: 99),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.open_with, color: AppColors.cyan, size: 16),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                'Moving ${t?.name ?? 'tile'}: tap a cell (occupied cells swap)',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.cyan,
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              ),
            ),
            const SizedBox(width: 6),
            TextButton(
              key: const ValueKey('cancel-move'),
              onPressed: () {
                Sound.play(Sfx.click);
                setState(() => _moveFrom = null);
              },
              child: const Text('Cancel'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Reports its child's laid-out size after each layout that changes it.
class SizeReporter extends SingleChildRenderObjectWidget {
  final ValueChanged<Size> onSize;
  const SizeReporter({super.key, required this.onSize, super.child});

  @override
  RenderObject createRenderObject(BuildContext context) => _SizeReporterBox(onSize);

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) =>
      (renderObject as _SizeReporterBox).onSize = onSize;
}

class _SizeReporterBox extends RenderProxyBox {
  ValueChanged<Size> onSize;
  Size? _last;
  _SizeReporterBox(this.onSize);

  @override
  void performLayout() {
    super.performLayout();
    if (size != _last) {
      _last = size;
      final s = size;
      WidgetsBinding.instance.addPostFrameCallback((_) => onSize(s));
    }
  }
}

class _Toast extends StatelessWidget {
  final String text;
  final Color color;
  const _Toast({super.key, required this.text, required this.color});

  @override
  Widget build(BuildContext context) => Center(
    child: Container(
      constraints: const BoxConstraints(maxWidth: 460),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Color.alphaBlend(color.withValues(alpha: 0.16), AppColors.surface),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.8), width: 1.5),
        boxShadow: const [BoxShadow(color: Color(0xCC000000), offset: Offset(0, 3))],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.info_outline, size: 16, color: color),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              text,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: AppColors.text, fontSize: 12.5, height: 1.3),
            ),
          ),
        ],
      ),
    ),
  );
}

class _TutorialStep {
  final int step;
  final String title;
  final String body;
  final String? action;
  final VoidCallback? onAction;
  const _TutorialStep({
    required this.step,
    required this.title,
    required this.body,
    this.action,
    this.onAction,
  });

  bool get pulseBuild => action != null && step == 2;
}

class _CoachMark extends StatelessWidget {
  final _TutorialStep step;
  final VoidCallback onSkip;
  const _CoachMark({required this.step, required this.onSkip});

  @override
  Widget build(BuildContext context) => Center(
    child: Container(
      key: const ValueKey('tutorial'),
      constraints: const BoxConstraints(maxWidth: 440),
      padding: const EdgeInsets.fromLTRB(14, 10, 8, 12),
      decoration: BoxDecoration(
        color: const Color(0xF20C1322),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.neon, width: 2),
        boxShadow: [
          const BoxShadow(color: Color(0xFF000000), offset: Offset(0, 4)),
          BoxShadow(color: AppColors.neon.withValues(alpha: 0.3), blurRadius: 18),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('TUTORIAL ${step.step}/${_GameShellState._tutorialSteps}', style: labelStyle(size: 10, color: AppColors.neon)),
              const Spacer(),
              TextButton(
                key: const ValueKey('tutorial-skip'),
                onPressed: onSkip,
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.muted,
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
                child: const Text('Skip', style: TextStyle(fontSize: 12)),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: Text(
              step.title,
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5, height: 1.2),
            ),
          ),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: Text(
              step.body,
              style: const TextStyle(color: AppColors.muted, fontSize: 13, height: 1.3),
            ),
          ),
          if (step.action != null) ...[
            const SizedBox(height: 10),
            Pulse(
              scale: 1.04,
              child: FilledButton.icon(
                key: const ValueKey('tutorial-action'),
                onPressed: () {
                  Sound.play(Sfx.click);
                  step.onAction?.call();
                },
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.neon,
                  foregroundColor: AppColors.bg,
                  textStyle: const TextStyle(fontWeight: FontWeight.w800),
                ),
                icon: const Icon(Icons.arrow_forward_rounded, size: 18),
                label: Text(step.action!),
              ),
            ),
          ],
        ],
      ),
    ),
  );
}
