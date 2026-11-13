import 'dart:io';

import 'package:ai_lab_tycoon/sim/game.dart';
import 'package:ai_lab_tycoon/sim/game_state.dart';
import 'package:ai_lab_tycoon/sim/run_phases.dart';
import 'package:ai_lab_tycoon/ui/app.dart';
import 'package:ai_lab_tycoon/ui/game_controller.dart';
import 'package:ai_lab_tycoon/sim/model_design.dart';
import 'package:ai_lab_tycoon/ui/model_design/benchmark_strip.dart';
import 'package:ai_lab_tycoon/ui/model_design/run_phases_ui.dart';
import 'package:ai_lab_tycoon/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The research the specialized garage-era options need (owning every item
/// would fire research moments over the card).
const _research = {'code_data', 'books_papers', 'long_context', 'reasoning', 'instruction_tuning', 'rlhf'};

Future<void> _withApp(
  WidgetTester tester,
  Future<void> Function(GameController c) body, {
  Set<String>? owned,
  Size size = const Size(430, 932),
}) async {
  SharedPreferences.setMockInitialValues({'intro_seen_v1': true, 'tutorial_done_v1': true});
  await tester.binding.setSurfaceSize(size);
  tester.view.physicalSize = size;
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

/// The app's real fonts (widget tests default to Ahem, whose square glyphs
/// overstate text width), so the fit check below measures what ships.
Future<void> _loadAppFonts() async {
  Future<void> font(String family, List<String> paths) async {
    final loader = FontLoader(family);
    for (final p in paths) {
      loader.addFont(Future.value(ByteData.sublistView(File(p).readAsBytesSync())));
    }
    await loader.load();
  }

  await font(headingFont, [
    'assets/fonts/SpaceGrotesk/SpaceGrotesk-Regular.ttf',
    'assets/fonts/SpaceGrotesk/SpaceGrotesk-Medium.ttf',
    'assets/fonts/SpaceGrotesk/SpaceGrotesk-Bold.ttf',
  ]);
  await font(monoFont, [
    'assets/fonts/JetBrainsMono/JetBrainsMono-Regular.ttf',
    'assets/fonts/JetBrainsMono/JetBrainsMono-Bold.ttf',
  ]);
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

  testWidgets('the Tuned mix segment is locked until Data mixture ablations, then the default (360 px)', (
    tester,
  ) async {
    Future<void> openSetup() async {
      await tester.tap(find.byKey(const ValueKey('project-bar')));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));
    }

    await _loadAppFonts();
    // Every early option researched but the ablations: Tuned shows, locked.
    final most = {..._research, 'synthetic_data', 'data_mixture'};
    await _withApp(tester, owned: most, size: const Size(360, 740), (c) async {
      await openSetup();
      expect(find.text('Data emphasis'), findsOneWidget);
      final picker = find.byKey(const ValueKey('early-focus'));
      expect(picker, findsOneWidget);
      expect(find.descendant(of: picker, matching: find.text('Tuned')), findsOneWidget);
      expect(find.byKey(const ValueKey('early-lock-tunedMix')), findsOneWidget);
      expect(find.byKey(const ValueKey('early-lock-codeMix')), findsNothing);
      final tip = find.byWidgetPredicate(
        (w) => w is Tooltip && (w.message ?? '').contains('Research Data mixture ablations to unlock'),
      );
      expect(tip, findsOneWidget);
      // Fits the phone: every segment inside the screen, labels readable.
      for (final o in RunPhase.early.options) {
        final label = find.descendant(of: picker, matching: find.text(o.shortLabel));
        expect(label, findsOneWidget, reason: o.name);
        final box = find.ancestor(of: label, matching: find.byType(FittedBox)).first;
        expect(tester.getRect(box).right, lessThanOrEqualTo(360), reason: o.name);
        // FittedBox scales its child down to fit: keep it at 75%+ of full size.
        final fitted = tester.renderObject<RenderFittedBox>(box);
        final scale = fitted.size.width / fitted.child!.size.width;
        expect(scale, greaterThanOrEqualTo(0.75), reason: '${o.name} scaled down too far');
      }
      // Tapping the locked segment does nothing.
      await tester.tap(find.byKey(const ValueKey('early-lock-tunedMix')), warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 200));
      await tester.tap(find.text('Start training'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(c.game.s.run!.phaseChoices[RunPhase.early], PhaseOption.webMix);
      expect(tester.takeException(), isNull);
    });

    // Researched: unlocked and picked by default.
    await _withApp(tester, owned: {...most, 'mixture_ablations'}, size: const Size(360, 740), (c) async {
      await openSetup();
      expect(find.byKey(const ValueKey('early-lock-tunedMix')), findsNothing);
      expect(find.byKey(const ValueKey('early-option-tunedMix')), findsOneWidget);
      await tester.tap(find.text('Start training'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(c.game.s.run!.phaseChoices[RunPhase.early], PhaseOption.tunedMix);
      expect(find.text('Mix: Tuned'), findsOneWidget); // the decisions line uses the short label
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('the release card names the Tuned mix in full at phone width', (tester) async {
    await _loadAppFonts();
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(),
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 296, // a 360 px phone minus the card's padding
              child: BenchmarkStrip(
                strengths: const BenchmarkStrengths(coding: 1.03, math: 1.03, chat: 1.03),
                phases: const [PhaseOption.tunedMix, PhaseOption.qualityAnneal, PhaseOption.helpfulPost],
              ),
            ),
          ),
        ),
      ),
    );
    final line = find.text('Tuned mix: all benchmarks ×1.03 · rating +2');
    expect(line, findsOneWidget);
    expect(tester.renderObject<RenderParagraph>(line).didExceedMaxLines, isFalse); // not cut off
    expect(tester.takeException(), isNull);
  });
}
