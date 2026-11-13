// The one full-screen world: the room you're in, lit, on a dark map, and a
// faint silhouette of the next property with its "Move here" sign. (The
// parents' house sits beside the garage while you're there.) Moving is a
// moment: boxes and a truck along the road, the camera follows, the old room
// fades away and your tiles pop in at the new place (to the orbital station
// it's a rocket on a launch arc instead). Tap to skip.
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

/// How long the move moment lasts (tap skips it).
const kMoveDuration = Duration(milliseconds: 2800);

class WorldMap extends StatefulWidget {
  final GameController controller;
  final BuildState build;

  /// Screen space covered by HUD / toolbar / drawer; the camera frames inside it.
  final EdgeInsets safe;
  final bool cheering;
  final void Function(String roomId, int x, int y) onCellTap;
  final void Function(String roomId, int x, int y)? onCellPaint;
  final VoidCallback? onPaintEnd;
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
    this.onCellPaint,
    this.onPaintEnd,
    this.cheering = false,
    this.onRevealDone,
  });

  @override
  State<WorldMap> createState() => WorldMapState();
}

/// The next room you could move to (shown faintly), if any.
RoomDef? nextPlot(Game g) => g.nextRoom;

/// The way between two places goes to orbit (a launch arc, not a road).
bool _toOrbit(String a, String b) =>
    (roomById(a)?.speculative ?? false) || (roomById(b)?.speculative ?? false);

