// OWNER: ui-moments agent.
// Called by the overview screen when a trained model is pending release.
import 'package:flutter/material.dart';

import '../shell/game_modal.dart';
import '../../sim/balance.dart';
import '../../sim/content.dart';
import '../../sim/game.dart';
import '../format.dart';
import '../game_controller.dart';
import '../sound.dart';
import 'moments_style.dart';
import 'naming_joke.dart';
import 'release_card.dart';

/// Default model name: lab initials + version, e.g. "GL-2".
String defaultModelName(Game g) {
  final initials = labInitials(g.s.labName);
  return '$initials-${g.s.releases.length}';
}

Future<void> showReleaseSheet(BuildContext context, GameController controller) async {
  if (controller.game.s.pendingEffectiveCompute == null) return;
  Sound.play(Sfx.click);
  final released = await showGameModal<bool>(
    context,
    title: 'Release model',
    icon: Icons.rocket_launch_rounded,
    maxWidth: 620,
    selfScrolling: true,
    child: ReleaseSheet(controller: controller),
  );
  if (released == true && context.mounted) {
    final data = ReleaseCardData.fromGame(controller.game);
    await showReleaseCardDialog(context, data, headline: '${data.modelName} is live!');
  }
}

class ReleaseSheet extends StatefulWidget {
  final GameController controller;
  const ReleaseSheet({super.key, required this.controller});

  @override
  State<ReleaseSheet> createState() => _ReleaseSheetState();
}

class _ReleaseSheetState extends State<ReleaseSheet> {
  late final TextEditingController _name;
  bool _open = false;
  String _stunt = launchStunts.first.id;

