// OWNER: ui-core agent. The "Research" tab: software, data and research upgrades.
import 'package:flutter/material.dart';

import '../../sim/content.dart';
import '../../sim/game.dart';
import '../format.dart';
import '../research_impact.dart';
import '../shell/game_modal.dart';
import '../game_assets.dart';
import '../game_controller.dart';
import '../sound.dart';
import '../theme.dart';
import '../widgets/buy.dart';
import '../widgets/effects.dart';
import '../widgets/game_builder.dart';
import '../widgets/hud.dart';
import '../widgets/panel.dart';

class EffectChip {
  final String text;
  final bool isCost;
  const EffectChip(this.text, {this.isCost = false});
}

/// Human-readable effect chips for an upgrade. Costs (e.g. reasoning's
/// serving penalty) are flagged so they render in amber.
List<EffectChip> effectChips(Effects e) => [
  if (e.utilizationAdd != 0) EffectChip('+${formatPercent(e.utilizationAdd)} utilization'),
  if (e.trainEffMult != 1)
    EffectChip('×${formatNumber(e.trainEffMult)} training efficiency', isCost: e.trainEffMult < 1),
  if (e.serveEffMult != 1)
    EffectChip('×${formatNumber(e.serveEffMult)} serving efficiency', isCost: e.serveEffMult < 1),
  if (e.dataMult != 1) EffectChip('×${formatNumber(e.dataMult)} data', isCost: e.dataMult < 1),
  if (e.ratingAdd != 0)
    EffectChip(
      '${e.ratingAdd > 0 ? '+' : '−'}${formatNumber(e.ratingAdd.abs())} rating',
      isCost: e.ratingAdd < 0,
    ),
  if (e.arpuMult != 1)
    EffectChip(
      '${e.arpuMult > 1 ? '+' : '−'}${formatPercent((e.arpuMult - 1).abs())} revenue/user',
      isCost: e.arpuMult < 1,
    ),
  if (e.powerMult != 1)
    EffectChip(
      '${e.powerMult < 1 ? '−' : '+'}${formatPercent((1 - e.powerMult).abs())} power',
      isCost: e.powerMult > 1,
    ),
];

const _categoryInfo = {
  UpgradeCategory.software: (
    'Software',
    'Squeeze more out of every GPU. No extra power needed.',
    Icons.code,
    AppColors.cyan,
  ),
  UpgradeCategory.data: (
    'Data',
    'More and better tokens, so extra compute keeps paying off.',
    Icons.dataset_outlined,
    AppColors.amber,
  ),
  UpgradeCategory.research: (
    'Research',
    'Training tricks that make the model itself better.',
    Icons.science_outlined,
    AppColors.violet,
  ),
};

class ResearchScreen extends StatefulWidget {
  final GameController controller;
  const ResearchScreen({super.key, required this.controller});

  @override
  State<ResearchScreen> createState() => _ResearchScreenState();
}

/// null = "Available now" across every category.
class _ResearchScreenState extends State<ResearchScreen> {
  UpgradeCategory? _tab;

  GameController get controller => widget.controller;

  bool _availableNow(Game g, UpgradeDef u) =>
      !g.s.ownedUpgrades.contains(u.id) &&
      g.isUnlocked(u.era) &&
      u.requires.every(g.s.ownedUpgrades.contains);

