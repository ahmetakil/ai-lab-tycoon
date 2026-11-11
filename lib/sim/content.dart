// Static game content: hardware, power tiers, upgrades, launch stunts, rivals.
// Pure Dart — no Flutter imports. All balance knobs live here or in balance.dart.

enum Era { garage, startup, lab }

extension EraInfo on Era {
  String get label => switch (this) {
        Era.garage => 'Garage',
        Era.startup => 'Startup',
        Era.lab => 'Lab',
      };
}

class HardwareDef {
  final String id;
  final String name;
  final String blurb;
  final Era era;
  final double tflops; // dense 16-bit TFLOPS, roughly real-world
  final double powerKw;
  final double cost; // flat price per unit (no idle-style cost growth)

  const HardwareDef({
    required this.id,
    required this.name,
    required this.blurb,
    required this.era,
    required this.tflops,
    required this.powerKw,
    required this.cost,
  });

  double get tflopsPerKw => tflops / powerKw;
}

class PowerDef {
  final String id;
  final String name;
  final String blurb;
  final Era era;
  final double capacityKw; // replaces the previous cap
  final double cost;

  const PowerDef({
    required this.id,
    required this.name,
    required this.blurb,
    required this.era,
    required this.capacityKw,
    required this.cost,
  });
}

enum UpgradeCategory { software, data, research }

/// Multiplicative / additive effects of an upgrade. Identity values = no effect.
class Effects {
  final double utilizationAdd; // + to MFU (fraction of peak FLOPS actually used)
  final double trainEffMult; // algorithmic efficiency: effective training compute
  final double serveEffMult; // fewer FLOPs needed per user served
  final double dataMult; // multiplies the data budget (tokens)
  final double ratingAdd; // flat model-rating bonus (post-training tricks)
  final double arpuMult; // revenue per user
  final double powerMult; // GPU power draw multiplier (cooling etc.)

  const Effects({
    this.utilizationAdd = 0,
    this.trainEffMult = 1,
    this.serveEffMult = 1,
    this.dataMult = 1,
    this.ratingAdd = 0,
    this.arpuMult = 1,
    this.powerMult = 1,
  });
}

class UpgradeDef {
  final String id;
  final String name;
  final String blurb; // the one-line educational explanation
  final UpgradeCategory category;
  final Era era;
  final double cost;
  final Effects effects;
  final List<String> requires;

  const UpgradeDef({
    required this.id,
    required this.name,
    required this.blurb,
    required this.category,
    required this.era,
    required this.cost,
    required this.effects,
    this.requires = const [],
  });
}

class LaunchStunt {
  final String id;
  final String name;
  final String blurb;
  final double costFraction; // fraction of current money spent
  final double successChance;
  final double hypeOnSuccess;
  final double hypeOnFail;

  const LaunchStunt({
    required this.id,
    required this.name,
    required this.blurb,
    this.costFraction = 0,
    this.successChance = 1,
    required this.hypeOnSuccess,
    this.hypeOnFail = 1,
  });
}

/// One historical snapshot of a parody rival lab. The ladder is ordered;
/// beating a snapshot advances you to the next one ("racing history").
class RivalSnapshot {
  final String lab;
  final int year;
  final String model;
  final double rating;
  final double users;

  /// Estimated GPUs (H100-equivalents) for display; 0 = unknown.
  final double gpus;

  /// One-line parody flavour shown on the rival card.
  final String quip;

  const RivalSnapshot({
    required this.lab,
    required this.year,
    required this.model,
    required this.rating,
    required this.users,
    this.gpus = 0,
    this.quip = '',
  });
}

// ---------------------------------------------------------------------------
// Hardware. Parody names; TFLOPS/power/price are loosely real-world.
// ---------------------------------------------------------------------------
const hardware = <HardwareDef>[
  HardwareDef(
    id: 'gamer',
    name: 'Gaming GPU',
    blurb: 'Great for games, decent at matrix math. Hungry for power.',
    era: Era.garage,
    tflops: 80,
    powerKw: 0.45,
    cost: 1600,
  ),
  HardwareDef(
    id: 'v_class',
    name: 'Used V-class Datacenter GPU',
    blurb: 'Older datacenter card off eBay. Slower, but sips power.',
    era: Era.garage,
    tflops: 125,
    powerKw: 0.3,
    cost: 4000,
  ),
  HardwareDef(
    id: 'a_class',
    name: 'A-class GPU',
    blurb: 'The workhorse that trained a generation of models.',
    era: Era.startup,
    tflops: 312,
    powerKw: 0.4,
    cost: 15000,
  ),
  HardwareDef(
    id: 'h_class',
    name: 'H-class GPU',
    blurb: 'Everyone wants one. Lead times measured in quarters.',
    era: Era.lab,
    tflops: 990,
    powerKw: 0.7,
    cost: 30000,
  ),
  HardwareDef(
    id: 'b_class',
    name: 'B-class GPU',
    blurb: 'Next-gen silicon. Needs serious power and cooling.',
    era: Era.lab,
    tflops: 2250,
    powerKw: 1.0,
    cost: 45000,
  ),
];

