import 'dart:convert';

import 'package:ai_lab_tycoon/sim/bot.dart';
import 'package:ai_lab_tycoon/sim/content.dart';
import 'package:ai_lab_tycoon/sim/game.dart';
import 'package:ai_lab_tycoon/sim/game_state.dart';
import 'package:ai_lab_tycoon/sim/model_design.dart';
import 'package:ai_lab_tycoon/sim/run_phases.dart';
import 'package:flutter_test/flutter_test.dart';
import 'phase_helpers.dart';

/// Every research id: most tests pick specialized options, which unlock
/// with research (see the 'locks' group for a bare garage).
final Set<String> _allResearch = {for (final u in allUpgrades) u.id};

Game _training({double duration = 90, PhaseOption? early, Set<String>? owned, Era era = Era.garage}) {
  final g = Game(GameState(money: 1e6, ownedUpgrades: {...(owned ?? _allResearch)}, era: era));
  expect(g.startTraining(fraction: 0.5, durationSeconds: duration, early: early), isTrue);
  return g;
}

/// [g] advanced to its next checkpoint.
Game _toCheckpoint(Game g) {
  final run = g.s.run!;
  final next = askingPhases.firstWhere((p) => !run.phaseChoices.containsKey(p));
  g.advance(run.durationSeconds * next.checkpoint - run.elapsedSeconds + 1);
  expect(g.awaitingPhase, next);
  return g;
}

DesignOutcome _plain() => const DesignOutcome(
  spec: ModelSpec(),
  ratingAdd: 10,
  serveCostMult: 2,
  demandMult: 1.5,
  serveCompute: 1e20,
  strengths: BenchmarkStrengths(coding: 1.5, math: 1.2),
);

