// The live rival feed in the UI: the news ticker card that drops in under the
// HUD ("yAI released Grokk 3"), the News tab of the leaderboard and the
// "while you were away" digest. Schedule and content: lib/sim/news.dart.
import 'dart:async';

import 'package:flutter/material.dart';

import '../../sim/content.dart';
import '../../sim/news.dart';
import '../format.dart';
import 'moments_style.dart';

/// "1,503": ratings with a thousands separator.
String _rating(double v) {
  final s = v.round().toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
    b.write(s[i]);
  }
  return b.toString();
}

/// "yAI released Grokk 3" or the flavour line itself.
String newsHeadline(NewsItem n) {
  final r = n.rival;
  return r == null ? n.flavour!.text : '${r.lab} released ${r.model}';
}

/// One detail about a released rival, rotating through fleet, users and the
/// parody quip so the feed doesn't read the same every time.
String rivalDetail(int index, RivalSnapshot r) {
  String gpus() =>
      'trained on ~${formatNumber(r.gpus, decimals: r.gpus >= 1e6 ? 1 : 0)} H100s';
  String users() => '~${formatNumber(r.users, decimals: 0)} users';
  return switch (index % 3) {
    0 when r.gpus >= 100 => gpus(),
    0 || 1 => users(),
    _ => r.quip.isEmpty ? users() : r.quip,
  };
}

/// "1,503 rating, trained on ~200k H100s" (a quip gets its own sentence);
/// null for flavour news.
String? newsDetail(NewsItem n) {
  final r = n.rival;
  if (r == null) return null;
  final d = rivalDetail(n.index, r);
  return '${_rating(r.rating)} rating${d == r.quip ? '. ' : ', '}$d';
}

/// "Overtook you (you were at 1,480)" / "You're still ahead"; [short]
/// drops the parenthesis (the ticker card).
String? newsVerdict(NewsItem n, {bool short = false}) {
  if (n.kind != NewsKind.rival) return null;
  if (!n.overtookYou) return 'You\'re still ahead';
  return short ? 'Overtook you' : 'Overtook you (you were at ${_rating(n.playerRating)})';
}

/// "just now", "12m ago", "3h ago" in game time.
String newsAgo(double seconds) {
  if (seconds < 60) return 'just now';
  if (seconds < 3600) return '${seconds ~/ 60}m ago';
  if (seconds < 48 * 3600) return '${seconds ~/ 3600}h ago';
  return '${seconds ~/ 86400}d ago';
}

Color _accent(NewsItem n) =>
    n.kind == NewsKind.flavour ? Neon.cyan : (n.overtookYou ? Neon.magenta : Neon.green);

/// The ticker card: one news item under the HUD. Tap to open the
/// leaderboard; swipe it away; it leaves on its own after [duration].
class NewsTicker extends StatefulWidget {
  final NewsItem item;
  final VoidCallback onTap;
  final VoidCallback onDone;
  final Duration duration;
  const NewsTicker({
    super.key,
    required this.item,
    required this.onTap,
    required this.onDone,
    this.duration = const Duration(milliseconds: 5200),
  });

  @override
  State<NewsTicker> createState() => _NewsTickerState();
}

class _NewsTickerState extends State<NewsTicker> with SingleTickerProviderStateMixin {
  late final _a = AnimationController(vsync: this, duration: const Duration(milliseconds: 320))..forward();
  Timer? _timer;
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer(widget.duration, _close);
  }

  Future<void> _close() async {
    if (_closing) return;
    _closing = true;
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
    final n = widget.item;
    final scheme = Theme.of(context).colorScheme;
    final accent = _accent(n);
    final detail = newsDetail(n);
    final verdict = newsVerdict(n, short: true);
    return FadeTransition(
      opacity: _a,
      child: SlideTransition(
        position: Tween(begin: const Offset(0, 0.5), end: Offset.zero)
            .animate(CurvedAnimation(parent: _a, curve: Curves.easeOutCubic)),
        child: Material(
          color: Colors.transparent,
          child: Dismissible(
            key: ValueKey('news-dismiss-${n.serial}'),
            onDismissed: (_) {
              _closing = true;
              widget.onDone();
            },
            child: InkWell(
              key: const ValueKey('news-toast'),
              borderRadius: BorderRadius.circular(12),
              onTap: () {
                widget.onTap();
                _close();
              },
              child: Ink(
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHigh.withValues(alpha: 0.96),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: accent.withValues(alpha: 0.55)),
                  boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 10, offset: Offset(0, 3))],
                ),
                padding: const EdgeInsets.fromLTRB(10, 8, 6, 8),
                child: Row(
                  children: [
                    RivalLogo(n.lab, size: 32),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            children: [
                              _Pill(n.kind == NewsKind.rival ? 'NEW MODEL' : 'NEWS', accent),
                              if (verdict != null) ...[
                                const SizedBox(width: 6),
                                Flexible(
                                  child: Text(
                                    verdict,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: mono(context, 10.5, color: accent, weight: FontWeight.w700),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 3),
                          Text(
                            newsHeadline(n),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style:
                                n.kind == NewsKind.rival
                                    ? display(context, 14.5)
                                    : TextStyle(fontSize: 13, color: scheme.onSurface, height: 1.25),
                          ),
                          if (detail != null)
                            Text(
                              detail,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant, height: 1.25),
                            ),
                        ],
                      ),
                    ),
                    Icon(Icons.chevron_right_rounded, color: scheme.onSurfaceVariant),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  final String text;
  final Color color;
  const _Pill(this.text, this.color);

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.16),
      borderRadius: BorderRadius.circular(4),
    ),
    child: Text(text, style: mono(context, 9.5, color: color, weight: FontWeight.w700).copyWith(letterSpacing: 1)),
  );
}

