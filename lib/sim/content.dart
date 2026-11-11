// Static game content: grid tiles and rooms, power tiers, upgrades, launch stunts, rivals.
// Pure Dart — no Flutter imports. All balance knobs live here or in balance.dart.

/// The six eras, one new room each (garage → gigawatt site). Order matters:
/// saves store the name, gates and unlocks use the index.
enum Era { garage, startup, smallLab, mediumLab, bigLab, globalLab }

extension EraInfo on Era {
  String get label => switch (this) {
    Era.garage => 'Parents\' garage',
    Era.startup => 'Startup',
    Era.smallLab => 'Small lab',
    Era.mediumLab => 'Medium lab',
    Era.bigLab => 'Big lab',
    Era.globalLab => 'Frontier lab',
  };

  /// Short form for tight spots (HUD tag).
  String get shortLabel => switch (this) {
    Era.garage => 'Garage',
    _ => label,
  };

  /// Roughly the years of AI history this era covers (flavour only).
  String get years => switch (this) {
    Era.garage => '2017',
    Era.startup => '2018–19',
    Era.smallLab => '2020–22',
    Era.mediumLab => '2023',
    Era.bigLab => '2023–25',
    Era.globalLab => '2025–26',
  };

  /// Training-run lengths the UI offers in this era (real seconds). Short
  /// runs early; late runs take hours so one finishes while you're away.
  List<double> get runDurations => switch (this) {
    Era.garage => const [60, 180, 600],
    Era.startup => const [180, 600, 1800],
    Era.smallLab => const [600, 1800, 3600],
    Era.mediumLab => const [1800, 3600, 3 * 3600],
    Era.bigLab => const [3600, 3 * 3600, 6 * 3600],
    Era.globalLab => const [2 * 3600, 4 * 3600, 8 * 3600],
  };

  /// Seconds of GPU work per real second for runs started in this era. Time
  /// compression eases off as the lab grows: in the garage one real minute
  /// is a day of compute; at the frontier one real hour is 1.5 days. So the
  /// longest run of every era is 2–4 weeks of compute on that era's cluster,
  /// and a bigger cluster, not a longer wait, is what makes a better model.
  double get computeTimeScale => switch (this) {
    Era.garage => 1440, // 1 min = 1 day
    Era.startup => 1440,
    Era.smallLab => 480, // 1 h = 20 days
    Era.mediumLab => 180, // 1 h = 7.5 days
    Era.bigLab => 72, // 1 h = 3 days
    Era.globalLab => 36, // 8 h = 12 days
  };
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
  final double
  utilizationAdd; // + to MFU (fraction of peak FLOPS actually used)
  final double
  trainEffMult; // algorithmic efficiency: effective training compute
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

  /// First era the stunt is offered in.
  final Era era;

  const LaunchStunt({
    required this.id,
    required this.name,
    required this.blurb,
    this.era = Era.garage,
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

  /// The era this rival belongs to: it can't be beaten before you reach it.
  final Era era;

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
    this.era = Era.garage,
  });

  /// Stable id derived from the lab name (matches the UI's rival logo slug).
  String get labId => lab.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_');
}

// ---------------------------------------------------------------------------
// Grid tiles (see docs/GRID.md). Every tile is 1×1 and lives in a room's grid.
// A GPU tile stands for more hardware in bigger rooms (1 GPU → 8-GPU server →
// rack → pod → building), so its numbers are per tile:
//   tflops = per-GPU dense 16-bit TFLOPS × gpusPerTile,
//   powerKw = per-GPU "all-in" kW × gpusPerTile (chip + host + network share).
// Heat and cooling are abstract units on each room's scale: a room removes
// ambientCooling × (its cell count) for free, shared evenly by its GPU tiles;
// a cooler's `cooling` is split evenly among its orthogonally adjacent GPUs.
// Network gpuCap is a GPU count (not tiles): the GPUs that switch keeps fed.
// Each newer GPU tile beats the older ones on TFLOPS/kW, and on TFLOPS/$
// except the deliberately bad gpu_old (cheap up front, worse on everything).
// Ids are save-format keys and art file names: never rename, append only.
// ---------------------------------------------------------------------------

enum TileKind { gpu, cooling, network }

class TileDef {
  final String id;
  final String name;
  final String blurb;
  final TileKind kind;
  final Era era;

  /// Room ids this tile can be placed in.
  final Set<String> rooms;
  final double cost;

  /// Power draw per tile. GPU tiles are scaled by upgrades (Game.powerMult);
  /// cooling and network gear are not.
  final double powerKw;

  // GPU tiles.
  final double tflops;
  final double heat;
  final double gpusPerTile;

  // Cooling tiles: heat removed, split evenly among adjacent GPU tiles.
  final double cooling;

  // Network tiles.
  final double gpuCap;
  final double linkGbps;

  /// Upgrades that must be owned first (e.g. liquid cooling).
  final List<String> requires;

  /// Index into [powerTiers] that must be reached first. 0 = none.
  final int minPowerTier;

  /// GPU supply crunch: each tile of this type you already own makes the
  /// next one this much pricier (0.05 = +5% compounding), up to
  /// maxSupplyPremium × list price. See Game.tilePrice.
  final double priceGrowth;

  const TileDef({
    required this.id,
    required this.name,
    required this.blurb,
    required this.kind,
    required this.era,
    required this.rooms,
    required this.cost,
    required this.powerKw,
    this.tflops = 0,
    this.heat = 0,
    this.gpusPerTile = 0,
    this.cooling = 0,
    this.gpuCap = 0,
    this.linkGbps = 0,
    this.requires = const [],
    this.minPowerTier = 0,
    this.priceGrowth = 0,
  });

  bool get isGpu => kind == TileKind.gpu;
  bool get isCooling => kind == TileKind.cooling;
  bool get isNetwork => kind == TileKind.network;
  double get tflopsPerKw => powerKw <= 0 ? 0 : tflops / powerKw;
}

class RoomDef {
  final String id;
  final String name;
  final String blurb;
  final Era era;
  final int width;
  final int height;
  final double cost;

  /// Heat removed for free per cell of floor space; the room's total
  /// (ambientCooling × width × height) is shared evenly by its GPU tiles.
  final double ambientCooling;

