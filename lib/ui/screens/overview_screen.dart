// OWNER: ui-core agent. The "Lab" tab.
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../sim/balance.dart' show maxUtilization, ratingBase;
import '../../sim/content.dart';
import '../../sim/game.dart';
import '../../sim/model_design.dart';
import '../../sim/run_phases.dart';
import '../format.dart';
import '../game_assets.dart';
import '../game_controller.dart';
import '../grid/grid_hints.dart';
import '../model_design/benchmark_strip.dart';
import '../model_design/run_phases_ui.dart';
import '../model_design/run_setup.dart';
import '../moments/launch_reviews.dart';
import '../moments/release_sheet.dart';
import '../sound.dart';
import '../theme.dart';
import '../widgets/effects.dart';
import '../widgets/game_builder.dart';
import '../widgets/hud.dart';
import '../widgets/loss_curve.dart';
import '../widgets/meters.dart';
import '../widgets/panel.dart';

String _rating(double r) => r.round().toString();

class OverviewScreen extends StatefulWidget {
  final GameController controller;
  const OverviewScreen({super.key, required this.controller});

  @override
  State<OverviewScreen> createState() => _OverviewScreenState();
}

class _OverviewScreenState extends State<OverviewScreen> {
  GameController get c => widget.controller;

  @override
  Widget build(BuildContext context) {
    return GameBuilder(
      controller: c,
      builder: (context) {
        final g = c.game;
        return TabScroll(
          children: [
            _Hero(game: g),
            gap12,
            if (g.s.viralSecondsLeft > 0) ...[
              _ViralBanner(seconds: g.s.viralSecondsLeft / c.speed),
              gap12,
            ],
            // A finished model waiting to ship is the top call to action.
            if (g.s.pendingEffectiveCompute != null) ...[
              TrainingPanel(controller: c),
              gap12,
              _CapacityCard(controller: c),
            ] else ...[
              _CapacityCard(controller: c),
              gap12,
              TrainingPanel(controller: c),
            ],
            gap12,
            _ComputeCard(game: g),
            gap8,
            ClusterSummaryCard(game: g),
            gap12,
            _ModelCard(game: g),
            if (g.s.releases.any((r) => r.review != null)) ...[
              gap12,
              _ReviewHistory(game: g),
            ],
            gap12,
            _RivalCard(game: g),
          ],
        );
      },
    );
  }
}

/// The training run card: set up a run, watch it train, or ship the result.
/// Used on the Lab stats panel and in the Train modal.
class TrainingPanel extends StatefulWidget {
  final GameController controller;
  const TrainingPanel({super.key, required this.controller});

  @override
  State<TrainingPanel> createState() => _TrainingPanelState();
}

class _TrainingPanelState extends State<TrainingPanel> {
  double _fraction = 0.5;
  double? _duration;

  /// The model design being edited; null = the remembered one
  /// (Game.nextSpec), so "Start training" stays one tap.
  ModelSpec? _draft;

  /// Early-phase data emphasis; null = the default for the spec.
  PhaseOption? _early;
  bool _designOpen = false;

  /// The picked run length if this era offers it, else the era's middle one.
  double _dur(Game g) {
    final opts = g.runDurations;
    final d = _duration;
    return d != null && opts.contains(d) ? d : opts[opts.length ~/ 2];
  }

  /// Run-length button label: 30s, 1m, 5m (an old save's run may be hours).
  static String _short(double seconds) => seconds < 60
      ? '${seconds.round()}s'
      : seconds < 3600
          ? '${(seconds / 60).round()}m'
          : '${(seconds / 3600).round()}h';

  GameController get c => widget.controller;

  @override
  Widget build(BuildContext context) =>
      GameBuilder(controller: c, builder: (context) => _trainingCard(c.game));

  // --- Training ---------------------------------------------------------------

  Widget _trainingCard(Game g) {
    if (g.s.pendingEffectiveCompute != null) return _pendingCard(g);
    if (g.s.run != null) return _runCard(g);
    return _setupCard(g);
  }

