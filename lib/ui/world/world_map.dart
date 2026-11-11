// The one full-screen world: every room at a fixed spot on a dark map. Owned
// rooms are lit, the next plot is a faint silhouette with an "Unlock area"
// sign, everything further out is black. Buying a room or reaching a new era
// pushes the darkness back and pulls the camera out to show it.
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../sim/content.dart';
import '../../sim/game.dart';
import '../format.dart';
import '../game_assets.dart';
import '../game_controller.dart';
import '../theme.dart';
import '../widgets/effects.dart';
import 'camera.dart';
import 'character.dart';
import 'room_fx.dart';
import 'room_grid.dart';
import 'world_layout.dart';

class WorldMap extends StatefulWidget {
  final GameController controller;
  final BuildState build;

  /// Screen space covered by HUD / toolbar / drawer; the camera frames inside it.
  final EdgeInsets safe;
  final bool cheering;
  final void Function(String roomId, int x, int y) onCellTap;
  final void Function(RoomDef room) onPlotTap;

  /// Fired once a reveal fly-over has finished (the shell lets moments play).
  final VoidCallback? onRevealDone;

  const WorldMap({
    super.key,
    required this.controller,
    required this.build,
    required this.safe,
    required this.onCellTap,
    required this.onPlotTap,
    this.cheering = false,
    this.onRevealDone,
  });

  @override
  State<WorldMap> createState() => WorldMapState();
}

/// The next room you could buy (shown faintly), if any.
RoomDef? nextPlot(Game g) => rooms.where((r) => !g.isRoomOwned(r.id)).firstOrNull;