  Game get g => widget.controller.game;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: defaultModelName(g))..addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _addSuffix(String s) {
    final t = _name.text.trimRight();
    _name.text = t.isEmpty ? s : '$t-$s';
    Sound.play(Sfx.click);
  }

  void _release() {
    final name = _name.text.trim().isEmpty ? defaultModelName(g) : _name.text.trim();
    final ok = widget.controller.act((g) => g.release(open: _open, stuntId: _stunt, name: name));
    Navigator.of(context).pop(ok);
  }

  void _discard() {
    widget.controller.act((g) => g.discardPending());
    Sound.play(Sfx.click);
    Navigator.of(context).pop(false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final pending = g.s.pendingEffectiveCompute;
    if (pending == null) {
      return const Padding(padding: EdgeInsets.all(32), child: Text('Nothing to release.'));
    }
    final predicted = g.pendingRating!;
    final current = g.rating;
    final delta = predicted - current;
    final joke = namingJoke(_name.text);

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Ship it?', style: display(context, 28)),
            const SizedBox(height: 4),
            Text(
              'Training finished. Name it, pick a license, pick a stunt.',
              style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            _RatingCompare(predicted: predicted, current: current),
            if (delta < 0) ...[
              const SizedBox(height: 8),
              _Warning(
                icon: Icons.trending_down_rounded,
                color: Neon.red,
                text:
                    'This model is ${(-delta).round()} points WORSE than what you serve now. '
                    'You can ship it anyway. Users will notice, and hype won\'t grow.',
              ),
            ],
            const SizedBox(height: 18),
            TextField(
              controller: _name,
              maxLength: 40,
              style: display(context, 20, weight: FontWeight.w600),
              decoration: const InputDecoration(labelText: 'Model name', border: OutlineInputBorder(), counterText: ''),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                for (final s in namingSuffixSuggestions)
                  ActionChip(
                    label: Text('+$s', style: mono(context, 12)),
                    visualDensity: VisualDensity.compact,
                    onPressed: () => _addSuffix(s),
                  ),
              ],
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 200),
              child:
                  joke == null
                      ? const SizedBox(width: double.infinity)
                      : Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: _Warning(
                          icon: Icons.sentiment_very_dissatisfied_rounded,
                          color: Neon.yellow,
                          text: joke,
                        ),
                      ),
            ),
            const SizedBox(height: 18),
            Text('License', style: display(context, 18)),
            const SizedBox(height: 8),
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: _ChoiceCard(
                      selected: !_open,
                      color: Neon.yellow,
                      icon: Icons.lock_rounded,
                      title: 'Closed API',
                      lines: const ['Full API revenue per user', 'Normal hype'],
                      onTap: () => setState(() => _open = false),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _ChoiceCard(
                      selected: _open,
                      color: Neon.cyan,
                      icon: Icons.lock_open_rounded,
                      title: 'Open weights',
                      lines: [
                        'Hype x${openSourceHypeMult.toStringAsFixed(1)} at launch',
                        '+${((openSourceCommunityTrainBonus - 1) * 100).round()}% training efficiency forever (community)',
                        '${((1 - openSourceArpuMult) * 100).round()}% less revenue per user',
                      ],
                      onTap: () => setState(() => _open = true),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            Text('Launch stunt', style: display(context, 18)),
            const SizedBox(height: 8),
            for (final s in launchStunts.where((s) => g.isUnlocked(s.era))) ...[
              _StuntTile(
                stunt: s,
                money: g.s.money,
                selected: _stunt == s.id,
                onTap: () => setState(() => _stunt = s.id),
              ),
              const SizedBox(height: 8),
            ],
            const SizedBox(height: 10),
            Row(
              children: [
                TextButton.icon(
                  onPressed: _discard,
                  icon: const Icon(Icons.delete_outline_rounded),
                  label: const Text('Discard'),
                  style: TextButton.styleFrom(foregroundColor: scheme.error),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton.icon(
                      onPressed: _release,
                      icon: const Icon(Icons.rocket_launch_rounded),
                      label: const Text('Release'),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
                        textStyle: display(context, 18),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _RatingCompare extends StatelessWidget {
  final double predicted, current;
  const _RatingCompare({required this.predicted, required this.current});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final delta = predicted - current;
    final up = delta >= 0;
    final deltaColor = up ? scheme.primary : Neon.red;
    Widget col(String label, double v, {Color? color}) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: mono(context, 11, color: scheme.onSurfaceVariant)),
        Text(v.round().toString(), style: mono(context, 32, color: color, weight: FontWeight.w700)),
      ],
    );
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Expanded(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Row(
                children: [
                  col('SERVING NOW', current),
                  const SizedBox(width: 14),
                  Icon(Icons.arrow_forward_rounded, color: scheme.onSurfaceVariant),
                  const SizedBox(width: 14),
                  col('NEW MODEL', predicted, color: deltaColor),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: deltaColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              '${up ? '+' : '−'}${delta.abs().round()}',
              style: mono(context, 18, color: deltaColor, weight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

class _Warning extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String text;
  const _Warning({required this.icon, required this.color, required this.text});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.12),
      border: Border.all(color: color.withValues(alpha: 0.5)),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Row(
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(width: 10),
        Expanded(child: Text(text, style: TextStyle(color: color, fontWeight: FontWeight.w600))),
      ],
    ),
  );
}

class _ChoiceCard extends StatelessWidget {
  final bool selected;
  final Color color;
  final IconData icon;
  final String title;
  final List<String> lines;
  final VoidCallback onTap;
  const _ChoiceCard({
    required this.selected,
    required this.color,
    required this.icon,
    required this.title,
    required this.lines,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      decoration: BoxDecoration(
        color: selected ? color.withValues(alpha: 0.08) : scheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: selected ? color : Colors.transparent, width: 2),
        boxShadow: selected ? [BoxShadow(color: color.withValues(alpha: 0.25), blurRadius: 16)] : null,
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () {
            Sound.play(Sfx.click);
            onTap();
          },
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(icon, color: color, size: 20),
                    const SizedBox(width: 6),
                    Flexible(child: Text(title, style: display(context, 16, color: selected ? color : null))),
                  ],
                ),
                const SizedBox(height: 6),
                for (final l in lines)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text('• $l', style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant)),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StuntTile extends StatelessWidget {
  final LaunchStunt stunt;
  final double money;
  final bool selected;
  final VoidCallback onTap;
  const _StuntTile({required this.stunt, required this.money, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final risky = stunt.successChance < 1;
    final accent = risky ? Neon.magenta : scheme.primary;
    String pct(double m) => '${m >= 1 ? '+' : '−'}${((m - 1).abs() * 100).round()}%';
    final tags = <(String, Color)>[
      (
        stunt.costFraction > 0
            ? 'Costs ${formatMoney(money * stunt.costFraction)} (${formatPercent(stunt.costFraction)} of cash)'
            : 'Free',
        scheme.onSurfaceVariant,
      ),
      if (stunt.hypeOnSuccess != 1) ('Hype ${pct(stunt.hypeOnSuccess)}', scheme.primary),
      if (risky)
        ('${formatPercent(1 - stunt.successChance)} chance it flops (hype ${pct(stunt.hypeOnFail)})', Neon.red),
    ];
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      decoration: BoxDecoration(
        color: selected ? accent.withValues(alpha: 0.10) : scheme.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: selected ? accent : Colors.transparent, width: 2),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () {
            Sound.play(Sfx.click);
            onTap();
          },
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 10, 12, 10),
            child: Row(
              children: [
                Icon(
                  selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                  color: selected ? accent : scheme.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(stunt.name, style: display(context, 16)),
                      Text(stunt.blurb, style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant)),
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 10,
                        runSpacing: 2,
                        children: [for (final (t, c) in tags) Text(t, style: mono(context, 11, color: c))],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
