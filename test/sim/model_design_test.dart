import 'dart:convert';

import 'package:ai_lab_tycoon/sim/content.dart';
import 'package:ai_lab_tycoon/sim/model_design.dart';
import 'package:flutter_test/flutter_test.dart';

final allResearch = {...upgrades.map((u) => u.id), ...designUpgrades.map((u) => u.id)};

/// Everything researched, a big fat-tree cluster, plenty of data.
final rich = DesignContext(
  clusterGpus: 20000,
  networkGpuCap: 32768,
  dataTokens: 1e14,
  ownedResearch: allResearch,
  eraIndex: Era.globalLab.index,
);

DesignContext ctxWith({Set<String>? owned, double gpus = 20000, double cap = 32768, double planned = 0}) =>
    DesignContext(
      clusterGpus: gpus,
      networkGpuCap: cap,
      dataTokens: 1e14,
      ownedResearch: owned ?? allResearch,
      eraIndex: Era.globalLab.index,
      plannedCompute: planned,
    );

const base = ModelSpec(
  sizing: Sizing.computeOptimal,
  context: ContextLength.k4,
  dataMix: DataMix.balanced,
);

/// Quality = predicted rating change (CEM, data limit, train cost, post-training).
double quality(ModelSpec s, [DesignContext? c]) => evaluate(s, c ?? rich).ratingDelta;