  /// What one GPU tile stands for here, e.g. "8-GPU server".
  final String tileScaleLabel;
  final int minPowerTier;

  const RoomDef({
    required this.id,
    required this.name,
    required this.blurb,
    required this.era,
    required this.width,
    required this.height,
    required this.cost,
    required this.ambientCooling,
    required this.tileScaleLabel,
    this.minPowerTier = 0,
  });

  int get cells => width * height;
  double get ambientTotal => ambientCooling * cells;
}

const _garage = {'garage'};
const _server = {'closet', 'colo'};

const tiles = <TileDef>[
  // --- GPUs ---------------------------------------------------------------
  TileDef(
    id: 'gpu_old',
    name: 'RTX 2060 (used)',
    blurb:
        'Still has RGB. Still has the dust. Early tensor cores and only 6 GB '
        'of VRAM, so it\'s slow at AI math and runs hot. But it\'s cheap!',
    kind: TileKind.gpu,
    era: Era.garage,
    rooms: _garage,
    cost: 900,
    powerKw: 0.35,
    tflops: 30,
    heat: 6,
    gpusPerTile: 1,
  ),
  TileDef(
    id: 'gpu_gamer',
    name: 'RTX 4090',
    blurb:
        'Built for games, decent at matrix math thanks to its tensor '
        'cores. 450 W of hunger, generous with heat.',
    kind: TileKind.gpu,
    era: Era.garage,
    rooms: _garage,
    cost: 2000,
    powerKw: 0.45,
    tflops: 80,
    heat: 4.5,
    gpusPerTile: 1,
  ),
  TileDef(
    id: 'gpu_v_class',
    name: 'Used V100',
    blurb:
        'Retired datacenter card off eBay: first-gen tensor cores, ECC HBM2 '
        'and more math per watt. No fan of its own, so give it airflow.',
    kind: TileKind.gpu,
    era: Era.garage,
    rooms: _garage,
    cost: 3000,
    powerKw: 0.5,
    tflops: 125,
    heat: 5,
    gpusPerTile: 1,
  ),
  TileDef(
    id: 'srv_a_class',
    name: 'DGX A100 (8× A100)',
    blurb:
        '8 A100s in one box, joined by NVLink so they act as one. '
        'The workhorse that trained a generation of models.',
    kind: TileKind.gpu,
    era: Era.startup,
    rooms: _server,
    cost: 50000,
    powerKw: 5.6, // 8 × 0.7
    tflops: 2496, // 8 × 312
    heat: 28,
    gpusPerTile: 8,
    priceGrowth: 0.05,
  ),
  TileDef(
    id: 'srv_h_class',
    name: 'HGX H100 (8× H100)',
    blurb:
        '8 H100s with FP8 tensor cores. Everyone wants one; lead '
        'times are measured in quarters.',
    kind: TileKind.gpu,
    era: Era.smallLab,
    rooms: _server,
    cost: 150000,
    powerKw: 10.4, // 8 × 1.3
    tflops: 7920, // 8 × 990
    heat: 42,
    gpusPerTile: 8,
    minPowerTier: 3, // colo
    priceGrowth: 0.12,
  ),
  TileDef(
    id: 'rack_h_class',
    name: 'H100 rack',
    blurb:
        'Four 8-GPU H100 servers stacked in one rack: 32 GPUs, about '
        '40 kW, and loud enough to need ear defenders.',
    kind: TileKind.gpu,
    era: Era.mediumLab,
    rooms: {'hall'},
    cost: 580000,
    powerKw: 40, // 32 × 1.25 (shared rack power and fans)
    tflops: 31680, // 32 × 990
    heat: 160,
    gpusPerTile: 32,
    minPowerTier: 4,
    priceGrowth: 0.10,
  ),
  TileDef(
    id: 'rack_b_class',
    name: 'GB200 NVL72',
    blurb:
        '72 Blackwell GPUs in one NVLink domain, cooled by liquid. Weighs '
        'about as much as a small car.',
    kind: TileKind.gpu,
    era: Era.mediumLab,
    rooms: {'hall'},
    cost: 2.85e6,
    powerKw: 172.8, // 72 × 2.4
    tflops: 162000, // 72 × 2250
    heat: 260,
    gpusPerTile: 72,
    requires: ['liquid_cooling'],
    minPowerTier: 5, // campus
    priceGrowth: 0.10,
  ),
  TileDef(
    id: 'pod_b_class',
    name: 'B200 SuperPOD',
    blurb:
        'About a thousand Blackwell GPUs: racks, InfiniBand, power and '
        'cooling designed and delivered as one unit.',
    kind: TileKind.gpu,
    era: Era.bigLab,
    rooms: {'campus'},
    cost: 39e6,
    powerKw: 2406.4, // 1024 × 2.35
    tflops: 2304000, // 1024 × 2250
    heat: 600,
    gpusPerTile: 1024,
    requires: ['liquid_cooling'],
    minPowerTier: 5,
    priceGrowth: 0.09,
  ),
  TileDef(
    id: 'rack_r_class',
    name: 'Vera Rubin NVL144',
    blurb:
        '72 Rubin packages (144 GPU dies) per liquid-cooled rack. Your '
        'utility now has your CEO on speed dial.',
    kind: TileKind.gpu,
    era: Era.bigLab,
    rooms: {'hall'},
    cost: 3.9e6,
    powerKw: 244.8, // 72 × 3.4
    tflops: 252000, // 72 × 3500
    heat: 340,
    gpusPerTile: 72,
    requires: ['liquid_cooling'],
    minPowerTier: 6, // power plant deal
    priceGrowth: 0.09,
  ),
  TileDef(
    id: 'pod_r_class',
    name: 'Rubin SuperPOD',
    blurb:
        'About a thousand Rubin GPUs per pod, liquid-cooled. Same floor '
        'space as a B200 SuperPOD, roughly 1.5× the math.',
    kind: TileKind.gpu,
    era: Era.bigLab,
    rooms: {'campus'},
    cost: 54.6e6,
    powerKw: 3430, // 1024 × 3.35
    tflops: 3584000, // 1024 × 3500
    heat: 750,
    gpusPerTile: 1024,
    requires: ['liquid_cooling'],
    minPowerTier: 6, // power plant deal
    priceGrowth: 0.09,
  ),
  TileDef(
    id: 'bldg_r_class',
    name: 'Rubin building',
    blurb:
        'A whole datacenter building: ~8,000 Rubin GPUs and ~27 MW. '
        'The construction crane is basically part of the logo.',
    kind: TileKind.gpu,
    era: Era.globalLab,
    rooms: {'gigasite'},
    cost: 3e8,
    powerKw: 27034, // 8192 × 3.3
    tflops: 28672000, // 8192 × 3500
    heat: 700,
    gpusPerTile: 8192,
    requires: ['liquid_cooling'],
    minPowerTier: 7, // gigawatt campus
    priceGrowth: 0.03,
  ),

  // --- Cooling --------------------------------------------------------------
  TileDef(
    id: 'cool_fan',
    name: 'Box fan',
    blurb:
        'Moves hot air somewhere slightly less important. Weak, but it '
        'barely touches your power budget.',
    kind: TileKind.cooling,
    era: Era.garage,
    rooms: _garage,
    cost: 120,
    powerKw: 0.05,
    cooling: 4,
  ),
  TileDef(
    id: 'cool_window_ac',
    name: 'Window AC',
    blurb:
        'Really pumps heat outside, but the compressor draws as much as two '
        'gaming GPUs. Cooling costs power: hello, PUE.',
    kind: TileKind.cooling,
    era: Era.garage,
    rooms: _garage,
    cost: 500,
    powerKw: 0.9,
    cooling: 10,
  ),
  TileDef(
    id: 'cool_crac',
    name: 'Precision AC (CRAC)',
    blurb:
        'Computer-room air conditioner: cold air up through a raised '
        'floor. Reliable, but chilling air takes a lot of power.',
    kind: TileKind.cooling,
    era: Era.startup,
    rooms: _server,
    cost: 12000,
    powerKw: 3,
    cooling: 40,
  ),
  TileDef(
    id: 'cool_rear_door',
    name: 'Rear-door heat exchanger',
    blurb:
        'A water-cooled radiator on the back of the rack catches the hot '
        'exhaust before it ever reaches the room.',
    kind: TileKind.cooling,
    era: Era.smallLab,
    rooms: _server,
    cost: 40000,
    powerKw: 1.5,
    cooling: 90,
    requires: ['liquid_cooling'],
  ),
  TileDef(
    id: 'cool_chiller',
    name: 'Chiller plant',
    blurb:
        'Industrial chillers making cold water for a whole hall. Strong, '
        'power-hungry, and why the roof is covered in fans.',
    kind: TileKind.cooling,
    era: Era.mediumLab,
    rooms: {'hall', 'campus'},
    cost: 150000,
    powerKw: 40,
    cooling: 300,
  ),
  TileDef(
    id: 'cool_liquid',
    name: 'Direct liquid-cooling loop',
    blurb:
        'Cold plates on every chip with coolant pumped through. Water '
        'carries thousands of times more heat per litre than air.',
    kind: TileKind.cooling,
    era: Era.mediumLab,
    rooms: {'hall', 'campus'},
    cost: 250000,
    powerKw: 10,
    cooling: 450,
    requires: ['liquid_cooling'],
  ),
  TileDef(
    id: 'cool_tower',
    name: 'Cooling tower',
    blurb:
        'Evaporates water to dump heat into the sky. Very efficient per '
        'watt; very thirsty.',
    kind: TileKind.cooling,
    era: Era.bigLab,
    rooms: {'campus', 'gigasite'},
    cost: 4e6,
    powerKw: 200,
    cooling: 1800,
  ),
  TileDef(
    id: 'cool_dry',
    name: 'Closed-loop dry coolers',
    blurb:
        'Acres of fan-blown radiators on a sealed coolant loop: almost no '
        'water used, but the fans draw more power than towers.',
    kind: TileKind.cooling,
    era: Era.globalLab,
    rooms: {'gigasite'},
    cost: 9e6,
    powerKw: 450,
    cooling: 3000,
  ),

  // --- Network ----------------------------------------------------------------
  TileDef(
    id: 'net_home',
    name: 'Home router',
    blurb:
        '1 GbE ports and a blinking light. Fine for 2–4 GPUs; any more '
        'and they mostly wait on each other.',
    kind: TileKind.network,
    era: Era.garage,
    rooms: _garage,
    cost: 150,
    powerKw: 0.01,
    gpuCap: 4,
    linkGbps: 1,
  ),
  TileDef(
    id: 'net_5g',
    name: '5 Gbit switch',
    blurb:
        'A small unmanaged switch. Enough bandwidth to keep about 8 GPUs '
        'fed during training.',
    kind: TileKind.network,
    era: Era.garage,
    rooms: _garage,
    cost: 600,
    powerKw: 0.02,
    gpuCap: 8,
    linkGbps: 5,
  ),
  TileDef(
    id: 'net_10g',
    name: '10 GbE switch',
    blurb:
        'Prosumer 10 Gigabit Ethernet. Keeps about 32 GPUs fed before '
        'the gradient sync clogs the pipe.',
    kind: TileKind.network,
    era: Era.garage,
    rooms: {'garage', 'closet', 'colo'},
    cost: 2500,
    powerKw: 0.05,
    gpuCap: 32,
    linkGbps: 10,
  ),
  TileDef(
    id: 'net_100g',
    name: '100G Ethernet',
    blurb:
        '100 Gbit/s top-of-rack switch with RDMA (RoCE): GPUs write '
        'straight into each other\'s memory. Feeds ~256 GPUs.',
    kind: TileKind.network,
    era: Era.startup,
    rooms: {'closet', 'colo', 'hall'},
    cost: 20000,
    powerKw: 0.5,
    gpuCap: 256,
    linkGbps: 100,
  ),
  TileDef(
    id: 'net_ib',
    name: 'InfiniBand NDR 400G',
    blurb:
        '400 Gbit/s ports, RDMA and microsecond latency: the classic '
        'AI-cluster fabric. Scales to thousands of GPUs.',
    kind: TileKind.network,
    era: Era.smallLab,
    rooms: {'closet', 'colo', 'hall', 'campus'},
    cost: 60000,
    powerKw: 1,
    gpuCap: 4096,
    linkGbps: 400,
    requires: ['interconnect'],
  ),
  TileDef(
    id: 'net_ib_spine',
    name: 'InfiniBand spine',
    blurb:
        'A second switch layer above the leaf switches (a fat tree), so '
        'tens of thousands of GPUs get full bandwidth.',
    kind: TileKind.network,
    era: Era.mediumLab,
    rooms: {'hall', 'campus'},
    cost: 1e6,
    powerKw: 10,
    gpuCap: 32768,
    linkGbps: 800,
    requires: ['interconnect'],
  ),
  TileDef(
    id: 'net_nvlink',
    name: 'NVLink fabric',
    blurb:
        'Terabytes per second between GPUs inside each rack, plus a fast '
        'scale-out network between racks. ~131k GPUs.',
    kind: TileKind.network,
    era: Era.bigLab,
    rooms: {'hall', 'campus', 'gigasite'},
    cost: 5e6,
    powerKw: 30,
    gpuCap: 131072,
    linkGbps: 14400,
  ),
  TileDef(
    id: 'net_optical',
    name: 'Optical fabric',
    blurb:
        'Optical circuit switches and co-packaged optics: light instead of '
        'copper, so millions of GPUs can train as one.',
    kind: TileKind.network,
    era: Era.globalLab,
    rooms: {'campus', 'gigasite'},
    cost: 30e6,
    powerKw: 100,
    gpuCap: 4194304,
    linkGbps: 1600,
    requires: ['parallelism'],
  ),
];

