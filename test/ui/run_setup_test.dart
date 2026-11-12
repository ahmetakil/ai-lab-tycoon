import 'package:ai_lab_tycoon/sim/content.dart';
import 'package:ai_lab_tycoon/sim/model_design.dart';
import 'package:ai_lab_tycoon/ui/model_design/benchmark_strip.dart';
import 'package:ai_lab_tycoon/ui/model_design/run_setup.dart';
import 'package:ai_lab_tycoon/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

final _all = {...upgrades.map((u) => u.id), ...designUpgrades.map((u) => u.id)};

/// Mid-game lab: medium-lab research, InfiniBand cluster.
final _mid = DesignContext(
  clusterGpus: 2000,
  networkGpuCap: 4096,
  dataTokens: 1e12,
  ownedResearch: {
    for (final u in [...upgrades, ...designUpgrades])
      if (u.era.index <= Era.mediumLab.index) u.id,
  },
  eraIndex: Era.mediumLab.index,
  plannedCompute: 1e23,
);

final _late = DesignContext(
  clusterGpus: 50000,
  networkGpuCap: 131072,
  dataTokens: 1e14,
  ownedResearch: _all,
  eraIndex: Era.globalLab.index,
  plannedCompute: 1e26,
);

Future<void> _pump(WidgetTester tester, double width, Widget child) async {
  tester.view.physicalSize = Size(width, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: buildTheme(),
      home: Scaffold(body: SingleChildScrollView(padding: const EdgeInsets.all(16), child: child)),
    ),
  );
  await tester.pump();
}

void main() {
  for (final width in [360.0, 1400.0]) {
    for (final (name, ctx, spec) in [
      ('garage', const DesignContext(), const ModelSpec()),
      ('mid', _mid, ModelSpec.bestGuessFor(_mid)),
      ('late', _late, ModelSpec.bestGuessFor(_late)),
      (
        'late-bad',
        _late,
        const ModelSpec(
          architecture: Architecture.fineMoe,
          context: ContextLength.m1,
          sizing: Sizing.edge,
          dataMix: DataMix.synthHeavy,
          postTraining: PostTraining.reasoning,
          rlStrength: RlStrength.extreme,
          quantization: Quantization.int4,
        ),
      ),
    ]) {
      testWidgets('RunSetupPanel $name renders at ${width.toInt()} px without overflow', (tester) async {
        await _pump(tester, width, RunSetupPanel(spec: spec, ctx: ctx, onChanged: (_) {}));
        expect(tester.takeException(), isNull);
        expect(find.byType(OptionChip), findsWidgets);
        expect(find.byKey(const ValueKey('preview-rating')), findsOneWidget);
        expect(find.byType(BenchmarkStrip), findsOneWidget);
      });
    }
  }

  testWidgets('locked options say what to research', (tester) async {
    await _pump(tester, 360, RunSetupPanel(spec: const ModelSpec(), ctx: const DesignContext(), onChanged: (_) {}));
    // The reason lives in the chip's "?" popup (hover on web, tap on touch).
    String tips() => tester
        .widgetList<Tooltip>(find.byType(Tooltip))
        .map((t) => t.richMessage?.toPlainText() ?? t.message ?? '')
        .join('\n');
    expect(tips(), contains('Research Mixture of Experts to unlock'));
    expect(tips(), contains('Research Grouped-query attention to unlock'));
  });

  testWidgets('tapping an option calls onChanged; locked ones do not', (tester) async {
    ModelSpec? changed;
    const start = ModelSpec();
    await _pump(tester, 360, RunSetupPanel(spec: start, ctx: _mid, onChanged: (s) => changed = s));

    final gqa = find.byKey(const ValueKey('design-attention-gqa'));
    await tester.ensureVisible(gqa);
    await tester.tap(gqa);
    expect(changed, start.copyWith(attention: Attention.gqa));

    changed = null;
    final locked = find.byKey(const ValueKey('design-architecture-fineMoe'));
    await tester.ensureVisible(locked);
    await tester.tap(locked);
    expect(changed, isNull);
  });

  testWidgets('RL strength slot only shows for RL post-training', (tester) async {
    await _pump(tester, 360, RunSetupPanel(spec: const ModelSpec(), ctx: _mid, onChanged: (_) {}));
    expect(find.byKey(const ValueKey('design-rlStrength-standard')), findsNothing);
    await _pump(
      tester,
      360,
      RunSetupPanel(spec: const ModelSpec(postTraining: PostTraining.rlhf), ctx: _mid, onChanged: (_) {}),
    );
    expect(find.byKey(const ValueKey('design-rlStrength-standard')), findsOneWidget);
  });

  testWidgets('BenchmarkStrip renders at 360 px', (tester) async {
    await _pump(
      tester,
      360,
      const BenchmarkStrip(
        strengths: BenchmarkStrengths(coding: 2.4, math: 4, chat: 0.4, longContext: 1.2),
        headline: 'RL reasoning won math',
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('RL reasoning won math'), findsOneWidget);
  });
}
