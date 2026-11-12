// OWNER: ui-moments agent.
// The leaderboard (your lab ranked among the rival labs by rating) on top of
// the rival ladder as a timeline: beaten, current target, released rivals
// ahead of you and the mysterious future. Your own lab card (with the share
// button) sits above both. A News tab lists the live rival feed.
import 'package:flutter/material.dart';

import '../../sim/content.dart';
import '../../sim/game.dart';
import '../../sim/news.dart';
import '../format.dart';
import '../game_assets.dart';
import '../game_controller.dart';
import '../shell/game_modal.dart';
import '../sound.dart';
import '../theme.dart';
import 'moments_style.dart';
import 'news_feed.dart';
import 'release_card.dart';

/// Opens the leaderboard modal, optionally on the News tab or with a rival
/// row (ladder index) highlighted.
Future<void> showLeaderboard(
  BuildContext context,
  GameController controller, {
  int? highlight,
  bool news = false,
}) => showGameModal<void>(
  context,
  title: 'Leaderboard',
  icon: Icons.leaderboard_rounded,
  color: AppColors.amber,
  maxWidth: 680,
  selfScrolling: true,
  child: RivalsScreen(controller: controller, highlight: highlight, showNews: news),
);

class RivalsScreen extends StatefulWidget {
  final GameController controller;

  /// Ladder index of a rival row to highlight (from a news toast).
  final int? highlight;

  /// Start on the News tab.
  final bool showNews;
  const RivalsScreen({super.key, required this.controller, this.highlight, this.showNews = false});

  @override
  State<RivalsScreen> createState() => _RivalsScreenState();
}

class _RivalsScreenState extends State<RivalsScreen> {
  late bool _news = widget.showNews;
  late int? _highlight = widget.highlight;

  GameController get controller => widget.controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final g = controller.game;
        if (_news) {
          return _list([
            _tabs(g),
            const SizedBox(height: 12),
            NewsList(
              news: g.s.news,
              now: g.s.time,
              onRival: (i) => setState(() {
                _news = false;
                _highlight = i;
              }),
            ),
          ]);
        }
        final items = <Widget>[];
        int? lastYear;
        for (final (i, r) in rivalLadder.indexed) {
          if (r.year != lastYear) {
            items.add(_YearHeader(year: r.year, reached: i <= g.s.rivalIndex));
            lastYear = r.year;
          }
          final status =
              i < g.s.rivalIndex
                  ? _Status.beaten
                  : i == g.s.rivalIndex
                  ? _Status.target
                  : g.isReleased(i)
                  ? _Status.released
                  : _Status.upcoming;
          items.add(
            _TimelineRow(
              last: i == rivalLadder.length - 1,
              status: status,
              child: switch (status) {
                _Status.beaten => _BeatenTile(rival: r),
                _Status.target => _TargetCard(rival: r, game: g),
                _Status.released => _ReleasedTile(rival: r, game: g),
                _Status.upcoming => _UpcomingTile(rival: r),
              },
            ),
          );
        }
        return _list([
          _tabs(g),
          const SizedBox(height: 12),
          _MyLabCard(controller: controller),
          const SizedBox(height: 18),
          Leaderboard(game: g, highlight: _highlight),
          const SizedBox(height: 22),
          Row(
            children: [
              Expanded(
                child: Text(
                  'The race',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: display(context, 24),
                ),
              ),
              Text(
                '${g.s.rivalIndex}/${rivalLadder.length} passed',
                style: mono(context, 13, color: Theme.of(context).colorScheme.primary),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ...items,
          if (g.nextRival == null) ...[
            const SizedBox(height: 12),
            Text(
              'You passed everyone. History is now yours to write.',
              textAlign: TextAlign.center,
              style: display(context, 16),
            ),
          ],
          const SizedBox(height: 24),
          Text(
            'Rival stats are loosely based on public estimates. All names are parodies.',
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
        ]);
      },
    );
  }

  Widget _list(List<Widget> children) => ListView(
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
    children: [
      Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
        ),
      ),
    ],
  );

  Widget _tabs(Game g) {
    final fresh = g.s.news.where((n) => g.s.time - n.time < 600).length;
    return SegmentedButton<bool>(
      key: const ValueKey('rivals-tabs'),
      showSelectedIcon: false,
      segments: [
        const ButtonSegment(
          value: false,
          icon: Icon(Icons.leaderboard_rounded, size: 18),
          label: Text('Board', key: ValueKey('tab-board')),
        ),
        ButtonSegment(
          value: true,
          icon: const Icon(Icons.newspaper_rounded, size: 18),
          label: Text(fresh > 0 ? 'News ($fresh new)' : 'News', key: const ValueKey('tab-news')),
        ),
      ],
      selected: {_news},
      onSelectionChanged: (v) {
        Sound.play(Sfx.click);
        setState(() => _news = v.first);
      },
    );
  }
}