class WorldMapState extends State<WorldMap> with TickerProviderStateMixin {
  final camera = WorldCamera();
  late final AnimationController _clock = AnimationController(
    vsync: this,
    duration: const Duration(minutes: 10),
  )..repeat();
  late final Animation<double> _seconds = _clock.drive(Tween(begin: 0.0, end: 600.0));
  late final AnimationController _fly = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1700),
  );
  final _reveal = <String, AnimationController>{};
  StreamSubscription<GameEvent>? _sub;

  Set<String> _owned = {};
  Era? _era;
  bool _placed = false;
  Size _lastViewport = Size.zero;

  Offset _flyFromC = Offset.zero, _flyToC = Offset.zero;
  double _flyFromZ = 1, _flyToZ = 1;

  GameController get c => widget.controller;
  Game get g => c.game;

  @override
  void initState() {
    super.initState();
    _owned = {for (final r in g.ownedRooms) r.id};
    _era = g.s.era;
    for (final id in _owned) {
      _reveal[id] = AnimationController(vsync: this, value: 1);
    }
    c.addListener(_onTick);
    _sub = c.events.listen(_onEvent);
    _fly.addListener(() {
      final t = Curves.easeInOutCubic.transform(_fly.value);
      final z = math.exp(_lerp(math.log(_flyFromZ), math.log(_flyToZ), t));
      camera.set(Offset.lerp(_flyFromC, _flyToC, t)!, z, clamp: false);
    });
    _fly.addStatusListener((s) {
      if (s == AnimationStatus.completed) widget.onRevealDone?.call();
    });
  }

  static double _lerp(double a, double b, double t) => a + (b - a) * t;

  @override
  void dispose() {
    c.removeListener(_onTick);
    _sub?.cancel();
    _clock.dispose();
    _fly.dispose();
    for (final a in _reveal.values) {
      a.dispose();
    }
    camera.dispose();
    super.dispose();
  }

  void _onEvent(GameEvent e) {
    if (e is EraUnlocked) {
      // The next plot just became reachable: pull back to show it.
      setState(() => _era = e.era);
      _updateBounds();
      _flyTo(_revealedRect(), fill: 0.86);
    }
  }

  void _onTick() {
    if (!mounted) return;
    final owned = {for (final r in g.ownedRooms) r.id};
    if (owned.length != _owned.length || !owned.containsAll(_owned)) {
      final fresh = owned.difference(_owned);
      _owned = owned;
      for (final id in fresh) {
        final a =
            _reveal[id] ??= AnimationController(
              vsync: this,
              duration: const Duration(milliseconds: 1800),
            );
        a.forward(from: 0);
      }
      setState(() {});
      _updateBounds();
      if (fresh.isNotEmpty) _flyTo(_purchaseFrame(fresh.last), fill: 0.86);
    }
    if (g.s.era != _era) {
      setState(() => _era = g.s.era);
      _updateBounds();
    }
  }

  // --- Camera -----------------------------------------------------------------

  Rect _revealedRect() {
    Rect? r;
    for (final id in _owned) {
      final f = geoOf(id).frameRect;
      r = r == null ? f : r.expandToInclude(f);
    }
    if (_owned.contains('garage')) r = r!.expandToInclude(geoOf('house').rect.deflate(60));
    final next = nextPlot(g);
    if (next != null) r = r!.expandToInclude(geoOf(next.id).frameRect);
    return r!;
  }

  /// A new room and the one before it on the road.
  Rect _purchaseFrame(String id) {
    final i = rooms.indexWhere((r) => r.id == id);
    var r = geoOf(id).frameRect;
    if (i > 0) r = r.expandToInclude(geoOf(rooms[i - 1].id).frameRect);
    return r;
  }

  void _updateBounds() {
    final r = _revealedRect();
    camera.bounds = r;
    camera.minZoom = math.min(camera.fitZoom(r, fill: 0.95), 0.6) * 0.8;
    camera.maxZoom = 2.4;
  }

  void _flyTo(Rect target, {double fill = 0.8, Duration? duration}) {
    if (camera.viewport.isEmpty) return;
    _flyFromC = camera.center;
    _flyFromZ = camera.zoom;
    _flyToC = target.center;
    _flyToZ = camera.fitZoom(target, fill: fill).clamp(camera.minZoom, camera.maxZoom);
    _fly.duration = duration ?? const Duration(milliseconds: 1700);
    _fly.forward(from: 0);
  }

  /// Fly to one room (e.g. picked from the build drawer).
  void focusRoom(String id) =>
      _flyTo(geoOf(id).frameRect, fill: 0.82, duration: const Duration(milliseconds: 700));

  /// Frame everything you have so far.
  void showAll({bool animate = true}) {
    final r = _revealedRect();
    if (animate) {
      _flyTo(r, fill: 0.9, duration: const Duration(milliseconds: 900));
    } else {
      camera.set(r.center, camera.fitZoom(r, fill: 0.9));
    }
  }

  void _placeInitial(Size viewport) {
    camera.viewport = viewport;
    camera.safe = widget.safe;
    _updateBounds();
    if (_owned.length <= 1) {
      // Fresh start: tight on the garage, darkness all around.
      final f = geoOf('garage').frameRect;
      final portrait = viewport.height > viewport.width * 1.2;
      camera.set(f.center, camera.fitZoom(f, fill: portrait ? 0.92 : 0.78));
    } else if (viewport.height > viewport.width * 1.2) {
      // Portrait: the whole map would be tiny; start on your newest room.
      final f = geoOf(g.ownedRooms.last.id).frameRect;
      camera.set(f.center, camera.fitZoom(f, fill: 0.85));
    } else {
      final r = _revealedRect();
      camera.set(r.center, camera.fitZoom(r, fill: 0.9));
    }
    _placed = true;
    _lastViewport = viewport;
  }

  // --- Build ------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final vp = box.biggest;
        if (camera.safe != widget.safe) {
          camera.safe = widget.safe;
          if (_placed) {
            WidgetsBinding.instance.addPostFrameCallback(
              (_) => camera.set(camera.center, camera.zoom),
            );
          }
        }
        if (!_placed) {
          _placeInitial(vp);
        } else if (vp != _lastViewport) {
          _lastViewport = vp;
          camera.viewport = vp;
          _updateBounds();
          camera.set(camera.center, camera.zoom);
        }
        return ColoredBox(
          color: Colors.black,
          child: CameraView(
            camera: camera,
            worldSize: worldRect.size,
            onUserMove: () {
              if (_fly.isAnimating) _fly.stop();
            },
            overlayBuilder: _overlay,
            child: _world(),
          ),
        );
      },
    );
  }

  Widget _world() {
    final next = nextPlot(g);
    final order = [
      ...roomGeos.keys.where((id) => id == 'house' || _owned.contains(id) || id == next?.id),
    ]..sort((a, b) => geoOf(a).worldCenter.dy.compareTo(geoOf(b).worldCenter.dy));
    final reveals = [for (final id in _owned) _reveal[id]!];
    return SizedBox.fromSize(
      size: worldRect.size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: RepaintBoundary(
              child: CustomPaint(
                painter: _Backdrop(
                  owned: _owned,
                  next: next?.id,
                  reveals: {for (final id in _owned) id: _reveal[id]!},
                  repaint: Listenable.merge(reveals),
                ),
              ),
            ),
          ),
          for (final id in order)
            if (id == 'house')
              Positioned.fromRect(
                rect: geoOf(id).rect,
                child: _Decor(geo: geoOf(id), clock: _seconds, reveal: _reveal['garage']!),
              )
            else if (_owned.contains(id))
              Positioned.fromRect(
                key: ValueKey('room-$id'),
                rect: geoOf(id).rect,
                child: _OwnedRoom(
                  controller: c,
                  room: roomById(id)!,
                  geo: geoOf(id),
                  clock: _seconds,
                  reveal: _reveal[id]!,
                  buildState: widget.build,
                  hasFounder: id == _founderRoom(),
                  cheering: widget.cheering,
                  onCellTap: widget.onCellTap,
                ),
              )
            else
              Positioned.fromRect(
                key: ValueKey('plot-$id'),
                rect: geoOf(id).rect,
                child: _FaintPlot(geo: geoOf(id), reachable: g.isUnlocked(roomById(id)!.era)),
              ),
        ],
      ),
    );
  }

  /// "You" sit in the newest room that has a desk.
  String? _founderRoom() {
    String? best;
    for (final r in rooms) {
      if (_owned.contains(r.id) && geoOf(r.id).art.seat != null) best = r.id;
    }
    return best;
  }

  Widget _overlay(BuildContext context) {
    final next = nextPlot(g);
    final children = <Widget>[];
    if (next != null) {
      final geo = geoOf(next.id);
      final p = camera.worldToScreen(geo.worldCenter - Offset(0, geo.side * 0.12 * geo.scale));
      final safe = camera.safe, vp = camera.viewport;
      final area = Rect.fromLTRB(safe.left, safe.top, vp.width, vp.height - safe.bottom);
      final sign = _UnlockSign(
        key: ValueKey('unlock-${next.id}'),
        controller: c,
        room: next,
        compact: !area.deflate(60).contains(p),
        pointsRight: p.dx > area.center.dx,
        onTap: () => widget.onPlotTap(next),
      );
      if (area.deflate(60).contains(p)) {
        children.add(Positioned(left: p.dx - 125, top: p.dy - 40, width: 250, child: sign));
      } else {
        // Off screen: a small pill at the map's top edge pointing the way.
        final right = p.dx > area.center.dx;
        children.add(
          Positioned(
            top: area.top + 4,
            left: right ? null : area.left + 4,
            right: right ? 8 : null,
            child: sign,
          ),
        );
      }
    }
    // Floating "+$" / "+users" ticks over the room where you work.
    final home = _founderRoom() ?? g.ownedRooms.last.id;
    final hp = camera.worldToScreen(geoOf(home).worldCenter - Offset(0, 40 * geoOf(home).scale));
    children.add(
      Positioned(
        left: hp.dx - 80,
        top: hp.dy - 60,
        width: 160,
        height: 80,
        child: IncomeTicks(key: const ValueKey('income-ticks'), controller: c),
      ),
    );
    return Stack(clipBehavior: Clip.hardEdge, children: children);
  }
}

