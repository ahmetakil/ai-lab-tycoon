// A small 2D camera for the world map: drag to pan, pinch / mouse wheel /
// trackpad to zoom around the pointer, clamped to the revealed area, with
// animated fly-tos for reveals.
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

class WorldCamera extends ChangeNotifier {
  Offset _center = Offset.zero;
  double _zoom = 1;
  Size viewport = Size.zero;

  /// Screen insets the camera should frame around (HUD, toolbar, drawer).
  EdgeInsets safe = EdgeInsets.zero;

  /// Where the centre may go (the revealed part of the world).
  Rect bounds = Rect.largest;
  double minZoom = 0.15;
  double maxZoom = 2.2;

  Offset get center => _center;
  double get zoom => _zoom;

  void set(Offset center, double zoom, {bool clamp = true}) {
    _zoom = clamp ? zoom.clamp(minZoom, maxZoom) : zoom;
    _center = clamp ? _clampCenter(center) : center;
    notifyListeners();
  }

  Offset _clampCenter(Offset c) {
    if (bounds == Rect.largest) return c;
    return Offset(
      c.dx.clamp(bounds.left, math.max(bounds.left, bounds.right)),
      c.dy.clamp(bounds.top, math.max(bounds.top, bounds.bottom)),
    );
  }

  /// Centre of the usable screen area (inside [safe]).
  Offset get _screenFocus => Offset(
    safe.left + (viewport.width - safe.horizontal) / 2,
    safe.top + (viewport.height - safe.vertical) / 2,
  );

  Offset worldToScreen(Offset w) => (w - _center) * _zoom + _screenFocus;
  Offset screenToWorld(Offset s) => (s - _screenFocus) / _zoom + _center;

  Matrix4 get matrix {
    final f = _screenFocus;
    return Matrix4.identity()
      ..translate(f.dx, f.dy)
      ..scale(_zoom, _zoom)
      ..translate(-_center.dx, -_center.dy);
  }

  /// The zoom at which [r] fills the usable screen area (with [fill] < 1 margin).
  double fitZoom(Rect r, {double fill = 0.9}) {
    final w = math.max(1.0, viewport.width - safe.horizontal);
    final h = math.max(1.0, viewport.height - safe.vertical);
    return math.min(w / r.width, h / r.height) * fill;
  }

  void zoomAt(Offset screen, double factor) {
    final before = screenToWorld(screen);
    _zoom = (_zoom * factor).clamp(minZoom, maxZoom);
    final f = _screenFocus;
    _center = _clampCenter(before - (screen - f) / _zoom);
    notifyListeners();
  }

  void panBy(Offset screenDelta) {
    _center = _clampCenter(_center - screenDelta / _zoom);
    notifyListeners();
  }
}

/// Paints [child] (a world-sized canvas) through [camera] and handles input.
class CameraView extends StatefulWidget {
  final WorldCamera camera;
  final Size worldSize;
  final Widget child;

  /// Painted in screen space above the world (signs, ticks), rebuilt with the camera.
  final Widget Function(BuildContext context)? overlayBuilder;
  final VoidCallback? onUserMove;

  const CameraView({
    super.key,
    required this.camera,
    required this.worldSize,
    required this.child,
    this.overlayBuilder,
    this.onUserMove,
  });

  @override
  State<CameraView> createState() => _CameraViewState();
}

class _CameraViewState extends State<CameraView> {
  double _startZoom = 1;

  WorldCamera get cam => widget.camera;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        cam.viewport = box.biggest;
        return Listener(
          onPointerSignal: (e) {
            if (e is PointerScrollEvent) {
              GestureBinding.instance.pointerSignalResolver.register(e, (e) {
                final dy = (e as PointerScrollEvent).scrollDelta.dy;
                cam.zoomAt(e.localPosition, math.exp(-dy / 400));
                widget.onUserMove?.call();
              });
            }
          },
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onScaleStart: (d) => _startZoom = cam.zoom,
            onScaleUpdate: (d) {
              if (d.pointerCount > 1 || d.scale != 1) {
                final target = _startZoom * d.scale;
                cam.zoomAt(d.localFocalPoint, target / cam.zoom);
              }
              cam.panBy(d.focalPointDelta);
              widget.onUserMove?.call();
            },
            child: ClipRect(
              child: Stack(
                clipBehavior: Clip.hardEdge,
                children: [
                  Positioned(
                    left: 0,
                    top: 0,
                    width: widget.worldSize.width,
                    height: widget.worldSize.height,
                    child: AnimatedBuilder(
                      animation: cam,
                      builder:
                          (context, child) => Transform(
                            transform: cam.matrix,
                            transformHitTests: true,
                            child: child,
                          ),
                      child: RepaintBoundary(child: widget.child),
                    ),
                  ),
                  if (widget.overlayBuilder != null)
                    Positioned.fill(
                      child: AnimatedBuilder(
                        animation: cam,
                        builder: (context, _) => widget.overlayBuilder!(context),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