const rooms = <RoomDef>[
  RoomDef(
    id: 'garage',
    name: 'Garage',
    blurb: 'One outlet, one GPU and a dream. Mind the car.',
    era: Era.garage,
    width: 4,
    height: 4,
    cost: 0,
    ambientCooling: 1,
    tileScaleLabel: '1 GPU',
  ),
  RoomDef(
    id: 'closet',
    name: 'Server closet',
    blurb:
        'A converted supply closet at the office. The door stays open '
        'for "airflow".',
    era: Era.startup,
    width: 6,
    height: 6,
    cost: 15000,
    ambientCooling: 4,
    tileScaleLabel: '8-GPU server',
    minPowerTier: 2, // office
  ),
  RoomDef(
    id: 'colo',
    name: 'Colocation cage',
    blurb:
        'Your own fenced-off corner of someone else\'s datacenter, with '
        'proper cold aisles.',
    era: Era.smallLab,
    width: 8,
    height: 8,
    cost: 2e6,
    ambientCooling: 8,
    tileScaleLabel: '8-GPU server',
    minPowerTier: 3, // colo
  ),
  RoomDef(
    id: 'hall',
    name: 'Datacenter hall',
    blurb:
        'A whole hall of racks with its own chillers. Every tile here is '
        'a rack.',
    era: Era.mediumLab,
    width: 12,
    height: 12,
    cost: 3e6,
    ambientCooling: 30,
    tileScaleLabel: 'rack (32–72 GPUs)',
    minPowerTier: 4, // hall
  ),
  RoomDef(
    id: 'campus',
    name: 'Datacenter campus',
    blurb:
        'Several halls and a substation. Every tile is a pod of about a '
        'thousand GPUs.',
    era: Era.bigLab,
    width: 12,
    height: 12,
    cost: 30e6,
    ambientCooling: 60,
    tileScaleLabel: 'pod (~1k GPUs)',
    minPowerTier: 5, // campus
  ),
  RoomDef(
    id: 'gigasite',
    name: 'Gigawatt site',
    blurb:
        'Buildings in a field next to a power plant. Every tile is a '
        'whole building of ~8k GPUs.',
    era: Era.globalLab,
    width: 12,
    height: 12,
    cost: 4e8,
    ambientCooling: 100,
    tileScaleLabel: 'building (~8k GPUs)',
    minPowerTier: 7, // gigawatt campus
  ),
];