// ---------------------------------------------------------------------------
// Power tiers. Each one replaces the previous cap. Cooling is flavour text.
// ---------------------------------------------------------------------------
const powerTiers = <PowerDef>[
  PowerDef(
    id: 'outlet',
    name: 'Garage outlet',
    blurb: 'One breaker. Don\'t run the microwave.',
    era: Era.garage,
    capacityKw: 1.8,
    cost: 0,
  ),
  PowerDef(
    id: 'panel',
    name: 'Upgraded electrical panel',
    blurb: 'An electrician and a box fan.',
    era: Era.garage,
    capacityKw: 8,
    cost: 3000,
  ),
  PowerDef(
    id: 'office',
    name: 'Office with 3-phase power',
    blurb: 'First real office. The server closet is louder than the team.',
    era: Era.startup,
    capacityKw: 40,
    cost: 25000,
  ),
  PowerDef(
    id: 'colo',
    name: 'Colocation cage',
    blurb: 'Rented racks in someone else\'s datacenter, with real cooling.',
    era: Era.startup,
    capacityKw: 250,
    cost: 150000,
  ),
  PowerDef(
    id: 'hall',
    name: 'Datacenter hall',
    blurb: 'Your own hall, your own chillers.',
    era: Era.lab,
    capacityKw: 2000,
    cost: 2e6,
  ),
  PowerDef(
    id: 'campus',
    name: 'Datacenter campus',
    blurb: 'Several halls and a substation.',
    era: Era.lab,
    capacityKw: 20000,
    cost: 25e6,
  ),
  PowerDef(
    id: 'plant',
    name: 'Dedicated power plant deal',
    blurb: 'You now have opinions about grid interconnect queues.',
    era: Era.lab,
    capacityKw: 150000,
    cost: 300e6,
  ),
];

