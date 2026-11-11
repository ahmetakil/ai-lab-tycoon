// OWNER: ui-moments agent.
// The Release Card: the shareable marketing engine. Rendered at a fixed
// 1200×675 logical size (social card aspect) and scaled to fit on screen.
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../../sim/content.dart';
import '../../sim/game.dart';
import '../../sim/game_state.dart';
import '../format.dart';
import '../game_assets.dart';
import '../sound.dart';
import 'benchmarks.dart';
import 'moments_style.dart';

/// Placeholder link printed on every card and post. Change before launch.
const kGameUrl = 'https://ai-lab-tycoon.example';

const kCardWidth = 1200.0;
const kCardHeight = 675.0;

/// Everything the card shows, snapshotted so it can be rendered any time.
class ReleaseCardData {
  final String labName;
  final String modelName;
  final bool open;
  final int year;
  final double rating;
  final double users;
  final double arr;
  final String rivalLab;
  final String rivalModel;
  final double rivalRating;
  final Era era;

  const ReleaseCardData({
    required this.labName,
    required this.modelName,
    required this.open,
    required this.year,
    required this.rating,
    required this.users,
    required this.arr,
    required this.rivalLab,
    required this.rivalModel,
    required this.rivalRating,
    required this.era,
  });

  /// Card for [release] (default: the model currently serving).
  /// Compares against the rival you are currently chasing; the year is the
  /// last-beaten rival's year (where you are in history).
  factory ReleaseCardData.fromGame(Game g, {ModelRelease? release}) {
    final r = release ?? g.s.currentModel;
    final rival = g.nextRival ?? rivalLadder.last;
    final year =
        g.s.rivalIndex > 0
            ? rivalLadder[math.min(g.s.rivalIndex, rivalLadder.length) - 1].year
            : rivalLadder.first.year;
    return ReleaseCardData(
      labName: g.s.labName,
      modelName: r.name,
      open: r.open,
      year: year,
      rating: r.rating,
      users: g.s.users,
      arr: g.arr,
      rivalLab: rival.lab,
      rivalModel: rival.model,
      rivalRating: rival.rating,
      era: g.s.era,
    );
  }

  BenchmarkReport get benchmarks => cherryPickedBenchmarks(rating, rivalRating);

  String get rivalFull => '$rivalLab $rivalModel';

  String get benchmarkLine {
    final b = benchmarks;
    final base = 'Beats $rivalFull on ${b.wins} of ${b.shown.length} cherry-picked benchmarks';
    if (b.wins == 0) return '$base. We tried.';
    if (b.wins == b.shown.length) return '$base. All of them. Allegedly.';
    return base;
  }

  /// Ready-to-paste post for X / LinkedIn.
  String get postText =>
      '$labName just shipped $modelName '
      '(${open ? 'open weights' : 'closed API'}).\n'
      'Arena-ish rating ${rating.round()} · ${formatNumber(users)} users · '
      '${formatMoney(arr)} ARR.\n'
      '$benchmarkLine.\n'
      'Started with one GPU in a garage. Your turn: $kGameUrl #AILabTycoon';
}

/// The card itself, always laid out at 1200×675 logical pixels.
class ReleaseCard extends StatelessWidget {
  final ReleaseCardData data;
  const ReleaseCard({super.key, required this.data});

  static const _bg = Color(0xFF070B10);
  static const _text = Color(0xFFEAF2F8);
  static const _muted = Color(0xFF8A9AA8);
  static const _rivalBar = Color(0xFF3A4652);

  TextStyle _d(double size, {Color color = _text, FontWeight w = FontWeight.w700, double? height, double ls = -0.5}) =>
      TextStyle(
        fontFamily: kDisplayFont,
        fontSize: size,
        fontWeight: w,
        color: color,
        height: height,
        letterSpacing: ls,
      );

  TextStyle _m(double size, {Color color = _text, FontWeight w = FontWeight.w500, double ls = 0}) => TextStyle(
    fontFamily: kMonoFont,
    fontSize: size,
    fontWeight: w,
    color: color,
    letterSpacing: ls,
    fontFeatures: const [FontFeature.tabularFigures()],
  );