/// Every few seconds a "+$123" (and "+45 users") floats up and fades.
class IncomeTicks extends StatefulWidget {
  final GameController controller;
  const IncomeTicks({super.key, required this.controller});

  @override
  State<IncomeTicks> createState() => _IncomeTicksState();
}

class _IncomeTicksState extends State<IncomeTicks> with SingleTickerProviderStateMixin {
  static const _every = Duration(milliseconds: 3200);
  late final AnimationController _a = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1500),
  );
  Timer? _timer;
  double _money = 0, _users = 0;
  String? _moneyText, _usersText;

  @override
  void initState() {
    super.initState();
    _snap();
    _timer = Timer.periodic(_every, (_) => _fire());
  }

  void _snap() {
    _money = widget.controller.game.s.money;
    _users = widget.controller.game.s.users;
  }

  void _fire() {
    if (!mounted) return;
    final s = widget.controller.game.s;
    final dm = s.money - _money, du = s.users - _users;
    _snap();
    if (dm <= 0.5 && du < 1) return;
    setState(() {
      _moneyText = dm > 0.5 ? '+${formatMoney(dm)}' : null;
      _usersText = du >= 1 ? '+${formatNumber(du)} users' : null;
    });
    _a.forward(from: 0);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _a.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _a,
        builder: (context, _) {
          final t = _a.value;
          if (t == 0 || t == 1) return const SizedBox.shrink();
          final fade = t < 0.15 ? t / 0.15 : 1 - Curves.easeIn.transform((t - 0.15) / 0.85);
          return Opacity(
            opacity: fade.clamp(0.0, 1.0),
            child: Transform.translate(
              offset: Offset(0, 30 - 46 * Curves.easeOut.transform(t)),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (_moneyText case final m?) Text(m, style: _tick(AppColors.neon, 17)),
                  if (_usersText case final u?) Text(u, style: _tick(AppColors.cyan, 13)),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  static TextStyle _tick(Color c, double size) => numStyle(
    size: size,
    color: c,
    weight: FontWeight.w800,
  ).copyWith(shadows: const [Shadow(color: Colors.black, offset: Offset(0, 2), blurRadius: 2)]);
}

// --- Pieces -----------------------------------------------------------------

class _Backdrop extends CustomPainter {
  final Set<String> owned;
  final String? next;
  final Map<String, Animation<double>> reveals;

  _Backdrop({
    required this.owned,
    required this.next,
    required this.reveals,
    required Listenable repaint,
  }) : super(repaint: repaint);

  static const _story = ['garage', 'closet', 'colo', 'hall', 'campus', 'gigasite'];

  @override
  void paint(Canvas canvas, Size size) {
    // Roads between consecutive plots you can see.
    final road =
        Paint()
          ..color = const Color(0xFF12151D)
          ..strokeWidth = 70
          ..strokeCap = StrokeCap.round;
    final dash =
        Paint()
          ..color = const Color(0x55E0C27A)
          ..strokeWidth = 4;
    for (var i = 0; i + 1 < _story.length; i++) {
      final a = _story[i], b = _story[i + 1];
      final seen = owned.contains(a) && (owned.contains(b) || next == b);
      if (!seen) continue;
      final t = owned.contains(b) ? (reveals[b]?.value ?? 1) : 0.45;
      final pa = geoOf(a).worldCenter, pb = geoOf(b).worldCenter;
      canvas.drawLine(
        pa,
        pb,
        road..color = const Color(0xFF12151D).withValues(alpha: 0.5 + 0.5 * t),
      );
      final len = (pb - pa).distance;
      final dir = (pb - pa) / len;
      for (var d = 0.0; d < len; d += 60) {
        canvas.drawLine(pa + dir * d, pa + dir * math.min(len, d + 28), dash);
      }
    }
    // Pools of light around what you own: the darkness recedes as they grow.
    for (final id in owned) {
      final geo = geoOf(id);
      final t = Curves.easeOut.transform(reveals[id]?.value ?? 1);
      final r = geo.frameRect.width * (0.35 + 0.5 * t);
      final c = id == 'garage' ? const Color(0xFF2A2214) : const Color(0xFF142034);
      final center = geo.worldCenter;
      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.scale(1, 0.62);
      canvas.drawCircle(
        Offset.zero,
        r,
        Paint()
          ..shader = RadialGradient(
            colors: [c.withValues(alpha: 0.9 * t), c.withValues(alpha: 0)],
          ).createShader(Rect.fromCircle(center: Offset.zero, radius: r)),
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_Backdrop old) => old.owned != owned || old.next != next;
}

class _Decor extends StatelessWidget {
  final RoomGeo geo;
  final Animation<double> clock;
  final Animation<double> reveal;
  const _Decor({required this.geo, required this.clock, required this.reveal});

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: Stack(
      fit: StackFit.expand,
      children: [
        RepaintBoundary(
          child: Image.asset(
            GameArt.world(geo.id),
            fit: BoxFit.fill,
            opacity: reveal,
            filterQuality: FilterQuality.medium,
            errorBuilder: (_, __, ___) => const SizedBox(),
          ),
        ),
        RoomFx(geo: geo, clock: clock, under: false),
      ],
    ),
  );
}

class _OwnedRoom extends StatelessWidget {
  final GameController controller;
  final RoomDef room;
  final RoomGeo geo;
  final Animation<double> clock;
  final Animation<double> reveal;
  final BuildState buildState;
  final bool hasFounder;
  final bool cheering;
  final void Function(String roomId, int x, int y) onCellTap;

  const _OwnedRoom({
    required this.controller,
    required this.room,
    required this.geo,
    required this.clock,
    required this.reveal,
    required this.buildState,
    required this.hasFounder,
    required this.cheering,
    required this.onCellTap,
  });

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: reveal.drive(CurveTween(curve: const Interval(0, 0.6))),
      alwaysIncludeSemantics: true,
      child: Stack(
        fit: StackFit.expand,
        clipBehavior: Clip.none,
        children: [
          RepaintBoundary(
            child: Image.asset(
              GameArt.world(room.id),
              fit: BoxFit.fill,
              filterQuality: FilterQuality.medium,
              gaplessPlayback: true,
              errorBuilder: (_, __, ___) => const ColoredBox(color: AppColors.surface),
            ),
          ),
          RoomFx(geo: geo, clock: clock, under: true),
          if (hasFounder)
            Positioned(
              left: geo.seatLocal().dx - Founder.box.width * geo.scale / 2,
              top: geo.seatLocal().dy - Founder.box.height * geo.scale,
              child: _FounderHost(
                controller: controller,
                clock: clock,
                scale: geo.scale,
                cheering: cheering,
              ),
            ),
          RoomGrid(controller: controller, room: room, build: buildState, onCellTap: onCellTap),
          RoomFx(geo: geo, clock: clock, under: false),
        ],
      ),
    );
  }
}

/// Rebuilds the founder only when the mood changes, not every tick.
class _FounderHost extends StatefulWidget {
  final GameController controller;
  final Animation<double> clock;
  final double scale;
  final bool cheering;
  const _FounderHost({
    required this.controller,
    required this.clock,
    required this.scale,
    required this.cheering,
  });

  @override
  State<_FounderHost> createState() => _FounderHostState();
}

class _FounderHostState extends State<_FounderHost> {
  late FounderMood _mood = _compute();

  FounderMood _compute() {
    if (widget.cheering) return FounderMood.cheering;
    return widget.controller.game.training ? FounderMood.typing : FounderMood.idle;
  }

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_check);
  }

  @override
  void didUpdateWidget(_FounderHost old) {
    super.didUpdateWidget(old);
    _mood = _compute();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_check);
    super.dispose();
  }

  void _check() {
    final m = _compute();
    if (m != _mood && mounted) setState(() => _mood = m);
  }

  @override
  Widget build(BuildContext context) => Founder(
    key: const ValueKey('founder'),
    mood: _mood,
    clock: widget.clock,
    scale: widget.scale,
  );
}

