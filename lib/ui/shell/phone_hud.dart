// Phone HUD (narrow screens): three small stat plates (money, users,
// rating), one "infra" plate with tiny power / network / cooling gauges that
// only light up when something needs attention, and one slim card that
// merges the training run with the next-era goal. Keeps the map in charge.
part of 'hud_overlay.dart';

const _phonePlateH = 44.0;
const _phoneCardH = 58.0;

/// Phone layout: below this width the HUD collapses to [PhoneHud].
bool isPhoneHud(double width) => width < 600;

class PhoneHud extends StatelessWidget {
  final GameController controller;
  final VoidCallback onPower;
  final VoidCallback onNetwork;
  final VoidCallback onCooling;
  final VoidCallback onProject;
  final VoidCallback onGoal;
  final VoidCallback onRivals;
  const PhoneHud({
    super.key,
    required this.controller,
    required this.onPower,
    required this.onNetwork,
    required this.onCooling,
    required this.onProject,
    required this.onGoal,
    required this.onRivals,
  });

  /// Height below the safe area (plates + card + gaps).
  static const height = 6 + _phonePlateH + 6 + _phoneCardH;

  @override
  Widget build(BuildContext context) {
    final g = controller.game;
    final over = g.overloaded;
    final next = g.nextRival;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: _phonePlateH,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  flex: 12,
                  child: _PhonePlate(
                    key: const ValueKey('hud-money'),
                    icon: Icons.attach_money_rounded,
                    color: AppColors.neon,
                    value: AnimatedNumber(
                      value: g.s.money,
                      format: formatMoney,
                      style: _phoneBig(AppColors.neon),
                    ),
                    sub: '+${formatMoney(g.revenuePerSecond)}/s',
                  ),
                ),
                const SizedBox(width: 5),
                Expanded(
                  flex: 10,
                  child: _PhonePlate(
                    icon: over ? Icons.warning_amber_rounded : Icons.people_alt_rounded,
                    color: over ? AppColors.red : AppColors.cyan,
                    lit: over,
                    value: Text(
                      formatNumber(g.s.users),
                      style: _phoneBig(over ? AppColors.red : AppColors.text),
                    ),
                    sub: over ? 'OVERLOADED' : 'cap ${formatNumber(g.capacity)}',
                    subColor: over ? AppColors.red : AppColors.cyan,
                  ),
                ),
                const SizedBox(width: 5),
                Expanded(
                  flex: 10,
                  child: Tooltip(
                    message:
                        next == null
                            ? 'Your model rating: ${formatRating(g.rating)}. You top the leaderboard.'
                            : 'Your model rating: ${formatRating(g.rating)}. Next rival to beat: '
                                '${next.lab} ${next.model} at ${formatRating(next.rating)}.',
                    child: GestureDetector(
                      key: const ValueKey('rating-chip'),
                      onTap: () {
                        Sound.play(Sfx.click);
                        onRivals();
                      },
                      child: _PhonePlate(
                        icon: Icons.emoji_events_rounded,
                        color: AppColors.amber,
                        value: Text(formatRating(g.rating), style: _phoneBig(AppColors.amber)),
                        sub: next == null ? 'top lab' : 'beat ${next.model}',
                        subColor: AppColors.muted,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 5),
                _InfraPlate(
                  controller: controller,
                  onPower: onPower,
                  onNetwork: onNetwork,
                  onCooling: onCooling,
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          _PhoneProjectCard(controller: controller, onTap: onProject, onGoal: onGoal),
        ],
      ),
    );
  }
}

TextStyle _phoneBig(Color c) => numStyle(
  size: 17,
  color: c,
  weight: FontWeight.w800,
).copyWith(height: 1.05, shadows: const [Shadow(color: Color(0xFF000000), offset: Offset(0, 2))]);