  Widget _setupCard(Game g) {
    final duration = _dur(g);
    final rawCompute = g.plannedFlops(_fraction, duration);
    final ctx = g.designContextFor(rawCompute);
    final spec = (_draft ?? g.s.lastSpec).clampTo(ctx);
    final effects = evaluate(spec, ctx);
    final predicted = g.predictRatingForFlops(rawCompute, spec);
    final current = g.rating;
    final dataLimited = g.isDataLimited(rawCompute, spec);
    final delta = predicted - current;
    final canStart = g.effectiveTflops > 0;
    final picked = _early;
    final early = picked != null && g.isPhaseOptionUnlocked(picked)
        ? picked
        : defaultPhaseOption(RunPhase.early, spec, g.phaseContext);
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const PanelHeader('Training run', icon: Icons.model_training, color: AppColors.neon),
          _OptionRow(
            label: 'Compute',
            child: SegmentedButton<double>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: 0.25, label: Text('25%')),
                ButtonSegment(value: 0.5, label: Text('50%')),
                ButtonSegment(value: 0.75, label: Text('75%')),
              ],
              selected: {_fraction},
              onSelectionChanged: (v) {
                Sound.play(Sfx.click);
                setState(() => _fraction = v.first);
              },
            ),
          ),
          gap8,
          _OptionRow(
            label: 'Duration',
            child: SegmentedButton<double>(
              showSelectedIcon: false,
              segments: [
                for (final d in g.runDurations)
                  ButtonSegment(value: d, label: Text(_short(d))),
              ],
              selected: {duration},
              onSelectionChanged: (v) {
                Sound.play(Sfx.click);
                setState(() => _duration = v.first);
              },
            ),
          ),
          gap8,
          // Up to five segments: the picker gets the full width under its
          // label so every one stays readable on a 360 px phone.
          _OptionRow(
            label: 'Data emphasis',
            stacked: true,
            child: EarlyFocusPicker(
              selected: early,
              lockReason: g.phaseLockReason,
              onChanged: (o) {
                Sound.play(Sfx.click);
                setState(() => _early = o);
              },
            ),
          ),
          gap8,
          _DesignSummary(
            spec: spec,
            effects: effects,
            open: _designOpen,
            onToggle: () {
              Sound.play(Sfx.click);
              setState(() => _designOpen = !_designOpen);
            },
          ),
          if (_designOpen) ...[
            gap8,
            RunSetupPanel(
              key: const ValueKey('run-setup'),
              spec: spec,
              ctx: ctx,
              onChanged: (next) {
                Sound.play(Sfx.click);
                setState(() => _draft = next);
              },
            ),
          ],
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.bg,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('PREDICTED RATING', style: labelStyle(size: 10)),
                      const SizedBox(height: 4),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.baseline,
                          textBaseline: TextBaseline.alphabetic,
                          children: [
                            Text(
                              _rating(predicted),
                              style: numStyle(
                                size: 26,
                                weight: FontWeight.w800,
                                color: AppColors.cyan,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '${delta >= 0 ? '+' : '−'}${_rating(delta.abs())}',
                              style: numStyle(
                                size: 14,
                                color: delta > 0 ? AppColors.neon : AppColors.red,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        'current ${_rating(current)}',
                        style: numStyle(
                          size: 11.5,
                          color: AppColors.muted,
                          weight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('COMPUTE', style: labelStyle(size: 10)),
                    const SizedBox(height: 4),
                    Text(formatFlops(rawCompute), style: numStyle(size: 12.5)),
                    Text(
                      'serving −${formatPercent(_fraction)}',
                      style: numStyle(size: 11.5, color: AppColors.amber, weight: FontWeight.w500),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (dataLimited) ...[
            gap8,
            const _Callout(
              icon: Icons.dataset_outlined,
              color: AppColors.amber,
              text: 'Data-limited: more compute gives diminishing returns, buy data upgrades.',
            ),
          ],
          const SizedBox(height: 14),
          NeonButton(
            label: 'Start training',
            icon: Icons.play_arrow_rounded,
            expand: true,
            onPressed:
                canStart
                    ? () {
                      final ok = c.act(
                        (g) => g.startTraining(
                          fraction: _fraction,
                          durationSeconds: duration,
                          spec: spec,
                          early: early,
                        ),
                      );
                      Sound.play(ok ? Sfx.trainingStart : Sfx.error);
                      if (ok) setState(() => _draft = null);
                    }
                    : null,
          ),
        ],
      ),
    );
  }

  LossCurveModel? _curve;
  int? _curveSeed;

  Widget _runCard(Game g) {
    final run = g.s.run!;
    final seed =
        (run.durationSeconds * 1000 + run.fraction * 97).round() ^ g.s.releases.length * 7919;
    if (_curveSeed != seed) {
      _curveSeed = seed;
      _curve = LossCurveModel(seed);
    }
    final curve = _curve!;
    final remaining = (run.durationSeconds - run.elapsedSeconds) / c.speed;
    final projectedFlops =
        run.computeFlops +
        g.trainingFlopsPerSecond(run.fraction) * (run.durationSeconds - run.elapsedSeconds);
    final projected = g.predictRatingForFlops(projectedFlops, run.spec) + phaseRating(run.phaseChoices);
    final waiting = run.awaitingPhase;
    final accent = run.paused ? AppColors.amber : AppColors.neon;
    return Panel(
      accent: accent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PanelHeader(
            run.paused
                ? 'Training paused'
                : waiting != null
                ? 'Checkpoint: ${waiting.label}'
                : 'Training · ${formatPercent(run.fraction)} compute',
            icon: Icons.model_training,
            color: accent,
            trailing: Text(
              run.paused ? 'paused' : '${formatDuration(math.max(0, remaining))} left',
              style: numStyle(size: 12, color: accent),
            ),
          ),
          SizedBox(
            height: 120,
            child: Stack(
              children: [
                Positioned.fill(
                  child: LossCurve(model: curve, progress: run.progress, paused: run.paused),
                ),
                Positioned(
                  right: 8,
                  top: 4,
                  child: Text(
                    'loss ${curve.lossAt(run.progress).toStringAsFixed(3)}',
                    style: numStyle(size: 11, color: AppColors.muted, weight: FontWeight.w500),
                  ),
                ),
              ],
            ),
          ),
          gap8,
          Text(
            specSummary(run.spec),
            key: const ValueKey('run-spec'),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: AppColors.muted, fontSize: 12, height: 1.3),
          ),
          gap8,
          PhaseTrack(key: const ValueKey('run-phase-track'), run: run, color: accent, height: 10),
          const SizedBox(height: 6),
          Row(
            children: [
              Text(formatPercent(run.progress), style: numStyle(size: 12, color: accent)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  formatFlops(run.computeFlops),
                  style: numStyle(size: 11.5, color: AppColors.muted, weight: FontWeight.w500),
                ),
              ),
              Text('→ ', style: numStyle(size: 12, color: AppColors.muted)),
              Text(
                'rating ${_rating(projected)}',
                style: numStyle(size: 12, color: AppColors.cyan),
              ),
            ],
          ),
          gap8,
          PhaseChoicesLine(run: run),
          if (waiting != null) ...[gap8, PhaseDecisionCard(controller: c)],
          if (g.dataLimited) ...[
            gap8,
            const _Callout(
              icon: Icons.dataset_outlined,
              color: AppColors.amber,
              text: 'Data-limited run: extra compute has diminishing returns.',
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: NeonButton(
                  label: run.paused ? 'Resume' : 'Pause',
                  icon: run.paused ? Icons.play_arrow_rounded : Icons.pause_rounded,
                  color: run.paused ? AppColors.neon : AppColors.amber,
                  filled: run.paused,
                  dense: true,
                  expand: true,
                  onPressed: () {
                    Sound.play(Sfx.click);
                    c.act((g) => g.togglePauseTraining());
                  },
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: NeonButton(
                  label: 'Cancel',
                  icon: Icons.close_rounded,
                  color: AppColors.red,
                  filled: false,
                  dense: true,
                  expand: true,
                  onPressed: () => _confirmCancel(),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _confirmCancel() async {
    Sound.play(Sfx.click);
    final ok = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Cancel training?'),
            content: const Text('All compute spent on this run is lost.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Keep training'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                style: TextButton.styleFrom(foregroundColor: AppColors.red),
                child: const Text('Cancel run'),
              ),
            ],
          ),
    );
    if (ok == true) c.act((g) => g.cancelTraining());
  }

  Widget _pendingCard(Game g) {
    final newRating = g.pendingRating!;
    final delta = newRating - g.rating;
    return Panel(
      accent: AppColors.neon,
      glow: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const PanelHeader(
            'Training complete',
            icon: Icons.check_circle_outline,
            color: AppColors.neon,
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                _rating(newRating),
                style: numStyle(size: 34, weight: FontWeight.w800, color: AppColors.neon),
              ),
              const SizedBox(width: 10),
              Flexible(
                child: Text(
                  '${delta >= 0 ? '+' : '−'}${_rating(delta.abs())} vs current',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: numStyle(size: 14, color: delta >= 0 ? AppColors.cyan : AppColors.red),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            'Your new model is ready. Ship it to win users and hype.',
            style: TextStyle(color: AppColors.muted, fontSize: 13),
          ),
          if (g.s.pendingDesign case final d?) ...[
            for (final line in d.highlights.take(3))
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  line,
                  style: const TextStyle(color: AppColors.muted, fontSize: 12, height: 1.3),
                ),
              ),
            const SizedBox(height: 12),
            BenchmarkStrip(
              key: const ValueKey('pending-benchmark-strip'),
              strengths: d.strengths,
              headline: phaseAwareHeadline(d),
              phases: d.phases,
            ),
          ],
          const SizedBox(height: 14),
          Pulse(
            child: NeonButton(
              label: 'Release model',
              icon: Icons.rocket_launch_rounded,
              expand: true,
              onPressed: () {
                Sound.play(Sfx.click);
                showReleaseSheet(context, c);
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _OptionRow extends StatelessWidget {
  final String label;
  final Widget child;

  /// Label above the control instead of beside it.
  final bool stacked;
  const _OptionRow({required this.label, required this.child, this.stacked = false});

  @override
  Widget build(BuildContext context) {
    final text = Text(label, style: const TextStyle(color: AppColors.muted, fontSize: 13));
    if (stacked) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [text, const SizedBox(height: 4), child],
      );
    }
    return Row(
      children: [
        SizedBox(width: 76, child: text),
        Expanded(child: child),
      ],
    );
  }
}

class _Callout extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String text;
  const _Callout({required this.icon, required this.color, required this.text});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: color.withValues(alpha: 0.3)),
    ),
    child: Row(
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 8),
        Expanded(child: Text(text, style: TextStyle(color: color, fontSize: 12.5, height: 1.3))),
      ],
    ),
  );
}