enum _Status { beaten, target, released, upcoming }

class _MyLabCard extends StatelessWidget {
  final GameController controller;
  const _MyLabCard({required this.controller});

  Future<void> _rename(BuildContext context) async {
    final ctl = TextEditingController(text: controller.game.s.labName);
    final name = await showDialog<String>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: const Text('Rename your lab'),
            content: TextField(
              controller: ctl,
              autofocus: true,
              maxLength: 28,
              textCapitalization: TextCapitalization.words,
              onSubmitted: (v) => Navigator.of(ctx).pop(v),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel')),
              FilledButton(onPressed: () => Navigator.of(ctx).pop(ctl.text), child: const Text('Rename')),
            ],
          ),
    );
    ctl.dispose();
    final n = name?.trim();
    if (n != null && n.isNotEmpty) controller.act((g) => g.s.labName = n);
  }

  @override
  Widget build(BuildContext context) {
    final g = controller.game;
    final scheme = Theme.of(context).colorScheme;
    final model = g.s.currentModel;
    final shipped = g.s.releases.length > 1;
    Widget stat(String label, String value) => Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: mono(context, 10.5, color: scheme.onSurfaceVariant)),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value, style: mono(context, 20, weight: FontWeight.w700)),
          ),
        ],
      ),
    );
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [scheme.primary.withValues(alpha: 0.16), scheme.surfaceContainerHigh],
        ),
        border: Border.all(color: scheme.primary.withValues(alpha: 0.45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  color: scheme.surface,
                  child: GameImage(GameArt.playerLab, size: 56, fallback: Icons.home_work_rounded),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'YOUR LAB · ${g.s.era.label.toUpperCase()} ERA',
                      style: mono(context, 11, color: scheme.primary, weight: FontWeight.w700),
                    ),
                    InkWell(
                      onTap: () => _rename(context),
                      borderRadius: BorderRadius.circular(6),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(
                            child: Text(
                              g.s.labName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: display(context, 22),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Icon(Icons.edit_rounded, size: 16, color: scheme.onSurfaceVariant),
                        ],
                      ),
                    ),
                    Text(
                      'Serving: ${model.name} ${model.open ? '(open)' : '(closed)'}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              stat('RATING', '${g.rating.round()}'),
              stat('USERS', formatNumber(g.s.users)),
              stat('ARR', formatMoney(g.arr)),
            ],
          ),
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: () {
              Sound.play(Sfx.click);
              showReleaseCardDialog(
                context,
                ReleaseCardData.fromGame(g),
                headline: shipped ? 'Your latest model' : 'Your starter model (ship something better!)',
              );
            },
            icon: const Icon(Icons.ios_share_rounded),
            label: const Text('Share your latest model'),
          ),
        ],
      ),
    );
  }
}

class _YearHeader extends StatelessWidget {
  final int year;
  final bool reached;
  const _YearHeader({required this.year, required this.reached});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 14, bottom: 6),
      child: Row(
        children: [
          SizedBox(
            width: 36,
            child: Center(
              child: Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: reached ? scheme.primary : scheme.surfaceContainerHighest,
                ),
              ),
            ),
          ),
          Text(
            '$year',
            style: mono(
              context,
              18,
              weight: FontWeight.w700,
              color: reached ? scheme.onSurface : scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(child: Divider(color: scheme.outlineVariant.withValues(alpha: 0.5))),
        ],
      ),
    );
  }
}

/// The vertical timeline rail with a node per rival.
class _TimelineRow extends StatelessWidget {
  final _Status status;
  final bool last;
  final Widget child;
  const _TimelineRow({required this.status, required this.last, required this.child});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final railColor =
        status == _Status.beaten ? scheme.primary.withValues(alpha: 0.6) : scheme.outlineVariant.withValues(alpha: 0.5);
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(width: 36, child: Center(child: Container(width: 2, color: railColor))),
          Expanded(child: Padding(padding: const EdgeInsets.symmetric(vertical: 5), child: child)),
        ],
      ),
    );
  }
}