  int _rank(Game g, UpgradeDef u) {
    if (g.s.ownedUpgrades.contains(u.id)) return 3;
    if (!g.isUnlocked(u.era)) return 2;
    if (!u.requires.every(g.s.ownedUpgrades.contains)) return 1;
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    return GameBuilder(
      controller: controller,
      builder: (context) {
        final g = controller.game;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _tabChip(g, null),
                    for (final cat in UpgradeCategory.values) _tabChip(g, cat),
                  ],
                ),
              ),
            ),
            Expanded(
              child: TabScroll(
                key: ValueKey('research-tab-${_tab?.name ?? 'available'}'),
                children: _tab == null ? _available(g) : _section(g, _tab!),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _tabChip(Game g, UpgradeCategory? cat) {
    final list = upgrades.where((u) => cat == null || u.category == cat);
    final available = list.where((u) => _availableNow(g, u)).length;
    final affordable = list.any((u) => g.canBuyUpgrade(u));
    final (label, icon, color) =
        cat == null
            ? ('Available now', Icons.bolt_rounded, AppColors.neon)
            : (_categoryInfo[cat]!.$1, _categoryInfo[cat]!.$3, _categoryInfo[cat]!.$4);
    final selected = _tab == cat;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: InkWell(
        key: ValueKey('research-tab-chip-${cat?.name ?? 'available'}'),
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          Sound.play(Sfx.click);
          setState(() => _tab = cat);
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: selected ? color.withValues(alpha: 0.18) : AppColors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? color : AppColors.border,
              width: selected ? 2 : 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  color: selected ? AppColors.text : AppColors.muted,
                ),
              ),
              if (available > 0) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    color: affordable ? AppColors.neon : AppColors.surfaceHi,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '$available',
                    style: numStyle(
                      size: 11,
                      weight: FontWeight.w800,
                      color: affordable ? AppColors.bg : AppColors.muted,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _available(Game g) {
    final list = upgrades.where((u) => _availableNow(g, u)).toList()
      ..sort((a, b) => a.cost.compareTo(b.cost));
    return [
      const Padding(
        padding: EdgeInsets.only(left: 4, bottom: 10),
        child: Text(
          'Everything you can research right now, cheapest first. '
          'Use the tabs to see each track, including what unlocks later.',
          style: TextStyle(color: AppColors.muted, fontSize: 12.5, height: 1.3),
        ),
      ),
      if (list.isEmpty)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 24),
          child: Text(
            'Nothing new to research in this era. Reach the next era for more.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.muted),
          ),
        ),
      for (final u in list) ...[
        UpgradeCard(controller: controller, u: u, accent: _categoryInfo[u.category]!.$4),
        const SizedBox(height: 10),
      ],
    ];
  }

  List<Widget> _section(Game g, UpgradeCategory cat) {
    final (title, subtitle, icon, color) = _categoryInfo[cat]!;
    final list =
        upgrades.where((u) => u.category == cat).toList()..sort((a, b) {
          final r = _rank(g, a).compareTo(_rank(g, b));
          return r != 0 ? r : a.cost.compareTo(b.cost);
        });
    final owned = list.where((u) => g.s.ownedUpgrades.contains(u.id)).length;
    return [
      SectionTitle(
        title,
        subtitle: subtitle,
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withValues(alpha: 0.4)),
          ),
          child: Center(child: GameImage(GameArt.upgradeCategory(cat), size: 30, fallback: icon)),
        ),
      ),
      Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 8),
        child: Text(
          '$owned / ${list.length} researched',
          style: numStyle(size: 11.5, color: AppColors.muted, weight: FontWeight.w500),
        ),
      ),
      for (final u in list) ...[
        UpgradeCard(controller: controller, u: u, accent: color),
        const SizedBox(height: 10),
      ],
    ];
  }
}

class UpgradeCard extends StatelessWidget {
  final GameController controller;
  final UpgradeDef u;
  final Color accent;
  const UpgradeCard({super.key, required this.controller, required this.u, required this.accent});