// --- Hero ---------------------------------------------------------------------

class _Hero extends StatelessWidget {
  final Game game;
  const _Hero({required this.game});

  @override
  Widget build(BuildContext context) {
    final s = game.s;
    final gpus = game.totalGpus.round();
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: SizedBox(
        height: 190,
        child: Stack(
          fit: StackFit.expand,
          children: [
            RepaintBoundary(child: _HeroImage(era: s.era)),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: [0.35, 1],
                  colors: [Color(0x00060A12), Color(0xE6060A12)],
                ),
              ),
            ),
            DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: AppColors.border),
              ),
            ),
            Positioned(
              left: 14,
              top: 12,
              child: Tag('${s.era.label.toUpperCase()} ERA', color: eraColor(s.era), filled: true),
            ),
            Positioned(
              left: 16,
              right: 16,
              bottom: 14,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        PopOnChange(
                          trigger: gpus,
                          scale: 1.15,
                          child: Text(
                            '$gpus GPU${gpus == 1 ? '' : 's'}',
                            style: numStyle(size: 28, weight: FontWeight.w800),
                          ),
                        ),
                        Text(
                          '${formatNumber(game.effectiveTflops)} effective TFLOPS',
                          style: numStyle(
                            size: 12.5,
                            color: AppColors.neon,
                            weight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (game.training)
                    const Tag('TRAINING', icon: Icons.circle, color: AppColors.neon)
                  else if (s.pendingEffectiveCompute != null)
                    const Tag('READY TO SHIP', icon: Icons.rocket_launch, color: AppColors.cyan),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HeroImage extends StatelessWidget {
  final Era era;
  const _HeroImage({required this.era});

  @override
  Widget build(BuildContext context) => Image.asset(
    GameArt.eraBackground(era),
    fit: BoxFit.cover,
    gaplessPlayback: true,
    errorBuilder: (context, _, __) => const _HeroFallback(),
  );
}

/// Shown until the era art exists: a neon grid "server room".
class _HeroFallback extends StatelessWidget {
  const _HeroFallback();

  @override
  Widget build(BuildContext context) => CustomPaint(painter: _GridPainter());
}

class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const RadialGradient(
          center: Alignment(0.4, -0.4),
          radius: 1.2,
          colors: [Color(0xFF12324A), Color(0xFF0A1120), AppColors.bg],
        ).createShader(rect),
    );
    // Perspective floor grid.
    final line =
        Paint()
          ..color = AppColors.neon.withValues(alpha: 0.18)
          ..strokeWidth = 1;
    final horizon = size.height * 0.45;
    final cx = size.width / 2;
    for (var i = -12; i <= 12; i++) {
      canvas.drawLine(
        Offset(cx + i * 10, horizon),
        Offset(cx + i * size.width / 6, size.height),
        line,
      );
    }
    for (var i = 0; i < 9; i++) {
      final t = math.pow(i / 8, 2).toDouble();
      final y = horizon + (size.height - horizon) * t;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), line);
    }
    // Server racks silhouettes with blinking-ish LEDs.
    final rack = Paint()..color = const Color(0xFF0E1A2C);
    final edge =
        Paint()
          ..color = AppColors.cyan.withValues(alpha: 0.25)
          ..style = PaintingStyle.stroke;
    final rnd = math.Random(7);
    for (var i = 0; i < 5; i++) {
      final w = size.width * 0.11;
      final x = size.width * 0.08 + i * (w + size.width * 0.07);
      final r = Rect.fromLTWH(x, horizon - size.height * 0.3, w, size.height * 0.42);
      canvas.drawRRect(RRect.fromRectAndRadius(r, const Radius.circular(3)), rack);
      canvas.drawRRect(RRect.fromRectAndRadius(r, const Radius.circular(3)), edge);
      for (var j = 0; j < 7; j++) {
        final led = rnd.nextDouble();
        canvas.drawCircle(
          Offset(r.left + 6 + rnd.nextDouble() * (w - 12), r.top + 8 + j * r.height / 7.5),
          1.6,
          Paint()..color = (led > 0.7 ? AppColors.amber : AppColors.neon).withValues(alpha: 0.85),
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// --- Viral --------------------------------------------------------------------

class _ViralBanner extends StatelessWidget {
  final double seconds;
  const _ViralBanner({required this.seconds});

  @override
  Widget build(BuildContext context) => Blink(
    builder:
        (context, t) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            gradient: LinearGradient(
              colors: [
                AppColors.violet.withValues(alpha: 0.25 + 0.15 * t),
                AppColors.red.withValues(alpha: 0.18 + 0.12 * t),
              ],
            ),
            border: Border.all(color: AppColors.violet.withValues(alpha: 0.6)),
          ),
          child: Row(
            children: [
              const Icon(Icons.local_fire_department, color: AppColors.amber),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'You went viral! Demand ×4',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                ),
              ),
              Text(formatDuration(seconds), style: numStyle(size: 15, color: AppColors.amber)),
            ],
          ),
        ),
  );
}