class _PhonePlate extends StatelessWidget {
  final IconData icon;
  final Color color;
  final Widget value;
  final String sub;
  final Color? subColor;
  final bool lit;
  const _PhonePlate({
    super.key,
    required this.icon,
    required this.color,
    required this.value,
    required this.sub,
    this.subColor,
    this.lit = false,
  });

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(5, 4, 6, 4),
    decoration: plateDecoration(color, radius: 10, lit: lit),
    child: Row(
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 3),
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: value,
                ),
              ),
              Text(
                sub,
                maxLines: 1,
                overflow: TextOverflow.fade,
                softWrap: false,
                style: numStyle(size: 9, color: subColor ?? color, weight: FontWeight.w600),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

/// Power, network (and central cooling, Medium lab on) as tiny gauges in one
/// plate. Calm when fine; amber/red, a short readout and an "▲" badge when
/// something is near its cap or an upgrade is worth it. Each opens its panel.
class _InfraPlate extends StatelessWidget {
  final GameController controller;
  final VoidCallback onPower;
  final VoidCallback onNetwork;
  final VoidCallback onCooling;
  const _InfraPlate({
    required this.controller,
    required this.onPower,
    required this.onNetwork,
    required this.onCooling,
  });

  @override
  Widget build(BuildContext context) {
    final g = controller.game;

    // Power.
    final pFrac = g.powerCapKw <= 0 ? 0.0 : g.powerUsedKw / g.powerCapKw;
    final pColor =
        pFrac >= 0.97
            ? AppColors.red
            : pFrac >= 0.8
            ? AppColors.amber
            : const Color(0xFFFFE066);
    final pNext = g.nextPowerTier;
    final pUp = pNext != null && g.isUnlocked(pNext.era) && g.s.money >= pNext.cost;
    final pNudge = powerNudge(g);

    // Network.
    final cl = g.trainingCluster;
    final gpus = cl?.gpus ?? 0;
    final nFrac = g.networkCap <= 0 ? 0.0 : gpus / g.networkCap;
    final nColor = networkMeterColor(g);
    final nOver = cl != null && cl.overCap;
    final nUp = g.nextNetworkTier != null && g.networkBlockReason() == null;

    final segments = <Widget>[
      _InfraGauge(
        key: const ValueKey('power-chip'),
        tooltip:
            'Power: ${formatPower(g.powerUsedKw)} of ${formatPower(g.powerCapKw)}. '
            '${pNext == null ? 'Top tier.' : 'Tap to see or buy ${pNext.name} (${formatMoney(pNext.cost)}).'}',
        icon: Icons.bolt_rounded,
        color: pColor,
        frac: pFrac,
        alert: pFrac >= 0.8 ? formatPercent(pFrac) : null,
        badge: pUp && (pNudge || pFrac >= 0.8),
        nudge: pNudge,
        onTap: onPower,
      ),
      _InfraGauge(
        key: const ValueKey('network-chip'),
        tooltip:
            'Network: ${networkMeterText(g)} on ${g.network.name}'
            '${nOver ? ', training at ${formatPercent(cl.scalingEfficiency)} scaling' : ''}. Tap for Network.',
        icon: Icons.cable_rounded,
        color: nColor,
        frac: nFrac,
        alert: nOver ? '${formatNumber(gpus)}/${formatNumber(g.networkCap)}' : null,
        badge: nUp && (nOver || nFrac >= 0.8),
        nudge: nOver && nUp,
        onTap: onNetwork,
      ),
    ];
    if (g.coolingTiersVisible) {
      final hot = throttlingTiles(g);
      final cUp = g.nextCoolingTier != null && g.coolingBlockReason() == null;
      segments.add(
        _InfraGauge(
          key: const ValueKey('cooling-chip'),
          tooltip: 'Central cooling: ${g.cooling.name}${hot > 0 ? ', $hot GPUs hot' : ''}. Tap for Cooling.',
          icon: Icons.ac_unit_rounded,
          color: hot > 0 ? AppColors.red : AppColors.cyan,
          frac: null,
          alert: hot > 0 ? '$hot hot' : null,
          badge: cUp && hot > 0,
          nudge: hot > 0 && cUp,
          onTap: onCooling,
        ),
      );
    }
    final lit = pFrac >= 0.97 || nOver;
    return Container(
      decoration: plateDecoration(lit ? AppColors.red : AppColors.border, radius: 10, lit: lit),
      padding: const EdgeInsets.symmetric(horizontal: 1),
      child: Row(mainAxisSize: MainAxisSize.min, children: segments),
    );
  }
}

class _InfraGauge extends StatelessWidget {
  final String tooltip;
  final IconData icon;
  final Color color;
  final double? frac;
  final String? alert;
  final bool badge;
  final bool nudge;
  final VoidCallback onTap;
  const _InfraGauge({
    super.key,
    required this.tooltip,
    required this.icon,
    required this.color,
    required this.frac,
    required this.alert,
    required this.badge,
    required this.nudge,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        Sound.play(Sfx.click);
        onTap();
      },
      child: _TapPlate(
        nudge: nudge,
        badge: badge,
        child: Container(
          constraints: const BoxConstraints(minWidth: 30),
          padding: const EdgeInsets.symmetric(horizontal: 3),
          alignment: Alignment.center,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: color),
              if (alert != null)
                Text(
                  alert!,
                  maxLines: 1,
                  style: numStyle(size: 8.5, color: color, weight: FontWeight.w800),
                ),
              if (frac != null)
                SizedBox(width: 22, child: _MiniBar(frac: frac!, color: color)),
            ],
          ),
        ),
      ),
    ),
  );
}