  @override
  Widget build(BuildContext context) {
    final g = controller.game;
    final owned = g.s.ownedUpgrades.contains(u.id);
    return AnimatedSize(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        child: owned ? _OwnedRow(key: const ValueKey('owned'), u: u) : _full(context, g),
      ),
    );
  }

  Widget _full(BuildContext context, Game g) {
    final eraOk = g.isUnlocked(u.era);
    final missing = u.requires.where((r) => !g.s.ownedUpgrades.contains(r)).toList();
    final affordable = g.s.money >= u.cost;
    final available = eraOk && missing.isEmpty;
    final chips = effectChips(u.effects);

    Widget footer;
    if (!eraOk) {
      footer = Row(
        children: [
          Text(formatMoney(u.cost), style: numStyle(size: 13, color: AppColors.muted)),
          const SizedBox(width: 8),
          const Icon(Icons.lock_outline, size: 15, color: AppColors.muted),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              // Names the gate: "Unlocks in Small lab: reach rating 1,000 (you're at 998)."
              g.eraLockReason(u.era),
              textAlign: TextAlign.right,
              style: TextStyle(color: eraColor(u.era), fontSize: 12, height: 1.25),
            ),
          ),
        ],
      );
    } else if (missing.isNotEmpty) {
      final names = missing.map((id) => upgrades.firstWhere((x) => x.id == id).name).join(', ');
      footer = Row(
        children: [
          const Icon(Icons.link, size: 16, color: AppColors.amber),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              'Requires: $names',
              style: const TextStyle(
                color: AppColors.amber,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Text(formatMoney(u.cost), style: numStyle(size: 13, color: AppColors.muted)),
        ],
      );
    } else {
      footer = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  formatMoney(u.cost),
                  style: numStyle(
                    size: 16,
                    weight: FontWeight.w800,
                    color: affordable ? AppColors.text : AppColors.muted,
                  ),
                ),
              ),
              BuyButton(
                label: 'Research',
                icon: Icons.science_outlined,
                enabled: affordable,
                onBuy: () {
                  final before = ImpactSnapshot.of(controller.game);
                  final ok = controller.act((g) => g.buyUpgrade(u.id));
                  Sound.play(ok ? Sfx.upgrade : Sfx.error);
                  if (!ok) return;
                  final lines = describeImpact(before, ImpactSnapshot.of(controller.game));
                  showGameModal<void>(
                    context,
                    title: 'Researched: ${u.name}',
                    icon: Icons.science_rounded,
                    color: AppColors.violet,
                    maxWidth: 480,
                    child: ImpactSummary(blurb: u.blurb, lines: lines),
                  );
                },
              ),
            ],
          ),
          if (!affordable) ...[
            const SizedBox(height: 8),
            AffordBar(money: g.s.money, cost: u.cost),
          ],
        ],
      );
    }

    return Panel(
      key: const ValueKey('full'),
      accent: available && affordable ? accent : null,
      opacity: eraOk ? 1 : 0.5,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: AppColors.bg,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.border),
                ),
                child: Center(
                  child: GameImage(
                    GameArt.upgrade(u.id),
                    size: 44,
                    fallback: _categoryInfo[u.category]!.$3,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      u.name,
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15.5),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      u.blurb,
                      style: const TextStyle(color: Color(0xFFC3CDDF), fontSize: 13.5, height: 1.4),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final c in chips)
                Tag(
                  c.text,
                  color: c.isCost ? AppColors.amber : AppColors.neon,
                  icon: c.isCost ? Icons.trending_down : Icons.trending_up,
                ),
            ],
          ),
          const SizedBox(height: 12),
          footer,
        ],
      ),
    );
  }
}

/// Collapsed state for researched upgrades. Tap to re-read the blurb.
class _OwnedRow extends StatefulWidget {
  final UpgradeDef u;
  const _OwnedRow({super.key, required this.u});

  @override
  State<_OwnedRow> createState() => _OwnedRowState();
}

class _OwnedRowState extends State<_OwnedRow> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final u = widget.u;
    final chips = effectChips(u.effects);
    return GestureDetector(
      onTap: () => setState(() => _open = !_open),
      child: Panel(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                PopOnChange(
                  trigger: u.id,
                  child: const Icon(Icons.check_circle, color: AppColors.neon, size: 20),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    u.name,
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                  ),
                ),
                Flexible(
                  child: Text(
                    chips.map((c) => c.text).join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.right,
                    style: const TextStyle(color: AppColors.muted, fontSize: 11.5),
                  ),
                ),
              ],
            ),
            if (_open) ...[
              const SizedBox(height: 6),
              Text(
                u.blurb,
                style: const TextStyle(color: AppColors.muted, fontSize: 12.5, height: 1.35),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
