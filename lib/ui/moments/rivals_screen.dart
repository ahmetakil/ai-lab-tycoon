// OWNER: ui-moments agent.
// The rival ladder as a timeline: beaten, current target, and the mysterious
// future. Your own lab card (with the share button) sits on top.
import 'package:flutter/material.dart';

import '../../sim/content.dart';
import '../../sim/game.dart';
import '../format.dart';
import '../game_assets.dart';
import '../game_controller.dart';
import '../sound.dart';
import 'moments_style.dart';
import 'release_card.dart';

class RivalsScreen extends StatelessWidget {
  final GameController controller;
  const RivalsScreen({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final g = controller.game;
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
                  : _Status.upcoming;
          items.add(
            _TimelineRow(
              last: i == rivalLadder.length - 1,
              status: status,
              child: switch (status) {
                _Status.beaten => _BeatenTile(rival: r),
                _Status.target => _TargetCard(rival: r, game: g),
                _Status.upcoming => _UpcomingTile(rival: r),
              },
            ),
          );
        }
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 640),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _MyLabCard(controller: controller),
                    const SizedBox(height: 22),
                    Row(
                      children: [
                        Text('The race', style: display(context, 24)),
                        const Spacer(),
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
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

enum _Status { beaten, target, upcoming }

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
            Text(label, style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant)),
            if (done) ...[const SizedBox(width: 6), Icon(Icons.check_rounded, size: 16, color: accent)],
            const Spacer(),
            Text('${format(mine)} / ${format(theirs)}', style: mono(context, 12.5, weight: FontWeight.w600)),
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
