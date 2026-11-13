// Mid-run decisions (Game Dev Tycoon's development stages): a training run
// passes through three phases, and at each checkpoint the player makes one
// quick call that shifts the model's benchmark profile with small
// trade-offs. Pure Dart, deterministic. Design notes: docs/MODEL_DESIGN.md
// "Run phases".

import 'dart:math' as math;

import 'content.dart';
import 'game_state.dart';
import 'model_design.dart';

/// The three phases of a run. [checkpoint] is the fraction of the run where
/// the phase's decision is due (a fraction, so it survives pacing changes).
/// The early phase is chosen when the run starts; the other two pause the
/// run and ask, so a run asks at most twice.
enum RunPhase {
  early('Early pre-training', 'Data mix emphasis', 0),
  anneal('Annealing', 'What to finish pre-training on', 1 / 3),
  post('Post-training', 'What fine-tuning and RL optimize for', 2 / 3);

  final String label;
  final String question;
  final double checkpoint;
  const RunPhase(this.label, this.question, this.checkpoint);

  /// Phases that pause the run and ask (the early one is picked at start).
  bool get asks => checkpoint > 0;

  List<PhaseOption> get options => PhaseOption.values.where((o) => o.phase == this).toList();
}

/// Phases that pause the run, in order.
final askingPhases = RunPhase.values.where((p) => p.asks).toList();

// Online, a checkpoint waits for the player as long as it takes (no
// countdown: read, then tap). Offline it takes the default at once.

/// One choice at one phase. Multipliers are relative (1 = no change);
/// [rating] is flat Arena rating. On the bot's design score (rating +
/// 30·log2 demand − 6·log2 serving) every option sits within about ±2
/// rating of zero, so the choice is roughly neutral for progress; what it
/// buys is the benchmark profile (specializing pays off on the matching
/// benchmarks) and a nudge toward rating, demand or cheaper serving.
///
/// Options unlock like the model-design slots ([DesignChoice]): [requires]
/// research ids and a [minEra], checked with [DesignContext.isUnlocked].
/// Every base default ([baseDefaultPhaseOption]) needs nothing, so a
/// garage lab always has one. Options are saved by name: append, never rename.
enum PhaseOption implements DesignChoice {
  // --- Early pre-training: data mix emphasis ----------------------------------
  webMix(
    RunPhase.early,
    'Web',
    'Keep filtered web text the bulk of the mix: broad knowledge and natural chat.',
    'The FineWeb Datasets, Penedo 2024',
    'Early web mix',
    chat: 1.06,
    coding: 0.97,
    math: 0.97,
  ),
  codeMix(
    RunPhase.early,
    'Code',
    'Upweight source code in the mix: better coding, and it also helps reasoning.',
    'To Code, or Not To Code, Aryabumi 2024',
    'Early code mix',
    requires: ['code_data'],
    coding: 1.2,
    math: 1.05,
    chat: 0.95,
  ),
  mathMix(
    RunPhase.early,
    'Math',
    'Upweight math web pages and papers in the mix: stronger math, a little less chat.',
    'DeepSeekMath, Shao 2024',
    'Early math mix',
    requires: ['books_papers'],
    math: 1.25,
    coding: 1.03,
    chat: 0.95,
  ),

  // --- Annealing: the data the learning-rate decay runs on -------------------
  qualityAnneal(
    RunPhase.anneal,
    'Quality data',
    'Decay the learning rate on a small, quality-filtered set: a lift on every benchmark.',
    'MiniCPM (WSD schedule), Hu 2024',
    'Annealed on curated data',
    coding: 1.04,
    math: 1.04,
    chat: 1.04,
  ),
  longContextAnneal(
    RunPhase.anneal,
    'Long context',
    'Continue on long documents with a bigger RoPE base: it uses long prompts, which cost more to serve.',
    'Effective Long-Context Scaling, Xiong 2023',
    'Context extended',
    requires: ['long_context'],
    rating: -1,
    longContext: 1.3,
    demand: 1.04,
    serve: 1.03,
  ),
  reasoningAnneal(
    RunPhase.anneal,
    'Reasoning',
    'Shift the decay mix toward math, code and worked solutions: a reasoning curriculum.',
    'The Llama 3 Herd of Models, Dubey 2024',
    'Annealed on math & code',
    requires: ['reasoning'],
    rating: 1,
    math: 1.2,
    coding: 1.1,
    chat: 0.96,
    demand: 0.97,
  ),