class _BeatenTile extends StatelessWidget {
  final RivalSnapshot rival;
  const _BeatenTile({required this.rival});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Opacity(
      opacity: 0.6,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(color: scheme.surfaceContainer, borderRadius: BorderRadius.circular(12)),
        child: Row(
          children: [
            RivalLogo(rival.lab, size: 34, dimmed: true),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(rival.lab, style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
                  Text(
                    rival.model,
                    style: display(context, 16, weight: FontWeight.w600).copyWith(
                      decoration: TextDecoration.lineThrough,
                      decorationColor: scheme.primary,
                      decorationThickness: 2,
                    ),
                  ),
                ],
              ),
            ),
            Text('${rival.rating.round()}', style: mono(context, 13, color: scheme.onSurfaceVariant)),
            const SizedBox(width: 10),
            Icon(Icons.check_circle_rounded, color: scheme.primary),
          ],
        ),
      ),
    );
  }
}

/// A rival that's out (on the leaderboard) but not your target yet.
class _ReleasedTile extends StatelessWidget {
  final RivalSnapshot rival;
  final Game game;
  const _ReleasedTile({required this.rival, required this.game});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final gap = rival.rating - game.rating;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: scheme.surfaceContainer,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.7)),
      ),
      child: Row(
        children: [
          RivalLogo(rival.lab, size: 34),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(rival.lab, style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
                Text(rival.model, style: display(context, 16, weight: FontWeight.w600)),
                Text(
                  'rating ${formatRating(rival.rating)} · ${formatNumber(rival.users)} users',
                  style: mono(context, 11, color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (gap > 0)
            Text('+${gap.ceil()}', style: mono(context, 12, color: Neon.magenta, weight: FontWeight.w700)),
        ],
      ),
    );
  }
}

class _UpcomingTile extends StatelessWidget {
  final RivalSnapshot rival;
  const _UpcomingTile({required this.rival});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          ImageFiltered(
            imageFilter: ColorFilter.mode(scheme.onSurfaceVariant.withValues(alpha: 0.6), BlendMode.srcIn),
            child: RivalLogo(rival.lab, size: 34),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(rival.lab, style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
                Text('???', style: display(context, 16, color: scheme.onSurfaceVariant, weight: FontWeight.w600)),
                Text('rating ??? · users ???', style: mono(context, 11, color: scheme.onSurfaceVariant)),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Icon(Icons.lock_outline_rounded, size: 20, color: scheme.onSurfaceVariant),
        ],
      ),
    );
  }
}

class _TargetCard extends StatefulWidget {
  final RivalSnapshot rival;
  final Game game;
  const _TargetCard({required this.rival, required this.game});

  @override
  State<_TargetCard> createState() => _TargetCardState();
}

class _TargetCardState extends State<_TargetCard> with SingleTickerProviderStateMixin {
  late final _glow = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600))
    ..repeat(reverse: true);

  @override
  void dispose() {
    _glow.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.rival;
    final g = widget.game;
    final scheme = Theme.of(context).colorScheme;
    final accent = scheme.primary;
    final rating = g.rating;
    final users = g.s.users;
    final ratingGap = r.rating - rating;
    final usersGap = r.users - users;
    final gaps = <String>[
      if (ratingGap > 0) '+${ratingGap.ceil()} rating',
      if (usersGap > 0) '+${formatNumber(usersGap)} users',
    ];
    return AnimatedBuilder(
      animation: _glow,
      builder:
          (context, child) => Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: accent, width: 2),
              color: Color.alphaBlend(accent.withValues(alpha: 0.08), scheme.surfaceContainerHigh),
              boxShadow: [
                BoxShadow(
                  color: accent.withValues(alpha: 0.15 + 0.25 * _glow.value),
                  blurRadius: 10 + 16 * _glow.value,
                ),
              ],
            ),
            child: child,
          ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                RivalLogo(r.lab, size: 52),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'CURRENT TARGET',
                        style: mono(context, 10.5, color: accent, weight: FontWeight.w700).copyWith(letterSpacing: 2),
                      ),
                      Text(r.lab, style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant)),
                      Text(r.model, style: display(context, 22)),
                    ],
                  ),
                ),
                if (r.gpus > 0)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text('GPUs (est.)', style: mono(context, 10, color: scheme.onSurfaceVariant)),
                      Text('~${formatNumber(r.gpus)}', style: mono(context, 15, weight: FontWeight.w700)),
                    ],
                  ),
              ],
            ),
            if (r.quip.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                '“${r.quip}”',
                style: TextStyle(fontStyle: FontStyle.italic, color: scheme.onSurfaceVariant, fontSize: 13.5),
              ),
            ],
            const SizedBox(height: 14),
            _VersusBar(label: 'Rating', mine: rating, theirs: r.rating, format: (v) => '${v.round()}', accent: accent),
            const SizedBox(height: 10),
            _VersusBar(label: 'Users', mine: users, theirs: r.users, format: formatNumber, accent: Neon.cyan),
            const SizedBox(height: 12),
            Text(
              gaps.isEmpty ? 'Passing them any second now…' : 'Gap: ${gaps.join(' and ')}',
              style: mono(context, 13, color: gaps.isEmpty ? accent : scheme.onSurface, weight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }
}