/// A point [t] along the launch arc from [a] to [b]: a quadratic curve that
/// climbs well above the straight line (up the screen) before coming down.
Offset _arcAt(Offset a, Offset b, double t) {
  final c = Offset((a.dx + b.dx) / 2, math.min(a.dy, b.dy) - 0.55 * (b - a).distance);
  final u = 1 - t;
  return a * (u * u) + c * (2 * u * t) + b * (t * t);
}

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

  /// 0 → 1 over a move (1 when no move is playing).
  late final AnimationController _move = AnimationController(
    vsync: this,
    duration: kMoveDuration,
    value: 1,
  );
  StreamSubscription<GameEvent>? _sub;

  late String _room;

  /// The room you just left, while the move moment plays.
  String? _from;
  Era? _era;
  bool _placed = false;
  Size _lastViewport = Size.zero;

  Offset _flyFromC = Offset.zero, _flyToC = Offset.zero;
  double _flyFromZ = 1, _flyToZ = 1;

  GameController get c => widget.controller;
  Game get g => c.game;

  /// True while the move moment plays.
  bool get moving => _from != null;

  @override
  void initState() {
    super.initState();
    _room = g.currentRoom.id;
    _era = g.s.era;
    c.addListener(_onTick);
    _sub = c.events.listen(_onEvent);
    _fly.addListener(() {
      final t = Curves.easeInOutCubic.transform(_fly.value);
      final z = math.exp(_lerp(math.log(_flyFromZ), math.log(_flyToZ), t));
      camera.set(Offset.lerp(_flyFromC, _flyToC, t)!, z, clamp: false);
    });
    _fly.addStatusListener((s) {
      if (s == AnimationStatus.completed && !moving) widget.onRevealDone?.call();
    });
    _move.addStatusListener((s) {
      if (s == AnimationStatus.completed && _from != null) {
        setState(() => _from = null);
        _updateBounds();
        widget.onRevealDone?.call();
      }
    });
  }

  static double _lerp(double a, double b, double t) => a + (b - a) * t;

  @override
  void dispose() {
    c.removeListener(_onTick);
    _sub?.cancel();
    _clock.dispose();
    _fly.dispose();
    _move.dispose();
    camera.dispose();
    super.dispose();
  }

  void _onEvent(GameEvent e) {
    if (e is EraUnlocked) {
      // The next plot just became reachable: pull back to show it.
      setState(() => _era = e.era);
      _updateBounds();
      if (!moving) _flyTo(_revealedRect(), fill: 0.86);
    }
  }

  void _onTick() {
    if (!mounted) return;
    final room = g.currentRoom.id;
    if (room != _room) _startMove(_room, room);
    if (g.s.era != _era) {
      setState(() => _era = g.s.era);
      _updateBounds();
    }
  }

  // --- Moving -------------------------------------------------------------------

  void _startMove(String from, String to) {
    setState(() {
      _from = from;
      _room = to;
    });
    _updateBounds();
    _move.forward(from: 0);
    // Camera: frame both places, then settle on the new one.
    _flyTo(
      geoOf(to).frameRect.expandToInclude(geoOf(from).frameRect.deflate(80)),
      fill: 0.9,
      duration: const Duration(milliseconds: 1100),
    );
    Future.delayed(const Duration(milliseconds: 1150), () {
      if (mounted && _from != null) {
        _flyTo(geoOf(_room).frameRect, fill: 0.84, duration: const Duration(milliseconds: 1400));
      }
    });
  }

  /// Jump to the end of the move moment.
  void skipMove() {
    if (!moving) return;
    _fly.stop();
    _move.value = 1; // completes → clears _from
    final f = geoOf(_room).frameRect;
    camera.set(f.center, camera.fitZoom(f, fill: 0.84).clamp(camera.minZoom, camera.maxZoom));
  }

  // --- Camera -----------------------------------------------------------------

  Rect _revealedRect() {
    var r = geoOf(_room).frameRect;
    if (_room == 'garage') r = r.expandToInclude(geoOf('house').rect.deflate(60));
    final next = nextPlot(g);
    if (next != null) r = r.expandToInclude(geoOf(next.id).frameRect);
    final from = _from;
    if (from != null) r = r.expandToInclude(geoOf(from).frameRect);
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

  /// Fly to one room.
  void focusRoom(String id) =>
      _flyTo(geoOf(id).frameRect, fill: 0.82, duration: const Duration(milliseconds: 700));

  /// Frame your place and the next plot.
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
    final f = geoOf(_room).frameRect;
    final portrait = viewport.height > viewport.width * 1.2;
    camera.set(f.center, camera.fitZoom(f, fill: portrait ? 0.92 : 0.8));
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
              if (_fly.isAnimating && !moving) _fly.stop();
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
    final from = _from;
    // While moving the plot you're moving into is the room itself.
    final showNext = next != null && next.id != _room;
    final ids = <String>[
      if (_room == 'garage' || from == 'garage') 'house',
      if (from != null) from,
      _room,
      if (showNext) next.id,
    ]..sort((a, b) => geoOf(a).worldCenter.dy.compareTo(geoOf(b).worldCenter.dy));
    // Fade-in of the new room and fade-out of the old one, from the move.
    final fadeIn = _move.drive(CurveTween(curve: const Interval(0.3, 0.75, curve: Curves.easeOut)));
    final fadeOut = _move.drive(
      Tween(begin: 1.0, end: 0.0).chain(CurveTween(curve: const Interval(0.15, 0.6))),
    );
    return SizedBox.fromSize(
      size: worldRect.size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: RepaintBoundary(
              child: CustomPaint(
                painter: _Backdrop(
                  room: _room,
                  from: from,
                  next: showNext ? next.id : null,
                  move: _move,
                ),
              ),
            ),
          ),
          for (final id in ids)
            if (id == 'house')
              Positioned.fromRect(
                rect: geoOf(id).rect,
                child: _Decor(
                  geo: geoOf(id),
                  clock: _seconds,
                  opacity: from == 'garage' ? fadeOut : const AlwaysStoppedAnimation(1),
                ),
              )
            else if (id == _room)
              Positioned.fromRect(
                key: ValueKey('room-$id'),
                rect: geoOf(id).rect,
                child: _OwnedRoom(
                  controller: c,
                  room: roomById(id)!,
                  geo: geoOf(id),
                  clock: _seconds,
                  reveal: fadeIn,
                  // Tiles pop in once the room has faded in.
                  showGrid: !moving || _move.value > 0.45,
                  move: _move,
                  buildState: widget.build,
                  hasFounder: geoOf(id).art.seat != null,
                  cheering: widget.cheering,
                  onCellTap: widget.onCellTap,
                  onCellPaint: widget.onCellPaint,
                  onPaintEnd: widget.onPaintEnd,
                ),
              )
            else if (id == from)
              Positioned.fromRect(
                key: ValueKey('leaving-$id'),
                rect: geoOf(id).rect,
                child: _LeavingRoom(geo: geoOf(id), opacity: fadeOut),
              )
            else
              Positioned.fromRect(
                key: ValueKey('plot-$id'),
                rect: geoOf(id).rect,
                child: _FaintPlot(
                  geo: geoOf(id),
                  reachable:
                      g.isUnlocked(roomById(id)!.era) &&
                      roomById(id)!.requires.every(g.s.ownedUpgrades.contains),
                ),
              ),
          if (from != null && _toOrbit(from, _room))
            _Launch(from: geoOf(from).worldCenter, to: geoOf(_room).worldCenter, t: _move)
          else if (from != null)
            _MovingTruck(from: geoOf(from).worldCenter, to: geoOf(_room).worldCenter, t: _move),
        ],
      ),
    );
  }

  Widget _overlay(BuildContext context) {
    final next = nextPlot(g);
    final children = <Widget>[];
    if (next != null && !moving) {
      final geo = geoOf(next.id);
      final p = camera.worldToScreen(geo.worldCenter - Offset(0, geo.side * 0.12 * geo.scale));
      final safe = camera.safe, vp = camera.viewport;
      final area = Rect.fromLTRB(safe.left, safe.top, vp.width, vp.height - safe.bottom);
      final sign = _MoveSign(
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
    final home = geoOf(_room);
    final hp = camera.worldToScreen(home.worldCenter - Offset(0, 40 * home.scale));
    children.add(
      Positioned(
        left: hp.dx - 80,
        top: hp.dy - 60,
        width: 160,
        height: 80,
        child: IncomeTicks(key: const ValueKey('income-ticks'), controller: c),
      ),
    );
    if (moving) {
      children.add(
        Positioned.fill(
          child: GestureDetector(
            key: const ValueKey('move-skip'),
            behavior: HitTestBehavior.opaque,
            onTap: skipMove,
            child: Align(
              alignment: const Alignment(0, -0.55),
              child: _MoveBanner(from: roomById(_from!)!, room: roomById(_room)!, t: _move),
            ),
          ),
        ),
      );
    }
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
  final String room;
  final String? from;
  final String? next;
  final Animation<double> move;

  _Backdrop({required this.room, required this.from, required this.next, required this.move})
    : super(repaint: move);

  @override
  void paint(Canvas canvas, Size size) {
    final road =
        Paint()
          ..strokeWidth = 70
          ..strokeCap = StrokeCap.round;
    final dash =
        Paint()
          ..color = const Color(0x55E0C27A)
          ..strokeWidth = 4;
    void drawRoad(String a, String b, double alpha) {
      final pa = geoOf(a).worldCenter, pb = geoOf(b).worldCenter;
      if (_toOrbit(a, b)) {
        // No road to orbit: a dotted launch trajectory.
        final dot = Paint()..color = const Color(0xFF7FD8FF).withValues(alpha: 0.55 * alpha);
        for (var i = 0; i <= 60; i++) {
          canvas.drawCircle(_arcAt(pa, pb, i / 60), i % 5 == 0 ? 7 : 4, dot);
        }
        return;
      }
      canvas.drawLine(pa, pb, road..color = const Color(0xFF12151D).withValues(alpha: alpha));
      final len = (pb - pa).distance;
      final dir = (pb - pa) / len;
      for (var d = 0.0; d < len; d += 60) {
        canvas.drawLine(pa + dir * d, pa + dir * math.min(len, d + 28), dash);
      }
    }

    final f = from;
    if (f != null) drawRoad(f, room, 1 - 0.5 * Curves.easeIn.transform(move.value));
    final n = next;
    if (n != null) drawRoad(room, n, 0.6);
    // A pool of light around where you are; while moving it follows you.
    void pool(String id, double t) {
      if (t <= 0) return;
      final geo = geoOf(id);
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

    final m = Curves.easeInOut.transform(move.value);
    if (f != null) pool(f, 1 - m);
    pool(room, f == null ? 1 : m);
  }

  @override
  bool shouldRepaint(_Backdrop old) =>
      old.room != room || old.from != from || old.next != next;
}

class _Decor extends StatelessWidget {
  final RoomGeo geo;
  final Animation<double> clock;
  final Animation<double> opacity;
  const _Decor({required this.geo, required this.clock, required this.opacity});

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: FadeTransition(
      opacity: opacity,
      child: Stack(
        fit: StackFit.expand,
        children: [
          RepaintBoundary(
            child: Image.asset(
              GameArt.world(geo.id),
              fit: BoxFit.fill,
              filterQuality: FilterQuality.medium,
              errorBuilder: (_, __, ___) => const SizedBox(),
            ),
          ),
          RoomFx(geo: geo, clock: clock, under: false),
        ],
      ),
    ),
  );
}

/// The room you just left: its art, packed boxes, fading out.
class _LeavingRoom extends StatelessWidget {
  final RoomGeo geo;
  final Animation<double> opacity;
  const _LeavingRoom({required this.geo, required this.opacity});

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: FadeTransition(
      opacity: opacity,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(
            GameArt.world(geo.id),
            fit: BoxFit.fill,
            filterQuality: FilterQuality.low,
            errorBuilder: (_, __, ___) => const SizedBox(),
          ),
          Align(
            alignment: const Alignment(0, 0.2),
            child: FractionallySizedBox(
              widthFactor: 0.35,
              child: AspectRatio(
                aspectRatio: 1,
                child: Image.asset(
                  GameArt.moveBoxes,
                  fit: BoxFit.contain,
                  errorBuilder:
                      (_, __, ___) => const FittedBox(
                        child: Icon(Icons.inventory_2_rounded, color: Color(0xFFC9A36A)),
                      ),
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

/// The moving truck driving along the road from the old place to the new.
class _MovingTruck extends StatelessWidget {
  final Offset from, to;
  final Animation<double> t;
  const _MovingTruck({required this.from, required this.to, required this.t});

  @override
  Widget build(BuildContext context) {
    final leftward = to.dx < from.dx;
    const w = 220.0, h = 140.0;
    return AnimatedBuilder(
      animation: t,
      builder: (context, _) {
        final k = Curves.easeInOutCubic.transform(((t.value - 0.05) / 0.7).clamp(0.0, 1.0));
        final p = Offset.lerp(from, to, k)!;
        final fade = t.value > 0.85 ? (1 - (t.value - 0.85) / 0.15) : 1.0;
        final bounce = math.sin(t.value * math.pi * 14).abs() * 6;
        return Positioned(
          left: p.dx - w / 2,
          top: p.dy - h + 20 - bounce,
          width: w,
          height: h,
          child: IgnorePointer(
            child: Opacity(
              opacity: fade.clamp(0.0, 1.0),
              child: Image.asset(
                leftward ? GameArt.moveTruckFlip : GameArt.moveTruck,
                key: const ValueKey('move-truck'),
                fit: BoxFit.contain,
                errorBuilder:
                    (_, __, ___) => Transform.flip(
                      flipX: leftward,
                      child: const FittedBox(
                        child: Icon(Icons.local_shipping_rounded, color: Color(0xFFFFB547)),
                      ),
                    ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Moving to orbit: a heavy-lift rocket climbs the launch arc from the old
/// site to the station, nose along its path, with a flickering plume.
class _Launch extends StatelessWidget {
  final Offset from, to;
  final Animation<double> t;
  const _Launch({required this.from, required this.to, required this.t});

  @override
  Widget build(BuildContext context) {
    const w = 120.0, h = 260.0;
    return AnimatedBuilder(
      animation: t,
      builder: (context, _) {
        // Liftoff pause, then an accelerating climb along the arc.
        final k = Curves.easeInQuad.transform(((t.value - 0.08) / 0.7).clamp(0.0, 1.0));
        final p = _arcAt(from, to, k);
        final q = _arcAt(from, to, math.min(1, k + 0.01));
        final dir = k >= 1 ? const Offset(0.4, 1) : q - p;
        // Nose up the screen at liftoff, then along the path.
        final angle = k <= 0 ? 0.0 : math.atan2(dir.dx, -dir.dy);
        final fade = t.value > 0.82 ? (1 - (t.value - 0.82) / 0.12) : 1.0;
        return Positioned(
          left: p.dx - w / 2,
          top: p.dy - h / 2,
          width: w,
          height: h,
          child: IgnorePointer(
            child: Opacity(
              opacity: fade.clamp(0.0, 1.0),
              child: Transform.rotate(
                key: const ValueKey('move-rocket'),
                angle: angle,
                child: CustomPaint(painter: _RocketPainter(t.value)),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _RocketPainter extends CustomPainter {
  final double t;
  _RocketPainter(this.t);

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final top = size.height * 0.1, body = size.height * 0.42, r = size.width * 0.16;
    final ink = Paint()
      ..color = const Color(0xFF080C1A)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    // Plume: a flickering teardrop of light below the engines.
    final flick = 0.85 + 0.15 * math.sin(t * 90);
    final base = top + body + r * 0.4;
    final plume = Path()
      ..moveTo(cx - r * 0.9, base)
      ..quadraticBezierTo(cx, base + size.height * 0.5 * flick, cx + r * 0.9, base)
      ..close();
    canvas.drawPath(
      plume,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFFFFFFF), Color(0xFFFFD58A), Color(0x00FF6B3D)],
        ).createShader(Rect.fromLTWH(cx - r, base, 2 * r, size.height * 0.5))
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );
    // Fins.
    for (final s in [-1.0, 1.0]) {
      final fin = Path()
        ..moveTo(cx + s * r, top + body - r * 1.6)
        ..lineTo(cx + s * r * 2.0, top + body + r * 0.4)
        ..lineTo(cx + s * r, top + body)
        ..close();
      canvas.drawPath(fin, Paint()..color = const Color(0xFF55658F));
      canvas.drawPath(fin, ink);
    }
    // Body with a nose cone and a window.
    final hull = Path()
      ..moveTo(cx, top - r * 1.2)
      ..quadraticBezierTo(cx + r * 1.05, top - r * 0.2, cx + r, top + r * 0.6)
      ..lineTo(cx + r, top + body)
      ..lineTo(cx - r, top + body)
      ..lineTo(cx - r, top + r * 0.6)
      ..quadraticBezierTo(cx - r * 1.05, top - r * 0.2, cx, top - r * 1.2)
      ..close();
    canvas.drawPath(
      hull,
      Paint()
        ..shader = const LinearGradient(
          colors: [Color(0xFFEAF2FF), Color(0xFFB8C2D6), Color(0xFF8E9CC4)],
        ).createShader(Rect.fromLTWH(cx - r, top, 2 * r, body)),
    );
    canvas.drawRect(Rect.fromLTWH(cx - r, top + body * 0.62, 2 * r, body * 0.06), Paint()..color = const Color(0xFF2E3B6B));
    canvas.drawPath(hull, ink);
    canvas.drawCircle(Offset(cx, top + body * 0.28), r * 0.42, Paint()..color = const Color(0xFF3DD6FF));
    canvas.drawCircle(Offset(cx, top + body * 0.28), r * 0.42, ink..strokeWidth = 2.4);
    // Engine bell.
    canvas.drawRect(
      Rect.fromLTWH(cx - r * 0.6, top + body, r * 1.2, r * 0.4),
      Paint()..color = const Color(0xFF2A3048),
    );
  }

  @override
  bool shouldRepaint(_RocketPainter old) => old.t != t;
}

/// "Moving to the Server closet · tap to skip".
class _MoveBanner extends StatelessWidget {
  final RoomDef from;
  final RoomDef room;
  final Animation<double> t;
  const _MoveBanner({required this.from, required this.room, required this.t});

  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity: t.drive(
      TweenSequence([
        TweenSequenceItem(tween: Tween(begin: 0.0, end: 1.0), weight: 10),
        TweenSequenceItem(tween: ConstantTween(1.0), weight: 75),
        TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.0), weight: 15),
      ]),
    ),
    child: Container(
      key: const ValueKey('move-banner'),
      padding: const EdgeInsets.fromLTRB(16, 9, 16, 10),
      decoration: BoxDecoration(
        color: const Color(0xEE0B1220),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.amber, width: 2),
        boxShadow: [BoxShadow(color: AppColors.amber.withValues(alpha: 0.3), blurRadius: 18)],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.local_shipping_rounded, color: AppColors.amber, size: 18),
              const SizedBox(width: 8),
              Text(
                'MOVING DAY',
                style: labelStyle(color: AppColors.amber, size: 12).copyWith(letterSpacing: 1.6),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            '${from.name}  →  ${room.name}',
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
          ),
          const Text(
            'everything comes with you · tap to skip',
            style: TextStyle(color: AppColors.muted, fontSize: 11),
          ),
        ],
      ),
    ),
  );
}

class _OwnedRoom extends StatelessWidget {
  final GameController controller;
  final RoomDef room;
  final RoomGeo geo;
  final Animation<double> clock;
  final Animation<double> reveal;

  /// Rebuilds the grid when the move moment reaches the pop-in.
  final Animation<double> move;
  final bool showGrid;
  final BuildState buildState;
  final bool hasFounder;
  final bool cheering;
  final void Function(String roomId, int x, int y) onCellTap;
  final void Function(String roomId, int x, int y)? onCellPaint;
  final VoidCallback? onPaintEnd;

  const _OwnedRoom({
    required this.controller,
    required this.room,
    required this.geo,
    required this.clock,
    required this.reveal,
    required this.move,
    required this.showGrid,
    required this.buildState,
    required this.hasFounder,
    required this.cheering,
    required this.onCellTap,
    this.onCellPaint,
    this.onPaintEnd,
  });

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: reveal,
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
          // While moving, the tiles pop in once the room has faded in.
          if (showGrid)
            RoomGrid(
              controller: controller,
              room: room,
              build: buildState,
              onCellTap: onCellTap,
              onCellPaint: onCellPaint,
              onPaintEnd: onPaintEnd,
            )
          else
            AnimatedBuilder(
              animation: move,
              builder:
                  (context, _) =>
                      move.value > 0.45
                          ? RoomGrid(
                            controller: controller,
                            room: room,
                            build: buildState,
                            onCellTap: onCellTap,
                          )
                          : const SizedBox.shrink(),
            ),
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

/// Floating "Move here" sign over the next plot ("Next place" while it's
/// still locked).
class _MoveSign extends StatelessWidget {
  final GameController controller;
  final RoomDef room;
  final VoidCallback onTap;

  /// Off-screen pointer: one line with an arrow towards the plot.
  final bool compact;
  const _MoveSign({
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
                      !buyable
                          ? Icons.lock_rounded
                          : room.speculative
                          ? Icons.rocket_launch_rounded
                          : Icons.local_shipping_rounded,
                      size: 13,
                      color: color,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      'Move to ${room.name} · ${formatMoney(room.cost)}',
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
                          !buyable
                              ? Icons.lock_rounded
                              : room.speculative
                              ? Icons.rocket_launch_rounded
                              : Icons.local_shipping_rounded,
                          size: 15,
                          color: color,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          buyable ? (room.speculative ? 'LAUNCH' : 'MOVE HERE') : 'NEXT PLACE',
                          style: labelStyle(color: color, size: 12).copyWith(letterSpacing: 1.6),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        'Move to ${room.name} · ${formatMoney(room.cost)}',
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