  // --- Post-training focus ----------------------------------------------------
  helpfulPost(
    RunPhase.post,
    'Helpful',
    'Spend the preference data on helpfulness: users and arena voters like it.',
    'InstructGPT, Ouyang 2022',
    'Tuned for helpfulness',
    chat: 1.1,
  ),
  safetyPost(
    RunPhase.post,
    'Safety',
    'More refusal and red-team data: fewer harmful answers, businesses trust it, some over-refusal.',
    'XSTest (over-refusal), Röttger 2023',
    'Safety-tuned',
    requires: ['rlhf'],
    rating: -3,
    chat: 0.94,
    demand: 1.07,
  ),
  reasoningPost(
    RunPhase.post,
    'Reasoning RL',
    'RL on verifiable math and code answers: longer chains of thought, pricier to serve.',
    'DeepSeek-R1, 2025',
    'RL on verifiable answers',
    requires: ['reasoning'],
    rating: 2,
    math: 1.25,
    coding: 1.15,
    chat: 0.97,
    serve: 1.05,
  ),

  // --- Later-era options (appended: saves store names) -----------------------
  synthMix(
    RunPhase.early,
    'Synthetic',
    'Upweight model-written textbooks and exercises: dense coding and math, thinner world knowledge.',
    'Textbooks Are All You Need, Gunasekar 2023',
    'Early synthetic mix',
    requires: ['synthetic_data'],
    coding: 1.12,
    math: 1.12,
    chat: 0.95,
    demand: 0.98,
  ),
  multimodalAnneal(
    RunPhase.anneal,
    'Multimodal',
    'Decay on interleaved image-text documents: it reads charts and photos; image tokens cost more to serve.',
    'MM1, McKinnon 2024',
    'Annealed on image-text',
    minEra: Era.bigLab,
    rating: -1,
    chat: 1.05,
    math: 0.97,
    demand: 1.05,
    serve: 1.04,
  ),
  agenticPost(
    RunPhase.post,
    'Agentic RL',
    'RL in sandboxed repos and tool environments: it plans, calls tools and fixes its own code.',
    'SWE-RL, Wei 2025',
    'RL in agent environments',
    requires: ['agentic_rl'],
    coding: 1.25,
    math: 1.05,
    chat: 0.96,
    longContext: 1.1,
    demand: 1.05,
    serve: 1.06,
  ),

  // A tuned blend instead of one emphasis: proportions picked by mixture
  // laws fit on small proxy runs (DoReMi, Xie 2023; RegMix, Liu 2024).
  // Llama 3's published mix is ~50% general, 25% math and reasoning, 17%
  // code, 8% multilingual (Meta 2024). No weak benchmark and a small
  // rating bonus: the late-game default once researched. Score +2 sits at
  // the edge of the neutral envelope; research-gated (Medium lab).
  tunedMix(
    RunPhase.early,
    'Tuned mix',
    'Proportions from mixture laws fit on small proxy runs: no weak benchmark.',
    'DoReMi, Xie 2023; RegMix, Liu 2024',
    'Tuned mix',
    requires: ['mixture_ablations'],
    rating: 2,
    coding: 1.03,
    math: 1.03,
    chat: 1.03,
  );

  final RunPhase phase;
  @override
  final String label;
  @override
  final String blurb;
  final String ref;

  /// Research ids that must be owned to pick this option.
  @override
  final List<String> requires;

  /// Era that must be reached to pick this option.
  @override
  final Era minEra;

  /// Start of the release-card line, e.g. "Annealed on math & code".
  final String tag;
  final double rating;
  final double coding;
  final double math;
  final double chat;
  final double longContext;
  final double demand;
  final double serve;

  const PhaseOption(
    this.phase,
    this.label,
    this.blurb,
    this.ref,
    this.tag, {
    this.requires = const [],
    this.minEra = Era.garage,
    this.rating = 0,
    this.coding = 1,
    this.math = 1,
    this.chat = 1,
    this.longContext = 1,
    this.demand = 1,
    this.serve = 1,
  });

  @override
  String get id => name;

  /// Label for tight spots (the run-setup segments, the decisions line).
  String get shortLabel => switch (this) {
    PhaseOption.synthMix => 'Synth',
    PhaseOption.tunedMix => 'Tuned',
    _ => label,
  };

  /// The benchmark multipliers, in BenchmarkStrengths order.
  Map<String, double> get strengthMults => {'Coding': coding, 'Math': math, 'Chat': chat, 'Long context': longContext};