void main() {
  group('content', () {
    test('three phases, 3-4 options each, every option explained and sourced', () {
      expect(RunPhase.values, hasLength(3));
      expect(askingPhases, [RunPhase.anneal, RunPhase.post]); // at most 2 prompts per run
      for (final p in RunPhase.values) {
        expect(p.options.length, inInclusiveRange(3, 4), reason: p.name);
        expect(defaultPhaseOption(p, const ModelSpec()).phase, p);
        for (final o in p.options) {
          expect(o.blurb.length, inInclusiveRange(30, 110), reason: o.name);
          expect(o.ref, matches(RegExp(r'\d{4}$')), reason: o.name);
          expect(o.effectsText, isNotEmpty, reason: o.name);
          expect(o.summary, startsWith(o.tag));
        }
      }
      expect(PhaseOption.reasoningAnneal.summary, 'Annealed on math & code: math ×1.2');
    });

    test('roughly neutral: every option is within ~2 rating of zero on the bot score', () {
      for (final (sw, dw) in [(6.0, 30.0), (4.0, 8.0), (23.0, 30.0)]) {
        for (final o in PhaseOption.values) {
          expect(o.score(serveWeight: sw, demandWeight: dw), inInclusiveRange(-2.5, 2), reason: '${o.name} $sw/$dw');
        }
      }
      // Specializing pays off on its benchmark.
      expect(PhaseOption.codeMix.coding, greaterThan(PhaseOption.webMix.coding));
      expect(PhaseOption.mathMix.math, greaterThan(PhaseOption.codeMix.math));
      expect(PhaseOption.longContextAnneal.longContext, greaterThan(1.2));
      expect(PhaseOption.reasoningPost.math, greaterThan(PhaseOption.helpfulPost.math));
      expect(PhaseOption.helpfulPost.chat, greaterThan(PhaseOption.safetyPost.chat));
    });
  });

  group('checkpoints', () {
    test('trigger at 1/3 and 2/3 of the run and hold it until the player decides', () {
      const d = 90.0;
      final g = _training(duration: d);
      final run = g.s.run!;
      expect(run.phaseChoices.keys, [RunPhase.early]); // chosen at start
      final seen = <RunPhase>[];
      while (g.s.run != null) {
        final before = run.elapsedSeconds;
        g.tick(1);
        final w = g.awaitingPhase;
        if (w != null && (seen.isEmpty || seen.last != w)) {
          seen.add(w);
          // Stops exactly at the checkpoint.
          expect(run.elapsedSeconds, closeTo(d * w.checkpoint, 1e-9));
          expect(run.elapsedSeconds - before, lessThanOrEqualTo(1));
        }
        if (w != null) {
          // Waiting: no training progress.
          final e = run.elapsedSeconds;
          final f = run.computeFlops;
          g.tick(1);
          if (g.awaitingPhase == w) {
            expect(run.elapsedSeconds, e);
            expect(run.computeFlops, f);
          }
          g.choosePhase(defaultPhaseOption(w, run.spec));
        }
      }
      expect(seen, [RunPhase.anneal, RunPhase.post]); // never more than 2 prompts
      final d0 = g.s.pendingDesign!;
      expect(d0.phases, [
        defaultPhaseOption(RunPhase.early, d0.spec),
        defaultPhaseOption(RunPhase.anneal, d0.spec),
        defaultPhaseOption(RunPhase.post, d0.spec),
      ]);
      // Only the seconds spent waiting at the two checkpoints on top.
      expect(g.s.time, closeTo(d + 2, 2.5));
    });

    test('online, a checkpoint waits for the player with no timeout', () {
      final g = _training();
      g.advance(g.s.run!.durationSeconds / 3 + 1);
      expect(g.awaitingPhase, RunPhase.anneal);
      final e = g.s.run!.elapsedSeconds;
      g.advance(600);
      expect(g.awaitingPhase, RunPhase.anneal);
      expect(g.s.run!.elapsedSeconds, e);
      expect(g.s.run!.phaseChoices.containsKey(RunPhase.anneal), isFalse);
      expect(g.s.run!.autoPhases, isEmpty);
    });

    test('choosing answers only the waiting checkpoint and resumes the run', () {
      final g = _training();
      expect(g.choosePhase(PhaseOption.reasoningAnneal), isFalse); // not there yet
      g.advance(g.s.run!.durationSeconds / 3 + 1);
      expect(g.choosePhase(PhaseOption.safetyPost), isFalse); // wrong phase
      expect(g.choosePhase(PhaseOption.reasoningAnneal), isTrue);
      expect(g.s.run!.autoPhases, isEmpty);
      final e = g.s.run!.elapsedSeconds;
      g.tick(1);
      expect(g.s.run!.elapsedSeconds, greaterThan(e));
    });

    test('offline never waits: defaults apply at once and the run finishes on time', () {
      const d = 600.0;
      final g = _training(duration: d);
      final report = g.applyOffline(d + 1);
      expect(report.trainingFinished, isTrue);
      expect(g.s.pendingDesign!.phases, hasLength(3));
      // A run that was waiting at a checkpoint when you left resumes too.
      final h = _training(duration: d);
      h.advance(d / 3 + 2);
      expect(h.awaitingPhase, RunPhase.anneal);
      expect(h.applyOffline(d).trainingFinished, isTrue);
    });

    test('a paused run does not count down', () {
      final g = _training();
      g.advance(g.s.run!.durationSeconds / 3 + 1);
      g.togglePauseTraining();
      g.advance(30);
      expect(g.awaitingPhase, RunPhase.anneal);
    });
  });

  group('effects', () {
    test('applyPhases multiplies strengths, serving and demand, and adds rating', () {
      final out = applyPhases(_plain(), {
        RunPhase.early: PhaseOption.mathMix,
        RunPhase.anneal: PhaseOption.reasoningAnneal,
        RunPhase.post: PhaseOption.reasoningPost,
      });
      const a = PhaseOption.mathMix, b = PhaseOption.reasoningAnneal, c = PhaseOption.reasoningPost;
      expect(out.strengths.math, closeTo(1.2 * a.math * b.math * c.math, 1e-12));
      expect(out.strengths.coding, closeTo(1.5 * a.coding * b.coding * c.coding, 1e-12));
      expect(out.ratingAdd, closeTo(10 + a.rating + b.rating + c.rating, 1e-12));
      expect(out.serveCostMult, closeTo(2 * a.serve * b.serve * c.serve, 1e-12));
      expect(out.demandMult, closeTo(1.5 * a.demand * b.demand * c.demand, 1e-12));
      expect(out.phases, [a, b, c]);
      // Missing phases (e.g. an old in-flight run) take their defaults.
      expect(applyPhases(_plain(), {}).phases, hasLength(3));
    });

    test('the release headline credits the phase that won the benchmark', () {
      const flat = DesignOutcome(spec: ModelSpec(), ratingAdd: 0, serveCostMult: 1, demandMult: 1, serveCompute: 1);
      final annealed = applyPhases(flat, {
        RunPhase.early: PhaseOption.mathMix,
        RunPhase.anneal: PhaseOption.reasoningAnneal,
      });
      expect(phaseAwareHeadline(annealed), 'Early math mix won math');
      // A design that won it alone keeps its own headline.
      const rl = DesignOutcome(
        spec: ModelSpec(postTraining: PostTraining.reasoning),
        ratingAdd: 0,
        serveCostMult: 1,
        demandMult: 1,
        serveCompute: 1,
        strengths: BenchmarkStrengths(math: 3),
      );
      expect(phaseAwareHeadline(applyPhases(rl, {})), 'RL reasoning won math');
    });

    test('specializing a real run moves its benchmarks and reaches the release', () {
      Game run(PhaseOption anneal, PhaseOption post) {
        final g = _training(early: PhaseOption.mathMix);
        g.advance(g.s.run!.durationSeconds / 3 + 1);
        g.choosePhase(anneal);
        g.advance(g.s.run!.durationSeconds / 3 + 1);
        g.choosePhase(post);
        g.advance(g.s.run!.durationSeconds);
        return g;
      }

      final math = run(PhaseOption.reasoningAnneal, PhaseOption.reasoningPost);
      final chat = run(PhaseOption.qualityAnneal, PhaseOption.helpfulPost);
      final m = math.s.pendingDesign!, c = chat.s.pendingDesign!;
      expect(m.strengths.math, greaterThan(c.strengths.math * 1.15));
      expect(c.strengths.chat, greaterThan(m.strengths.chat * 1.1));
      expect(m.ratingAdd - c.ratingAdd, closeTo(PhaseOption.reasoningAnneal.rating + PhaseOption.reasoningPost.rating, 1e-9));
      expect(m.serveCostMult / c.serveCostMult, closeTo(PhaseOption.reasoningPost.serve, 1e-9));
      expect(math.pendingRating! - chat.pendingRating!, closeTo(m.ratingAdd - c.ratingAdd, 1e-6));
      expect(math.release(open: false), isTrue);
      expect(math.s.currentModel.design!.phases, [
        PhaseOption.mathMix,
        PhaseOption.reasoningAnneal,
        PhaseOption.reasoningPost,
      ]);
    });
  });

  group('saves', () {
    test('a run waiting at a checkpoint round-trips, and so does the release', () {
      final g = _training(early: PhaseOption.codeMix);
      g.advance(g.s.run!.durationSeconds / 3 + 4);
      final loaded = GameState.fromJson(jsonDecode(jsonEncode(g.s.toJson())) as Map<String, dynamic>);
      final run = loaded.run!;
      expect(run.phaseChoices, {RunPhase.early: PhaseOption.codeMix});
      expect(run.awaitingPhase, RunPhase.anneal);
      expect(run.phaseWaitSeconds, closeTo(g.s.run!.phaseWaitSeconds, 1e-9));

      g.advance(g.s.run!.durationSeconds + 2, onStep: decideDefaults(g));
      expect(g.release(open: true), isTrue);
      final s2 = GameState.fromJson(jsonDecode(jsonEncode(g.s.toJson())) as Map<String, dynamic>);
      expect(s2.currentModel.design!.phases, g.s.currentModel.design!.phases);
      expect(s2.currentModel.design!.phases.first, PhaseOption.codeMix);
      final auto = GameState.fromJson(jsonDecode(jsonEncode(_training().s.toJson())) as Map<String, dynamic>);
      expect(auto.run!.autoPhases, isEmpty);
    });

    test('old saves (no phase fields) still load and the run carries on', () {
      final g = _training();
      g.advance(g.s.run!.durationSeconds / 2);
      final j = jsonDecode(jsonEncode(g.s.toJson())) as Map<String, dynamic>;
      final run = j['run'] as Map<String, dynamic>;
      run
        ..remove('phases')
        ..remove('autoPhases')
        ..remove('phaseWait');
      // An old release: design without phases.
      final loaded = Game(GameState.fromJson(j));
      expect(loaded.s.run!.phaseChoices, isEmpty);
      // Past the first checkpoint without a decision: it asks now; the early
      // phase takes its default.
      loaded.tick(1);
      expect(loaded.s.run!.phaseChoices[RunPhase.early], isNotNull);
      expect(loaded.awaitingPhase, RunPhase.anneal);
      expect(DesignOutcome.fromJson({'spec': const ModelSpec().toJson()})!.phases, isEmpty);
      expect(phaseChoicesFromJson({'anneal': 'webMix', 'post': 'nope', 'x': 'helpfulPost'}), isEmpty);
    });
  });

  group('locks', () {
    const garage = DesignContext();
    final rich = DesignContext(ownedResearch: _allResearch, eraIndex: Era.globalLab.index);

    test('a garage lab has exactly the defaults; every gate is real research', () {
      for (final p in RunPhase.values) {
        expect(p.options.where(garage.isUnlocked), [baseDefaultPhaseOption(p)], reason: p.name);
        expect(defaultPhaseOption(p, const ModelSpec(), garage), baseDefaultPhaseOption(p));
        expect(baseDefaultPhaseOption(p).requires, isEmpty);
        expect(baseDefaultPhaseOption(p).minEra, Era.garage);
      }
      for (final o in PhaseOption.values) {
        expect(rich.isUnlocked(o), isTrue, reason: o.name);
        for (final id in o.requires) {
          expect(researchById(id), isNotNull, reason: '${o.name} needs $id');
        }
      }
      // Gates that follow the history of the technique.
      expect(PhaseOption.reasoningAnneal.requires, ['reasoning']);
      expect(PhaseOption.reasoningPost.requires, ['reasoning']);
      expect(PhaseOption.longContextAnneal.requires, ['long_context']);
      expect(PhaseOption.safetyPost.requires, ['rlhf']);
      expect(PhaseOption.agenticPost.requires, ['agentic_rl']);
      expect(garage.lockReason(PhaseOption.reasoningPost), 'Research Reasoning (RL on chain of thought) to unlock');
      expect(
        DesignContext(ownedResearch: _allResearch).lockReason(PhaseOption.multimodalAnneal),
        'Reach Big lab to unlock',
      );
    });

    test('the sim rejects a locked option at a checkpoint and in the run setup', () {
      final g = _toCheckpoint(_training(owned: {}, early: PhaseOption.mathMix));
      expect(g.s.run!.phaseChoices[RunPhase.early], PhaseOption.webMix); // locked emphasis: default
      for (final o in RunPhase.anneal.options) {
        expect(g.choosePhase(o), o == PhaseOption.qualityAnneal, reason: o.name);
        if (o == PhaseOption.qualityAnneal) break;
      }
      expect(g.s.run!.phaseChoices[RunPhase.anneal], PhaseOption.qualityAnneal);
      _toCheckpoint(g);
      expect(g.choosePhase(PhaseOption.reasoningPost), isFalse);
      expect(g.choosePhase(PhaseOption.safetyPost), isFalse);
      expect(g.awaitingPhase, RunPhase.post); // still waiting
      expect(g.phaseLockReason(PhaseOption.safetyPost), 'Research RLHF to unlock');
      expect(g.choosePhase(PhaseOption.helpfulPost), isTrue);
    });

    test('research bought mid-run unlocks the option at the next checkpoint', () {
      final g = _toCheckpoint(_training(owned: {'instruction_tuning'}));
      g.choosePhase(PhaseOption.qualityAnneal);
      _toCheckpoint(g);
      expect(g.choosePhase(PhaseOption.safetyPost), isFalse);
      g.s.ownedUpgrades.add('rlhf');
      expect(g.isPhaseOptionUnlocked(PhaseOption.safetyPost), isTrue);
      expect(g.choosePhase(PhaseOption.safetyPost), isTrue);
      expect(g.s.run!.phaseChoices[RunPhase.post], PhaseOption.safetyPost);
    });

    test('later-era options need their era as well as their research', () {
      final big = _toCheckpoint(_training(era: Era.bigLab));
      final early = _toCheckpoint(_training());
      expect(early.choosePhase(PhaseOption.multimodalAnneal), isFalse);
      expect(big.choosePhase(PhaseOption.multimodalAnneal), isTrue);
      // The early emphasis: a code-heavy design gets Code once it's unlocked.
      const codey = ModelSpec(dataMix: DataMix.codeHeavy);
      expect(defaultPhaseOption(RunPhase.early, codey, garage), PhaseOption.webMix);
      expect(defaultPhaseOption(RunPhase.early, codey, rich), PhaseOption.codeMix);
    });

    test('the bot only picks unlocked options', () {
      for (final p in RunPhase.values) {
        for (final (sw, dw) in [(6.0, 30.0), (4.0, 8.0), (23.0, 30.0)]) {
          final pick = bestPhaseOption(p, ctx: garage, serveWeight: sw, demandWeight: dw);
          expect(pick, baseDefaultPhaseOption(p), reason: '${p.name} $sw/$dw');
        }
      }
      // With everything unlocked it does specialize somewhere.
      expect(
        RunPhase.values.any((p) => bestPhaseOption(p, ctx: rich) != baseDefaultPhaseOption(p)),
        isTrue,
      );
      final r = runPlaythrough(maxSeconds: 30 * 60, stopWhenDone: false, specializePhases: true);
      for (final m in r.game.s.releases.where((m) => m.design != null)) {
        for (final o in m.design!.phases) {
          expect(o.requires.every(r.game.s.ownedUpgrades.contains), isTrue, reason: o.name);
        }
      }
    });
  });

  test('the bot answers every checkpoint itself', () {
    final r = runPlaythrough(maxSeconds: 20 * 60, stopWhenDone: false);
    final designed = r.game.s.releases.where((m) => m.design != null).toList();
    expect(designed, isNotEmpty);
    for (final m in designed) {
      expect(m.design!.phases, hasLength(3));
    }
  });
}
