// OWNER: ui-moments agent.
// Launch reviews, Game Dev Tycoon style: four parody outlets flip their
// scores in one at a time (with a sound each), then the verdict banner and
// the buzz it gives. The whole reveal takes ~2.4 s; a tap skips to the end,
// and a tap when it's done continues. Scores come from lib/sim/reviews.dart.
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../sim/game_state.dart';
import '../../sim/reviews.dart';
import '../format.dart';
import '../sound.dart';
import 'moments_style.dart';

/// When each score flips (fractions of [kReviewRevealDuration]); the banner
/// comes last.
const kReviewRevealDuration = Duration(milliseconds: 2400);
const _flipAt = [0.12, 0.30, 0.48, 0.66];
const _bannerAt = 0.84;
const _flipLength = 0.12;

/// True from the moment the player hits Release until the reviews close.
/// EventPresenter holds celebrations, news and the release toast meanwhile
/// (its overlay sits above every route and would cover the reveal).
final launchReviewsActive = ValueNotifier<bool>(false);

Color reviewScoreColor(num score) => score >= 8
    ? Neon.green
    : score >= 6
    ? Neon.cyan
    : score >= 4
    ? Neon.yellow
    : Neon.red;

/// Shows the reviews for [release] (no-op without reviews). With [animate]
/// false (e.g. from the stats screen) everything is shown at once.
Future<void> showLaunchReviewsDialog(BuildContext context, ModelRelease release, {bool animate = true}) async {
  final review = release.review;
  if (review == null) return;
  await showGeneralDialog<void>(
    context: context,
    barrierDismissible: !animate,
    barrierLabel: 'Launch reviews',
    barrierColor: Colors.black.withValues(alpha: 0.8),
    transitionDuration: const Duration(milliseconds: 260),
    pageBuilder: (ctx, _, __) => LaunchReviewsView(
      modelName: release.name,
      review: review,
      animate: animate,
      onDone: () => Navigator.of(ctx).pop(),
    ),
    transitionBuilder: (ctx, anim, _, child) => FadeTransition(
      opacity: anim,
      child: ScaleTransition(
        scale: Tween(begin: 0.92, end: 1.0).animate(CurvedAnimation(parent: anim, curve: Curves.easeOutBack)),
        child: child,
      ),
    ),
  );
}

class LaunchReviewsView extends StatefulWidget {
  final String modelName;
  final LaunchReview review;
  final bool animate;
  final VoidCallback onDone;

  /// Plays a sound effect (Sound.play; tests record them).
  final void Function(Sfx) playSound;
  const LaunchReviewsView({
    super.key,
    required this.modelName,
    required this.review,
    required this.onDone,
    this.animate = true,
    this.playSound = Sound.play,
  });

  @override
  State<LaunchReviewsView> createState() => _LaunchReviewsViewState();
}