// --- Capacity -----------------------------------------------------------------

class _CapacityCard extends StatelessWidget {
  final GameController controller;
  const _CapacityCard({required this.controller});

  @override
  Widget build(BuildContext context) {
    final g = controller.game;
    final s = g.s;
    final over = g.overloaded;
    final cap = g.capacity;
    final load = cap <= 0 ? (s.users > 0 ? 1.0 : 0.0) : s.users / cap;
    final color =
        over
            ? AppColors.red
            : load > 0.85
            ? AppColors.amber
            : AppColors.cyan;
    final cloudLeft = s.cloudSecondsLeft;
    final canRent = cloudLeft <= 0 && s.money >= g.cloudRentCost;

    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PanelHeader(
          over ? 'Servers overloaded' : 'Serving capacity',
          icon: over ? Icons.warning_amber_rounded : Icons.dns_outlined,
          color: color,
          trailing: Text('load ${formatPercent(load)}', style: numStyle(size: 12, color: color)),
        ),
        Row(
          children: [
            Expanded(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      formatNumber(s.users),
                      style: numStyle(
                        size: 22,
                        weight: FontWeight.w800,
                        color: over ? AppColors.red : AppColors.text,
                      ),
                    ),
                    const SizedBox(width: 6),
                    const Text('users', style: TextStyle(color: AppColors.muted, fontSize: 13)),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerRight,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    const Text('capacity ', style: TextStyle(color: AppColors.muted, fontSize: 13)),
                    Text(formatNumber(cap), style: numStyle(size: 15)),
                  ],
                ),
              ),
            ),
          ],
        ),
        gap8,
        MeterBar(value: math.min(1, load), color: color, height: 10),
        const SizedBox(height: 6),
        Text(
          over
              ? '${formatNumber(g.unservedUsers)} users hitting errors and churning. Free up compute for serving.'
              : 'Demand ${formatNumber(g.demand)} · each user needs ${formatNumber(g.currentPerUserTflops, decimals: 2)} TFLOPS',
          style: TextStyle(
            color: over ? AppColors.red : AppColors.muted,
            fontSize: 12.5,
            height: 1.3,
          ),
        ),
        if (cloudLeft > 0) ...[
          gap8,
          Row(
            children: [
              const Icon(Icons.cloud_outlined, size: 16, color: AppColors.violet),
              const SizedBox(width: 6),
              const Expanded(
                child: Text(
                  'Cloud GPUs rented: serving ×2',
                  style: TextStyle(color: AppColors.violet, fontSize: 12.5),
                ),
              ),
              Text(
                formatDuration(cloudLeft / controller.speed),
                style: numStyle(size: 12.5, color: AppColors.violet),
              ),
            ],
          ),
        ],
        if (over) ...[
          const SizedBox(height: 12),
          Row(
            children: [
              if (s.run != null && !s.run!.paused) ...[
                Expanded(
                  child: NeonButton(
                    label: 'Pause training',
                    icon: Icons.pause_rounded,
                    color: AppColors.amber,
                    dense: true,
                    expand: true,
                    onPressed: () {
                      Sound.play(Sfx.click);
                      controller.act((g) => g.togglePauseTraining());
                    },
                  ),
                ),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: NeonButton(
                  label: cloudLeft > 0 ? 'Cloud active' : 'Rent cloud GPUs',
                  sublabel:
                      cloudLeft > 0
                          ? formatDuration(cloudLeft / controller.speed)
                          : formatMoney(g.cloudRentCost),
                  icon: Icons.cloud_upload_outlined,
                  color: AppColors.violet,
                  dense: true,
                  expand: true,
                  onPressed:
                      canRent
                          ? () {
                            final ok = controller.act((g) => g.rentCloud());
                            Sound.play(ok ? Sfx.purchase : Sfx.error);
                          }
                          : null,
                ),
              ),
            ],
          ),
        ],
      ],
    );

    if (!over) return Panel(accent: load > 0.85 ? AppColors.amber : null, child: body);
    return Blink(
      builder:
          (context, t) => Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: AppColors.red.withValues(alpha: 0.12 + 0.25 * t),
                  blurRadius: 10 + 12 * t,
                ),
              ],
            ),
            child: Panel(accent: AppColors.red, glow: true, child: body),
          ),
    );
  }
}

