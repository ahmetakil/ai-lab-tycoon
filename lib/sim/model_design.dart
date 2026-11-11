// Model design: the choices a player makes when starting a training run
// (architecture, attention, context, model size vs training length, data mix,
// post-training, serving quantization) and what they do to the model.
//
// Pure Dart, deterministic, no Flutter. Rules and sources:
// docs/MODEL_DESIGN.md and docs/research/model_choices.md.
//
// The shared unit is the compute-equivalent multiplier (CEM): a choice worth
// "the same loss with 2× less compute" has CEM 2, which is +23 rating
// (ratingPerDoubling × log2(CEM)).
import 'dart:math' as math;

import 'balance.dart';
import 'content.dart';

// ---------------------------------------------------------------------------
// Choices
// ---------------------------------------------------------------------------

/// What every option of every slot exposes to the UI.
abstract interface class DesignChoice {
  /// Stable id (the enum name), used in saves and widget keys.
  String get id;
  String get label;

  /// One-line, technically accurate explanation.
  String get blurb;

  /// Research ids (from [upgrades] or [designUpgrades]) that must be owned.
  List<String> get requires;

  /// Era that must be reached.
  Era get minEra;
}

enum Architecture implements DesignChoice {
  dense(
    'Dense',
    'Every parameter works on every token. Simple, stable, network-friendly.',
    [],
  ),
  moe(
    'MoE (8–16 experts)',
    'A router sends each token to 1–2 of 8–16 expert MLPs: ~2× quality per '
        'FLOP, but expert traffic needs a fast network.',
    ['moe'],
  ),
  fineMoe(
    'Fine-grained MoE',
    'Hundreds of small experts plus shared ones (DeepSeekMoE): ~3× quality '
        'per FLOP, all-to-all traffic needs a fat-tree or NVLink fabric.',
    ['fine_grained_moe'],
  );

  const Architecture(this.label, this.blurb, this.requires);
  @override
  final String label;
  @override
  final String blurb;
  @override
  final List<String> requires;
  @override
  Era get minEra => Era.garage;
  @override
  String get id => name;
}

enum Attention implements DesignChoice {
  mha(
    'Full attention (MHA)',
    'Every head keeps its own keys and values: the baseline, with the '
        'biggest KV cache.',
    [],
  ),
  gqa(
    'Grouped-query (GQA)',
    'Query heads share 8 K/V heads: ~8× smaller KV cache and much faster '
        'decoding for a ~0.1-point quality cost.',
    ['gqa'],
  ),
  slidingWindow(
    'Sliding window',
    'GQA plus local attention over the last 4k tokens: the KV cache stops '
        'growing, but far-away tokens are only reached indirectly.',
    ['sliding_window'],
  ),
  hybridSsm(
    'Hybrid SSM',
    'Mostly Mamba-style state-space layers with a few attention layers: '
        'near-constant memory per token and a slight quality gain.',
    ['ssm_hybrid'],
  );

  const Attention(this.label, this.blurb, this.requires);
  @override
  final String label;
  @override
  final String blurb;
  @override
  final List<String> requires;
  @override
  Era get minEra => Era.garage;
  @override
  String get id => name;
}

enum ContextLength implements DesignChoice {
  k2(2048, '2k', 'Short prompts only. Cheap to train and serve.', [], Era.garage),
  k4(4096, '4k', 'A few pages of text: the classic GPT-3 window.', [], Era.startup),
  k8(
    8192,
    '8k',
    'FlashAttention makes 8k sequences fit in GPU memory during training.',
    ['flash_attention'],
    Era.garage,
  ),
  k32(
    32768,
    '32k',
    'Position interpolation stretches RoPE to 32k with a short '
        'continued-training phase.',
    ['rope_scaling'],
    Era.garage,
  ),
  k128(
    131072,
    '128k',
    'YaRN extension plus long-context continued pre-training: whole books '
        'in one prompt.',
    ['yarn'],
    Era.garage,
  ),
  m1(
    1048576,
    '1M',
    'Ring attention shards the sequence across GPUs: whole codebases in one '
        'prompt, at a big KV-cache cost.',
    ['long_context', 'yarn'],
    Era.garage,
  );

  const ContextLength(this.tokens, this.label, this.blurb, this.requires, this.minEra);
  final int tokens;
  @override
  final String label;
  @override
  final String blurb;
  @override
  final List<String> requires;
  @override
  final Era minEra;
  @override
  String get id => name;

  /// Steps above 4k (2k = -1, 4k = 0, 8k = 1 ... 1M = 4).
  int get tier => index - 1;
}

/// Model size vs training length, as training tokens per parameter.
enum Sizing implements DesignChoice {
  bigShort(
    2,
    'Big & short (2 tok/param)',
    'A huge model stopped early, GPT-3 style. Wastes ~⅓ of the compute, '
        'but needs few tokens and costs a lot to serve.',
    [],
    Era.garage,
  ),
  kaplan(
    6,
    'Kaplan-style (6 tok/param)',
    'Spend most new compute on parameters (Kaplan 2020): close to optimal, '
        'a bit big to serve.',
    [],
    Era.garage,
  ),
  computeOptimal(
    20,
    'Compute-optimal (20 tok/param)',
    'Chinchilla: scale parameters and tokens equally, ~20 tokens per '
        'parameter. Best quality for the compute.',
    ['chinchilla_scaling'],
    Era.garage,
  ),
  overTrained(
    200,
    'Over-trained (200 tok/param)',
    'A smaller model trained far longer (Llama-style): ~3× cheaper to serve, '
        'needs 3× the tokens, a little worse per FLOP.',
    ['overtraining'],
    Era.garage,
  ),
  edge(
    1000,
    'Edge model (1000 tok/param)',
    'A tiny model on a huge corpus: very cheap to serve, much weaker per '
        'FLOP and data-hungry.',
    ['overtraining'],
    Era.bigLab,
  );

  const Sizing(this.tokensPerParam, this.label, this.blurb, this.requires, this.minEra);
  final double tokensPerParam;
  @override
  final String label;
  @override
  final String blurb;
  @override
  final List<String> requires;
  @override
  final Era minEra;
  @override
  String get id => name;
}