  @override
  Widget build(BuildContext context) {
    const accent = Neon.green;
    final bench = data.benchmarks;
    return SizedBox(
      width: kCardWidth,
      height: kCardHeight,
      child: DefaultTextStyle(
        style: _d(20),
        child: ClipRect(
          child: Stack(
            children: [
              const Positioned.fill(child: ColoredBox(color: _bg)),
              Positioned.fill(child: CustomPaint(painter: _GridPainter())),
              // Glow blobs.
              Positioned(left: -220, top: -260, child: _glow(accent.withValues(alpha: 0.22), 720)),
              Positioned(right: -260, bottom: -320, child: _glow(Neon.magenta.withValues(alpha: 0.16), 760)),
              Padding(
                padding: const EdgeInsets.fromLTRB(64, 52, 64, 40),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(flex: 11, child: _left(accent)),
                          const SizedBox(width: 48),
                          Expanded(flex: 10, child: _right(accent, bench)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    Container(height: 1, color: Colors.white.withValues(alpha: 0.08)),
                    const SizedBox(height: 16),
                    _footer(accent),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _glow(Color c, double size) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(shape: BoxShape.circle, gradient: RadialGradient(colors: [c, c.withValues(alpha: 0)])),
  );

  Widget _left(Color accent) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _chip(data.labName.toUpperCase(), accent, filled: true),
            const SizedBox(width: 12),
            _chip('${data.year}', _text),
          ],
        ),
        const SizedBox(height: 26),
        Text('NEW MODEL RELEASE', style: _m(18, color: _muted, ls: 4)),
        const SizedBox(height: 6),
        SizedBox(
          height: 112,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              data.modelName,
              maxLines: 1,
              style: _d(
                96,
                height: 1.05,
                ls: -2.5,
              ).copyWith(shadows: [Shadow(color: accent.withValues(alpha: 0.55), blurRadius: 28)]),
            ),
          ),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Icon(
              data.open ? Icons.lock_open_rounded : Icons.lock_rounded,
              color: data.open ? Neon.cyan : Neon.yellow,
              size: 24,
            ),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                data.open ? 'Open weights. Fork away.' : 'Closed API. Trust us.',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: _d(24, color: data.open ? Neon.cyan : Neon.yellow, w: FontWeight.w600),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Builder(
          builder: (_) {
            final gap = (data.rating - data.rivalRating).round();
            return Text(
              'vs ${data.rivalFull}: ${gap >= 0 ? '+' : '−'}${gap.abs()} Arena-ish',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: _m(18, color: _muted),
            );
          },
        ),
        const Spacer(),
        Row(
          children: [
            Expanded(child: _stat('ARENA-ISH', '${data.rating.round()}', accent)),
            const SizedBox(width: 20),
            Expanded(child: _stat('USERS', formatNumber(data.users), _text)),
            const SizedBox(width: 20),
            Expanded(child: _stat('ARR', formatMoney(data.arr), _text)),
          ],
        ),
      ],
    );
  }

  Widget _stat(String label, String value, Color color) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: _m(16, color: _muted, ls: 2)),
      const SizedBox(height: 4),
      FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Text(value, style: _m(46, color: color, w: FontWeight.w700, ls: -1.5)),
      ),
    ],
  );

  Widget _chip(String text, Color color, {bool filled = false}) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
    constraints: const BoxConstraints(maxWidth: 420),
    decoration: BoxDecoration(
      color: filled ? color.withValues(alpha: 0.14) : Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: color.withValues(alpha: filled ? 0.9 : 0.35), width: 1.5),
    ),
    child: Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: _m(18, color: color, w: FontWeight.w700, ls: 1.5),
    ),
  );

  Widget _right(Color accent, BenchmarkReport bench) {
    return Container(
      padding: const EdgeInsets.fromLTRB(26, 20, 26, 18),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.035),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.09)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text.rich(
                  TextSpan(
                    children: [
                      const TextSpan(text: 'Benchmarks'),
                      TextSpan(text: '*', style: _d(26, color: Neon.magenta)),
                    ],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _d(26),
                ),
              ),
              _legendDot(accent),
              const SizedBox(width: 6),
              Text('Ours', style: _m(15, color: _muted)),
              const SizedBox(width: 14),
              _legendDot(_rivalBar),
              const SizedBox(width: 6),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 140),
                child: Text(
                  data.rivalModel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _m(15, color: _muted),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          for (final r in bench.shown) ...[_benchRow(r, accent), const SizedBox(height: 14)],
          const Spacer(),
          Text(
            data.benchmarkLine,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: _d(19, w: FontWeight.w600, height: 1.2, ls: -0.2),
          ),
        ],
      ),
    );
  }

  Widget _legendDot(Color c) =>
      Container(width: 12, height: 12, decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(3)));

  Widget _benchRow(BenchmarkResult r, Color accent) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                r.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: _d(16, w: FontWeight.w600, ls: 0, color: r.win ? _text : _muted, height: 1.1),
              ),
            ),
            if (r.win) Icon(Icons.check_rounded, size: 16, color: accent),
          ],
        ),
        const SizedBox(height: 4),
        _bar(r.mine, accent, bold: true),
        const SizedBox(height: 2),
        _bar(r.theirs, _rivalBar),
      ],
    );
  }

  Widget _bar(double value, Color color, {bool bold = false}) => SizedBox(
    height: bold ? 15 : 12,
    child: Row(
      children: [
        Expanded(
          child: LayoutBuilder(
            builder:
                (_, c) => Stack(
                  children: [
                    Container(
                      height: bold ? 12 : 8,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                    Container(
                      width: c.maxWidth * value / 100,
                      height: bold ? 12 : 8,
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius: BorderRadius.circular(6),
                        boxShadow: bold ? [BoxShadow(color: color.withValues(alpha: 0.5), blurRadius: 10)] : null,
                      ),
                    ),
                  ],
                ),
          ),
        ),
        SizedBox(
          width: 64,
          child: Text(
            value.toStringAsFixed(1),
            textAlign: TextAlign.right,
            style: _m(
              bold ? 14 : 12,
              color: bold ? _text : _muted,
              w: bold ? FontWeight.w700 : FontWeight.w500,
            ).copyWith(height: 1),
          ),
        ),
      ],
    ),
  );

  Widget _footer(Color accent) {
    return Row(
      children: [
        SizedBox(
          width: 40,
          height: 40,
          child: Image.asset(
            GameArt.logo,
            errorBuilder:
                (_, __, ___) => Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    gradient: LinearGradient(colors: [accent, Neon.cyan]),
                  ),
                  alignment: Alignment.center,
                  child: const Icon(Icons.memory_rounded, color: Neon.ink, size: 26),
                ),
          ),
        ),
        const SizedBox(width: 14),
        Text('AI LAB TYCOON', style: _d(24, w: FontWeight.w800, ls: 1)),
        const SizedBox(width: 22),
        Expanded(
          child: Text(
            '*Benchmarks hand-picked by our marketing team.',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: _m(15, color: _muted),
          ),
        ),
        Text('Play: ', style: _m(20, color: _muted)),
        Text(kGameUrl.replaceFirst(RegExp(r'^https?://'), ''), style: _m(20, color: accent, w: FontWeight.w700)),
      ],
    );
  }
}