/// The leaderboard's News tab: newest first, with relative game time.
class NewsList extends StatelessWidget {
  final List<NewsItem> news;
  final double now;

  /// Tap on a rival release (its ladder index).
  final ValueChanged<int> onRival;
  const NewsList({super.key, required this.news, required this.now, required this.onRival});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (news.isEmpty) {
      return Padding(
        key: const ValueKey('news-list'),
        padding: const EdgeInsets.symmetric(vertical: 32),
        child: Text(
          'No news yet. The other labs are busy training.',
          textAlign: TextAlign.center,
          style: TextStyle(color: scheme.onSurfaceVariant),
        ),
      );
    }
    return Column(
      key: const ValueKey('news-list'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final n in news.reversed) _NewsRow(item: n, now: now, onRival: onRival),
      ],
    );
  }
}

class _NewsRow extends StatelessWidget {
  final NewsItem item;
  final double now;
  final ValueChanged<int> onRival;
  const _NewsRow({required this.item, required this.now, required this.onRival});

  @override
  Widget build(BuildContext context) {
    final n = item;
    final scheme = Theme.of(context).colorScheme;
    final accent = _accent(n);
    final detail = newsDetail(n);
    final verdict = newsVerdict(n);
    final rival = n.kind == NewsKind.rival;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        key: ValueKey('news-row-${n.serial}'),
        borderRadius: BorderRadius.circular(12),
        onTap: rival ? () => onRival(n.index) : null,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: scheme.surfaceContainer,
            borderRadius: BorderRadius.circular(12),
            border: Border(left: BorderSide(color: accent, width: 3)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              RivalLogo(n.lab, size: 34),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            rival ? 'NEW MODEL' : 'INDUSTRY',
                            style: mono(context, 10, color: accent, weight: FontWeight.w700).copyWith(letterSpacing: 1.2),
                          ),
                        ),
                        Text(newsAgo(now - n.time), style: mono(context, 10.5, color: scheme.onSurfaceVariant)),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      newsHeadline(n),
                      style: rival ? display(context, 15.5) : TextStyle(fontSize: 13.5, color: scheme.onSurface, height: 1.3),
                    ),
                    if (detail != null) ...[
                      const SizedBox(height: 2),
                      Text(detail, style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant, height: 1.3)),
                    ],
                    if (verdict != null) ...[
                      const SizedBox(height: 4),
                      Text(verdict, style: mono(context, 11, color: accent, weight: FontWeight.w700)),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// "While you were away" digest: the newest few headlines.
class NewsDigest extends StatelessWidget {
  final List<NewsItem> news;
  final int max;
  const NewsDigest({super.key, required this.news, this.max = 4});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final shown = news.reversed.take(max).toList();
    final more = news.length - shown.length;
    return Container(
      key: const ValueKey('news-digest'),
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('MEANWHILE IN AI', style: mono(context, 10.5, color: Neon.cyan, weight: FontWeight.w700).copyWith(letterSpacing: 1.5)),
          const SizedBox(height: 6),
          for (final n in shown)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  RivalLogo(n.lab, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      [
                        newsHeadline(n),
                        if (n.kind == NewsKind.rival) '(${_rating(n.rival!.rating)}${n.overtookYou ? ', ahead of you' : ''})',
                      ].join(' '),
                      style: const TextStyle(fontSize: 13, height: 1.3),
                    ),
                  ),
                ],
              ),
            ),
          if (more > 0)
            Text('+$more more in the leaderboard\'s News tab', style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
        ],
      ),
    );
  }
}