// ---------------------------------------------------------------------------
// Upgrades: software (efficiency), data (data budget), research (model quality).
// Blurbs must stay technically accurate — have an ML engineer review them.
// ---------------------------------------------------------------------------
const upgrades = <UpgradeDef>[
  // --- Garage -------------------------------------------------------------
  UpgradeDef(
    id: 'mixed_precision',
    name: 'Mixed precision (FP16)',
    blurb: 'Use 16-bit numbers instead of 32-bit: about twice the math per '
        'cycle with nearly the same accuracy.',
    category: UpgradeCategory.software,
    era: Era.garage,
    cost: 800,
    effects: Effects(utilizationAdd: 0.08),
  ),
  UpgradeDef(
    id: 'batching',
    name: 'Request batching',
    blurb: 'Serve many users\' requests together, so the GPU does one big '
        'matrix multiply instead of many small ones.',
    category: UpgradeCategory.software,
    era: Era.garage,
    cost: 1200,
    effects: Effects(serveEffMult: 2),
  ),
  UpgradeDef(
    id: 'kv_cache',
    name: 'KV cache',
    blurb: 'Keep the attention keys and values of earlier tokens, so each new '
        'token doesn\'t recompute the whole prompt.',
    category: UpgradeCategory.software,
    era: Era.garage,
    cost: 2500,
    effects: Effects(serveEffMult: 1.5),
  ),
  UpgradeDef(
    id: 'lora',
    name: 'LoRA fine-tuning',
    blurb: 'Train small adapter matrices instead of updating every weight. '
        'Most of the gain at a fraction of the compute.',
    category: UpgradeCategory.research,
    era: Era.garage,
    cost: 2000,
    effects: Effects(trainEffMult: 1.5),
  ),
  UpgradeDef(
    id: 'common_crawl',
    name: 'Filtered web crawl',
    blurb: 'Scrape and filter a big slice of the public web. More tokens = '
        'you can usefully spend more compute.',
    category: UpgradeCategory.data,
    era: Era.garage,
    cost: 3000,
    effects: Effects(dataMult: 25),
  ),
  // --- Startup ------------------------------------------------------------
  UpgradeDef(
    id: 'cuda_kernels',
    name: 'Custom CUDA kernels',
    blurb: 'Hand-write GPU code for the hottest loops instead of relying on '
        'generic library calls.',
    category: UpgradeCategory.software,
    era: Era.startup,
    cost: 20000,
    effects: Effects(utilizationAdd: 0.10),
  ),
  UpgradeDef(
    id: 'flash_attention',
    name: 'FlashAttention',
    blurb: 'Compute attention in small tiles that fit in fast on-chip memory, '
        'avoiding slow round-trips to GPU RAM.',
    category: UpgradeCategory.software,
    era: Era.startup,
    cost: 35000,
    effects: Effects(utilizationAdd: 0.07, trainEffMult: 1.1),
    requires: ['cuda_kernels'],
  ),
  UpgradeDef(
    id: 'quantization',
    name: 'Quantization (INT8/INT4)',
    blurb: 'Store weights in 8 or 4 bits instead of 16. The model gets 2–4× '
        'smaller and faster with little quality loss.',
    category: UpgradeCategory.software,
    era: Era.startup,
    cost: 25000,
    effects: Effects(serveEffMult: 2),
  ),
  UpgradeDef(
    id: 'interconnect',
    name: 'High-speed interconnect',
    blurb: 'Fast links between machines so a thousand GPUs can act like one '
        'instead of waiting on each other.',
    category: UpgradeCategory.software,
    era: Era.startup,
    cost: 60000,
    effects: Effects(utilizationAdd: 0.05),
  ),
  UpgradeDef(
    id: 'liquid_cooling',
    name: 'Liquid cooling',
    blurb: 'Pipe coolant straight to the chips. Less energy wasted on fans '
        'and air conditioning.',
    category: UpgradeCategory.software,
    era: Era.startup,
    cost: 80000,
    effects: Effects(powerMult: 0.85),
  ),
  UpgradeDef(
    id: 'code_data',
    name: 'Public code dataset',
    blurb: 'Train on open-source code. It helps with programming and, it '
        'turns out, with reasoning in general.',
    category: UpgradeCategory.data,
    era: Era.startup,
    cost: 30000,
    effects: Effects(dataMult: 3, ratingAdd: 10),
  ),
  UpgradeDef(
    id: 'dedup',
    name: 'Deduplication & quality filters',
    blurb: 'Remove duplicate and junk documents. Cleaner data trains a better '
        'model with the same compute.',
    category: UpgradeCategory.data,
    era: Era.startup,
    cost: 40000,
    effects: Effects(trainEffMult: 1.5),
  ),
  UpgradeDef(
    id: 'instruction_tuning',
    name: 'Instruction tuning',
    blurb: 'Fine-tune on question/answer examples, so the model follows '
        'instructions instead of just continuing text.',
    category: UpgradeCategory.research,
    era: Era.startup,
    cost: 25000,
    effects: Effects(ratingAdd: 25),
  ),
  UpgradeDef(
    id: 'rlhf',
    name: 'RLHF',
    blurb: 'Humans rank answers, a reward model learns their preferences, and '
        'the model is trained to score well on it.',
    category: UpgradeCategory.research,
    era: Era.startup,
    cost: 90000,
    effects: Effects(ratingAdd: 40, arpuMult: 1.2),
    requires: ['instruction_tuning'],
  ),
  UpgradeDef(
    id: 'moe',
    name: 'Mixture of Experts',
    blurb: 'Many "expert" sub-networks with a router that sends each token to '
        'only a couple of them: more parameters, same compute per token.',
    category: UpgradeCategory.research,
    era: Era.startup,
    cost: 150000,
    effects: Effects(trainEffMult: 2.5, serveEffMult: 1.5),
  ),
  // --- Lab ----------------------------------------------------------------
  UpgradeDef(
    id: 'fp8',
    name: 'FP8 training',
    blurb: 'Train with 8-bit floating point on hardware that supports it. '
        'Roughly double the throughput if you keep it stable.',
    category: UpgradeCategory.software,
    era: Era.lab,
    cost: 1.5e6,
    effects: Effects(utilizationAdd: 0.06),
  ),
  UpgradeDef(
    id: 'parallelism',
    name: '3D parallelism',
    blurb: 'Split the model across GPUs three ways (data, tensor, pipeline) '
        'so huge models fit and GPUs stay busy.',
    category: UpgradeCategory.software,
    era: Era.lab,
    cost: 2.5e6,
    effects: Effects(utilizationAdd: 0.05, trainEffMult: 1.2),
    requires: ['interconnect'],
  ),
  UpgradeDef(
    id: 'distillation',
    name: 'Distillation',
    blurb: 'Train a small "student" model to imitate the big one, then serve '
        'the cheap student to most users.',
    category: UpgradeCategory.software,
    era: Era.lab,
    cost: 3e6,
    effects: Effects(serveEffMult: 3),
  ),
  UpgradeDef(
    id: 'speculative',
    name: 'Speculative decoding',
    blurb: 'A tiny model drafts several tokens; the big model checks them all '
        'in one pass and keeps the ones it agrees with.',
    category: UpgradeCategory.software,
    era: Era.lab,
    cost: 4e6,
    effects: Effects(serveEffMult: 1.8),
  ),
  UpgradeDef(
    id: 'synthetic_data',
    name: 'Synthetic data',
    blurb: 'Have your models generate and grade new training data. Useful '
        'once you run low on fresh human text.',
    category: UpgradeCategory.data,
    era: Era.lab,
    cost: 5e6,
    effects: Effects(dataMult: 10),
  ),
  UpgradeDef(
    id: 'rlaif',
    name: 'AI feedback (RLAIF)',
    blurb: 'Use a model guided by written principles to grade answers, '
        'scaling up feedback beyond what humans can label.',
    category: UpgradeCategory.research,
    era: Era.lab,
    cost: 6e6,
    effects: Effects(ratingAdd: 30),
    requires: ['rlhf'],
  ),
  UpgradeDef(
    id: 'reasoning',
    name: 'Reasoning (RL on chain of thought)',
    blurb: 'Train the model to think step by step before answering. Much '
        'smarter, but every answer now costs many more tokens.',
    category: UpgradeCategory.research,
    era: Era.lab,
    cost: 12e6,
    effects: Effects(ratingAdd: 70, serveEffMult: 0.6),
    requires: ['rlhf'],
  ),
];