class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p =
        Paint()
          ..color = Colors.white.withValues(alpha: 0.035)
          ..strokeWidth = 1;
    const step = 40.0;
    for (var x = 0.0; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), p);
    }
    for (var y = 0.0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), p);
    }
  }

  @override
  bool shouldRepaint(_GridPainter oldDelegate) => false;
}

/// Renders the boundary behind [key] to PNG bytes.
Future<Uint8List> renderCardPng(GlobalKey key, {double pixelRatio = 2}) async {
  final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final image = await boundary.toImage(pixelRatio: pixelRatio);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return bytes!.buffer.asUint8List();
}

/// Share the card image + post text. On web, share_plus uses the Web Share
/// API when files are shareable and otherwise downloads the PNG.
Future<String> shareReleaseCard(BuildContext context, GlobalKey key, ReleaseCardData data) async {
  final box = context.findRenderObject() as RenderBox?;
  final origin = box == null ? null : box.localToGlobal(Offset.zero) & box.size;
  final png = await renderCardPng(key);
  final fileName = '${data.modelName.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_')}_release.png';
  final result = await SharePlus.instance.share(
    ShareParams(
      files: [XFile.fromData(png, mimeType: 'image/png', name: fileName)],
      fileNameOverrides: [fileName],
      text: data.postText,
      subject: '${data.labName} releases ${data.modelName}',
      sharePositionOrigin: origin,
      downloadFallbackEnabled: true,
      mailToFallbackEnabled: false,
    ),
  );
  if (kIsWeb && result.status == ShareResultStatus.unavailable) {
    return 'Saved $fileName. Attach it to your post!';
  }
  return result.status == ShareResultStatus.dismissed ? '' : 'Shared. The timeline will never recover.';
}