enum DataMix implements DesignChoice {
  web(0.9, 0.05, 0.05, 0, 'Web crawl', 'Mostly filtered web text: broad but shallow.', []),
  webCode(
    0.7,
    0.25,
    0.05,
    0,
    'Web + code',
    'A quarter code: better coding, and code helps reasoning on plain '
        'text too.',
    ['code_data'],
  ),
  balanced(
    0.6,
    0.2,
    0.2,
    0,
    'Balanced',
    'Web, code, books and papers: the all-rounder.',
    ['code_data', 'books_papers'],
  ),
  codeHeavy(
    0.3,
    0.55,
    0.15,
    0,
    'Code-heavy',
    'Over half code: wins coding, but past ~50% it starts to cost world '
        'knowledge and chat.',
    ['code_data'],
  ),
  synthMix(
    0.4,
    0.2,
    0.15,
    0.25,
    'Synthetic-augmented',
    'A quarter model-generated data added on top of real data: stretches '
        'the data budget without collapse.',
    ['synthetic_data'],
  ),
  synthHeavy(
    0.15,
    0.1,
    0.05,
    0.7,
    'Mostly synthetic',
    'Model output replaces most real data: lots of tokens, but the rare '
        'tails vanish (model collapse).',
    ['synthetic_data'],
  );

  const DataMix(this.webShare, this.code, this.books, this.synthetic, this.label, this.blurb, this.requires);

  /// Shares of the training tokens (sum to 1).
  final double webShare;
  final double code;
  final double books;
  final double synthetic;
  @override
  final String label;
  @override
  final String blurb;
  @override
  final List<String> requires;
  @override
  Era get minEra => Era.garage;
  @override
  String get id => name;
}

enum PostTraining implements DesignChoice {
  none('Base model', 'No post-training: it continues text instead of answering. Few users want it.', []),
  sft(
    'SFT',
    'Fine-tune on curated chat examples: unlocks the assistant format; '
        'almost all knowledge still comes from pre-training.',
    [],
  ),
  rlhf(
    'RLHF',
    'A reward model learns human rankings and PPO optimizes against it. '
        'Push too hard and the policy games the reward model.',
    ['rlhf'],
  ),
  dpo(
    'DPO',
    'Optimize preferences directly with a classification loss: no reward '
        'model, ~0.3× the cost, over-optimizes a bit sooner.',
    ['dpo'],
  ),
  reasoning(
    'RL reasoning',
    'RL on verifiable rewards (math answers, unit tests): the model learns '
        'to think at length. Much better at math, ~10× tokens per answer.',
    ['reasoning'],
  );

  const PostTraining(this.label, this.blurb, this.requires);
  @override
  final String label;
  @override
  final String blurb;
  @override
  final List<String> requires;
  @override
  Era get minEra => Era.garage;
  @override
  String get id => name;

  bool get usesRl => this == rlhf || this == dpo || this == reasoning;
}

/// How far RL moves the policy from the SFT model, as a multiple of the
/// reward model's sweet spot d* (Gao 2022: gold reward rises, peaks at d*,
/// then falls while the proxy reward keeps climbing).
enum RlStrength implements DesignChoice {
  light(0.5, 'Light', 'Stay close to the SFT model: safe, leaves quality on the table.'),
  standard(1.0, 'Standard', 'Stop near the reward model\'s sweet spot.'),
  strong(1.5, 'Strong', 'Past the sweet spot of a normal reward model; right for a big one.'),
  heavy(2.0, 'Heavy', 'The proxy reward keeps rising, the true quality is falling.'),
  extreme(3.0, 'Extreme', 'Reward hacking: the model games its grader and gets worse.');

  const RlStrength(this.kl, this.label, this.blurb);

  /// sqrt(KL) distance as a multiple of the baseline d*.
  final double kl;
  @override
  final String label;
  @override
  final String blurb;
  @override
  List<String> get requires => const [];
  @override
  Era get minEra => Era.garage;
  @override
  String get id => name;
}

enum Quantization implements DesignChoice {
  fp16('FP16', 'Serve the weights in 16-bit: the reference quality.', []),
  int8(
    'INT8',
    '8-bit weights with outlier features kept in 16-bit (LLM.int8): about '
        'half the memory, no measurable quality loss.',
    ['quantization'],
  ),
  int4(
    'INT4',
    '4-bit weights (GPTQ/AWQ): ~3× faster serving, small loss that grows '
        'the more over-trained the model is.',
    ['int4_weights'],
  );

  const Quantization(this.label, this.blurb, this.requires);
  @override
  final String label;
  @override
  final String blurb;
  @override
  final List<String> requires;
  @override
  Era get minEra => Era.garage;
  @override
  String get id => name;
}

/// The slots, in the order the run-setup panel shows them.
enum DesignSlot {
  architecture('Architecture'),
  attention('Attention'),
  context('Context length'),
  sizing('Model size vs training length'),
  dataMix('Data mix'),
  postTraining('Post-training'),
  rlStrength('RL strength'),
  quantization('Serving precision');

  const DesignSlot(this.label);
  final String label;

  List<DesignChoice> get options => switch (this) {
    architecture => Architecture.values,
    attention => Attention.values,
    context => ContextLength.values,
    sizing => Sizing.values,
    dataMix => DataMix.values,
    postTraining => PostTraining.values,
    rlStrength => RlStrength.values,
    quantization => Quantization.values,
  };

  DesignChoice of(ModelSpec s) => switch (this) {
    architecture => s.architecture,
    attention => s.attention,
    context => s.context,
    sizing => s.sizing,
    dataMix => s.dataMix,
    postTraining => s.postTraining,
    rlStrength => s.rlStrength,
    quantization => s.quantization,
  };

  /// [s] with this slot set to [c] (which must be one of [options]).
  ModelSpec set(ModelSpec s, DesignChoice c) => switch (this) {
    architecture => s.copyWith(architecture: c as Architecture),
    attention => s.copyWith(attention: c as Attention),
    context => s.copyWith(context: c as ContextLength),
    sizing => s.copyWith(sizing: c as Sizing),
    dataMix => s.copyWith(dataMix: c as DataMix),
    postTraining => s.copyWith(postTraining: c as PostTraining),
    rlStrength => s.copyWith(rlStrength: c as RlStrength),
    quantization => s.copyWith(quantization: c as Quantization),
  };

  /// RL strength only matters for RL-based post-training.
  bool relevant(ModelSpec s) => this != rlStrength || s.postTraining.usesRl;
}

// ---------------------------------------------------------------------------
// Spec and context
// ---------------------------------------------------------------------------

class ModelSpec {
  final Architecture architecture;
  final Attention attention;
  final ContextLength context;
  final Sizing sizing;
  final DataMix dataMix;
  final PostTraining postTraining;
  final RlStrength rlStrength;
  final Quantization quantization;

  const ModelSpec({
    this.architecture = Architecture.dense,
    this.attention = Attention.mha,
    this.context = ContextLength.k2,
    this.sizing = Sizing.kaplan,
    this.dataMix = DataMix.web,
    this.postTraining = PostTraining.sft,
    this.rlStrength = RlStrength.standard,
    this.quantization = Quantization.fp16,
  });