  /// Short effect list for the decision card, e.g. "coding ×1.2 · chat ×0.95".
  String get effectsText {
    // Benchmarks with the same multiplier share one entry ("coding, math ×1.04").
    final byMult = <double, List<String>>{};
    for (final e in strengthMults.entries) {
      if (e.value != 1) (byMult[e.value] ??= []).add(e.key.toLowerCase());
    }
    final parts = <String>[
      for (final e in byMult.entries) '${e.value.join(', ')} ×${_mult(e.key)}',
      if (rating != 0) 'rating ${rating > 0 ? '+' : '−'}${rating.abs().round()}',
      if (demand != 1) 'demand ×${_mult(demand)}',
      if (serve != 1) 'serving ×${_mult(serve)}',
    ];
    return parts.join(' · ');
  }

  /// One line for the release card, e.g. "Annealed on math & code: math ×1.2".
  String get summary {
    final bench = strengthMults.entries.where((e) => e.key != 'Long context').map((e) => e.value).toSet();
    final best = strengthMults.entries.reduce((a, b) => b.value > a.value ? b : a);
    final String what;
    if (bench.length == 1 && bench.single > 1) {
      what = 'all benchmarks ×${_mult(bench.single)}${rating > 0 ? ' · rating +${rating.round()}' : ''}';
    } else if (best.value > 1.05) {
      what = '${best.key.toLowerCase()} ×${_mult(best.value)}';
    } else {
      what = 'demand ×${_mult(demand)}';
    }
    return '$tag: $what';
  }

  /// The bot's (and a thoughtful player's) score for this option, using the
  /// same weights as ModelSpec.bestGuessFor.
  double score({double serveWeight = 6, double demandWeight = 30}) =>
      rating + demandWeight * _log2(demand) - serveWeight * _log2(serve);
}

String _mult(double v) {
  final s = v.toStringAsFixed(2);
  return s.endsWith('0') ? s.substring(0, s.length - 1) : s;
}

double _log2(double x) => math.log(x) / math.ln2;

/// The default when the player doesn't decide (idle or offline). The early
/// emphasis follows the model design (a code-heavy mix gets the code
/// emphasis, RL reasoning the math one); the checkpoints take the
/// all-rounder (quality data, helpfulness). These defaults only shape the
/// benchmark profile: no rating, demand or serving change. With [ctx], an
/// early emphasis the lab hasn't unlocked falls back to Web; the base
/// defaults (Web, Quality data, Helpful) need no research. Once [ctx] owns
/// Data mixture ablations the early default is the Tuned mix (a small
/// rating bonus), as at frontier labs that tune the blend instead of
/// picking one emphasis.
PhaseOption defaultPhaseOption(RunPhase phase, ModelSpec spec, [DesignContext? ctx]) {
  if (phase == RunPhase.early && ctx != null && ctx.isUnlocked(PhaseOption.tunedMix)) return PhaseOption.tunedMix;
  final pick = switch (phase) {
    RunPhase.early =>
      spec.dataMix == DataMix.codeHeavy
          ? PhaseOption.codeMix
          : spec.postTraining == PostTraining.reasoning
          ? PhaseOption.mathMix
          : PhaseOption.webMix,
    RunPhase.anneal => PhaseOption.qualityAnneal,
    RunPhase.post => PhaseOption.helpfulPost,
  };
  return ctx == null || ctx.isUnlocked(pick) ? pick : baseDefaultPhaseOption(phase);
}

/// The run-phase options research [id] unlocks (for "Unlocks: ..." on
/// research cards and the bot's valuation).
List<PhaseOption> phaseOptionsUnlockedBy(String id) => [
  for (final o in PhaseOption.values)
    if (o.requires.contains(id)) o,
];

/// The phase's always-available option (no research, garage era).
PhaseOption baseDefaultPhaseOption(RunPhase phase) => switch (phase) {
  RunPhase.early => PhaseOption.webMix,
  RunPhase.anneal => PhaseOption.qualityAnneal,
  RunPhase.post => PhaseOption.helpfulPost,
};

/// The option a player who wants [serveWeight]/[demandWeight] would pick
/// among those [ctx] has unlocked (all when null); near-ties go to the
/// default for [spec].
PhaseOption bestPhaseOption(
  RunPhase phase, {
  ModelSpec spec = const ModelSpec(),
  DesignContext? ctx,
  double serveWeight = 6,
  double demandWeight = 30,
}) {
  double sc(PhaseOption o) => o.score(serveWeight: serveWeight, demandWeight: demandWeight);
  var best = defaultPhaseOption(phase, spec, ctx);
  for (final o in phase.options) {
    if (ctx != null && !ctx.isUnlocked(o)) continue;
    if (sc(o) > sc(best) + 0.05) best = o;
  }
  return best;
}

/// The phase decisions of a run, keyed by phase.
typedef PhaseChoices = Map<RunPhase, PhaseOption>;