final Map<String, TileDef> _tileById = {for (final t in tiles) t.id: t};
final Map<String, RoomDef> _roomById = {for (final r in rooms) r.id: r};

/// Null for unknown ids (e.g. from a newer or corrupted save).
TileDef? tileById(String id) => _tileById[id];
RoomDef? roomById(String id) => _roomById[id];

// ---------------------------------------------------------------------------
// Power tiers. Each one replaces the previous cap; the cap is global across
// all rooms (GPU, cooling and network tiles all draw from it).
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
    cost: 60000,
  ),
  PowerDef(
    id: 'colo',
    name: 'Colocation cage',
    blurb: 'Rented racks in someone else\'s datacenter, with real cooling.',
    era: Era.smallLab,
    capacityKw: 500,
    cost: 1e6,
  ),
  PowerDef(
    id: 'hall',
    name: 'Datacenter hall',
    blurb: 'Your own hall, your own chillers.',
    era: Era.mediumLab,
    capacityKw: 2000,
    cost: 4e6,
  ),
  PowerDef(
    id: 'campus',
    name: 'Datacenter campus',
    blurb: 'Several halls and a substation.',
    era: Era.mediumLab,
    capacityKw: 20000,
    cost: 12e6,
  ),
  PowerDef(
    id: 'plant',
    name: 'Dedicated power plant deal',
    blurb: 'You now have opinions about grid interconnect queues.',
    era: Era.bigLab,
    capacityKw: 300000,
    cost: 250e6,
  ),
  PowerDef(
    id: 'gw_campus',
    name: 'Gigawatt campus',
    blurb:
        'A small city\'s worth of electricity, turned into matrix '
        'multiplies and heat.',
    era: Era.globalLab,
    capacityKw: 1e6,
    cost: 6e8,
  ),
  PowerDef(
    id: 'nuclear_restart',
    name: 'Restarted nuclear plant',
    blurb:
        'A 20-year deal to bring a mothballed reactor back online. Plus '
        'some gas turbines nobody mentions.',
    era: Era.globalLab,
    capacityKw: 2e6,
    cost: 2e9,
  ),
  PowerDef(
    id: 'multi_site',
    name: 'Multi-site cluster',
    blurb:
        'Several gigawatt campuses training one model over long-haul '
        'fiber.',
    era: Era.globalLab,
    capacityKw: 4e6,
    cost: 5e9,
  ),
];

