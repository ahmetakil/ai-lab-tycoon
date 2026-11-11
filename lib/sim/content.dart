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
  final double powerKw; // per unit, roughly "all-in" for datacenter parts
  final double cost; // flat price per unit (no idle-style cost growth)

  /// Upgrades that must be owned before this can be bought (e.g. liquid
  /// cooling for rack-scale parts). Empty = no requirement.
  final List<String> requires;

  /// Index into [powerTiers] that must be reached before buying (a site that
  /// can physically host it). 0 = no requirement.
  final int minPowerTier;

  const HardwareDef({
    required this.id,
    required this.name,
    required this.blurb,
    required this.era,
    required this.tflops,
    required this.powerKw,
    required this.cost,
    this.requires = const [],
    this.minPowerTier = 0,
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

  /// Estimated flagship training FLOPs of the real model this parodies
  /// (0 = not given). [rating] = ratingOf(trainingFlops) + [postTrainingBonus].
  final double trainingFlops;

  /// Rating bonus for that era's post-training (instruction tuning, RLHF,
  /// reasoning RL...). Mirrors the player's research upgrades.
  final double postTrainingBonus;

  /// True when [trainingFlops] is interpolated (no public estimate exists).
  final bool flopsInterpolated;

  const RivalSnapshot({
    required this.lab,
    required this.year,
    required this.model,
    required this.rating,
    required this.users,
    this.gpus = 0,
    this.quip = '',
    this.trainingFlops = 0,
    this.postTrainingBonus = 0,
    this.flopsInterpolated = false,
  });

  /// Stable id derived from the lab name (matches the UI's rival logo slug).
  String get labId =>
      lab.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_');
}


// ---------------------------------------------------------------------------
// Hardware. Parody names; TFLOPS/power/price are loosely real-world.
// tflops = dense 16-bit tensor math. powerKw for datacenter parts is "all-in"
// (chip + its share of host, network and cooling), e.g. ~1.3 kW per H-class. Each newer part
// beats the older ones on BOTH TFLOPS/\$ and TFLOPS/kW, so upgrading is never
// a trap; the power cap is what pushes you to newer silicon.
// Ids are save-format keys: append only.
// ---------------------------------------------------------------------------
const hardware = <HardwareDef>[
  HardwareDef(
    id: 'gamer',
    name: 'Gaming GPU',
    blurb: 'Great for games, decent at matrix math. Hungry for power.',
    era: Era.garage,
    tflops: 80,
    powerKw: 0.45,
    cost: 2000,
  ),
  HardwareDef(
    id: 'v_class',
    name: 'Used V-class Datacenter GPU',
    blurb: 'Older datacenter card off eBay: tensor cores, ECC memory and '
        'more math per watt than a gaming card.',
    era: Era.garage,
    tflops: 125,
    powerKw: 0.5,
    cost: 3000,
  ),
  HardwareDef(
    id: 'a_class',
    name: 'A-class GPU',
    blurb: 'The workhorse that trained a generation of models.',
    era: Era.startup,
    tflops: 312,
    powerKw: 0.7,
    cost: 7000,
  ),
  HardwareDef(
    id: 'h_class',
    name: 'H-class GPU',
    blurb: 'Everyone wants one. Lead times measured in quarters.',
    era: Era.lab,
    tflops: 990,
    powerKw: 1.3,
    cost: 20000,
  ),
  HardwareDef(
    id: 'b_class',
    name: 'B-class GPU',
    blurb: 'Next-gen silicon in liquid-cooled racks. Needs a campus-sized '
        'power feed.',
    era: Era.lab,
    tflops: 2250,
    powerKw: 2.4,
    cost: 40000,
    requires: ['liquid_cooling'],
    minPowerTier: 5, // campus
  ),
  HardwareDef(
    id: 'r_class',
    name: 'R-class Superchip',
    blurb: 'The generation after B-class, sold by the rack. Your utility now '
        'has your CEO on speed dial.',
    era: Era.lab,
    tflops: 3500,
    powerKw: 3.4,
    cost: 55000,
    requires: ['liquid_cooling'],
    minPowerTier: 6, // power plant deal
  ),
];

// ---------------------------------------------------------------------------
// Power tiers. Each one replaces the previous cap. Cooling is flavour text.
// APPEND ONLY: saves store the tier index.
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
    cost: 2.5e6,
  ),
  PowerDef(
    id: 'hall',
    name: 'Datacenter hall',
    blurb: 'Your own hall, your own chillers.',
    era: Era.lab,
    capacityKw: 2000,
    cost: 6e6,
  ),
  PowerDef(
    id: 'campus',
    name: 'Datacenter campus',
    blurb: 'Several halls and a substation.',
    era: Era.lab,
    capacityKw: 20000,
    cost: 40e6,
  ),
  PowerDef(
    id: 'plant',
    name: 'Dedicated power plant deal',
    blurb: 'You now have opinions about grid interconnect queues.',
    era: Era.lab,
    capacityKw: 150000,
    cost: 150e6,
  ),
  PowerDef(
    id: 'gw_campus',
    name: 'Gigawatt campus',
    blurb: 'A small city\'s worth of electricity, turned into matrix '
        'multiplies and heat.',
    era: Era.lab,
    capacityKw: 1e6,
    cost: 750e6,
  ),
  PowerDef(
    id: 'nuclear_restart',
    name: 'Restarted nuclear plant',
    blurb: 'A 20-year deal to bring a mothballed reactor back online. Plus '
        'some gas turbines nobody mentions.',
    era: Era.lab,
    capacityKw: 2e6,
    cost: 2.5e9,
  ),
  PowerDef(
    id: 'multi_site',
    name: 'Multi-site cluster',
    blurb: 'Several gigawatt campuses training one model over long-haul '
        'fiber.',
    era: Era.lab,
    capacityKw: 4e6,
    cost: 6e9,
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
    blurb: 'Do most math in 16-bit on tensor cores, keeping 32-bit master '
        'weights: several times the throughput, nearly the same accuracy.',
    category: UpgradeCategory.software,
    era: Era.garage,
    cost: 800,
    effects: Effects(utilizationAdd: 0.08),
  ),
  UpgradeDef(
    id: 'batching',
    name: 'Request batching',
    blurb: 'Serve many users\' requests together, so the weights are read '
        'from memory once per step for the whole batch.',
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
    blurb: 'Freeze the model and train small low-rank adapters instead: a '
        'fraction of the memory, so you can fine-tune on modest GPUs.',
    category: UpgradeCategory.research,
    era: Era.garage,
    cost: 2000,
    effects: Effects(trainEffMult: 1.3),
  ),
  UpgradeDef(
    id: 'common_crawl',
    name: 'Filtered web crawl',
    blurb: 'Scrape and filter a big slice of the public web. More tokens = '
        'you can usefully spend more compute.',
    category: UpgradeCategory.data,
    era: Era.garage,
    cost: 3000,
    effects: Effects(dataMult: 50),
  ),
  // --- Startup ------------------------------------------------------------
  UpgradeDef(
    id: 'cuda_kernels',
    name: 'Custom CUDA kernels',
    blurb: 'Fuse and hand-tune GPU code for the hottest operations instead '
        'of chaining many generic library calls.',
    category: UpgradeCategory.software,
    era: Era.startup,
    cost: 60000,
    effects: Effects(utilizationAdd: 0.10),
  ),
  UpgradeDef(
    id: 'flash_attention',
    name: 'FlashAttention',
    blurb: 'Compute exact attention in tiles that fit in fast on-chip memory, '
        'avoiding slow round-trips to GPU RAM.',
    category: UpgradeCategory.software,
    era: Era.startup,
    cost: 150000,
    effects: Effects(utilizationAdd: 0.07, trainEffMult: 1.1),
    requires: ['cuda_kernels'],
  ),
  UpgradeDef(
    id: 'quantization',
    name: 'Quantization (INT8/INT4)',
    blurb: 'Store weights in 8 or 4 bits instead of 16: a 2–4× smaller model '
        'that serves faster, usually with little quality loss.',
    category: UpgradeCategory.software,
    era: Era.startup,
    cost: 80000,
    effects: Effects(serveEffMult: 2),
  ),
  UpgradeDef(
    id: 'interconnect',
    name: 'High-speed interconnect',
    blurb: 'Fast links between machines so a thousand GPUs can act like one '
        'instead of waiting on each other.',
    category: UpgradeCategory.software,
    era: Era.startup,
    cost: 400000,
    effects: Effects(utilizationAdd: 0.05),
  ),
  UpgradeDef(
    id: 'liquid_cooling',
    name: 'Liquid cooling',
    blurb: 'Pipe coolant straight to the chips. Less energy wasted on fans '
        'and air conditioning, and denser racks.',
    category: UpgradeCategory.software,
    era: Era.startup,
    cost: 600000,
    effects: Effects(powerMult: 0.85),
  ),
  UpgradeDef(
    id: 'code_data',
    name: 'Public code dataset',
    blurb: 'Train on open-source code. It helps with programming and seems '
        'to help structured reasoning too.',
    category: UpgradeCategory.data,
    era: Era.startup,
    cost: 120000,
    effects: Effects(dataMult: 3, ratingAdd: 10),
  ),
  UpgradeDef(
    id: 'dedup',
    name: 'Deduplication & quality filters',
    blurb: 'Remove duplicate and junk documents. Cleaner data trains a better '
        'model with the same compute.',
    category: UpgradeCategory.data,
    era: Era.startup,
    cost: 200000,
    effects: Effects(trainEffMult: 1.5),
  ),
  UpgradeDef(
    id: 'data_mixture',
    name: 'Data mixture optimisation',
    blurb: 'Tune the ratio of web, code, books and math using small proxy '
        'runs: same compute, better model.',
    category: UpgradeCategory.data,
    era: Era.startup,
    cost: 350000,
    effects: Effects(trainEffMult: 1.3),
    requires: ['dedup'],
  ),
  UpgradeDef(
    id: 'instruction_tuning',
    name: 'Instruction tuning',
    blurb: 'Fine-tune on question/answer examples, so the model follows '
        'instructions instead of just continuing text.',
    category: UpgradeCategory.research,
    era: Era.startup,
    cost: 100000,
    effects: Effects(ratingAdd: 25),
  ),
  UpgradeDef(
    id: 'moe',
    name: 'Mixture of Experts',
    blurb: 'Many "expert" sub-networks with a router that sends each token to '
        'only a few: more parameters for the same compute per token.',
    category: UpgradeCategory.research,
    era: Era.startup,
    cost: 1.5e6,
    effects: Effects(trainEffMult: 2.5, serveEffMult: 1.5),
  ),
  // --- Lab ----------------------------------------------------------------
  UpgradeDef(
    id: 'rlhf',
    name: 'RLHF',
    blurb: 'Humans rank answers, a reward model learns their preferences, and '
        'the model is trained to score well on it.',
    category: UpgradeCategory.research,
    era: Era.lab,
    cost: 2e6,
    effects: Effects(ratingAdd: 35, arpuMult: 1.2),
    requires: ['instruction_tuning'],
  ),
  UpgradeDef(
    id: 'fp8',
    name: 'FP8 training',
    blurb: 'Run most matrix multiplies in 8-bit floats with careful scaling: '
        'up to twice the peak math of 16-bit on chips that support it.',
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
    id: 'multi_token_prediction',
    name: 'Multi-token prediction',
    blurb: 'Train extra heads to predict several upcoming tokens: a denser '
        'training signal, and free draft tokens for faster decoding.',
    category: UpgradeCategory.research,
    era: Era.lab,
    cost: 60e6,
    effects: Effects(trainEffMult: 1.15, serveEffMult: 1.2),
  ),
  UpgradeDef(
    id: 'synthetic_data',
    name: 'Synthetic data',
    blurb: 'Have your models generate and grade new training data. Useful '
        'once you run low on fresh human text.',
    category: UpgradeCategory.data,
    era: Era.lab,
    cost: 5e6,
    effects: Effects(dataMult: 50),
  ),
  UpgradeDef(
    id: 'licensed_data',
    name: 'Licensed data deals',
    blurb: 'Pay publishers, forums and archives for access to text you '
        'can\'t (or shouldn\'t) scrape.',
    category: UpgradeCategory.data,
    era: Era.lab,
    cost: 30e6,
    effects: Effects(dataMult: 2.5),
  ),
  UpgradeDef(
    id: 'human_expert_data',
    name: 'Expert data (PhD annotators)',
    blurb: 'Pay domain experts to write and grade hard problems. Few tokens, '
        'big gains on exactly the questions users care about.',
    category: UpgradeCategory.data,
    era: Era.lab,
    cost: 600e6,
    effects: Effects(ratingAdd: 20, arpuMult: 1.1),
    requires: ['rlhf'],
  ),
  UpgradeDef(
    id: 'rlaif',
    name: 'AI feedback (RLAIF)',
    blurb: 'Use a model, guided by written principles, to grade answers: '
        'feedback that scales beyond what humans can label.',
    category: UpgradeCategory.research,
    era: Era.lab,
    cost: 40e6,
    effects: Effects(ratingAdd: 20),
    requires: ['rlhf'],
  ),
  UpgradeDef(
    id: 'long_context',
    name: 'Long context (ring attention)',
    blurb: 'Shard very long sequences across GPUs that pass key/value blocks '
        'around a ring, so whole codebases fit in one prompt.',
    category: UpgradeCategory.research,
    era: Era.lab,
    cost: 400e6,
    effects: Effects(ratingAdd: 10, arpuMult: 1.25),
    requires: ['parallelism'],
  ),
  UpgradeDef(
    id: 'reasoning',
    name: 'Reasoning (RL on chain of thought)',
    blurb: 'Reward correct final answers with RL so the model learns to think '
        'at length first. Much smarter, but answers cost many more tokens.',
    category: UpgradeCategory.research,
    era: Era.lab,
    cost: 150e6,
    effects: Effects(ratingAdd: 60, serveEffMult: 0.6),
    requires: ['rlhf'],
  ),
  UpgradeDef(
    id: 'test_time_compute',
    name: 'Test-time compute scaling',
    blurb: 'Let the model spend more thinking tokens on hard questions; '
        'accuracy keeps climbing with inference compute.',
    category: UpgradeCategory.research,
    era: Era.lab,
    cost: 2.5e9,
    effects: Effects(ratingAdd: 35, serveEffMult: 0.7),
    requires: ['reasoning'],
  ),
  UpgradeDef(
    id: 'agentic_rl',
    name: 'Agentic RL environments',
    blurb: 'RL in sandboxes with real tools (code, browsers, terminals), '
        'rewarding the model for finishing multi-step tasks.',
    category: UpgradeCategory.research,
    era: Era.lab,
    cost: 6e9,
    effects: Effects(ratingAdd: 35, arpuMult: 1.2),
    requires: ['reasoning'],
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
// Rival ladder, calibrated from docs/research/rival_labs.md.
// Parody names only; never real company names.
//
// rating = ratingBase + ratingPerDoubling·log2(trainingFlops / 1e18)
//          + postTrainingBonus
// i.e. the player's own ratingOf(): to beat a rival you need about the same
// effective training compute plus a similar post-training stack.
// FLOPs are Epoch AI estimates unless flopsInterpolated is set.
// users = real reported/estimated figures where they exist; otherwise
// interpolated (marked "interp."). Mixed WAU/MAU, as in the research notes.
// gpus  = rough H100-equivalents of the lab's fleet/cluster at the time.
// Ordered so rating strictly increases. Users mostly increase too; the few
// dips are real (labs with small consumer apps) and act as pure rating gates.
// ---------------------------------------------------------------------------
const rivalLadder = <RivalSnapshot>[
  RivalSnapshot(
    lab: 'Hugging Hands Collective', year: 2017, model: 'Tiny-Transformer',
    trainingFlops: 7e18, rating: 765, users: 1e3, gpus: 1, // users interp.
    quip: 'Uploads a model card with more emoji than parameters.',
  ),
  RivalSnapshot(
    lab: 'ClosedAI', year: 2018, model: 'GPT-ish-1',
    trainingFlops: 1.8e19, rating: 796, users: 3e3, gpus: 1, // users interp.
    quip: 'Pre-trains on 7,000 unpublished novels, just to see what happens.',
  ),
  RivalSnapshot(
    lab: 'Gogol DeepThought', year: 2018, model: 'BURT-Large',
    // FLOPs: Epoch DB (~2.9e20), not in the research table.
    trainingFlops: 2.9e20, rating: 888, users: 1e4, gpus: 3, // users interp.
    quip: 'Hides 15% of every sentence and calls it [MASK]ed learning.',
  ),
  RivalSnapshot(
    lab: 'ClosedAI', year: 2019, model: 'GPT-ish-2',
    trainingFlops: 1.9e21, rating: 950, users: 3e4, gpus: 30, // users interp.
    quip: 'Too dangerous to release. Releases it nine months later.',
  ),
  RivalSnapshot(
    lab: 'Gogol DeepThought', year: 2020, model: 'Meenie',
    trainingFlops: 1.1e23, rating: 1085, users: 1e5, gpus: 130, // users interp.
    quip: 'A chatbot so good that nobody outside the company may talk to it.',
  ),
  RivalSnapshot(
    lab: 'ClosedAI', year: 2020, model: 'GPT-ish-3',
    trainingFlops: 3.1e23, rating: 1120, users: 3e5, gpus: 1300, // users interp.
    quip: '175B parameters, an API waitlist and a thousand threads about '
        '"few-shot".',
  ),
  RivalSnapshot(
    lab: 'Mistrawl', year: 2023, model: 'Mixtrawl 8x7B',
    trainingFlops: 7.7e23, postTrainingBonus: 60, rating: 1210,
    users: 3e6, gpus: 1500, // users + gpus interp.
    quip: 'Launch event: a torrent magnet link and zero explanation.',
  ),
  RivalSnapshot(
    lab: 'ClosedAI', year: 2023, model: 'ChatGPT-ish',
    trainingFlops: 2.6e24, postTrainingBonus: 70, rating: 1260,
    users: 1e8, gpus: 7900, // 100M MAU, Jan 2023
    quip: 'Releases a "research preview" that 100M people use as a product.',
  ),
  RivalSnapshot(
    lab: 'ClosedAI', year: 2023, model: 'GPT-ish-4',
    trainingFlops: 2.1e25, postTrainingBonus: 80, rating: 1339,
    users: 1e8, gpus: 30000, // 100M WAU, Nov 2023
    quip: 'A 100-page technical report. Parameter count: "no comment".',
  ),
  RivalSnapshot(
    lab: 'Anthropomorphic', year: 2024, model: 'Claudette 3.5 Sonata',
    trainingFlops: 2.7e25, postTrainingBonus: 105, rating: 1373,
    users: 5e7, gpus: 200000, // users + gpus interp. (never published)
    quip: 'Left to build it more safely. Ships the model every coder quietly '
        'switches to.',
  ),
  RivalSnapshot(
    lab: 'DeepSleep', year: 2025, model: 'DeepSleep-R1',
    trainingFlops: 3.3e24, postTrainingBonus: 180, rating: 1378,
    users: 9.7e7, gpus: 50000, // ~97M MAU, Apr 2025
    quip: 'Near-frontier for "\$5.6M" (final run only, see footnote). Chip '
        'stocks have a bad day.',
  ),
  RivalSnapshot(
    lab: 'Anthropomorphic', year: 2025, model: 'Claudette 3.7 Sonata',
    trainingFlops: 3.4e25, postTrainingBonus: 180, rating: 1455,
    users: 1e8, gpus: 400000, // users interp. (never published)
    quip: 'Barely any consumers. Writes half of everyone\'s code anyway.',
  ),
  RivalSnapshot(
    lab: 'ClosedAI', year: 2025, model: 'o-three',
    trainingFlops: 5e25, flopsInterpolated: true, postTrainingBonus: 175,
    rating: 1463, users: 4e8, gpus: 500000, // 400M WAU, Feb 2025
    quip: 'Thinks for a minute before answering. Bills you for every thought.',
  ),
  RivalSnapshot(
    lab: 'yAI', year: 2025, model: 'Grokk 3',
    trainingFlops: 3.5e26, postTrainingBonus: 150, rating: 1503,
    users: 6.4e7, gpus: 200000, // 64M MAU, Sep 2025
    quip: 'Built a 100k-GPU cluster in 122 days. Launch date: "two weeks".',
  ),
  RivalSnapshot(
    lab: 'ClosedAI', year: 2025, model: 'GPT-ish-4.5',
    trainingFlops: 3.8e26, postTrainingBonus: 150, rating: 1506,
    users: 5e8, gpus: 600000, // 500M WAU, end Mar 2025
    quip: 'The biggest pre-training run yet. Reviews: "warm vibes". '
        'API price: also warm.',
  ),
  RivalSnapshot(
    lab: 'ClosedAI', year: 2025, model: 'GPT-ish-5',
    trainingFlops: 6.6e25, postTrainingBonus: 215, rating: 1512,
    users: 8e8, gpus: 900000, // 800M WAU, Oct 2025
    quip: 'A router picks which model answers you. The router is the product.',
  ),
  RivalSnapshot(
    lab: 'Gogol DeepThought', year: 2025, model: 'Gemeni 3 Pro',
    trainingFlops: 6e26, flopsInterpolated: true, postTrainingBonus: 200,
    rating: 1571, users: 6.5e8, gpus: 1700000, // 650M MAU, Oct 2025
    quip: 'Owns the most chips on Earth. Still says "coming soon" a lot.',
  ),
  RivalSnapshot(
    lab: 'MetaMind Labs', year: 2026, model: 'Amused Spark',
    trainingFlops: 5e26, flopsInterpolated: true, postTrainingBonus: 215,
    rating: 1580, users: 1e9, gpus: 2600000, // 1B MAU across apps (2025)
    quip: 'Gave the weights away for three years, then closed them. Capex: '
        'yes.',
  ),
  RivalSnapshot(
    lab: 'ClosedAI', year: 2026, model: 'GPT-ish-5.5 "Tater"',
    trainingFlops: 6e26, flopsInterpolated: true, postTrainingBonus: 225,
    rating: 1596, users: 9e8, gpus: 2000000, // 900M WAU, Feb 2026
    quip: 'Codename: a potato. Benchmarks: not a potato.',
  ),
  RivalSnapshot(
    lab: 'Anthropomorphic', year: 2026, model: 'Claudette Parable 5',
    trainingFlops: 1e27, flopsInterpolated: true, postTrainingBonus: 230,
    rating: 1618, users: 2.45e8, gpus: 1400000, // ~245M MAU est.
    quip: 'Rents compute from three clouds and a rival\'s supercomputer. '
        'Revenue chart goes vertical.',
  ),
  RivalSnapshot(
    lab: 'Gogol DeepThought', year: 2026, model: 'Gemeni 4 Xenon',
    trainingFlops: 9e26, flopsInterpolated: true, postTrainingBonus: 238,
    rating: 1622, users: 1e9, gpus: 3700000, // >1B MAU, Aug 2026
    quip: 'Wins 12 of 18 benchmarks. Benchmarks chosen by: Gogol.',
  ),
  RivalSnapshot(
    lab: 'ClosedAI', year: 2026, model: 'GPT-ish-6 Astral',
    trainingFlops: 9.4e26, postTrainingBonus: 240, rating: 1626,
    users: 1.2e9, gpus: 2700000, // 1.2B WAU, Nov 2026
    quip: 'Trained on 100k next-gen chips. Has "secured" 10 GW it hasn\'t '
        'built yet.',
  ),
];