class _LaunchReviewsViewState extends State<LaunchReviewsView> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: kReviewRevealDuration);

  /// Sounds already played (flips 0..3, then the banner).
  int _sounds = 0;

  /// Tapped to skip: the remaining flips land silently.
  bool _skipped = false;

  @override
  void initState() {
    super.initState();
    _c.addListener(_onTick);
    if (widget.animate) {
      _c.forward();
    } else {
      _sounds = 5;
      _c.value = 1;
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _onTick() {
    final reviews = widget.review.reviews;
    while (_sounds < reviews.length && _sounds < _flipAt.length && _c.value >= _flipAt[_sounds]) {
      final s = reviews[_sounds].score;
      // A skip jumps straight to the banner's sound.
      if (!_skipped) widget.playSound(s >= 7 ? Sfx.purchase : (s <= 3 ? Sfx.error : Sfx.click));
      _sounds++;
    }
    if (_sounds >= _flipAt.length && _sounds < _flipAt.length + 1 && _c.value >= _bannerAt) {
      final avg = widget.review.average;
      widget.playSound(avg >= 7.5 ? Sfx.rivalBeaten : avg >= 6 ? Sfx.upgrade : avg >= 4.5 ? Sfx.click : Sfx.stuntFail);
      _sounds++;
    }
  }

  void _tap() {
    if (_c.value < 1) {
      _skipped = true;
      _c.value = 1; // Skip: flips land, banner plays its sound once.
    } else {
      widget.playSound(Sfx.click);
      widget.onDone();
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.review;
    return GestureDetector(
      key: const ValueKey('reviews-tap'),
      behavior: HitTestBehavior.opaque,
      onTap: _tap,
      child: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Material(
              type: MaterialType.transparency,
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: AnimatedBuilder(
                  animation: _c,
                  builder: (context, _) => Column(
                    key: const ValueKey('launch-reviews'),
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('THE REVIEWS ARE IN', style: mono(context, 13, color: Neon.yellow, weight: FontWeight.w700)),
                      const SizedBox(height: 4),
                      Text(
                        widget.modelName,
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: display(context, 28),
                      ),
                      const SizedBox(height: 12),
                      LayoutBuilder(
                        builder: (context, box) {
                          final cols = box.maxWidth >= 560 ? 2 : 1;
                          final w = (box.maxWidth - 12 * (cols - 1)) / cols;
                          return Wrap(
                            spacing: 12,
                            runSpacing: 8,
                            children: [
                              for (var i = 0; i < r.reviews.length; i++)
                                SizedBox(
                                  width: w,
                                  child: _ReviewCard(
                                    review: r.reviews[i],
                                    t: _flipProgress(i),
                                  ),
                                ),
                            ],
                          );
                        },
                      ),
                      const SizedBox(height: 14),
                      _Banner(review: r, t: ((_c.value - _bannerAt) / (1 - _bannerAt)).clamp(0.0, 1.0)),
                      const SizedBox(height: 14),
                      AnimatedOpacity(
                        duration: const Duration(milliseconds: 200),
                        opacity: _c.value >= 1 ? 1 : 0.55,
                        child: Text(
                          _c.value >= 1 ? 'Tap to continue' : 'Tap to skip',
                          key: const ValueKey('reviews-hint'),
                          style: mono(context, 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
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

  /// 0 = face down, 1 = score showing.
  double _flipProgress(int i) {
    final at = i < _flipAt.length ? _flipAt[i] : _flipAt.last;
    return ((_c.value - at) / _flipLength).clamp(0.0, 1.0);
  }
}

class _ReviewCard extends StatelessWidget {
  final Review review;

  /// Flip progress 0..1.
  final double t;
  const _ReviewCard({required this.review, required this.t});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final shown = t >= 0.5;
    final color = shown ? reviewScoreColor(review.score) : scheme.onSurfaceVariant;
    final angle = (shown ? 1 - t : t) * math.pi; // flips around the X axis
    final o = review.outlet;
    return Transform(
      alignment: Alignment.center,
      transform: Matrix4.identity()
        ..setEntry(3, 2, 0.0015)
        ..rotateX(angle),
      child: Container(
        key: ValueKey('review-${review.outletId}${shown ? '-shown' : ''}'),
        padding: const EdgeInsets.fromLTRB(14, 9, 12, 9),
        constraints: const BoxConstraints(minHeight: 80),
        decoration: BoxDecoration(
          color: Color.alphaBlend(color.withValues(alpha: shown ? 0.08 : 0.03), Neon.panel),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: shown ? 0.6 : 0.2), width: 1.5),
          boxShadow: shown ? [BoxShadow(color: color.withValues(alpha: 0.18), blurRadius: 14)] : null,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(o.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: display(context, 16)),
                  Text(o.tagline.toUpperCase(), style: mono(context, 10, color: scheme.onSurfaceVariant)),
                  const SizedBox(height: 4),
                  Text(
                    shown ? review.quip : '…',
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13, height: 1.25, color: shown ? scheme.onSurface : scheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            SizedBox(
              width: 58,
              child: Column(
                children: [
                  Text(
                    shown ? '${review.score}' : '?',
                    style: mono(context, 34, color: color, weight: FontWeight.w700).copyWith(height: 1.05),
                  ),
                  Text('/10', style: mono(context, 11, color: scheme.onSurfaceVariant)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  final LaunchReview review;

  /// Reveal progress 0..1.
  final double t;
  const _Banner({required this.review, required this.t});

  @override
  Widget build(BuildContext context) {
    final avg = review.average;
    final color = reviewScoreColor(avg);
    final pct = ((review.buzz - 1) * 100).round();
    final buzz = pct == 0
        ? 'No buzz either way.'
        : 'Buzz: demand ${pct > 0 ? '+' : '−'}${pct.abs()}% for ${formatDuration(review.buzzSeconds)}, fading.';
    final scale = t <= 0 ? 0.0 : Curves.easeOutBack.transform(t);
    return Opacity(
      opacity: t.clamp(0.0, 1.0),
      child: Transform.scale(
        scale: 0.6 + 0.4 * scale,
        child: Container(
          key: const ValueKey('reviews-verdict'),
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [color.withValues(alpha: 0.22), color.withValues(alpha: 0.06)]),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: color, width: 2),
            boxShadow: [BoxShadow(color: color.withValues(alpha: 0.3), blurRadius: 24)],
          ),
          child: Column(
            children: [
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(review.verdict.toUpperCase(), style: display(context, 26, color: color)),
                    const SizedBox(width: 14),
                    Text(review.averageText, style: mono(context, 30, color: color, weight: FontWeight.w700)),
                    Text(' /10', style: mono(context, 14, color: color)),
                  ],
                ),
              ),
              const SizedBox(height: 2),
              Text(
                buzz,
                textAlign: TextAlign.center,
                style: mono(context, 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