void main() {
  group('failure modes lower quality', () {
    test('under-trained', () {
      final good = quality(base);
      final bad = quality(base.copyWith(sizing: Sizing.bigShort));
      expect(bad, lessThan(good - 10));
      expect(evaluate(base.copyWith(sizing: Sizing.bigShort), rich).cem, closeTo(0.64 * 1.134, 0.01));
    });

    test('tokens/param valley peaks at 20', () {
      final q = [for (final s in Sizing.values) evaluate(base.copyWith(sizing: s), rich).cem];
      final best = q.indexOf(q.reduce((a, b) => a > b ? a : b));
      expect(Sizing.values[best], Sizing.computeOptimal);
      // Over-training buys cheaper serving.
      expect(
        evaluate(base.copyWith(sizing: Sizing.overTrained), rich).serveCostMult,
        lessThan(evaluate(base, rich).serveCostMult * 0.4),
      );
    });

    test('too much synthetic data collapses', () {
      final mix = quality(base.copyWith(dataMix: DataMix.synthMix));
      final heavy = quality(base.copyWith(dataMix: DataMix.synthHeavy));
      expect(heavy, lessThan(mix - 10));
      final e = evaluate(base.copyWith(dataMix: DataMix.synthHeavy), rich);
      expect(e.demandMult, lessThan(evaluate(base, rich).demandMult));
      expect(e.notes.any((n) => n.tone == NoteTone.bad && n.ref.contains('Shumailov')), isTrue);
    });

    test('synthetic data helps when data-limited', () {
      final c = DesignContext(
        dataTokens: 1e10,
        plannedCompute: 1e23,
        ownedResearch: allResearch,
        eraIndex: Era.globalLab.index,
      );
      expect(quality(base.copyWith(dataMix: DataMix.synthMix), c), greaterThan(quality(base, c)));
    });

    test('long context without long data', () {
      final noLongData = ctxWith(owned: allResearch.difference({'long_data'}));
      for (final ctx in [ContextLength.k32, ContextLength.k128, ContextLength.m1]) {
        final spec = base.copyWith(context: ctx, attention: Attention.gqa);
        expect(quality(spec, noLongData), lessThan(quality(spec)), reason: '$ctx');
        expect(
          evaluate(spec, noLongData).demandMult,
          lessThan(evaluate(spec, rich).demandMult),
          reason: '$ctx',
        );
      }
    });

    test('longer context raises demand, training and serving cost', () {
      final specs = [for (final c in ContextLength.values) base.copyWith(context: c, attention: Attention.gqa)];
      final e = [for (final s in specs) evaluate(s, rich)];
      for (var i = 1; i < e.length; i++) {
        expect(e[i].demandMult, greaterThan(e[i - 1].demandMult));
        expect(e[i].serveCostMult, greaterThan(e[i - 1].serveCostMult));
        expect(e[i].trainCostMult, greaterThanOrEqualTo(e[i - 1].trainCostMult));
      }
      // The KV cache explodes on full attention.
      final mha = evaluate(base.copyWith(context: ContextLength.m1), rich).serveCostMult;
      final gqa = evaluate(base.copyWith(context: ContextLength.m1, attention: Attention.gqa), rich).serveCostMult;
      expect(mha, greaterThan(gqa * 3));
    });

    test('MoE on a weak network is communication-bound', () {
      final ethernet = ctxWith(cap: 256, gpus: 200);
      final dense = quality(base, ethernet);
      expect(quality(base.copyWith(architecture: Architecture.moe), ethernet), lessThan(dense));
      expect(quality(base.copyWith(architecture: Architecture.fineMoe), ethernet), lessThan(dense));
    });

    test('RL too strong (reward hacking)', () {
      final c = ctxWith(owned: allResearch.difference({'reward_model_scaling'}));
      final rl = base.copyWith(postTraining: PostTraining.rlhf);
      expect(
        quality(rl.copyWith(rlStrength: RlStrength.extreme), c),
        lessThan(quality(rl.copyWith(rlStrength: RlStrength.standard), c) - 50),
      );
      // Past x = e the bonus turns negative: worse than plain SFT.
      expect(evaluate(rl.copyWith(rlStrength: RlStrength.extreme), c).ratingAdd, lessThan(0));
    });

    test('INT4 on an over-trained model', () {
      double int4Loss(Sizing s) {
        final spec = base.copyWith(sizing: s);
        return evaluate(spec.copyWith(quantization: Quantization.int8), rich).cem /
            evaluate(spec.copyWith(quantization: Quantization.int4), rich).cem;
      }

      expect(int4Loss(Sizing.overTrained), greaterThan(int4Loss(Sizing.computeOptimal) * 1.05));
      expect(int4Loss(Sizing.edge), greaterThan(int4Loss(Sizing.overTrained)));
      expect(int4Loss(Sizing.computeOptimal), closeTo(1 / 0.97, 1e-9));
    });

    test('base model (no post-training) loses rating and demand', () {
      final none = evaluate(base.copyWith(postTraining: PostTraining.none), rich);
      expect(none.ratingAdd, -sftRating);
      expect(none.demandMult, lessThan(0.5));
    });

    test('alignment tax hits small models unless PPO-ptx', () {
      final rl = base.copyWith(postTraining: PostTraining.rlhf);
      final small = ctxWith(owned: allResearch.difference({'ppo_ptx'}), planned: 1e20);
      final fixed = ctxWith(planned: 1e20);
      expect(evaluate(rl, small).ratingAdd, lessThan(evaluate(rl, fixed).ratingAdd - 5));
    });
  });

  test('GQA cuts serving cost with a tiny quality change', () {
    final mha = evaluate(base, rich);
    final gqa = evaluate(base.copyWith(attention: Attention.gqa), rich);
    expect(gqa.serveCostMult, closeTo(mha.serveCostMult * 0.7, 1e-9));
    expect((gqa.ratingDelta - mha.ratingDelta).abs(), lessThan(0.5));
  });

  test('MoE helps only with an adequate network', () {
    double gain(Architecture a, DesignContext c) => quality(base.copyWith(architecture: a), c) - quality(base, c);
    final ethernet = ctxWith(cap: 256, gpus: 200);
    final ib = ctxWith(cap: 4096, gpus: 4000);
    final fabric = ctxWith(cap: 32768, gpus: 20000);
    final oversubscribed = ctxWith(cap: 4096, gpus: 20000);
    for (final a in [Architecture.moe, Architecture.fineMoe]) {
      expect(gain(a, ethernet), lessThan(0));
      expect(gain(a, ib), greaterThan(5));
      expect(gain(a, fabric), greaterThan(gain(a, ib)));
      expect(gain(a, oversubscribed), lessThan(gain(a, ib)));
    }
    expect(gain(Architecture.moe, fabric), closeTo(23, 0.01)); // CEM 2
    expect(gain(Architecture.fineMoe, fabric), greaterThan(gain(Architecture.moe, fabric)));
  });

  test('MoE routing collapse is a risk until router balancing', () {
    final moe = base.copyWith(architecture: Architecture.moe);
    final risky = evaluate(moe, ctxWith(owned: allResearch.difference({'router_balancing'})));
    expect(risky.risks.single.id, 'routing_collapse');
    expect(risky.risks.single.cemMultOnHit, closeTo(1.2 / 2, 1e-9));
    expect(evaluate(moe, rich).risks, isEmpty);
  });

  test('RL strength curve peaks', () {
    expect(rlCurve(1), 1);
    for (final x in [0.25, 0.5, 0.9, 1.1, 1.5, 2.0, 3.0]) {
      expect(rlCurve(x), lessThan(1));
    }
    final c = ctxWith(owned: allResearch.difference({'reward_model_scaling'}));
    for (final method in [PostTraining.rlhf, PostTraining.dpo, PostTraining.reasoning]) {
      final adds = [
        for (final k in RlStrength.values)
          evaluate(base.copyWith(postTraining: method, rlStrength: k), c).ratingAdd,
      ];
      final peak = adds.indexOf(adds.reduce((a, b) => a > b ? a : b));
      expect(peak, inInclusiveRange(1, RlStrength.values.length - 2), reason: '$method $adds');
      expect(adds.first, lessThan(adds[peak]));
      expect(adds.last, lessThan(adds[peak]));
    }
    // A bigger reward model moves the peak to stronger RL and raises it.
    final rl = base.copyWith(postTraining: PostTraining.rlhf);
    double add(RlStrength k, DesignContext ctx) => evaluate(rl.copyWith(rlStrength: k), ctx).ratingAdd;
    expect(add(RlStrength.strong, rich), greaterThan(add(RlStrength.standard, rich)));
    expect(add(RlStrength.strong, rich), greaterThan(add(RlStrength.standard, c)));
  });

  test('reasoning: math up, serving much pricier, adaptive thinking helps', () {
    final r = base.copyWith(postTraining: PostTraining.reasoning);
    final noAdaptive = evaluate(r, ctxWith(owned: allResearch.difference({'adaptive_thinking'})));
    final rlhf = evaluate(base.copyWith(postTraining: PostTraining.rlhf), rich);
    expect(noAdaptive.strengths.math, greaterThan(rlhf.strengths.math * 2.5));
    expect(noAdaptive.serveCostMult, closeTo(rlhf.serveCostMult * reasoningServeMult, 1e-9));
    expect(evaluate(r, rich).serveCostMult, lessThan(noAdaptive.serveCostMult));
    expect(strengthHeadline(r, noAdaptive.strengths), 'RL reasoning won math');
  });

  test('code-heavy mix wins coding', () {
    final spec = base.copyWith(dataMix: DataMix.codeHeavy);
    final e = evaluate(spec, rich);
    expect(e.strengths.coding, greaterThan(evaluate(base, rich).strengths.coding));
    expect(strengthHeadline(spec, e.strengths), 'Code-heavy mix won coding');
  });

  test('over-training eases the data wall; big & short needs fewer tokens', () {
    final r200 = evaluate(base.copyWith(sizing: Sizing.overTrained), rich).dataBudgetMult;
    final r2 = evaluate(base.copyWith(sizing: Sizing.bigShort), rich).dataBudgetMult;
    expect(r200, lessThan(1));
    expect(r2, greaterThan(1));
  });

  test('deterministic', () {
    final c = ctxWith(planned: 1e22, cap: 4096, gpus: 3000);
    for (final s in [base, ModelSpec.bestGuessFor(c), ModelSpec.defaultFor(c)]) {
      final a = evaluate(s, c);
      final b = evaluate(s, c);
      expect(a.ratingDelta, b.ratingDelta);
      expect(a.serveCostMult, b.serveCostMult);
      expect(a.notes.map((n) => n.toString()), b.notes.map((n) => n.toString()));
    }
    expect(ModelSpec.bestGuessFor(c), ModelSpec.bestGuessFor(c));
  });

  test('JSON round-trips', () {
    for (final s in [
      const ModelSpec(),
      base,
      ModelSpec.bestGuessFor(rich),
      const ModelSpec(
        architecture: Architecture.fineMoe,
        attention: Attention.hybridSsm,
        context: ContextLength.m1,
        sizing: Sizing.edge,
        dataMix: DataMix.synthHeavy,
        postTraining: PostTraining.dpo,
        rlStrength: RlStrength.extreme,
        quantization: Quantization.int4,
      ),
    ]) {
      final back = ModelSpec.fromJson(jsonDecode(jsonEncode(s.toJson())) as Map<String, dynamic>);
      expect(back, s);
    }
    expect(ModelSpec.fromJson({'arch': 'bogus'}), const ModelSpec());
    const st = BenchmarkStrengths(coding: 2, math: 3, chat: 0.5, longContext: 1.5);
    final back = BenchmarkStrengths.fromJson(jsonDecode(jsonEncode(st.toJson())) as Map<String, dynamic>);
    expect(back.asMap, st.asMap);
  });

  group('unlocks', () {
    test('a fresh garage only has the basics', () {
      const garage = DesignContext();
      final d = ModelSpec.defaultFor(garage);
      for (final slot in DesignSlot.values) {
        expect(garage.isUnlocked(slot.of(d)), isTrue, reason: '$slot');
      }
      expect(garage.isUnlocked(Architecture.moe), isFalse);
      expect(garage.lockReason(Architecture.moe), 'Research Mixture of Experts to unlock');
      expect(garage.lockReason(Attention.gqa), 'Research Grouped-query attention to unlock');
      expect(garage.lockReason(ContextLength.k4), 'Reach Startup to unlock');
      expect(ModelSpec.bestGuessFor(garage), isNot(equals(null)));
      expect(garage.isUnlocked(ModelSpec.bestGuessFor(garage).architecture), isTrue);
    });

    test('bestGuess only uses unlocked options and beats the default', () {
      for (final era in Era.values) {
        final owned = {
          for (final u in [...upgrades, ...designUpgrades])
            if (u.era.index <= era.index) u.id,
        };
        final c = DesignContext(
          eraIndex: era.index,
          ownedResearch: owned,
          clusterGpus: 1000,
          networkGpuCap: era.index >= 3 ? 32768 : 256,
          plannedCompute: 1e18 * (1 << (era.index * 4)),
          dataTokens: 4e9 * (1 << (era.index * 2)),
        );
        final best = ModelSpec.bestGuessFor(c);
        for (final slot in DesignSlot.values) {
          expect(c.isUnlocked(slot.of(best)), isTrue, reason: '$era $slot');
        }
        expect(
          designScore(evaluate(best, c)),
          greaterThanOrEqualTo(designScore(evaluate(ModelSpec.defaultFor(c), c))),
        );
      }
    });

    test('clampTo replaces locked choices', () {
      final s = ModelSpec.bestGuessFor(rich).clampTo(const DesignContext());
      for (final slot in DesignSlot.values) {
        expect(const DesignContext().isUnlocked(slot.of(s)), isTrue);
      }
    });

    test('every requirement is a real research id', () {
      final ids = allResearch;
      for (final slot in DesignSlot.values) {
        for (final c in slot.options) {
          for (final r in c.requires) {
            expect(ids, contains(r), reason: '${c.id} requires $r');
          }
        }
      }
      for (final u in designUpgrades) {
        for (final r in u.requires) {
          expect(ids, contains(r));
        }
        expect(
          optionsUnlockedBy(u.id).isNotEmpty || designResearchModifiers.containsKey(u.id),
          isTrue,
          reason: '${u.id} does nothing',
        );
      }
    });

    test('design upgrades are new, unique and identity', () {
      final existing = upgrades.map((u) => u.id).toSet();
      final seen = <String>{};
      for (final u in designUpgrades) {
        expect(existing.contains(u.id), isFalse, reason: u.id);
        expect(seen.add(u.id), isTrue, reason: u.id);
        expect(u.effects.trainEffMult, 1);
        expect(u.effects.serveEffMult, 1);
        expect(u.effects.ratingAdd, 0);
        expect(u.effects.dataMult, 1);
        expect(u.effects.utilizationAdd, 0);
      }
    });

    test('every research id has a track', () {
      for (final id in allResearch) {
        expect(researchTracks.containsKey(id), isTrue, reason: id);
      }
      for (final t in ResearchTrack.values) {
        expect(researchTracks.values, contains(t));
      }
    });
  });

  group('frontier recipe (docs/MODEL_DESIGN.md)', () {
    /// All research up to [era] owned, a cluster the era's network feeds.
    DesignContext eraCtx(Era era, {double planned = 0}) {
      final net = switch (era) {
        Era.globalLab || Era.bigLab => 65536.0,
        Era.mediumLab => 4096.0,
        _ => 256.0,
      };
      return DesignContext(
        clusterGpus: net,
        networkGpuCap: net,
        dataTokens: 3e13,
        ownedResearch: {
          for (final u in allUpgrades)
            if (u.era.index <= era.index) u.id,
        },
        eraIndex: era.index,
        plannedCompute: planned,
      );
    }

    test('the endgame optimum is the modern frontier recipe', () {
      for (final planned in [0.0, 1e26]) {
        final c = eraCtx(Era.globalLab, planned: planned);
        final s = ModelSpec.bestGuessFor(c);
        expect(s.architecture, Architecture.fineMoe, reason: '$s');
        expect(s.attention, Attention.hybridLinear, reason: '$s');
        expect(s.context, ContextLength.m1, reason: '$s');
        expect(s.sizing, isIn([Sizing.computeOptimal, Sizing.overTrained]), reason: '$s');
        expect(s.dataMix, DataMix.curated, reason: '$s');
        expect(s.postTraining, PostTraining.pipeline, reason: '$s');
        expect(s.quantization, Quantization.fp4, reason: '$s');
      }
      // Whatever blocks progress, the core ingredients stay.
      for (final w in [4.0, 23.0]) {
        final s = ModelSpec.bestGuessFor(eraCtx(Era.globalLab), serveWeight: w, demandWeight: w <= 4 ? 8 : 30);
        expect(s.architecture, Architecture.fineMoe, reason: '$w $s');
        expect(s.attention, Attention.hybridLinear, reason: '$w $s');
        expect(s.dataMix, DataMix.curated, reason: '$w $s');
        expect(s.postTraining, PostTraining.pipeline, reason: '$w $s');
        expect(s.quantization, Quantization.fp4, reason: '$w $s');
      }
    });

    test('earlier eras keep era-appropriate optima', () {
      final frontierOnly = <DesignChoice>[
        Attention.hybridLinear,
        DataMix.curated,
        PostTraining.pipeline,
        Quantization.fp4,
      ];
      for (final era in [Era.garage, Era.startup, Era.smallLab, Era.mediumLab, Era.bigLab]) {
        final c = eraCtx(era);
        final s = ModelSpec.bestGuessFor(c);
        for (final slot in DesignSlot.values) {
          expect(frontierOnly, isNot(contains(slot.of(s))), reason: '$era $s');
        }
        for (final o in frontierOnly) {
          expect(c.isUnlocked(o), isFalse, reason: '$era $o');
        }
      }
      // Before MoE research (2017-22 era labs): a dense model, no reasoning RL.
      final small = ModelSpec.bestGuessFor(eraCtx(Era.smallLab));
      expect(small.architecture, Architecture.dense);
      expect(small.postTraining.thinks, isFalse);
      expect(small.context.tier, lessThanOrEqualTo(1));
    });

    test('each frontier option beats the option it supersedes', () {
      final c = eraCtx(Era.globalLab, planned: 1e26);
      final best = ModelSpec.bestGuessFor(c);
      double score(ModelSpec s) => designScore(evaluate(s, c));
      for (final (newer, older) in <(ModelSpec, ModelSpec)>[
        (best, best.copyWith(attention: Attention.hybridSsm)),
        (best, best.copyWith(attention: Attention.latent)),
        (best, best.copyWith(dataMix: DataMix.balanced)),
        (best, best.copyWith(dataMix: DataMix.synthMix)),
        (best, best.copyWith(postTraining: PostTraining.reasoning)),
        (best, best.copyWith(quantization: Quantization.int4)),
      ]) {
        expect(score(newer), greaterThan(score(older)), reason: '$older');
      }
      // MLA: GQA's serving win without its quality cost, and full recall.
      final mla = evaluate(base.copyWith(attention: Attention.latent), rich);
      final gqa = evaluate(base.copyWith(attention: Attention.gqa), rich);
      expect(mla.cem, greaterThan(gqa.cem));
      expect(mla.serveCostMult, lessThan(gqa.serveCostMult));
    });

    test('frontier research is gated and appended', () {
      for (final id in ['linear_attention_hybrid', 'rephrased_data', 'fp4_qat', 'post_training_pipeline']) {
        expect(researchById(id)!.era, Era.globalLab, reason: id);
        expect(optionsUnlockedBy(id), isNotEmpty, reason: id);
      }
      expect(researchById('latent_attention')!.era, Era.bigLab);
      expect(designUpgrades.last.id, 'post_training_pipeline');
      // Saved by name: the new options are appended after the old ones.
      expect(Attention.values.last, Attention.hybridLinear);
      expect(DataMix.values.last, DataMix.curated);
      expect(PostTraining.values.last, PostTraining.pipeline);
      expect(Quantization.values.last, Quantization.fp4);
      const s = ModelSpec(
        attention: Attention.hybridLinear,
        dataMix: DataMix.curated,
        postTraining: PostTraining.pipeline,
        quantization: Quantization.fp4,
      );
      expect(ModelSpec.fromJson(jsonDecode(jsonEncode(s.toJson())) as Map<String, dynamic>), s);
    });
  });
}