class _VersusBar extends StatelessWidget {
  final String label;
  final double mine, theirs;
  final String Function(double) format;
  final Color accent;
  const _VersusBar({
    required this.label,
    required this.mine,
    required this.theirs,
    required this.format,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final p = theirs <= 0 ? 1.0 : (mine / theirs).clamp(0.0, 1.0);
    final done = mine >= theirs;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant),
              ),
            ),
            if (done) ...[const SizedBox(width: 6), Icon(Icons.check_rounded, size: 16, color: accent)],
            const Spacer(),
            const SizedBox(width: 8),
            Flexible(
              flex: 3,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerRight,
                child: Text(
                  '${format(mine)} / ${format(theirs)}',
                  style: mono(context, 12.5, weight: FontWeight.w600),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: TweenAnimationBuilder<double>(
            tween: Tween(end: p),
            duration: const Duration(milliseconds: 500),
            curve: Curves.easeOutCubic,
            builder:
                (_, v, __) => LinearProgressIndicator(
                  value: v,
                  minHeight: 10,
                  color: accent,
                  backgroundColor: scheme.surfaceContainerHighest,
                ),
          ),
        ),
      ],
    );
  }
}


/// Your lab ranked among the rivals by rating: a window of rows around you
/// (lab, model, rating, users, year), your row highlighted, beaten rivals
/// marked, and the gap to the next one.
class Leaderboard extends StatelessWidget {
  final Game game;

  /// Ladder index of a rival row to show and highlight (fresh news).
  final int? highlight;
  const Leaderboard({super.key, required this.game, this.highlight});

  @override
  Widget build(BuildContext context) {
    final g = game;
    final scheme = Theme.of(context).colorScheme;
    // (rival or null for you, ladder index)
    // Only rivals that have released a model so far (news.dart).
    final rows = <(RivalSnapshot?, int)>[
      for (final (i, r) in rivalLadder.indexed)
        if (g.isReleased(i)) (r, i),
      (null, -1),
    ];
    double ratingOf((RivalSnapshot?, int) e) => e.$1?.rating ?? g.rating;
    rows.sort((a, b) {
      final c = ratingOf(b).compareTo(ratingOf(a));
      if (c != 0) return c;
      return a.$1 == null ? -1 : (b.$1 == null ? 1 : 0); // ties: you first
    });
    final me = rows.indexWhere((e) => e.$1 == null);
    // Centre the window on you, or on the highlighted row if it's far off.
    final hi = highlight == null ? -1 : rows.indexWhere((e) => e.$1 != null && e.$2 == highlight);
    final centre = hi >= 0 && (hi - me).abs() >= 4 ? hi : me;
    final from = (centre - 4).clamp(0, rows.length);
    final to = (centre + 4).clamp(0, rows.length);
    final next = g.nextRival;
    String gap() {
      if (next == null) return 'You top the leaderboard.';
      final dr = next.rating - g.rating;
      final du = next.users - g.s.users;
      if (!g.isUnlocked(next.era)) {
        return 'Next: ${next.model} (${next.lab}). Reach the ${next.era.label} era first.';
      }
      if (dr > 0) return '+${dr.ceil()} rating to pass ${next.model} (${next.lab})';
      if (du > 0) return '+${formatNumber(du)} users to pass ${next.model} (${next.lab})';
      return 'Passing ${next.model} now…';
    }

    Widget cell(String t, {double? w, TextAlign align = TextAlign.right, TextStyle? style, int flex = 0}) {
      final text = Text(t, maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: align, style: style);
      return flex > 0 ? Expanded(flex: flex, child: text) : SizedBox(width: w, child: text);
    }

    final head = mono(context, 10.5, color: scheme.onSurfaceVariant);
    return Container(
      key: const ValueKey('leaderboard'),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.emoji_events_rounded, size: 18, color: Color(0xFFFFB547)),
              const SizedBox(width: 6),
              Expanded(child: Text('Leaderboard', style: display(context, 18))),
              Text('#${me + 1} of ${rows.length}', style: mono(context, 13, color: scheme.primary)),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            gap(),
            key: const ValueKey('leaderboard-gap'),
            style: mono(context, 12.5, color: const Color(0xFF39FF9F), weight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              cell('#', w: 26, align: TextAlign.left, style: head),
              cell('LAB · MODEL', flex: 1, align: TextAlign.left, style: head),
              cell('RATING', w: 50, style: head),
              cell('USERS', w: 54, style: head),
              cell('YEAR', w: 40, style: head),
            ],
          ),
          const Divider(height: 10),
          for (var i = from; i < to; i++)
            _LeaderRow(
              rank: i + 1,
              rival: rows[i].$1,
              beaten: rows[i].$1 != null && rows[i].$2 < g.s.rivalIndex,
              target: rows[i].$1 != null && rows[i].$2 == g.s.rivalIndex,
              highlighted: hi >= 0 && i == hi,
              game: g,
              cell: cell,
            ),
        ],
      ),
    );
  }
}