const launchStunts = <LaunchStunt>[
  LaunchStunt(
    id: 'none',
    name: 'Quiet release',
    blurb: 'Push it to the API and go to bed.',
    hypeOnSuccess: 1.0,
  ),
  LaunchStunt(
    id: 'cryptic_tweet',
    name: 'Cryptic tweet',
    blurb: 'Post a single emoji. Let the timeline do the rest.',
    hypeOnSuccess: 1.4,
  ),
  LaunchStunt(
    id: 'live_demo',
    name: 'Live demo',
    blurb: 'Big stage, live audience. What could go wrong?',
    costFraction: 0.10,
    successChance: 0.7,
    hypeOnSuccess: 2.2,
    hypeOnFail: 0.8,
  ),
];

// ---------------------------------------------------------------------------
// Rival ladder. PLACEHOLDER numbers — calibrate from docs/research/rival_labs.md.
// Parody names only; never real company names.
// ---------------------------------------------------------------------------
const rivalLadder = <RivalSnapshot>[
  RivalSnapshot(lab: 'Hugging Hands Collective', year: 2017, model: 'tiny-lstm', rating: 760, users: 2e3),
  RivalSnapshot(lab: 'ClosedAI', year: 2018, model: 'GPT-ish-1', rating: 850, users: 2e4),
  RivalSnapshot(lab: 'Gogol DeepThought', year: 2019, model: 'BURT', rating: 920, users: 2e5),
  RivalSnapshot(lab: 'ClosedAI', year: 2019, model: 'GPT-ish-2', rating: 980, users: 1e6),
  RivalSnapshot(lab: 'Mistrawl', year: 2020, model: 'Mistrawl-7B', rating: 1040, users: 3e6),
  RivalSnapshot(lab: 'ClosedAI', year: 2020, model: 'GPT-ish-3', rating: 1100, users: 5e6),
  RivalSnapshot(lab: 'Anthropomorphic', year: 2022, model: 'Claudette 1', rating: 1150, users: 2e7),
  RivalSnapshot(lab: 'ClosedAI', year: 2022, model: 'ChatGPT-ish', rating: 1200, users: 1e8),
  RivalSnapshot(lab: 'Gogol DeepThought', year: 2023, model: 'Gemeni Ultra', rating: 1260, users: 2e8),
  RivalSnapshot(lab: 'ClosedAI', year: 2023, model: 'GPT-ish-4', rating: 1300, users: 2e8),
];