// --- Compute split + MFU -------------------------------------------------------

class _ComputeCard extends StatelessWidget {
  final Game game;
  const _ComputeCard({required this.game});

  @override
  Widget build(BuildContext context) {
    final g = game;
    final train = g.trainingTflops;
    final cloud = g.s.cloudSecondsLeft > 0 ? g.effectiveTflops : 0.0;
    final serve = g.servingTflops - cloud;
    final total = train + serve + cloud;
    String share(double v) => total <= 0 ? '0%' : formatPercent(v / total);
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PanelHeader(
            'Compute',
            icon: Icons.memory,
            trailing: Text(
              '${formatNumber(total)} TFLOPS',
              style: numStyle(size: 12, color: AppColors.text),
            ),
          ),
          SplitBar(
            segments: [
              SplitSegment('Training', train, AppColors.neon),
              SplitSegment('Serving', serve, AppColors.cyan),
              if (cloud > 0) SplitSegment('Cloud', cloud, AppColors.violet),
            ],
          ),
          gap8,
          Wrap(
            spacing: 16,
            runSpacing: 4,
            children: [
              LegendItem(color: AppColors.neon, label: 'Training', value: share(train)),
              LegendItem(color: AppColors.cyan, label: 'Serving', value: share(serve)),
              if (cloud > 0)
                LegendItem(color: AppColors.violet, label: 'Cloud', value: share(cloud)),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Text(
                  'GPU utilization: ${formatPercent(g.utilization)}',
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                ),
              ),
              Text(
                'max ${formatPercent(maxUtilization)}',
                style: numStyle(size: 11.5, color: AppColors.muted, weight: FontWeight.w500),
              ),
            ],
          ),
          const SizedBox(height: 6),
          MeterBar(value: g.utilization, color: AppColors.neon),
          const SizedBox(height: 6),
          Text(
            'Most of a GPU\'s peak FLOPS go unused waiting on memory and communication. '
            'Software upgrades in Research raise utilization without using any power.',
            style: const TextStyle(color: AppColors.muted, fontSize: 12, height: 1.35),
          ),
        ],
      ),
    );
  }
}