  /// The sensible, conservative default: the safest unlocked option per slot.
  factory ModelSpec.defaultFor(DesignContext ctx) {
    T pick<T extends DesignChoice>(List<T> prefs) => prefs.firstWhere(ctx.isUnlocked, orElse: () => prefs.last);
    return ModelSpec(
      architecture: Architecture.dense,
      attention: pick([Attention.gqa, Attention.mha]),
      context: pick([ContextLength.k8, ContextLength.k4, ContextLength.k2]),
      sizing: pick([Sizing.computeOptimal, Sizing.kaplan]),
      dataMix: pick([DataMix.balanced, DataMix.webCode, DataMix.web]),
      postTraining: pick([PostTraining.rlhf, PostTraining.sft]),
      rlStrength: RlStrength.standard,
      quantization: pick([Quantization.int8, Quantization.fp16]),
    );
  }

  /// A decent automatic pick (for the bot): coordinate ascent over the
  /// unlocked options of every slot, scored by [designScore]. Deterministic.
  static ModelSpec bestGuessFor(DesignContext ctx, {double serveWeight = 6, double demandWeight = 30}) {
    var best = ModelSpec.defaultFor(ctx);
    var bestScore = designScore(evaluate(best, ctx), serveWeight: serveWeight, demandWeight: demandWeight);
    for (var pass = 0; pass < 3; pass++) {
      var improved = false;
      for (final slot in DesignSlot.values) {
        for (final c in slot.options) {
          if (!ctx.isUnlocked(c) || c == slot.of(best)) continue;
          final cand = slot.set(best, c);
          final score = designScore(evaluate(cand, ctx), serveWeight: serveWeight, demandWeight: demandWeight);
          if (score > bestScore + 1e-9) {
            best = cand;
            bestScore = score;
            improved = true;
          }
        }
      }
      if (!improved) break;
    }
    return best;
  }

  /// This spec with every locked choice replaced by [defaultFor]'s pick, so a
  /// remembered setup stays valid (e.g. after loading an older save).
  ModelSpec clampTo(DesignContext ctx) {
    final d = ModelSpec.defaultFor(ctx);
    var out = this;
    for (final slot in DesignSlot.values) {
      if (!ctx.isUnlocked(slot.of(out))) out = slot.set(out, slot.of(d));
    }
    return out;
  }

  ModelSpec copyWith({
    Architecture? architecture,
    Attention? attention,
    ContextLength? context,
    Sizing? sizing,
    DataMix? dataMix,
    PostTraining? postTraining,
    RlStrength? rlStrength,
    Quantization? quantization,
  }) => ModelSpec(
    architecture: architecture ?? this.architecture,
    attention: attention ?? this.attention,
    context: context ?? this.context,
    sizing: sizing ?? this.sizing,
    dataMix: dataMix ?? this.dataMix,
    postTraining: postTraining ?? this.postTraining,
    rlStrength: rlStrength ?? this.rlStrength,
    quantization: quantization ?? this.quantization,
  );

  Map<String, dynamic> toJson() => {
    'arch': architecture.name,
    'attn': attention.name,
    'ctx': context.name,
    'size': sizing.name,
    'data': dataMix.name,
    'post': postTraining.name,
    'rl': rlStrength.name,
    'quant': quantization.name,
  };