Map<String, String> phaseChoicesToJson(PhaseChoices c) => {for (final e in c.entries) e.key.name: e.value.name};

/// Tolerant: unknown or mismatched entries are dropped.
PhaseChoices phaseChoicesFromJson(Object? raw) {
  final out = <RunPhase, PhaseOption>{};
  if (raw is! Map) return out;
  final phases = RunPhase.values.asNameMap();
  final options = PhaseOption.values.asNameMap();
  raw.forEach((k, v) {
    final p = phases[k];
    final o = options[v];
    if (p != null && o != null && o.phase == p) out[p] = o;
  });
  return out;
}

extension RunPhaseSteps on TrainingRun {
  /// The asking phase whose checkpoint the run has reached without a
  /// decision, or null. While set, the run waits (no compute is added).
  RunPhase? get awaitingPhase {
    for (final p in askingPhases) {
      if (!phaseChoices.containsKey(p) && progress >= p.checkpoint - 1e-9) return p;
    }
    return null;
  }

  /// Record [option] for its phase (player, bot or default).
  void choosePhase(PhaseOption option, {bool auto = false}) {
    phaseChoices[option.phase] = option;
    if (auto) {
      autoPhases.add(option.phase);
    } else {
      autoPhases.remove(option.phase);
    }
    phaseWaitSeconds = 0;
  }

  void _autoPick(RunPhase p) => choosePhase(defaultPhaseOption(p, spec), auto: true);

  /// Advance the phase state by [dt] and return how many seconds of it the
  /// run trains. Online, a run stops exactly at an undecided checkpoint and
  /// waits for the player for as long as it takes. Offline, defaults apply
  /// at once and the run never waits.
  double stepPhases(double dt, {required bool offline}) {
    if (!phaseChoices.containsKey(RunPhase.early)) _autoPick(RunPhase.early);
    final waiting = awaitingPhase;
    if (waiting != null) {
      if (!offline) {
        phaseWaitSeconds += dt;
        return 0;
      }
      _autoPick(waiting);
    }
    final end = elapsedSeconds + dt;
    for (final p in askingPhases) {
      if (phaseChoices.containsKey(p)) continue;
      final at = p.checkpoint * durationSeconds;
      if (end < at) break;
      if (offline) {
        _autoPick(p);
      } else {
        return math.max(0, at - elapsedSeconds);
      }
    }
    return dt;
  }
}

/// [design] with the run's phase decisions applied (missing phases take
/// their defaults): strengths, flat rating, serving and demand.
DesignOutcome applyPhases(DesignOutcome design, PhaseChoices choices) {
  final picked = [for (final p in RunPhase.values) choices[p] ?? defaultPhaseOption(p, design.spec)];
  var rating = 0.0, serve = 1.0, demand = 1.0;
  var coding = 1.0, mathS = 1.0, chat = 1.0, longCtx = 1.0;
  for (final o in picked) {
    rating += o.rating;
    serve *= o.serve;
    demand *= o.demand;
    coding *= o.coding;
    mathS *= o.math;
    chat *= o.chat;
    longCtx *= o.longContext;
  }
  final s = design.strengths;
  return DesignOutcome(
    spec: design.spec,
    ratingAdd: design.ratingAdd + rating,
    serveCostMult: design.serveCostMult * serve,
    demandMult: design.demandMult * demand,
    serveCompute: design.serveCompute,
    strengths: BenchmarkStrengths(
      coding: s.coding * coding,
      math: s.math * mathS,
      chat: s.chat * chat,
      longContext: s.longContext * longCtx,
    ),
    highlights: design.highlights,
    phases: picked,
  );
}

/// Summed flat rating of [choices] (for the in-run projection).
double phaseRating(PhaseChoices choices) => choices.values.fold(0.0, (a, o) => a + o.rating);

/// strengthHeadline, but credits a phase decision when it, not the model
/// design, made the best benchmark stand out ("Annealed on math & code won
/// math").
String phaseAwareHeadline(DesignOutcome d) {
  final base = strengthHeadline(d.spec, d.strengths);
  final best = d.strengths.asMap.entries.reduce((a, b) => b.value > a.value ? b : a);
  if (best.value < 1.15 || d.phases.isEmpty) return base;
  double mult(PhaseOption o) => o.strengthMults[best.key]!;
  final fromPhases = d.phases.fold(1.0, (a, o) => a * mult(o));
  if (best.value / fromPhases >= 1.15) return base; // the design did most of it
  final top = d.phases.reduce((a, b) => mult(b) > mult(a) ? b : a);
  return '${top.tag} won ${best.key.toLowerCase()}';
}