// --- Current model ----------------------------------------------------------------

class _ModelCard extends StatelessWidget {
  final Game game;
  const _ModelCard({required this.game});

  @override
  Widget build(BuildContext context) {
    final m = game.s.currentModel;
    return Panel(
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              color: AppColors.cyan.withValues(alpha: 0.1),
              border: Border.all(color: AppColors.cyan.withValues(alpha: 0.4)),
            ),
            child: const Icon(Icons.psychology_outlined, color: AppColors.cyan, size: 28),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('CURRENT MODEL', style: labelStyle(size: 10)),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        m.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Tag(
                      m.open ? 'OPEN' : 'CLOSED',
                      color: m.open ? AppColors.neon : AppColors.amber,
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'rating ${_rating(game.rating)} · ARR ${formatMoney(game.arr)}',
                  style: numStyle(size: 12.5, color: AppColors.muted, weight: FontWeight.w500),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// --- Past launch reviews ---------------------------------------------------------

/// The last few releases' review averages; a row opens the full reviews.
class _ReviewHistory extends StatelessWidget {
  final Game game;
  const _ReviewHistory({required this.game});

  @override
  Widget build(BuildContext context) {
    final reviewed = game.s.releases.reversed.where((r) => r.review != null).take(6).toList();
    return Panel(
      key: const ValueKey('review-history'),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('LAUNCH REVIEWS', style: labelStyle(size: 10)),
          const SizedBox(height: 4),
          for (final m in reviewed)
            InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () {
                Sound.play(Sfx.click);
                showLaunchReviewsDialog(context, m, animate: false);
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        m.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        m.review!.verdict,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12.5, color: AppColors.muted),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      m.review!.averageText,
                      style: numStyle(size: 15, color: reviewScoreColor(m.review!.average), weight: FontWeight.w700),
                    ),
                    const Icon(Icons.chevron_right_rounded, size: 18, color: AppColors.faint),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// --- Next rival ------------------------------------------------------------------

class _RivalCard extends StatelessWidget {
  final Game game;
  const _RivalCard({required this.game});

  @override
  Widget build(BuildContext context) {
    final r = game.nextRival;
    if (r == null) {
      return const Panel(
        accent: AppColors.neon,
        child: Row(
          children: [
            Icon(Icons.emoji_events, color: AppColors.amber),
            SizedBox(width: 12),
            Expanded(child: Text('You\'ve passed every rival in history. The frontier is yours.')),
          ],
        ),
      );
    }
    final ratingGap = r.rating - game.rating;
    final userGap = r.users - game.s.users;
    final parts = <String>[
      if (ratingGap > 0) '${_rating(ratingGap)} rating',
      if (userGap > 0) '${formatNumber(userGap)} users',
    ];
    return Panel(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: GameImage(GameArt.rivalLogo(r.lab), size: 44, fallback: Icons.flag_outlined),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('NEXT: RACING HISTORY', style: labelStyle(size: 10)),
                const SizedBox(height: 2),
                Text(
                  '${r.lab} ${r.model} (${r.year})',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5, height: 1.25),
                ),
                const SizedBox(height: 2),
                Text(
                  parts.isEmpty ? 'Passing them now…' : '${parts.join(' · ')} behind',
                  style: numStyle(size: 12, color: AppColors.amber, weight: FontWeight.w500),
                ),
              ],
            ),
          ),
          SizedBox(
            width: 44,
            height: 44,
            child: Stack(
              alignment: Alignment.center,
              children: [
                CircularProgressIndicator(
                  value: math.min(
                    ((game.rating - ratingBase) / math.max(1, r.rating - ratingBase)).clamp(
                      0.0,
                      1.0,
                    ),
                    r.users <= 0 ? 1.0 : (game.s.users / r.users).clamp(0.0, 1.0),
                  ),
                  strokeWidth: 3,
                  backgroundColor: AppColors.border,
                  color: AppColors.neon,
                ),
                Text(
                  '#${game.s.rivalIndex + 1}',
                  style: numStyle(size: 11, color: AppColors.muted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// "Dense · GQA · 8k · 20 tok/param · Balanced · RLHF · INT8".
String specSummary(ModelSpec s) {
  String short(String label) => label.split(' (').first;
  return [
    short(s.architecture.label),
    switch (s.attention) {
      Attention.mha => 'MHA',
      Attention.gqa => 'GQA',
      Attention.slidingWindow => 'Sliding window',
      Attention.hybridSsm => 'Hybrid SSM',
    },
    s.context.label,
    '${s.sizing.tokensPerParam.round()} tok/param',
    s.dataMix.label,
    s.postTraining.usesRl ? '${s.postTraining.label} (${s.rlStrength.label.toLowerCase()})' : s.postTraining.label,
    s.quantization.label,
  ].join(' · ');
}

/// One tappable row: the current setup and its headline effects, opening
/// the full run-setup panel.
class _DesignSummary extends StatelessWidget {
  final ModelSpec spec;
  final DesignEffects effects;
  final bool open;
  final VoidCallback onToggle;
  const _DesignSummary({required this.spec, required this.effects, required this.open, required this.onToggle});

  @override
  Widget build(BuildContext context) {
    final bad = effects.notes.where((n) => n.tone == NoteTone.bad).length + effects.risks.length;
    String m(double v) => '×${v.toStringAsFixed(v >= 10 ? 0 : 2)}';
    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: const ValueKey('run-setup-toggle'),
        borderRadius: BorderRadius.circular(12),
        onTap: onToggle,
        child: Ink(
          padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
          decoration: BoxDecoration(
            color: open ? AppColors.violet.withValues(alpha: 0.10) : AppColors.surfaceHi,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: open ? AppColors.violet : AppColors.borderHi),
          ),
          child: Row(
            children: [
              const Icon(Icons.tune, size: 18, color: AppColors.violet),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('MODEL DESIGN', style: labelStyle(size: 10, color: AppColors.violet)),
                    const SizedBox(height: 3),
                    Text(
                      specSummary(spec),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12.5, height: 1.3),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'serving ${m(effects.serveCostMult)} · demand ${m(effects.demandMult)}'
                      '${bad > 0 ? ' · $bad warning${bad == 1 ? '' : 's'}' : ''}',
                      style: numStyle(
                        size: 11,
                        weight: FontWeight.w500,
                        color: bad > 0 ? AppColors.amber : AppColors.muted,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(open ? Icons.expand_less : Icons.expand_more, color: AppColors.muted),
            ],
          ),
        ),
      ),
    );
  }
}
