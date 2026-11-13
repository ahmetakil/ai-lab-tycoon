import 'package:ai_lab_tycoon/sim/game.dart';
import 'package:ai_lab_tycoon/sim/game_state.dart';
import 'package:ai_lab_tycoon/sim/run_phases.dart';
import 'package:ai_lab_tycoon/ui/app.dart';
import 'package:ai_lab_tycoon/ui/game_controller.dart';
import 'package:ai_lab_tycoon/ui/model_design/run_phases_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The research the specialized garage-era options need (owning every item
/// would fire research moments over the card).
const _research = {'code_data', 'books_papers', 'long_context', 'reasoning', 'instruction_tuning', 'rlhf'};

Future<void> _withApp(
  WidgetTester tester,
  Future<void> Function(GameController c) body, {
  Set<String>? owned,
}) async {
  SharedPreferences.setMockInitialValues({'intro_seen_v1': true, 'tutorial_done_v1': true});
  await tester.binding.setSurfaceSize(const Size(430, 932));
  tester.view.physicalSize = const Size(430, 932);
  tester.view.devicePixelRatio = 1;
  final c = await GameController.load();
  c.game = Game(GameState(money: 1e5, ownedUpgrades: {...(owned ?? _research)}));
  await tester.pumpWidget(AiLabTycoonApp(controller: c));
  await tester.pump(const Duration(milliseconds: 500));
  try {
    await body(c);
  } finally {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 15));
    c.dispose();
    await tester.binding.setSurfaceSize(null);
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  }
}

Future<void> _toCheckpoint(WidgetTester tester, GameController c) async {
  c.act((g) => g.startTraining(fraction: 0.5, durationSeconds: 90, early: PhaseOption.mathMix));
  c.act((g) => g.advance(31));
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  testWidgets('the checkpoint card appears with its options and no countdown', (tester) async {
    await _withApp(tester, (c) async {
      expect(find.byType(PhaseDecisionCard), findsOneWidget); // empty until a checkpoint
      expect(find.byKey(const ValueKey('phase-decision-anneal')), findsNothing);
      await _toCheckpoint(tester, c);
      expect(c.game.awaitingPhase, RunPhase.anneal);
      expect(find.byKey(const ValueKey('phase-decision-anneal')), findsOneWidget);
      for (final o in RunPhase.anneal.options) {
        expect(find.byKey(ValueKey('phase-option-${o.name}')), findsOneWidget);
      }
      expect(find.textContaining('Quality data is the safe default'), findsOneWidget);
      expect(find.byKey(const ValueKey('hud-phase-track')), findsOneWidget);
      expect(find.byKey(const ValueKey('phase-marker-anneal')), findsWidgets);
      expect(find.textContaining('checkpoint'), findsWidgets); // project bar
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('choosing an option records it and resumes the run', (tester) async {
    await _withApp(tester, (c) async {
      await _toCheckpoint(tester, c);
      await tester.tap(find.byKey(const ValueKey('phase-option-longContextAnneal')));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300)); // the card fades out
      final run = c.game.s.run!;
      expect(run.phaseChoices[RunPhase.anneal], PhaseOption.longContextAnneal);
      expect(run.autoPhases, isEmpty);
      expect(find.byKey(const ValueKey('phase-decision-anneal')), findsNothing);
      final before = run.elapsedSeconds;
      c.act((g) => g.advance(1));
      expect(run.elapsedSeconds, greaterThan(before));
      // The training panel lists the decisions so far.
      await tester.tap(find.byKey(const ValueKey('project-bar')));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byKey(const ValueKey('run-phase-track')), findsOneWidget);
      expect(find.text('Mix: Math'), findsOneWidget);
      expect(find.text('Anneal: Long context'), findsOneWidget);
      expect(find.text('Post: …'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('no decision: the card stays up and the run waits', (tester) async {
    await _withApp(tester, (c) async {
      await _toCheckpoint(tester, c);
      expect(find.byKey(const ValueKey('phase-decision-anneal')), findsOneWidget);
      final run = c.game.s.run!;
      final e = run.elapsedSeconds;
      c.act((g) => g.advance(300));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byKey(const ValueKey('phase-decision-anneal')), findsOneWidget); // still waiting
      expect(run.elapsedSeconds, e);
      expect(run.phaseChoices.containsKey(RunPhase.anneal), isFalse);
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('a garage lab sees the research-gated options locked, with the reason', (tester) async {
    await _withApp(tester, owned: {}, (c) async {
      await _toCheckpoint(tester, c);
      expect(c.game.s.run!.phaseChoices[RunPhase.early], PhaseOption.webMix); // Math is locked too
      expect(find.byKey(const ValueKey('phase-decision-anneal')), findsOneWidget);
      for (final o in RunPhase.anneal.options) {
        expect(find.byKey(ValueKey('phase-option-${o.name}')), findsOneWidget, reason: o.name);
        final locked = o != PhaseOption.qualityAnneal;
        expect(find.byKey(ValueKey('phase-lock-${o.name}')), locked ? findsOneWidget : findsNothing, reason: o.name);
      }
      expect(find.text('Research Reasoning (RL on chain of thought) to unlock'), findsOneWidget);
      expect(find.text('Research Long context (ring attention) to unlock'), findsOneWidget);
      expect(find.text('Reach Big lab to unlock'), findsOneWidget);
      // Tapping a locked option does nothing; the run keeps waiting.
      await tester.tap(find.byKey(const ValueKey('phase-option-reasoningAnneal')));
      await tester.pump(const Duration(milliseconds: 300));
      expect(c.game.awaitingPhase, RunPhase.anneal);
      expect(c.game.s.run!.phaseChoices.containsKey(RunPhase.anneal), isFalse);
      // The default still works.
      await tester.tap(find.byKey(const ValueKey('phase-option-qualityAnneal')));
      await tester.pump(const Duration(milliseconds: 300));
      expect(c.game.s.run!.phaseChoices[RunPhase.anneal], PhaseOption.qualityAnneal);
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('the run setup offers the early data focus', (tester) async {
    await _withApp(tester, (c) async {
      await tester.tap(find.byKey(const ValueKey('project-bar')));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byKey(const ValueKey('early-focus')), findsOneWidget);
      await tester.tap(find.text('Code'));
      await tester.pump(const Duration(milliseconds: 200));
      await tester.tap(find.text('Start training'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(c.game.s.run!.phaseChoices[RunPhase.early], PhaseOption.codeMix);
      expect(tester.takeException(), isNull);
    });
  });
}