class _FaintPlot extends StatelessWidget {
  final RoomGeo geo;
  final bool reachable;
  const _FaintPlot({required this.geo, required this.reachable});

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: Stack(
      fit: StackFit.expand,
      children: [
        RepaintBoundary(
          child: Image.asset(
            GameArt.world(geo.id),
            fit: BoxFit.fill,
            opacity: AlwaysStoppedAnimation(reachable ? 0.2 : 0.09),
            color: const Color(0xFF3A4A70),
            colorBlendMode: BlendMode.modulate,
            filterQuality: FilterQuality.low,
            errorBuilder: (_, __, ___) => const SizedBox(),
          ),
        ),
        CustomPaint(painter: _PlotOutline(geo, reachable)),
      ],
    ),
  );
}

class _PlotOutline extends CustomPainter {
  final RoomGeo geo;
  final bool reachable;
  _PlotOutline(this.geo, this.reachable);

  @override
  void paint(Canvas canvas, Size size) {
    final side = geo.side;
    final pts = [
      geo.svgToLocal(isoPt(0, 0)),
      geo.svgToLocal(isoPt(side, 0)),
      geo.svgToLocal(isoPt(side, side)),
      geo.svgToLocal(isoPt(0, side)),
    ];
    final paint =
        Paint()
          ..color = (reachable ? AppColors.amber : AppColors.faint).withValues(
            alpha: reachable ? 0.7 : 0.45,
          )
          ..strokeWidth = 3
          ..style = PaintingStyle.stroke;
    for (var i = 0; i < 4; i++) {
      final a = pts[i], b = pts[(i + 1) % 4];
      final len = (b - a).distance;
      final dir = (b - a) / len;
      for (var d = 0.0; d < len; d += 34) {
        canvas.drawLine(a + dir * d, a + dir * math.min(len, d + 18), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_PlotOutline old) => old.reachable != reachable;
}

/// Floating "Unlock area" sign over the next plot.
class _UnlockSign extends StatelessWidget {
  final GameController controller;
  final RoomDef room;
  final VoidCallback onTap;

  /// Off-screen pointer: one line with an arrow towards the plot.
  final bool compact;
  const _UnlockSign({
    super.key,
    required this.controller,
    required this.room,
    required this.onTap,
    this.compact = false,
    this.pointsRight = true,
  });

  final bool pointsRight;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final g = controller.game;
        final reason = g.roomBlockReason(room.id);
        final buyable = reason == null;
        final eraOk = g.isUnlocked(room.era);
        final color =
            buyable
                ? AppColors.neon
                : eraOk
                ? AppColors.amber
                : AppColors.muted;
        if (compact) {
          return Pulse(
            active: buyable,
            scale: 1.05,
            child: GestureDetector(
              onTap: onTap,
              child: Container(
                padding: const EdgeInsets.fromLTRB(8, 5, 10, 5),
                decoration: BoxDecoration(
                  color: const Color(0xE60B1220),
                  borderRadius: BorderRadius.circular(99),
                  border: Border.all(color: color, width: 1.6),
                  boxShadow: const [BoxShadow(color: Color(0xAA000000), offset: Offset(0, 3))],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      buyable ? Icons.lock_open_rounded : Icons.lock_rounded,
                      size: 13,
                      color: color,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      '${room.name} · ${formatMoney(room.cost)}',
                      style: numStyle(size: 11, color: AppColors.text, weight: FontWeight.w700),
                    ),
                    const SizedBox(width: 3),
                    Icon(
                      pointsRight ? Icons.east_rounded : Icons.west_rounded,
                      size: 14,
                      color: color,
                    ),
                  ],
                ),
              ),
            ),
          );
        }
        return Center(
          child: Pulse(
            active: buyable,
            scale: 1.05,
            child: GestureDetector(
              onTap: onTap,
              child: Container(
                padding: const EdgeInsets.fromLTRB(12, 7, 12, 8),
                decoration: BoxDecoration(
                  color: const Color(0xE60B1220),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: color, width: 2),
                  boxShadow: [
                    BoxShadow(
                      color: color.withValues(alpha: buyable ? 0.45 : 0.15),
                      blurRadius: 16,
                    ),
                    const BoxShadow(color: Color(0xAA000000), offset: Offset(0, 4)),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          buyable ? Icons.lock_open_rounded : Icons.lock_rounded,
                          size: 15,
                          color: color,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'UNLOCK AREA',
                          style: labelStyle(color: color, size: 12).copyWith(letterSpacing: 1.6),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        '${room.name} · ${formatMoney(room.cost)}',
                        maxLines: 1,
                        style: numStyle(size: 12, color: AppColors.text, weight: FontWeight.w700),
                      ),
                    ),
                    if (reason != null)
                      Text(
                        reason,
                        maxLines: 2,
                        textAlign: TextAlign.center,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: AppColors.muted, fontSize: 10.5, height: 1.2),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