// ---------------------------------------------------------------------------
// Upgrades: software (efficiency), data (data budget), research (model quality).
// Blurbs must stay technically accurate — have an ML engineer review them.
// ---------------------------------------------------------------------------
const upgrades = <UpgradeDef>[
  // --- Parents' garage -------------------------------------------------------
  UpgradeDef(
    id: 'mixed_precision',
    name: 'Mixed precision (FP16)',
    blurb:
        'Do most math in 16-bit on tensor cores, keeping 32-bit master '
        'weights: several times the throughput, nearly the same accuracy.',
    category: UpgradeCategory.software,
    era: Era.garage,
    cost: 800,
    effects: Effects(utilizationAdd: 0.08),
  ),
  UpgradeDef(
    id: 'batching',
    name: 'Request batching',
    blurb:
        'Serve many users\' requests together, so the weights are read '
        'from memory once per step for the whole batch.',
    category: UpgradeCategory.software,
    era: Era.garage,
    cost: 1200,
    effects: Effects(serveEffMult: 2),
  ),
  UpgradeDef(
    id: 'kv_cache',
    name: 'KV cache',
    blurb:
        'Keep the attention keys and values of earlier tokens, so each new '
        'token doesn\'t recompute the whole prompt.',
    category: UpgradeCategory.software,
    era: Era.garage,
    cost: 2500,
    effects: Effects(serveEffMult: 1.5),
  ),
  UpgradeDef(
    id: 'lora',
    name: 'LoRA fine-tuning',
    blurb:
        'Freeze the model and train small low-rank adapters instead: a '
        'fraction of the memory, so you can fine-tune on modest GPUs.',
    category: UpgradeCategory.research,
    era: Era.garage,
    cost: 2000,
    effects: Effects(trainEffMult: 1.3),
  ),
  UpgradeDef(
    id: 'common_crawl',
    name: 'Filtered web crawl',
    blurb:
        'Scrape and filter a big slice of the public web. More tokens = '
        'you can usefully spend more compute.',
    category: UpgradeCategory.data,
    era: Era.garage,
    cost: 3000,
    effects: Effects(dataMult: 50),
  ),
  // --- Startup ---------------------------------------------------------------
  UpgradeDef(
    id: 'cuda_kernels',
    name: 'Custom CUDA kernels',
    blurb:
        'Fuse and hand-tune GPU code for the hottest operations instead '
        'of chaining many generic library calls.',
    category: UpgradeCategory.software,
    era: Era.startup,
    cost: 234000,
    effects: Effects(utilizationAdd: 0.10),
  ),
  UpgradeDef(
    id: 'quantization',
    name: 'Quantization (INT8/INT4)',
    blurb:
        'Store weights in 8 or 4 bits instead of 16: a 2–4× smaller model '
        'that serves faster, usually with little quality loss.',
    category: UpgradeCategory.software,
    era: Era.startup,
    cost: 292500,
    effects: Effects(serveEffMult: 2),
  ),
  UpgradeDef(
    id: 'code_data',
    name: 'Public code dataset',
    blurb:
        'Train on open-source code. It helps with programming and seems '
        'to help structured reasoning too.',
    category: UpgradeCategory.data,
    era: Era.startup,
    cost: 390000,
    effects: Effects(dataMult: 3, ratingAdd: 10),
  ),
  UpgradeDef(
    id: 'dedup',
    name: 'Deduplication & quality filters',
    blurb:
        'Remove duplicate and junk documents. Cleaner data trains a better '
        'model with the same compute.',
    category: UpgradeCategory.data,
    era: Era.startup,
    cost: 585000,
    effects: Effects(trainEffMult: 1.5),
  ),
  UpgradeDef(
    id: 'data_mixture',
    name: 'Data mixture optimisation',
    blurb:
        'Tune the ratio of web, code, books and math using small proxy '
        'runs: same compute, better model.',
    category: UpgradeCategory.data,
    era: Era.startup,
    cost: 1.5e6,
    effects: Effects(trainEffMult: 1.3),
    requires: ['dedup'],
  ),
  UpgradeDef(
    id: 'instruction_tuning',
    name: 'Instruction tuning',
    blurb:
        'Fine-tune on question/answer examples, so the model follows '
        'instructions instead of just continuing text.',
    category: UpgradeCategory.research,
    era: Era.startup,
    cost: 390000,
    effects: Effects(ratingAdd: 25),
  ),
  // --- Small lab -------------------------------------------------------------
  UpgradeDef(
    id: 'flash_attention',
    name: 'FlashAttention',
    blurb:
        'Compute exact attention in tiles that fit in fast on-chip memory, '
        'avoiding slow round-trips to GPU RAM.',
    category: UpgradeCategory.software,
    era: Era.smallLab,
    cost: 2.5e+06,
    effects: Effects(utilizationAdd: 0.07, trainEffMult: 1.1),
    requires: ['cuda_kernels'],
  ),
  UpgradeDef(
    id: 'interconnect',
    name: 'High-speed interconnect',
    blurb:
        'Fast links between machines so a thousand GPUs can act like one '
        'instead of waiting on each other.',
    category: UpgradeCategory.software,
    era: Era.smallLab,
    cost: 4.2e+06,
    effects: Effects(utilizationAdd: 0.05),
  ),
  UpgradeDef(
    id: 'liquid_cooling',
    name: 'Liquid cooling',
    blurb:
        'Pipe coolant straight to the chips. Less energy wasted on fans '
        'and air conditioning, and denser racks.',
    category: UpgradeCategory.software,
    era: Era.smallLab,
    cost: 6.7e+06,
    effects: Effects(powerMult: 0.85),
  ),
  UpgradeDef(
    id: 'books_papers',
    name: 'Books & papers corpus',
    blurb:
        'Add digitised books, scientific papers and encyclopedias: dense, '
        'well-edited text the web crawl is short on. Twice the tokens.',
    category: UpgradeCategory.data,
    era: Era.smallLab,
    cost: 2e7,
    effects: Effects(dataMult: 2),
  ),
  UpgradeDef(
    id: 'chinchilla_scaling',
    name: 'Compute-optimal scaling',
    blurb:
        'Fit scaling laws, then train a smaller model on more tokens (about '
        '20 per parameter): a better model for the same compute.',
    category: UpgradeCategory.research,
    era: Era.smallLab,
    cost: 8.3e+06,
    effects: Effects(trainEffMult: 1.3),
  ),
  UpgradeDef(
    id: 'zero_sharding',
    name: 'FSDP / ZeRO sharding',
    blurb:
        'Shard weights, gradients and optimizer state across data-parallel '
        'GPUs instead of copying them: far bigger models fit in memory.',
    category: UpgradeCategory.software,
    era: Era.smallLab,
    cost: 1.2e+07,
    effects: Effects(utilizationAdd: 0.04, trainEffMult: 1.1),
  ),
  // --- Medium lab ------------------------------------------------------------
  UpgradeDef(
    id: 'moe',
    name: 'Mixture of Experts',
    blurb:
        'Many "expert" sub-networks with a router that sends each token to '
        'only a few: more parameters for the same compute per token.',
    category: UpgradeCategory.research,
    era: Era.mediumLab,
    cost: 7.5e+07,
    effects: Effects(trainEffMult: 2.5, serveEffMult: 1.5),
  ),
  UpgradeDef(
    id: 'rlhf',
    name: 'RLHF',
    blurb:
        'Humans rank answers, a reward model learns their preferences, and '
        'the model is trained to score well on it.',
    category: UpgradeCategory.research,
    era: Era.mediumLab,
    cost: 1e+08,
    effects: Effects(ratingAdd: 35, arpuMult: 1.2),
    requires: ['instruction_tuning'],
  ),
  UpgradeDef(
    id: 'parallelism',
    name: '3D parallelism',
    blurb:
        'Split the model across GPUs three ways (data, tensor, pipeline) '
        'so huge models fit and GPUs stay busy.',
    category: UpgradeCategory.software,
    era: Era.mediumLab,
    cost: 1.25e+08,
    effects: Effects(utilizationAdd: 0.05, trainEffMult: 1.2),
    requires: ['interconnect'],
  ),
  UpgradeDef(
    id: 'distillation',
    name: 'Distillation',
    blurb:
        'Train a small "student" model to imitate the big one, then serve '
        'the cheap student to most users.',
    category: UpgradeCategory.software,
    era: Era.mediumLab,
    cost: 1.5e+08,
    effects: Effects(serveEffMult: 3),
  ),
  UpgradeDef(
    id: 'paged_attention',
    name: 'Paged KV cache',
    blurb:
        'Store the KV cache in small fixed-size pages, like virtual memory: '
        'no fragmentation, so far more requests fit in each batch.',
    category: UpgradeCategory.software,
    era: Era.mediumLab,
    cost: 1.25e+08,
    effects: Effects(serveEffMult: 2.4),
    requires: ['kv_cache'],
  ),
  UpgradeDef(
    id: 'licensed_data',
    name: 'Licensed data deals',
    blurb:
        'Pay publishers, forums and archives for books, news and Q&A you '
        'can\'t (or shouldn\'t) scrape: trillions of fresh tokens.',
    category: UpgradeCategory.data,
    era: Era.mediumLab,
    cost: 8e6,
    effects: Effects(dataMult: 16),
  ),
  // --- Big lab ---------------------------------------------------------------
  UpgradeDef(
    id: 'fp8',
    name: 'FP8 training',
    blurb:
        'Run most matrix multiplies in 8-bit floats with careful scaling: '
        'up to twice the peak math of 16-bit on chips that support it.',
    category: UpgradeCategory.software,
    era: Era.bigLab,
    cost: 3e8,
    effects: Effects(utilizationAdd: 0.06),
  ),
  UpgradeDef(
    id: 'speculative',
    name: 'Speculative decoding',
    blurb:
        'A tiny model drafts several tokens; the big model checks them all '
        'in one pass and keeps the ones it agrees with.',
    category: UpgradeCategory.software,
    era: Era.bigLab,
    cost: 2.25e+09,
    effects: Effects(serveEffMult: 1.8),
  ),
  UpgradeDef(
    id: 'synthetic_data',
    name: 'Synthetic data',
    blurb:
        'Have your models generate and grade new training data. Useful '
        'once you run low on fresh human text.',
    category: UpgradeCategory.data,
    era: Era.bigLab,
    cost: 3e+09,
    effects: Effects(dataMult: 4),
  ),
  UpgradeDef(
    id: 'rlaif',
    name: 'AI feedback (RLAIF)',
    blurb:
        'Use a model, guided by written principles, to grade answers: '
        'feedback that scales beyond what humans can label.',
    category: UpgradeCategory.research,
    era: Era.bigLab,
    cost: 1e9,
    effects: Effects(ratingAdd: 20),
    requires: ['rlhf'],
  ),
  UpgradeDef(
    id: 'long_context',
    name: 'Long context (ring attention)',
    blurb:
        'Shard very long sequences across GPUs that pass key/value blocks '
        'around a ring, so whole codebases fit in one prompt.',
    category: UpgradeCategory.research,
    era: Era.bigLab,
    cost: 1.5e9,
    effects: Effects(ratingAdd: 10, arpuMult: 1.25),
    requires: ['parallelism'],
  ),
  UpgradeDef(
    id: 'reasoning',
    name: 'Reasoning (RL on chain of thought)',
    blurb:
        'Reward correct final answers with RL so the model learns to think '
        'at length first. Much smarter, but answers cost many more tokens.',
    category: UpgradeCategory.research,
    era: Era.bigLab,
    cost: 2.5e9,
    effects: Effects(ratingAdd: 60, serveEffMult: 0.6),
    requires: ['rlhf'],
  ),
  // --- Frontier lab ----------------------------------------------------------
  UpgradeDef(
    id: 'multi_token_prediction',
    name: 'Multi-token prediction',
    blurb:
        'Train extra heads to predict several upcoming tokens: a denser '
        'training signal, and free draft tokens for faster decoding.',
    category: UpgradeCategory.research,
    era: Era.globalLab,
    cost: 6e9,
    effects: Effects(trainEffMult: 1.15, serveEffMult: 1.2),
  ),
  UpgradeDef(
    id: 'human_expert_data',
    name: 'Expert data (PhD annotators)',
    blurb:
        'Pay domain experts to write and grade hard problems. Few tokens, '
        'big gains on exactly the questions users care about.',
    category: UpgradeCategory.data,
    era: Era.globalLab,
    cost: 7e9,
    effects: Effects(ratingAdd: 20, arpuMult: 1.1),
    requires: ['rlhf'],
  ),
  UpgradeDef(
    id: 'test_time_compute',
    name: 'Test-time compute scaling',
    blurb:
        'Let the model spend more thinking tokens on hard questions; '
        'accuracy keeps climbing with inference compute.',
    category: UpgradeCategory.research,
    era: Era.globalLab,
    cost: 28e9,
    effects: Effects(ratingAdd: 35, serveEffMult: 0.7),
    requires: ['reasoning'],
  ),
  UpgradeDef(
    id: 'agentic_rl',
    name: 'Agentic RL environments',
    blurb:
        'RL in sandboxes with real tools (code, browsers, terminals), '
        'rewarding the model for finishing multi-step tasks.',
    category: UpgradeCategory.research,
    era: Era.globalLab,
    cost: 35e9,
    effects: Effects(ratingAdd: 35, arpuMult: 1.2),
    requires: ['reasoning'],
  ),
  UpgradeDef(
    id: 'disaggregated_serving',
    name: 'Prefill/decode disaggregation',
    blurb:
        'Run prompt processing (compute-bound) and token generation '
        '(memory-bound) on separate GPU pools, each tuned for its job.',
    category: UpgradeCategory.software,
    era: Era.globalLab,
    cost: 10e9,
    effects: Effects(serveEffMult: 1.4),
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
  LaunchStunt(
    id: 'arena_drop',
    name: 'Mystery model on the arena',
    blurb: 'Ship it anonymously to a public leaderboard. Let people guess.',
    era: Era.smallLab,
    successChance: 0.8,
    hypeOnSuccess: 2.0,
    hypeOnFail: 1.2,
  ),
  LaunchStunt(
    id: 'keynote',
    name: 'Livestreamed keynote',
    blurb: 'Turtleneck, big screen, a demo that was rehearsed 40 times.',
    era: Era.bigLab,
    costFraction: 0.05,
    successChance: 0.9,
    hypeOnSuccess: 2.6,
    hypeOnFail: 0.9,
  ),
  LaunchStunt(
    id: 'big_game_ad',
    name: 'Big-game TV ad',
    blurb: 'Thirty seconds between the touchdowns. Your mum finally gets it.',
    era: Era.globalLab,
    costFraction: 0.08,
    hypeOnSuccess: 2.8,
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
    lab: 'Hugging Hands Collective',
    year: 2017,
    model: 'Tiny-Transformer',
    trainingFlops: 7e18,
    rating: 765,
    users: 1e3,
    gpus: 1, // users interp.
    quip: 'Uploads a model card with more emoji than parameters.',
  ),
  RivalSnapshot(
    lab: 'ClosedAI',
    year: 2018,
    model: 'GPT-ish-1',
    trainingFlops: 1.8e19,
    rating: 796,
    users: 3e3,
    gpus: 1, // users interp.
    quip: 'Pre-trains on 7,000 unpublished novels, just to see what happens.',
  ),
  RivalSnapshot(
    lab: 'Gogol DeepThought',
    era: Era.startup,
    year: 2018,
    model: 'BURT-Large',
    // FLOPs: Epoch DB (~2.9e20), not in the research table.
    trainingFlops: 2.9e20,
    rating: 888,
    users: 1e4,
    gpus: 3, // users interp.
    quip: 'Hides 15% of every sentence and calls it [MASK]ed learning.',
  ),
  RivalSnapshot(
    lab: 'ClosedAI',
    era: Era.startup,
    year: 2019,
    model: 'GPT-ish-2',
    trainingFlops: 1.9e21,
    rating: 950,
    users: 3e4,
    gpus: 30, // users interp.
    quip: 'Too dangerous to release. Releases it nine months later.',
  ),
  RivalSnapshot(
    lab: 'Gogol DeepThought',
    era: Era.smallLab,
    year: 2020,
    model: 'Meenie',
    trainingFlops: 1.1e23,
    rating: 1085,
    users: 1e5,
    gpus: 130, // users interp.
    quip: 'A chatbot so good that nobody outside the company may talk to it.',
  ),
  RivalSnapshot(
    lab: 'ClosedAI',
    era: Era.smallLab,
    year: 2020,
    model: 'GPT-ish-3',
    trainingFlops: 3.1e23,
    rating: 1120,
    users: 3e5,
    gpus: 1300, // users interp.
    quip:
        '175B parameters, an API waitlist and a thousand threads about '
        '"few-shot".',
  ),
  RivalSnapshot(
    lab: 'Mistrawl',
    era: Era.mediumLab,
    year: 2023,
    model: 'Mixtrawl 8x7B',
    trainingFlops: 7.7e23,
    postTrainingBonus: 60,
    rating: 1210,
    users: 3e6,
    gpus: 1500, // users + gpus interp.
    quip: 'Launch event: a torrent magnet link and zero explanation.',
  ),
  RivalSnapshot(
    lab: 'ClosedAI',
    era: Era.mediumLab,
    year: 2023,
    model: 'ChatGPT-ish',
    trainingFlops: 2.6e24,
    postTrainingBonus: 70,
    rating: 1260,
    users: 1e8,
    gpus: 7900, // 100M MAU, Jan 2023
    quip: 'Releases a "research preview" that 100M people use as a product.',
  ),
  RivalSnapshot(
    lab: 'ClosedAI',
    era: Era.bigLab,
    year: 2023,
    model: 'GPT-ish-4',
    trainingFlops: 2.1e25,
    postTrainingBonus: 80,
    rating: 1339,
    users: 1e8,
    gpus: 30000, // 100M WAU, Nov 2023
    quip: 'A 100-page technical report. Parameter count: "no comment".',
  ),
  RivalSnapshot(
    lab: 'Anthropomorphic',
    era: Era.bigLab,
    year: 2024,
    model: 'Claudette 3.5 Sonata',
    trainingFlops: 2.7e25,
    postTrainingBonus: 105,
    rating: 1373,
    users: 5e7,
    gpus: 200000, // users + gpus interp. (never published)
    quip:
        'Left to build it more safely. Ships the model every coder quietly '
        'switches to.',
  ),
  RivalSnapshot(
    lab: 'DeepSleep',
    era: Era.bigLab,
    year: 2025,
    model: 'DeepSleep-R1',
    trainingFlops: 3.3e24,
    postTrainingBonus: 180,
    rating: 1378,
    users: 9.7e7,
    gpus: 50000, // ~97M MAU, Apr 2025
    quip:
        'Near-frontier for "\$5.6M" (final run only, see footnote). Chip '
        'stocks have a bad day.',
  ),
  RivalSnapshot(
    lab: 'Anthropomorphic',
    era: Era.bigLab,
    year: 2025,
    model: 'Claudette 3.7 Sonata',
    trainingFlops: 3.4e25,
    postTrainingBonus: 180,
    rating: 1455,
    users: 1e8,
    gpus: 400000, // users interp. (never published)
    quip: 'Barely any consumers. Writes half of everyone\'s code anyway.',
  ),
  RivalSnapshot(
    lab: 'ClosedAI',
    era: Era.bigLab,
    year: 2025,
    model: 'o-three',
    trainingFlops: 5e25,
    flopsInterpolated: true,
    postTrainingBonus: 175,
    rating: 1463,
    users: 4e8,
    gpus: 500000, // 400M WAU, Feb 2025
    quip: 'Thinks for a minute before answering. Bills you for every thought.',
  ),
  RivalSnapshot(
    lab: 'yAI',
    era: Era.bigLab,
    year: 2025,
    model: 'Grokk 3',
    trainingFlops: 3.5e26,
    postTrainingBonus: 150,
    rating: 1503,
    users: 6.4e7,
    gpus: 200000, // 64M MAU, Sep 2025
    quip: 'Built a 100k-GPU cluster in 122 days. Launch date: "two weeks".',
  ),
  RivalSnapshot(
    lab: 'ClosedAI',
    era: Era.bigLab,
    year: 2025,
    model: 'GPT-ish-4.5',
    trainingFlops: 3.8e26,
    postTrainingBonus: 150,
    rating: 1506,
    users: 5e8,
    gpus: 600000, // 500M WAU, end Mar 2025
    quip:
        'The biggest pre-training run yet. Reviews: "warm vibes". '
        'API price: also warm.',
  ),
  RivalSnapshot(
    lab: 'ClosedAI',
    era: Era.globalLab,
    year: 2025,
    model: 'GPT-ish-5',
    trainingFlops: 6.6e25,
    postTrainingBonus: 215,
    rating: 1512,
    users: 8e8,
    gpus: 900000, // 800M WAU, Oct 2025
    quip: 'A router picks which model answers you. The router is the product.',
  ),
  RivalSnapshot(
    lab: 'Gogol DeepThought',
    era: Era.globalLab,
    year: 2025,
    model: 'Gemeni 3 Pro',
    trainingFlops: 6e26,
    flopsInterpolated: true,
    postTrainingBonus: 200,
    rating: 1571,
    users: 6.5e8,
    gpus: 1700000, // 650M MAU, Oct 2025
    quip: 'Owns the most chips on Earth. Still says "coming soon" a lot.',
  ),
  RivalSnapshot(
    lab: 'MetaMind Labs',
    era: Era.globalLab,
    year: 2026,
    model: 'Amused Spark',
    trainingFlops: 5e26,
    flopsInterpolated: true,
    postTrainingBonus: 215,
    rating: 1580,
    users: 1e9,
    gpus: 2600000, // 1B MAU across apps (2025)
    quip:
        'Gave the weights away for three years, then closed them. Capex: '
        'yes.',
  ),
  RivalSnapshot(
    lab: 'ClosedAI',
    era: Era.globalLab,
    year: 2026,
    model: 'GPT-ish-5.5 "Tater"',
    trainingFlops: 6e26,
    flopsInterpolated: true,
    postTrainingBonus: 225,
    rating: 1596,
    users: 9e8,
    gpus: 2000000, // 900M WAU, Feb 2026
    quip: 'Codename: a potato. Benchmarks: not a potato.',
  ),
  RivalSnapshot(
    lab: 'Anthropomorphic',
    era: Era.globalLab,
    year: 2026,
    model: 'Claudette Parable 5',
    trainingFlops: 1e27,
    flopsInterpolated: true,
    postTrainingBonus: 230,
    rating: 1618,
    users: 2.45e8,
    gpus: 1400000, // ~245M MAU est.
    quip:
        'Rents compute from three clouds and a rival\'s supercomputer. '
        'Revenue chart goes vertical.',
  ),
  RivalSnapshot(
    lab: 'Gogol DeepThought',
    era: Era.globalLab,
    year: 2026,
    model: 'Gemeni 4 Xenon',
    trainingFlops: 9e26,
    flopsInterpolated: true,
    postTrainingBonus: 238,
    rating: 1622,
    users: 1e9,
    gpus: 3700000, // >1B MAU, Aug 2026
    quip: 'Wins 12 of 18 benchmarks. Benchmarks chosen by: Gogol.',
  ),
  RivalSnapshot(
    lab: 'ClosedAI',
    era: Era.globalLab,
    year: 2026,
    model: 'GPT-ish-6 Astral',
    trainingFlops: 9.4e26,
    postTrainingBonus: 240,
    rating: 1626,
    users: 1.2e9,
    gpus: 2700000, // 1.2B WAU, Nov 2026
    quip:
        'Trained on 100k next-gen chips. Has "secured" 10 GW it hasn\'t '
        'built yet.',
  ),
];