  /// Tolerant: unknown or missing values fall back to the defaults.
  factory ModelSpec.fromJson(Map<String, dynamic> j) {
    T e<T extends Enum>(List<T> values, String key, T d) => values.asNameMap()[j[key]] ?? d;
    const d = ModelSpec();
    return ModelSpec(
      architecture: e(Architecture.values, 'arch', d.architecture),
      attention: e(Attention.values, 'attn', d.attention),
      context: e(ContextLength.values, 'ctx', d.context),
      sizing: e(Sizing.values, 'size', d.sizing),
      dataMix: e(DataMix.values, 'data', d.dataMix),
      postTraining: e(PostTraining.values, 'post', d.postTraining),
      rlStrength: e(RlStrength.values, 'rl', d.rlStrength),
      quantization: e(Quantization.values, 'quant', d.quantization),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ModelSpec &&
      other.architecture == architecture &&
      other.attention == attention &&
      other.context == context &&
      other.sizing == sizing &&
      other.dataMix == dataMix &&
      other.postTraining == postTraining &&
      other.rlStrength == rlStrength &&
      other.quantization == quantization;

  @override
  int get hashCode =>
      Object.hash(architecture, attention, context, sizing, dataMix, postTraining, rlStrength, quantization);

  @override
  String toString() => 'ModelSpec(${toJson().values.join(', ')})';
}

/// Plain numbers the game passes in. See docs/MODEL_DESIGN.md "Integration".
class DesignContext {
  /// GPUs in the training cluster.
  final double clusterGpus;

  /// GPUs the cluster's slowest switch can keep fed (TileDef.gpuCap of the
  /// bottleneck network tile; 0 for a lone, unnetworked GPU).
  final double networkGpuCap;

  /// Unique tokens in the data budget (Game.dataTokens).
  final double dataTokens;

  /// Owned research ids (GameState.ownedUpgrades).
  final Set<String> ownedResearch;

  /// Era.index of the current era.
  final int eraIndex;

  /// Effective training compute (raw FLOPs × Game.trainEffMult, before the
  /// data limit) the planned run would get. 0 = unknown: the data wall,
  /// alignment tax and reasoning base-model checks are then skipped.
  final double plannedCompute;

  const DesignContext({
    this.clusterGpus = 1,
    this.networkGpuCap = 0,
    this.dataTokens = startDataTokens,
    this.ownedResearch = const {},
    this.eraIndex = 0,
    this.plannedCompute = 0,
  });

  bool owns(String id) => ownedResearch.contains(id);

  bool isUnlocked(DesignChoice c) => eraIndex >= c.minEra.index && c.requires.every(owns);

  /// "Research X to unlock" / "Reach Big lab to unlock", or null if unlocked.
  String? lockReason(DesignChoice c) {
    for (final id in c.requires) {
      if (!owns(id)) return 'Research ${researchName(id)} to unlock';
    }
    if (eraIndex < c.minEra.index) return 'Reach ${c.minEra.label} to unlock';
    return null;
  }

  NetworkClass get networkClass {
    var cls = networkGpuCap >= fabricGpuCap
        ? NetworkClass.fabric
        : networkGpuCap >= infinibandGpuCap
        ? NetworkClass.infiniband
        : NetworkClass.ethernet;
    // An oversubscribed fabric (more GPUs than the switch can feed) behaves
    // like the class below it.
    if (clusterGpus > networkGpuCap && cls != NetworkClass.ethernet) {
      cls = NetworkClass.values[cls.index - 1];
    }
    return cls;
  }
}

/// How well the training network handles MoE all-to-all expert traffic.
enum NetworkClass {
  ethernet('Ethernet', 0.25, 0.6),
  infiniband('InfiniBand', 0.6, 0.9),
  fabric('Fat-tree / NVLink', 1.0, 1.0);

  const NetworkClass(this.label, this.moeGain, this.commEfficiency);
  final String label;

  /// Share of the MoE quality gain that survives (doc §2 netFactor).
  final double moeGain;

  /// Compute left after un-hidden expert all-to-all (DeepSeek-V3 reports a
  /// ~1:1 compute:communication ratio across nodes).
  final double commEfficiency;
}

/// Switch gpuCap at or above which the network counts as InfiniBand
/// (net_ib is 4096) or a full fabric (net_ib_spine 32768 and up).
const infinibandGpuCap = 1024.0;
const fabricGpuCap = 32768.0;

// ---------------------------------------------------------------------------
// Effects
// ---------------------------------------------------------------------------

enum NoteTone { good, bad, neutral }

class DesignNote {
  final DesignSlot slot;
  final String text;

  /// Paper reference: short title + year.
  final String ref;
  final NoteTone tone;
  const DesignNote(this.slot, this.text, this.ref, this.tone);

  @override
  String toString() => '[$tone] $text ($ref)';
}

/// A chance the game rolls (with its own RNG) when the run finishes.
class DesignRisk {
  final String id;
  final double chance;

  /// Multiplies [DesignEffects.cem] if it fires.
  final double cemMultOnHit;
  final String text;
  final String ref;
  const DesignRisk(this.id, this.chance, this.cemMultOnHit, this.text, this.ref);
}

/// Relative benchmark profile (1.0 = a plain dense SFT model on web data).
class BenchmarkStrengths {
  final double coding;
  final double math;
  final double chat;
  final double longContext;
  const BenchmarkStrengths({this.coding = 1, this.math = 1, this.chat = 1, this.longContext = 1});

  Map<String, double> get asMap => {'Coding': coding, 'Math': math, 'Chat': chat, 'Long context': longContext};

  Map<String, dynamic> toJson() => {'code': coding, 'math': math, 'chat': chat, 'long': longContext};

  factory BenchmarkStrengths.fromJson(Map<String, dynamic> j) {
    double v(String k) => (j[k] as num?)?.toDouble() ?? 1;
    return BenchmarkStrengths(coding: v('code'), math: v('math'), chat: v('chat'), longContext: v('long'));
  }
}

class DesignEffects {
  /// Compute-equivalent multiplier on training quality (all slots except the
  /// data budget and training cost). Rating change = 23·log2(cem).
  final double cem;

  /// Multiplies the data budget the game's data limit uses: tokens/param and
  /// synthetic data change how many unique tokens a run can usefully eat.
  final double dataBudgetMult;

  /// Flat rating from post-training, relative to plain SFT (the starting
  /// model is already fine-tuned): base model −60, RLHF up to +70...
  final double ratingAdd;

  /// Training compute needed per unit of pre-training (context length and
  /// post-training overhead). The run's compute is divided by this.
  final double trainCostMult;

  /// Per-user serving TFLOPS multiplier (lower = cheaper).
  final double serveCostMult;

  /// User demand multiplier (context and reasoning appeal, base-model penalty).
  final double demandMult;

  final BenchmarkStrengths strengths;
  final List<DesignNote> notes;
  final List<DesignRisk> risks;

  /// Predicted rating change vs a plain run on the same compute: CEM, the
  /// data limit (when DesignContext.plannedCompute is known), training cost
  /// and post-training together.
  final double ratingDelta;

  const DesignEffects({
    required this.cem,
    required this.dataBudgetMult,
    required this.ratingAdd,
    required this.trainCostMult,
    required this.serveCostMult,
    required this.demandMult,
    required this.strengths,
    required this.notes,
    required this.risks,
    required this.ratingDelta,
  });

  /// Rating from [cem] alone.
  double get cemRating => ratingPerDoubling * _log2(cem);

  /// The run's final effective compute: [compute] is raw FLOPs ×
  /// Game.trainEffMult, [dataTokens] is Game.dataTokens. Replaces
  /// Game.effectiveComputeOf for designed runs.
  double effectiveCompute(double compute, double dataTokens) =>
      dataLimited(compute * cem / trainCostMult, dataTokens * dataBudgetMult);
}

/// The game's data limit (Game.effectiveComputeOf), with an explicit budget.
double dataLimited(double compute, double dataTokens) {
  final cStar = chinchillaK * dataTokens * dataTokens;
  if (compute <= cStar) return compute;
  return cStar * math.pow(compute / cStar, dataLimitedExponent);
}

double _log2(double x) => math.log(x) / math.ln2;

/// Gao 2022 shape, normalised: g(1) = 1 at the sweet spot, falls on both
/// sides, negative past x = e (reward hacking).
double rlCurve(double x) => x <= 0 ? 0 : x * (1 - math.log(x));

// --- Rule constants (see docs/MODEL_DESIGN.md for the table) ---------------

/// SFT's absolute rating bonus (LIMA / InstructGPT; Design). [DesignEffects.
/// ratingAdd] is reported relative to it.
const sftRating = 60.0;
const rlhfBonus = 70.0;
const reasoningBonus = 40.0;
const alignmentTaxRating = 15.0;
const alignmentTaxParams = 50e9;
const reasoningMinBaseRating = 1000.0;
const reasoningServeMult = 10.0;
const adaptiveReasoningServeMult = 4.0;
const moeCollapseChance = 0.25;
const moeCollapsedCem = 1.2;

/// Doc §8 uses 0.03 per decade of over-training; steepened so INT4 on an
/// over-trained model is a visible mistake (Kumar 2024 direction).
const int4OvertrainPenalty = 0.08;

/// Score the bot maximises: rating, plus demand and serving cost in rating
/// points per doubling, with risks at their expected (log) value.
double designScore(DesignEffects e, {double serveWeight = 6, double demandWeight = 30}) {
  var s = e.ratingDelta + demandWeight * _log2(e.demandMult) - serveWeight * _log2(e.serveCostMult);
  for (final r in e.risks) {
    s += r.chance * ratingPerDoubling * _log2(r.cemMultOnHit);
  }
  return s;
}

/// Evaluate [spec] for a lab described by [ctx]. Pure and deterministic.
/// Locked options are evaluated as if owned (check [DesignContext.isUnlocked]).
DesignEffects evaluate(ModelSpec spec, DesignContext ctx) {
  final notes = <DesignNote>[];
  final risks = <DesignRisk>[];
  void note(DesignSlot slot, String text, String ref, NoteTone tone) => notes.add(DesignNote(slot, text, ref, tone));
  String pct(double m) => '${m >= 1 ? '+' : '−'}${((m - 1).abs() * 100).round()}%';
  String times(double m) => '×${m.toStringAsFixed(m >= 10 ? 0 : (m < 1 ? 2 : 1))}';

  var cem = 1.0;
  var dataMult = 1.0;
  var train = 1.0;
  var serve = 1.0;
  var demand = 1.0;
  var coding = 1.0, mathS = 1.0, chat = 1.0, longCtx = 1.0;

  // --- Model size vs training length (§1) ----------------------------------
  final r = spec.sizing.tokensPerParam;
  final sizeCem = math.exp(-0.45 * math.pow(math.log(r / 20) / math.ln10, 2));
  final sizeServe = math.sqrt(20 / r);
  cem *= sizeCem;
  serve *= sizeServe;
  // Tokens needed at fixed compute scale as sqrt(r): D = sqrt(C·r/6).
  dataMult *= math.sqrt(20 / r);
  const chinchillaRef = 'Training Compute-Optimal LLMs, Hoffmann 2022';
  if (r < 20) {
    note(
      DesignSlot.sizing,
      'Under-trained: ${(sizeCem * 100).round()}% of the compute is useful, serving ${times(sizeServe)}',
      chinchillaRef,
      sizeCem < 0.8 ? NoteTone.bad : NoteTone.neutral,
    );
  } else if (r == 20) {
    note(DesignSlot.sizing, 'Compute-optimal: ~20 tokens per parameter', chinchillaRef, NoteTone.good);
  } else {
    note(
      DesignSlot.sizing,
      'Over-trained: serving ${times(sizeServe)}, ${(sizeCem * 100).round()}% compute efficiency, '
          '${math.sqrt(r / 20).toStringAsFixed(1)}× the tokens',
      'Beyond Chinchilla-Optimal, Sardana 2023',
      sizeCem < 0.5 ? NoteTone.bad : NoteTone.neutral,
    );
  }

  // --- Architecture (§2) ----------------------------------------------------
  if (spec.architecture != Architecture.dense) {
    final fine = spec.architecture == Architecture.fineMoe;
    final raw = fine ? 3.0 : 2.0;
    final net = ctx.networkClass;
    final eff = (1 + (raw - 1) * net.moeGain) * net.commEfficiency;
    cem *= eff;
    final mem = fine ? 1.35 : 1.2;
    serve *= mem;
    note(
      DesignSlot.architecture,
      net == NetworkClass.fabric
          ? '${spec.architecture.label}: ${times(eff)} quality per FLOP'
          : '${spec.architecture.label} on ${net.label}: expert all-to-all eats the gain (${times(eff)})',
      fine ? 'DeepSeekMoE, Dai 2024' : 'Switch Transformers, Fedus 2021',
      eff > 1.05 ? NoteTone.good : NoteTone.bad,
    );
    if (net != NetworkClass.fabric) {
      note(
        DesignSlot.architecture,
        'MoE wants a fat-tree or NVLink network (${net.label} keeps ${(net.moeGain * 100).round()}% of the gain)',
        'DeepSeek-V3 Technical Report, 2024',
        NoteTone.bad,
      );
    }
    note(
      DesignSlot.architecture,
      'All experts sit in memory: serving ${times(mem)}',
      'Mixtral of Experts, Jiang 2024',
      NoteTone.neutral,
    );
    if (!ctx.owns('router_balancing')) {
      final collapsed = (1 + (moeCollapsedCem - 1) * net.moeGain) * net.commEfficiency;
      risks.add(
        DesignRisk(
          'routing_collapse',
          moeCollapseChance,
          collapsed / eff,
          '${(moeCollapseChance * 100).round()}% risk the router collapses onto a few experts',
          'Outrageously Large Neural Networks, Shazeer 2017',
        ),
      );
      note(
        DesignSlot.architecture,
        '${(moeCollapseChance * 100).round()}% routing-collapse risk until Router load balancing',
        'Outrageously Large Neural Networks, Shazeer 2017',
        NoteTone.bad,
      );
    }
  }

  // --- Attention (§3) -------------------------------------------------------
  final (attnCem, attnServe, ctxGrowth, attnLong) = switch (spec.attention) {
    Attention.mha => (1.0, 1.0, 1.4, 1.0),
    Attention.gqa => (0.99, 0.5, 1.15, 1.0),
    Attention.slidingWindow => (0.99 * 0.97, 0.4, 1.05, 0.8),
    Attention.hybridSsm => (1.02, 0.35, 1.03, 0.92),
  };
  cem *= attnCem;
  serve *= attnServe;
  longCtx *= attnLong;
  switch (spec.attention) {
    case Attention.mha:
      break;
    case Attention.gqa:
      note(DesignSlot.attention, 'GQA: serving ×0.5, quality −1%', 'GQA, Ainslie 2023', NoteTone.good);
    case Attention.slidingWindow:
      note(
        DesignSlot.attention,
        'Sliding window: serving ×0.4, KV cache capped; weaker long-range recall',
        'Mistral 7B, Jiang 2023',
        NoteTone.neutral,
      );
    case Attention.hybridSsm:
      note(
        DesignSlot.attention,
        'Hybrid SSM: serving ×0.35, near-constant memory, quality +2%',
        'An Empirical Study of Mamba-based LMs, Waleffe 2024',
        NoteTone.good,
      );
  }

  // --- Context length (§4) --------------------------------------------------
  final tier = spec.context.tier;
  final longData = ctx.owns('long_data');
  final double ctxEff;
  if (tier <= 1) {
    ctxEff = 1;
  } else if (tier == 2) {
    ctxEff = longData ? (ctx.owns('yarn') ? 1.0 : 0.8) : 0.5;
  } else {
    ctxEff = longData ? 1.0 : 0.25;
  }
  final doublings = _log2(spec.context.tokens / 4096);
  final ctxDemand = 1 + 0.08 * doublings * ctxEff;
  final ctxTrain = 1 + 0.06 * math.max(0, tier);
  final ctxServe = math.pow(ctxGrowth, tier).toDouble();
  demand *= ctxDemand;
  train *= ctxTrain;
  serve *= ctxServe;
  longCtx *= 1 + 0.25 * tier * ctxEff;
  if (tier >= 2 && !longData) {
    final hit = tier == 2 ? 0.95 : 0.9;
    cem *= hit;
    note(
      DesignSlot.context,
      '${spec.context.label} claimed, far less usable without long-document data (quality ${pct(hit)})',
      'RULER: real context size, Hsieh 2024',
      NoteTone.bad,
    );
  }
  if (tier != 0) {
    note(
      DesignSlot.context,
      '${spec.context.label} context: demand ${pct(ctxDemand)}, serving ${times(ctxServe)}'
          '${tier > 0 ? ', training ${pct(ctxTrain)}' : ''}',
      tier >= 2 ? 'Data Engineering for 128K Context, Fu 2024' : 'Scaling Laws for Neural LMs, Kaplan 2020',
      tier < 0 ? NoteTone.neutral : (ctxEff >= 0.8 ? NoteTone.good : NoteTone.neutral),
    );
  }
  if (tier >= 2 && spec.attention == Attention.mha) {
    note(
      DesignSlot.context,
      'Long context on full attention: the KV cache explodes (serving ${times(ctxServe)})',
      'GQA, Ainslie 2023',
      NoteTone.bad,
    );
  }

  // --- Data mix (§5) --------------------------------------------------------
  final mix = spec.dataMix;
  final codeCem = 1 + 0.4 * math.min(mix.code, 0.3);
  final codeTax = mix.code > 0.5 ? 1 - 0.6 * (mix.code - 0.5) : 1.0;
  final booksCem = 1 + 0.25 * math.min(mix.books, 0.2);
  cem *= codeCem * codeTax * booksCem;
  // Synthetic tokens count at half value (doc §5e) on top of the real pool.
  final synthBudget = 1 + 0.5 * mix.synthetic / (1 - mix.synthetic);
  dataMult *= synthBudget;
  coding *= 0.6 + 2 * mix.code;
  mathS *= 0.7 + 0.8 * mix.code + 0.8 * mix.books + 0.4 * mix.synthetic;
  chat *= 1 - 0.4 * math.max(0, mix.code - 0.3);
  if (mix.code >= 0.2) {
    note(
      DesignSlot.dataMix,
      '${(mix.code * 100).round()}% code: coding ${times((0.6 + 2 * mix.code) / 0.7)}, quality ${pct(codeCem * codeTax)}',
      'To Code, or Not To Code, Aryabumi 2024',
      codeTax < 1 ? NoteTone.neutral : NoteTone.good,
    );
  }
  if (codeTax < 1) {
    note(
      DesignSlot.dataMix,
      'Over half code costs world knowledge and chat',
      'To Code, or Not To Code, Aryabumi 2024',
      NoteTone.bad,
    );
  }
  if (mix.synthetic > 0) {
    note(
      DesignSlot.dataMix,
      'Synthetic data stretches the data budget ${times(synthBudget)} (counts at half value)',
      'Is Model Collapse Inevitable?, Gerstgrasser 2024',
      NoteTone.good,
    );
  }
  if (mix.synthetic > 0.5) {
    cem *= 0.7;
    demand *= 0.9;
    chat *= 0.75;
    coding *= 0.9;
    note(
      DesignSlot.dataMix,
      'Model collapse: synthetic data replaced real data, quality −30%, bland answers',
      'The Curse of Recursion, Shumailov 2023',
      NoteTone.bad,
    );
  }

  // --- Post-training (§7) ---------------------------------------------------
  final post = spec.postTraining;
  var absRating = 0.0;
  final bigRm = ctx.owns('reward_model_scaling');
  switch (post) {
    case PostTraining.none:
      demand *= 0.3;
      chat *= 0.4;
      note(DesignSlot.postTraining, 'Base model: no chat format, demand ×0.3', 'LIMA, Zhou 2023', NoteTone.bad);
    case PostTraining.sft:
      absRating = sftRating;
      train *= 1.01;
    case PostTraining.rlhf || PostTraining.dpo || PostTraining.reasoning:
      absRating = sftRating;
      train *= 1.01;
      final isDpo = post == PostTraining.dpo;
      final dStar = (bigRm ? 1.5 : 1.0) * (isDpo ? 0.8 : 1.0);
      final b = rlhfBonus * (bigRm ? 1.15 : 1.0) * (isDpo ? 0.9 : 1.0);
      final x = spec.rlStrength.kl / dStar;
      final g = rlCurve(x);
      final rl = b * g;
      absRating += rl;
      train *= 1 + (isDpo ? 0.012 : 0.04) * spec.rlStrength.kl;
      chat *= 1 + 0.4 * g;
      demand *= 1 + 0.1 * g;
      final peak = (dStar - spec.rlStrength.kl).abs() < 1e-9;
      note(
        DesignSlot.rlStrength,
        x > math.e
            ? 'Reward hacking: RL pushed past the reward model, rating ${rl.toStringAsFixed(0)}'
            : x > 1.05
            ? 'Over-optimized: past the reward model\'s sweet spot (+${rl.round()} of a possible +${b.round()})'
            : peak
            ? 'RL strength at the sweet spot: +${rl.round()} rating'
            : 'Under-optimized: +${rl.round()} of a possible +${b.round()}',
        isDpo ? 'DPO over-optimization, Rafailov 2024' : 'Scaling Laws for RM Overoptimization, Gao 2022',
        x > 1.6 ? NoteTone.bad : (peak ? NoteTone.good : NoteTone.neutral),
      );
      if (post == PostTraining.rlhf) {
        note(
          DesignSlot.postTraining,
          'RLHF: a 1.3B model beat a 100× larger one in human ratings',
          'InstructGPT, Ouyang 2022',
          NoteTone.good,
        );
      } else if (isDpo) {
        note(
          DesignSlot.postTraining,
          'DPO: no reward model, ~0.3× the post-training compute',
          'Direct Preference Optimization, Rafailov 2023',
          NoteTone.good,
        );
      }
      if (post == PostTraining.reasoning) {
        var bonus = reasoningBonus;
        final baseRating = ctx.plannedCompute > 0
            ? ratingBase + ratingPerDoubling * _log2(ctx.plannedCompute * cem / startEffectiveCompute)
            : double.infinity;
        if (baseRating < reasoningMinBaseRating) {
          bonus /= 2;
          note(
            DesignSlot.postTraining,
            'Base model too weak for RL reasoning: half the bonus',
            'DeepSeek-R1, 2025',
            NoteTone.bad,
          );
        }
        absRating += bonus;
        train *= 1 + 0.10 * spec.rlStrength.kl;
        final adaptive = ctx.owns('adaptive_thinking');
        final s = adaptive ? adaptiveReasoningServeMult : reasoningServeMult;
        serve *= s;
        demand *= 1.25;
        mathS *= 3;
        coding *= 2;
        note(
          DesignSlot.postTraining,
          'RL reasoning: math ×3, coding ×2, +${bonus.round()} rating, demand +25%',
          'DeepSeek-R1, 2025',
          NoteTone.good,
        );
        note(
          DesignSlot.postTraining,
          'Thinks at length: serving ${times(s)}${adaptive ? ' (adaptive budgets)' : ''}',
          adaptive ? 'Scaling Test-Time Compute, Snell 2024' : 'Do NOT Think That Much for 2+3=?, Chen 2024',
          NoteTone.bad,
        );
      }
      // Alignment tax hits small models (Askell 2021, Bai 2022).
      if (!ctx.owns('ppo_ptx') && ctx.plannedCompute > 0) {
        final params = math.sqrt(ctx.plannedCompute / (6 * r));
        final tax = alignmentTaxRating * (1 - math.min(1.0, params / alignmentTaxParams));
        if (tax > 0.5) {
          absRating -= tax;
          note(
            DesignSlot.postTraining,
            'Alignment tax on a small model: −${tax.round()} rating (PPO-ptx fixes it)',
            'InstructGPT, Ouyang 2022',
            NoteTone.bad,
          );
        }
      }
  }

  // --- Quantization (§8) ----------------------------------------------------
  switch (spec.quantization) {
    case Quantization.fp16:
      break;
    case Quantization.int8:
      serve *= 0.55;
      note(DesignSlot.quantization, 'INT8: serving ×0.55, no quality loss', 'LLM.int8(), Dettmers 2022', NoteTone.good);
    case Quantization.int4:
      final over = math.max(0.0, math.log(r / 20) / math.ln10);
      final q = 0.97 - int4OvertrainPenalty * over;
      cem *= q;
      serve *= 0.35;
      note(
        DesignSlot.quantization,
        over > 0
            ? 'INT4 on an over-trained model: quality ${pct(q)} (more tokens, harder to quantize)'
            : 'INT4: serving ×0.35, quality ${pct(q)}',
        over > 0 ? 'Scaling Laws for Precision, Kumar 2024' : 'GPTQ, Frantar 2022',
        over > 0.5 ? NoteTone.bad : NoteTone.good,
      );
  }

  final ratingAdd = absRating - sftRating;
  final double ratingDelta;
  if (ctx.plannedCompute > 0) {
    final c = ctx.plannedCompute;
    final base = dataLimited(c, ctx.dataTokens);
    final designed = dataLimited(c * cem / train, ctx.dataTokens * dataMult);
    ratingDelta = ratingPerDoubling * _log2(designed / base) + ratingAdd;
    final neededD = math.sqrt(c * cem / train * r / 6) / synthBudget;
    if (neededD > ctx.dataTokens * 1.05) {
      note(
        DesignSlot.sizing,
        'Data wall: the run wants ${(neededD / ctx.dataTokens).toStringAsFixed(1)}× your unique tokens',
        'Will We Run Out of Data?, Villalobos 2022',
        NoteTone.bad,
      );
    }
  } else {
    ratingDelta = ratingPerDoubling * _log2(cem / train) + ratingAdd;
  }

  return DesignEffects(
    cem: cem,
    dataBudgetMult: dataMult,
    ratingAdd: ratingAdd,
    trainCostMult: train,
    serveCostMult: serve,
    demandMult: demand,
    strengths: BenchmarkStrengths(coding: coding / 0.7, math: mathS / 0.78, chat: chat, longContext: longCtx),
    notes: notes,
    risks: risks,
    ratingDelta: ratingDelta,
  );
}

/// One line for the release card, e.g. "Code-heavy mix won coding".
String strengthHeadline(ModelSpec spec, BenchmarkStrengths s) {
  final best = s.asMap.entries.reduce((a, b) => b.value > a.value ? b : a);
  if (best.value < 1.15) return 'An all-rounder';
  final cause = switch (best.key) {
    'Coding' when spec.dataMix == DataMix.codeHeavy => 'Code-heavy mix',
    'Coding' || 'Math' when spec.postTraining == PostTraining.reasoning => 'RL reasoning',
    'Coding' => '${spec.dataMix.label} data',
    'Math' => '${spec.dataMix.label} data',
    'Chat' => spec.postTraining.label,
    _ => '${spec.context.label} context',
  };
  return '$cause won ${best.key.toLowerCase()}';
}

// ---------------------------------------------------------------------------
// Research: new unlocks and tracks
// ---------------------------------------------------------------------------

/// Research that unlocks design options. Effects are identity: their value is
/// the option they unlock. Wire in by adding them to the research list
/// (see docs/MODEL_DESIGN.md "Integration").
const designUpgrades = <UpgradeDef>[
  // --- Medium lab ------------------------------------------------------------
  UpgradeDef(
    id: 'gqa',
    name: 'Grouped-query attention',
    blurb:
        'Let groups of query heads share one key/value head: an ~8× smaller '
        'KV cache and much faster decoding for almost no quality.',
    category: UpgradeCategory.research,
    era: Era.mediumLab,
    cost: 6e7,
    effects: Effects(),
  ),
  UpgradeDef(
    id: 'sliding_window',
    name: 'Sliding-window attention',
    blurb:
        'Each layer attends only to the last few thousand tokens; stacked '
        'layers still reach further. The KV cache stops growing.',
    category: UpgradeCategory.research,
    era: Era.mediumLab,
    cost: 1.1e8,
    effects: Effects(),
    requires: ['gqa'],
  ),
  UpgradeDef(
    id: 'rope_scaling',
    name: 'RoPE position interpolation',
    blurb:
        'Squeeze longer sequences into the rotary position range seen in '
        'training, then fine-tune briefly: 32k context from a 4k model.',
    category: UpgradeCategory.research,
    era: Era.mediumLab,
    cost: 5e7,
    effects: Effects(),
    requires: ['flash_attention'],
  ),
  UpgradeDef(
    id: 'router_balancing',
    name: 'Router load balancing',
    blurb:
        'An auxiliary loss (or per-expert bias) spreads tokens evenly, so '
        'the router can\'t collapse onto a few experts.',
    category: UpgradeCategory.research,
    era: Era.mediumLab,
    cost: 9e7,
    effects: Effects(),
    requires: ['moe'],
  ),
  UpgradeDef(
    id: 'overtraining',
    name: 'Inference-aware scaling',
    blurb:
        'When a model will serve billions of requests, a smaller model '
        'trained on far more tokens is cheaper overall.',
    category: UpgradeCategory.research,
    era: Era.mediumLab,
    cost: 4e7,
    effects: Effects(),
    requires: ['chinchilla_scaling'],
  ),
  UpgradeDef(
    id: 'ppo_ptx',
    name: 'Pre-training mix in RL (PPO-ptx)',
    blurb:
        'Mix pre-training gradients into the RL updates, so preference '
        'tuning doesn\'t erode benchmark skills (the alignment tax).',
    category: UpgradeCategory.research,
    era: Era.mediumLab,
    cost: 8e7,
    effects: Effects(),
    requires: ['rlhf'],
  ),
  UpgradeDef(
    id: 'long_data',
    name: 'Long-document data',
    blurb:
        'Up-sample long documents across all domains for continued '
        'pre-training, so the model really uses its long context.',
    category: UpgradeCategory.data,
    era: Era.mediumLab,
    cost: 9e7,
    effects: Effects(),
  ),
  UpgradeDef(
    id: 'int4_weights',
    name: '4-bit weights (GPTQ/AWQ)',
    blurb:
        'Quantize weights to 4 bits using second-order or activation-aware '
        'error correction: ~3× faster serving, small quality loss.',
    category: UpgradeCategory.software,
    era: Era.mediumLab,
    cost: 1e8,
    effects: Effects(),
    requires: ['quantization'],
  ),
  // --- Big lab ---------------------------------------------------------------
  UpgradeDef(
    id: 'yarn',
    name: 'YaRN context extension',
    blurb:
        'Rescale RoPE frequencies unevenly and adjust attention temperature: '
        '128k context with ~10× fewer tokens than earlier methods.',
    category: UpgradeCategory.research,
    era: Era.bigLab,
    cost: 6e8,
    effects: Effects(),
    requires: ['rope_scaling'],
  ),
  UpgradeDef(
    id: 'fine_grained_moe',
    name: 'Fine-grained experts',
    blurb:
        'Split experts into many small ones and add always-on shared '
        'experts: more specialised experts for the same compute per token.',
    category: UpgradeCategory.research,
    era: Era.bigLab,
    cost: 1.8e9,
    effects: Effects(),
    requires: ['moe'],
  ),
  UpgradeDef(
    id: 'ssm_hybrid',
    name: 'Hybrid state-space layers',
    blurb:
        'Replace most attention layers with Mamba-style SSM layers that keep '
        'a fixed-size state; a few attention layers keep recall sharp.',
    category: UpgradeCategory.research,
    era: Era.bigLab,
    cost: 1.2e9,
    effects: Effects(),
    requires: ['gqa'],
  ),
  UpgradeDef(
    id: 'dpo',
    name: 'Direct Preference Optimization',
    blurb:
        'Turn preference tuning into a classification loss on chosen vs '
        'rejected answers: no reward model, no RL sampling loop.',
    category: UpgradeCategory.research,
    era: Era.bigLab,
    cost: 5e8,
    effects: Effects(),
    requires: ['rlhf'],
  ),
  UpgradeDef(
    id: 'reward_model_scaling',
    name: 'Bigger reward models',
    blurb:
        'A larger reward model is harder to game: RL can push further '
        'before true quality starts falling.',
    category: UpgradeCategory.research,
    era: Era.bigLab,
    cost: 9e8,
    effects: Effects(),
    requires: ['rlhf'],
  ),
  // --- Frontier lab ----------------------------------------------------------
  UpgradeDef(
    id: 'adaptive_thinking',
    name: 'Adaptive thinking budgets',
    blurb:
        'Spend thinking tokens by difficulty instead of on every prompt: '
        'easy questions get short answers, hard ones think longer.',
    category: UpgradeCategory.research,
    era: Era.globalLab,
    cost: 1.2e10,
    effects: Effects(),
    requires: ['reasoning'],
  ),
];

final Map<String, UpgradeDef> _researchById = {for (final u in [...upgrades, ...designUpgrades]) u.id: u};

/// Display name of a research id from either list (falls back to the id).
String researchName(String id) => _researchById[id]?.name ?? id;

enum ResearchTrack {
  preTraining('Pre-training'),
  postTraining('Post-training'),
  data('Data'),
  infrastructure('Infrastructure');

  const ResearchTrack(this.label);
  final String label;
}

/// Every research id (content.dart `upgrades` and [designUpgrades]) → track,
/// for tabbing the research screen.
const researchTracks = <String, ResearchTrack>{
  // Existing upgrades.
  'mixed_precision': ResearchTrack.preTraining,
  'batching': ResearchTrack.infrastructure,
  'kv_cache': ResearchTrack.infrastructure,
  'lora': ResearchTrack.postTraining,
  'common_crawl': ResearchTrack.data,
  'cuda_kernels': ResearchTrack.infrastructure,
  'quantization': ResearchTrack.infrastructure,
  'code_data': ResearchTrack.data,
  'dedup': ResearchTrack.data,
  'data_mixture': ResearchTrack.data,
  'instruction_tuning': ResearchTrack.postTraining,
  'flash_attention': ResearchTrack.infrastructure,
  'interconnect': ResearchTrack.infrastructure,
  'liquid_cooling': ResearchTrack.infrastructure,
  'books_papers': ResearchTrack.data,
  'chinchilla_scaling': ResearchTrack.preTraining,
  'zero_sharding': ResearchTrack.infrastructure,
  'moe': ResearchTrack.preTraining,
  'rlhf': ResearchTrack.postTraining,
  'parallelism': ResearchTrack.infrastructure,
  'distillation': ResearchTrack.infrastructure,
  'paged_attention': ResearchTrack.infrastructure,
  'licensed_data': ResearchTrack.data,
  'fp8': ResearchTrack.preTraining,
  'speculative': ResearchTrack.infrastructure,
  'synthetic_data': ResearchTrack.data,
  'rlaif': ResearchTrack.postTraining,
  'long_context': ResearchTrack.preTraining,
  'reasoning': ResearchTrack.postTraining,
  'multi_token_prediction': ResearchTrack.preTraining,
  'human_expert_data': ResearchTrack.data,
  'test_time_compute': ResearchTrack.postTraining,
  'agentic_rl': ResearchTrack.postTraining,
  'disaggregated_serving': ResearchTrack.infrastructure,
  // Design upgrades.
  'gqa': ResearchTrack.preTraining,
  'sliding_window': ResearchTrack.preTraining,
  'rope_scaling': ResearchTrack.preTraining,
  'router_balancing': ResearchTrack.preTraining,
  'overtraining': ResearchTrack.preTraining,
  'ppo_ptx': ResearchTrack.postTraining,
  'long_data': ResearchTrack.data,
  'int4_weights': ResearchTrack.infrastructure,
  'yarn': ResearchTrack.preTraining,
  'fine_grained_moe': ResearchTrack.preTraining,
  'ssm_hybrid': ResearchTrack.preTraining,
  'dpo': ResearchTrack.postTraining,
  'reward_model_scaling': ResearchTrack.postTraining,
  'adaptive_thinking': ResearchTrack.postTraining,
};

/// Track of a research id; unknown ids (e.g. added later) default to
/// pre-training so they still show up somewhere.
ResearchTrack trackOf(String id) => researchTracks[id] ?? ResearchTrack.preTraining;

/// Which design options a research id unlocks (for "Unlocks: GQA" on cards).
List<(DesignSlot, DesignChoice)> optionsUnlockedBy(String id) => [
  for (final slot in DesignSlot.values)
    for (final c in slot.options)
      if (c.requires.contains(id)) (slot, c),
];

/// Research that changes how design options behave instead of unlocking one.
const designResearchModifiers = <String, String>{
  'router_balancing': 'Removes the MoE routing-collapse risk',
  'long_data': 'Long contexts (32k+) become fully usable',
  'ppo_ptx': 'Removes the alignment tax on small models',
  'reward_model_scaling': 'RL sweet spot ×1.5 further, RL bonus +15%',
  'adaptive_thinking': 'RL reasoning serving ×10 → ×4',
};