class _LeaderRow extends StatelessWidget {
  final int rank;
  final RivalSnapshot? rival;
  final bool beaten;
  final bool target;
  final bool highlighted;
  final Game game;
  final Widget Function(String t, {double? w, TextAlign align, TextStyle? style, int flex}) cell;

  const _LeaderRow({
    required this.rank,
    required this.rival,
    required this.beaten,
    required this.target,
    this.highlighted = false,
    required this.game,
    required this.cell,
  });

  @override
  Widget build(BuildContext context) {
    final r = rival;
    final you = r == null;
    final scheme = Theme.of(context).colorScheme;
    final color =
        you
            ? const Color(0xFF39FF9F)
            : beaten
            ? scheme.onSurfaceVariant
            : scheme.onSurface;
    final style = mono(context, 12, color: color, weight: you ? FontWeight.w800 : FontWeight.w500);
    final name =
        you
            ? '${game.s.labName} · ${game.s.releases.last.name}'
            : '${r.lab} · ${r.model}';
    return Container(
      key: you ? const ValueKey('leaderboard-you') : (highlighted ? const ValueKey('leaderboard-highlight') : null),
      margin: const EdgeInsets.only(bottom: 2),
      padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 4),
      decoration: BoxDecoration(
        color:
            you
                ? const Color(0x2239FF9F)
                : highlighted
                ? Neon.cyan.withValues(alpha: 0.14)
                : (target ? const Color(0x14FFB547) : null),
        borderRadius: BorderRadius.circular(8),
        border:
            you
                ? Border.all(color: const Color(0xAA39FF9F))
                : (highlighted ? Border.all(color: Neon.cyan.withValues(alpha: 0.8)) : null),
      ),
      child: Row(
        children: [
          cell('$rank', w: 22, align: TextAlign.left, style: style),
          if (beaten)
            const Padding(
              padding: EdgeInsets.only(right: 4),
              child: Icon(Icons.check_circle, size: 13, color: Color(0xFF39FF9F)),
            )
          else if (target)
            const Padding(
              padding: EdgeInsets.only(right: 4),
              child: Icon(Icons.gps_fixed, size: 13, color: Color(0xFFFFB547)),
            )
          else if (highlighted)
            const Padding(
              padding: EdgeInsets.only(right: 4),
              child: Icon(Icons.fiber_new_rounded, size: 14, color: Neon.cyan),
            ),
          cell(
            beaten ? '$name · beaten' : (target ? '$name · next' : name),
            flex: 1,
            align: TextAlign.left,
            style: style,
          ),
          cell(formatRating(r?.rating ?? game.rating), w: 50, style: style),
          cell(formatNumber(r?.users ?? game.s.users), w: 54, style: style),
          cell(you ? 'now' : '${r.year}', w: 40, style: style),
        ],
      ),
    );
  }
}