/// The project bar and the goal strip in one slim card: the run (or what to
/// do) on top, the next-era goal as a thin line underneath.
class _PhoneProjectCard extends StatelessWidget {
  final GameController controller;
  final VoidCallback onTap;
  final VoidCallback onGoal;
  const _PhoneProjectCard({required this.controller, required this.onTap, required this.onGoal});

  @override
  Widget build(BuildContext context) {
    final g = controller.game;
    final s = g.s;
    final run = s.run;
    final pending = s.pendingEffectiveCompute != null;
    final String title;
    final String sub;
    final double? progress;
    final Color color;
    final IconData icon;
    if (pending) {
      title = 'Release ready: ${defaultModelName(g)}';
      sub = 'rating ${formatRating(g.pendingRating!)}';
      progress = 1;
      color = AppColors.neon;
      icon = Icons.rocket_launch_rounded;
    } else if (run != null) {
      final left = math.max(0.0, (run.durationSeconds - run.elapsedSeconds) / controller.speed);
      title = 'Training ${defaultModelName(g)}';
      sub =
          run.paused
              ? 'paused'
              : '${formatPercent(run.progress)} · ${formatDuration(left)}';
      progress = run.progress;
      color = run.paused ? AppColors.amber : AppColors.cyan;
      icon = Icons.model_training_rounded;
    } else {
      title = 'No training run';
      sub = 'tap to train';
      progress = null;
      color = AppColors.amber;
      icon = Icons.play_arrow_rounded;
    }
    final goal = GoalInfo.of(g);
    final goalColor =
        goal == null ? AppColors.muted : (goal.era == null ? AppColors.amber : eraColor(goal.era!));

    final top = GestureDetector(
      key: const ValueKey('project-bar'),
      behavior: HitTestBehavior.opaque,
      onTap: () {
        Sound.play(Sfx.click);
        onTap();
      },
      child: Padding(
        padding: const EdgeInsets.fromLTRB(5, 5, 10, 3),
        child: Row(
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color.withValues(alpha: 0.2),
                border: Border.all(color: color, width: 1.6),
              ),
              child: Icon(icon, color: color, size: 16),
            ),
            const SizedBox(width: 7),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 12.5,
                            height: 1.1,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        sub,
                        maxLines: 1,
                        style: numStyle(size: 10, color: color, weight: FontWeight.w700),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  _MiniBar(frac: progress ?? 0, color: color),
                ],
              ),
            ),
          ],
        ),
      ),
    );

    final card = Container(
      height: _phoneCardH,
      decoration: plateDecoration(color, radius: 14, lit: pending),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: top),
          if (goal != null)
            GestureDetector(
              key: const ValueKey('goal-strip'),
              behavior: HitTestBehavior.opaque,
              onTap: () {
                Sound.play(Sfx.click);
                onGoal();
              },
              child: Container(
                height: 18,
                padding: const EdgeInsets.fromLTRB(10, 0, 10, 2),
                decoration: BoxDecoration(
                  border: Border(top: BorderSide(color: goalColor.withValues(alpha: 0.25))),
                ),
                child: Row(
                  children: [
                    Icon(Icons.flag_rounded, size: 10, color: goalColor),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: goal.title,
                              style: TextStyle(color: goalColor, fontWeight: FontWeight.w700),
                            ),
                            TextSpan(
                              text: ' · ${goal.progress}',
                              style: numStyle(size: 9.5, color: AppColors.muted),
                            ),
                          ],
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 9.5, height: 1.1),
                      ),
                    ),
                    const SizedBox(width: 6),
                    SizedBox(width: 44, child: _MiniBar(frac: goal.value, color: goalColor)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
    if (pending) return Pulse(scale: 1.02, child: card);
    return Nudge(active: run == null, child: card);
  }
}