/// Card scaled to fit its parent, wrapped in a RepaintBoundary for export.
class ScaledReleaseCard extends StatelessWidget {
  final ReleaseCardData data;
  final GlobalKey boundaryKey;
  const ScaledReleaseCard({super.key, required this.data, required this.boundaryKey});

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: kCardWidth / kCardHeight,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: FittedBox(fit: BoxFit.contain, child: RepaintBoundary(key: boundaryKey, child: ReleaseCard(data: data))),
      ),
    );
  }
}

/// Dialog with the card, Share and Copy buttons.
Future<void> showReleaseCardDialog(BuildContext context, ReleaseCardData data, {String? headline}) {
  return showGeneralDialog(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Release card',
    barrierColor: Colors.black.withValues(alpha: 0.78),
    transitionDuration: const Duration(milliseconds: 420),
    pageBuilder: (ctx, _, __) => _ReleaseCardDialog(data: data, headline: headline),
    transitionBuilder: (ctx, anim, _, child) {
      final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutBack, reverseCurve: Curves.easeIn);
      return FadeTransition(
        opacity: anim,
        child: ScaleTransition(scale: Tween(begin: 0.85, end: 1.0).animate(curved), child: child),
      );
    },
  );
}

class _ReleaseCardDialog extends StatefulWidget {
  final ReleaseCardData data;
  final String? headline;
  const _ReleaseCardDialog({required this.data, this.headline});

  @override
  State<_ReleaseCardDialog> createState() => _ReleaseCardDialogState();
}

class _ReleaseCardDialogState extends State<_ReleaseCardDialog> {
  final _key = GlobalKey();
  final _shareKey = GlobalKey();
  String _status = '';
  bool _busy = false;

  Future<void> _share() async {
    Sound.play(Sfx.click);
    setState(() => _busy = true);
    try {
      final msg = await shareReleaseCard(_shareKey.currentContext ?? context, _key, widget.data);
      if (mounted) setState(() => _status = msg);
    } catch (e) {
      if (mounted) setState(() => _status = 'Could not share: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _copy() async {
    Sound.play(Sfx.click);
    await Clipboard.setData(ClipboardData(text: widget.data.postText));
    if (mounted) setState(() => _status = 'Post text copied. Paste it on X or LinkedIn.');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Material(
              type: MaterialType.transparency,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    widget.headline ?? 'Your latest model',
                    textAlign: TextAlign.center,
                    style: display(context, 26),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Post it. Tag a friend who still runs a garage GPU.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [BoxShadow(color: Neon.green.withValues(alpha: 0.25), blurRadius: 40)],
                    ),
                    child: ScaledReleaseCard(data: widget.data, boundaryKey: _key),
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 12,
                    runSpacing: 10,
                    children: [
                      FilledButton.icon(
                        key: _shareKey,
                        onPressed: _busy ? null : _share,
                        icon:
                            _busy
                                ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                                : const Icon(Icons.ios_share_rounded),
                        label: Text(kIsWeb ? 'Share / save image' : 'Share image'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _copy,
                        icon: const Icon(Icons.copy_rounded),
                        label: const Text('Copy post text'),
                      ),
                      TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Done')),
                    ],
                  ),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 250),
                    child:
                        _status.isEmpty
                            ? const SizedBox(height: 28)
                            : Padding(
                              key: ValueKey(_status),
                              padding: const EdgeInsets.only(top: 10),
                              child: Text(
                                _status,
                                textAlign: TextAlign.center,
                                style: mono(context, 13, color: theme.colorScheme.primary),
                              ),
                            ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
