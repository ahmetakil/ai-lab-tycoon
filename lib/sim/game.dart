import 'dart:math' as math;

import 'balance.dart';
import 'content.dart';
import 'game_state.dart';
import 'grid.dart';
import 'model_design.dart';
import 'news.dart';
import 'reviews.dart';
import 'run_phases.dart';

export 'grid.dart' show TileStatus, Cluster, minThrottleSpeed;

/// One planned (not yet bought) tile in the current room: place [tileId]
/// on the empty cell (x, y), or with [replace], swap the tile there for it.
class PlannedTile {
  final int x, y;
  final String tileId;
  final bool replace;
  const PlannedTile(this.x, this.y, this.tileId, {this.replace = false});

  @override
  bool operator ==(Object other) =>
      other is PlannedTile &&
      other.x == x &&
      other.y == y &&
      other.tileId == tileId &&
      other.replace == replace;

  @override
  int get hashCode => Object.hash(x, y, tileId, replace);

  @override
  String toString() => '${replace ? 'swap' : 'place'} $tileId at ($x, $y)';
}

/// Transient notifications for the UI (not saved).
sealed class GameEvent {
  const GameEvent();
}

class EraUnlocked extends GameEvent {
  final Era era;
  const EraUnlocked(this.era);
}

class RivalBeaten extends GameEvent {
  final RivalSnapshot rival;
  const RivalBeaten(this.rival);
}

class ViralSpikeStarted extends GameEvent {
  const ViralSpikeStarted();
}

class TrainingFinished extends GameEvent {
  final double effectiveCompute;
  final double predictedRating;

  /// Design risks that fired, e.g. "Router collapse: ...".
  final List<String> mishaps;
  const TrainingFinished(this.effectiveCompute, this.predictedRating, [this.mishaps = const []]);
}

/// You moved to the next room; every tile came along, shifted by [offset]
/// (cells) so the old layout sits centred in the bigger floor.
class RoomMoved extends GameEvent {
  final RoomDef from;
  final RoomDef to;
  final (int, int) offset;
  const RoomMoved(this.from, this.to, this.offset);
}

class ModelReleased extends GameEvent {
  final ModelRelease release;
  final LaunchStunt stunt;
  final bool stuntSucceeded;
  const ModelReleased(this.release, this.stunt, this.stuntSucceeded);
}

/// What the next era asks for, for the UI ("Next: Small lab at rating 1000").
class EraGoal {
  final Era era;
  final String metric; // 'users' | 'rating' | 'arr'
  final double target;
  final double current;
  const EraGoal(this.era, this.metric, this.target, this.current);

  bool get met => current >= target;

  /// 0..1 on the metric's natural scale (log for users and ARR).
  double get progress {
    if (met) return 1;
    if (metric == 'rating') {
      return ((current - ratingBase) / (target - ratingBase)).clamp(0.0, 1.0);
    }
    if (current <= 1) return 0;
    return (math.log(current) / math.log(target)).clamp(0.0, 1.0);
  }
}

/// What a requirement row's button should open.
enum RequirementAction { none, power, train }

/// One line of a "what do I still need" checklist (moving to the next room).
class Requirement {
  /// 'era' | 'power' | 'cash'.
  final String kind;

  /// E.g. "Startup era", "Power limit", "Cash".
  final String title;

  /// Progress text, e.g. "1.2k / 3k users", "\$4k / \$15k", "done".
  final String detail;

  /// How to make progress, e.g. "grow users by releasing better models".
  final String? hint;
  final bool done;

  /// 0..1.
  final double progress;
  final RequirementAction action;

  /// False for "good to have" rows that don't block (the era, power).
  final bool required;

  const Requirement({
    required this.kind,
    required this.title,
    required this.detail,
    required this.done,
    required this.progress,
    this.hint,
    this.action = RequirementAction.none,
    this.required = true,
  });

  /// One line, e.g. "Startup era: 1.2k / 3k users (grow users by ...)".
  String get line => '$title: $detail${hint == null || done ? '' : ' ($hint)'}';
}

class OfflineReport {
  final double seconds;
  final double moneyEarned;
  final double usersBefore;
  final double usersAfter;
  final bool trainingFinished;

  /// Rival releases and industry news posted while you were away (filled
  /// by NewsFeed.catchUp).
  final List<NewsItem> news;
  const OfflineReport({
    required this.seconds,
    required this.moneyEarned,
    required this.usersBefore,
    required this.usersAfter,
    required this.trainingFinished,
    this.news = const [],
  });

  OfflineReport withNews(List<NewsItem> news) => OfflineReport(
    seconds: seconds,
    moneyEarned: moneyEarned,
    usersBefore: usersBefore,
    usersAfter: usersAfter,
    trainingFinished: trainingFinished,
    news: news,
  );
}

/// The whole simulation. Pure Dart, deterministic for a given seed.
class Game {
  final GameState s;
  final List<GameEvent> events = [];

  Game([GameState? state]) : s = state ?? GameState();

  // ---------------------------------------------------------------------------
  // Derived values
  // ---------------------------------------------------------------------------

  Iterable<Effects> get _effects => allUpgrades
      .where((u) => s.ownedUpgrades.contains(u.id))
      .map((u) => u.effects);

  double get utilization => math.min(
    maxUtilization,
    baseUtilization + _effects.fold(0.0, (a, e) => a + e.utilizationAdd),
  );

  double get trainEffMult =>
      _effects.fold(1.0, (a, e) => a * e.trainEffMult) *
      math.pow(openSourceCommunityTrainBonus, math.min(s.openReleases, openSourceCommunityMaxStacks));

  double get serveEffMult => _effects.fold(1.0, (a, e) => a * e.serveEffMult);
  double get dataTokens =>
      startDataTokens * _effects.fold(1.0, (a, e) => a * e.dataMult);
  double get ratingBonus => _effects.fold(0.0, (a, e) => a + e.ratingAdd);
  double get arpuMult =>
      _effects.fold(1.0, (a, e) => a * e.arpuMult) *
      (s.currentModel.open ? openSourceArpuMult : 1) *
      (s.era == Era.garage ? garageArpuMult : 1);
  double get powerMult => _effects.fold(1.0, (a, e) => a * e.powerMult);

  // --- Grid ------------------------------------------------------------------

  GridStats? _grid;
  int _gridRevision = -1;
  int _gridNetwork = -1;
  int _gridCooling = -1;

  /// Derived grid data, recomputed only when the grid or the network /
  /// cooling tier changes. Utilization is applied on top, so upgrades don't
  /// invalidate it.
  GridStats get grid {
    if (_grid == null ||
        _gridRevision != s.gridRevision ||
        _gridNetwork != s.networkTier ||
        _gridCooling != s.coolingTier) {
      _grid = computeGridStats(s, networkCap, cooling.perGpuTile);
      _gridRevision = s.gridRevision;
      _gridNetwork = s.networkTier;
      _gridCooling = s.coolingTier;
    }
    return _grid!;
  }

  // --- Central cooling -------------------------------------------------------

  CoolingDef get cooling => coolingTiers[s.coolingTier];

  CoolingDef? get nextCoolingTier =>
      s.coolingTier + 1 < coolingTiers.length
          ? coolingTiers[s.coolingTier + 1]
          : null;

  /// Why the next central cooling tier can't be bought, or null if it can.
  String? coolingBlockReason() {
    final next = nextCoolingTier;
    if (next == null) return 'You have the best cooling plant.';
    if (!isUnlocked(next.era)) return eraLockReason(next.era);
    final missing = [
      for (final id in next.requires)
        if (!s.ownedUpgrades.contains(id))
          researchName(id),
    ];
    if (missing.isNotEmpty) return 'Research ${missing.join(' + ')} first.';
    if (s.money < next.cost) {
      return 'Costs ${_money(next.cost)}. You have ${_money(s.money)}.';
    }
    return null;
  }

  bool buyNextCoolingTier() {
    if (coolingBlockReason() != null) return false;
    s.money -= nextCoolingTier!.cost;
    s.coolingTier++;
    return true;
  }

  /// Central cooling matters from the Medium lab on (the panel shows then).
  bool get coolingTiersVisible =>
      s.coolingTier > 0 || isUnlocked(coolingTiers[1].era);

  // --- Network ---------------------------------------------------------------

  NetworkDef get network => networkTiers[s.networkTier];

  /// GPUs one cluster keeps fed at full training efficiency.
  double get networkCap => network.gpuCap;

  NetworkDef? get nextNetworkTier =>
      s.networkTier + 1 < networkTiers.length
          ? networkTiers[s.networkTier + 1]
          : null;

  /// Why the next network tier can't be bought, or null if it can.
  String? networkBlockReason() {
    final next = nextNetworkTier;
    if (next == null) return 'You have the fastest network.';
    if (!isUnlocked(next.era)) return eraLockReason(next.era);
    final missing = [
      for (final id in next.requires)
        if (!s.ownedUpgrades.contains(id))
          researchName(id),
    ];
    if (missing.isNotEmpty) return 'Research ${missing.join(' + ')} first.';
    if (s.money < next.cost) {
      return 'Costs ${_money(next.cost)}. You have ${_money(s.money)}.';
    }
    return null;
  }

  bool buyNextNetworkTier() {
    if (networkBlockReason() != null) return false;
    s.money -= nextNetworkTier!.cost;
    s.networkTier++;
    return true;
  }

  /// Sum of GPU tile TFLOPS ignoring heat.
  double get peakTflops => grid.peakTflops;

  /// Sum of GPU tile TFLOPS after heat throttling (before utilization).
  double get rawTflops => grid.rawTflops;
  double get effectiveTflops => rawTflops * utilization;

  /// GPUs in the room (a server tile counts 8, a rack 32–72...).
  double get totalGpus => grid.totalGpus;

  /// The cluster that trains: every GPU tile in the room (cabled overhead).
  /// Null only with no GPUs at all.
  Cluster? get trainingCluster => grid.training?.withUtilization(utilization);

  /// The room's cluster (one, or none without GPUs), as a list.
  List<Cluster> clusters(String roomId) => [
    for (final c in grid.clusters)
      if (c.roomId == roomId) c.withUtilization(utilization),
  ];

  /// Compute the training cluster delivers at 100% of a run (after its
  /// scaling efficiency).
  double get trainingClusterTflops {
    final c = grid.training;
    return c == null ? 0 : c.rawTflops * c.scalingEfficiency * utilization;
  }

  double get _trainingClusterEffective =>
      (grid.training?.rawTflops ?? 0) * utilization;

  GridStats? _spareFor;
  Set<int> _spare = const {};

  /// Cooler cells in the current room that do nothing right now: clearing
  /// one alone slows no GPU (it touches none, or its GPUs stay cool from
  /// the room's air and other coolers). Each is a cell a GPU could use.
  /// Cached per grid.
  Set<int> spareCoolers() {
    final base = grid;
    if (identical(_spareFor, base)) return _spare;
    final room = currentRoom;
    final cells = s.grids[room.id];
    final rs = base.rooms[room.id];
    final out = <int>{};
    if (cells != null && rs != null) {
      for (var i = 0; i < cells.length; i++) {
        if (rs.defs[i]?.isCooling != true) continue;
        final without = List<String?>.of(cells)..[i] = null;
        final alt = computeGridStats(GameState(grids: {room.id: without}), networkCap, cooling.perGpuTile);
        final ars = alt.rooms[room.id]!;
        var slower = false;
        for (var j = 0; j < cells.length && !slower; j++) {
          if (rs.defs[j]?.isGpu == true && ars.speed[j] < rs.speed[j] - 1e-9) slower = true;
        }
        if (!slower) out.add(i);
      }
    }
    _spareFor = base;
    return _spare = out;
  }

  TileStatus? tileStatus(String roomId, int x, int y) {
    final rs = grid.rooms[roomId];
    if (rs == null) return null;
    final room = rs.room;
    if (x < 0 || y < 0 || x >= room.width || y >= room.height) return null;
    final i = y * room.width + x;
    final def = rs.defs[i];
    if (def == null) return null;
    final ci = rs.cluster[i];
    return TileStatus(
      def: def,
      netHeat: rs.netHeat[i],
      speed: rs.speed[i],
      clusterId: ci < 0 ? null : ci,
      inTrainingCluster: ci >= 0 && ci == grid.trainingIndex,
      effectiveTflops: def.tflops * rs.speed[i] * utilization,
      ambientCooling: rs.ambient[i],
      plantCooling: rs.plant[i],
      adjacentCooling: rs.adjCooling[i],
      adjacentGpus: rs.coolerGpus[i],
    );
  }

  /// What placing one more [t] costs now: the list price, plus the supply
  /// crunch premium for every tile of that type already placed
  /// (TileDef.priceGrowth, GPUs only).
  double tilePrice(TileDef t) => _priceWith(t, grid.counts[t.id] ?? 0);

  /// The price of [t] with [count] of them already placed.
  double _priceWith(TileDef t, int count) => t.priceGrowth == 0
      ? t.cost
      : t.cost *
          math.min(maxSupplyPremium, math.pow(1 + t.priceGrowth, count).toDouble());

  /// Supply-crunch premium on the next [t] as a fraction (0.3 = +30%).
  double tilePremium(TileDef t) => tilePrice(t) / t.cost - 1;

  /// Power one tile draws (GPU tiles get upgrade savings like liquid cooling).
  double tilePowerKw(TileDef t) => t.isGpu ? t.powerKw * powerMult : t.powerKw;

  /// GPU tiles (× upgrade savings) plus cooling and network gear.
  double get powerUsedKw => grid.gpuPowerKw * powerMult + grid.otherPowerKw;
  double get powerCapKw => powerTiers[s.powerTier].capacityKw;
  PowerDef? get nextPowerTier =>
      s.powerTier + 1 < powerTiers.length ? powerTiers[s.powerTier + 1] : null;

  /// The first room whose electrical service takes power tier [tier].
  static RoomDef roomForPowerTier(int tier) =>
      rooms.firstWhere((r) => r.maxPowerTier >= tier, orElse: () => rooms.last);

  /// The next power tier exists and is unlocked, but the building you're in
  /// can't take it: move first. The room to move to is
  /// [roomForPowerTier]`(s.powerTier + 1)`.
  bool get powerNeedsMove {
    final next = nextPowerTier;
    return next != null &&
        isUnlocked(next.era) &&
        s.powerTier + 1 > currentRoom.maxPowerTier;
  }

  /// Why the next power tier can't be bought here and now, or null if it
  /// can: top tier, era, the building's electrical service, then money.
  String? powerBlockReason() {
    final next = nextPowerTier;
    if (next == null) return 'You have the biggest power supply.';
    if (!isUnlocked(next.era)) return eraLockReason(next.era);
    if (powerNeedsMove) {
      return 'Needs a bigger building: move to the '
          '${roomForPowerTier(s.powerTier + 1).name} first.';
    }
    if (s.money < next.cost) {
      return 'Costs ${_money(next.cost)}. You have ${_money(s.money)}.';
    }
    return null;
  }

  bool get training => s.run != null && !s.run!.paused;

  /// Training compute actually delivered (after the cluster's scaling
  /// efficiency).
  double get trainingTflops =>
      training ? trainingClusterTflops * s.run!.fraction : 0;

  /// The compute not committed to training serves users: the cluster's
  /// unused fraction (plus rented cloud GPUs).
  double get servingTflops =>
      effectiveTflops -
      (training ? _trainingClusterEffective * s.run!.fraction : 0) +
      (s.cloudSecondsLeft > 0 ? effectiveTflops : 0);

  /// Per-user TFLOPS for a model of [effectiveCompute] (its size), before
  /// the design's serving multiplier.
  double perUserTflops(double effectiveCompute) =>
      servingBase *
      math.pow(effectiveCompute / startEffectiveCompute, servingExponent) /
      serveEffMult;

  /// The starting model counts as the plain garage design (dense, full
  /// attention, 2k, Kaplan-style, web crawl, SFT, FP16).
  static final DesignEffects startDesign = evaluate(const ModelSpec(), const DesignContext());

  /// The current model's design serving and demand multipliers.
  double get modelServeMult =>
      s.currentModel.design?.serveCostMult ?? startDesign.serveCostMult;
  double get modelDemandMult =>
      s.currentModel.design?.demandMult ?? startDesign.demandMult;

  /// What serving one user of the current model costs (its size and design).
  double get currentPerUserTflops =>
      perUserTflops(s.currentModel.design?.serveCompute ?? s.currentModel.effectiveCompute) *
      modelServeMult;

  double get capacity => servingTflops / currentPerUserTflops;

  /// What serving one user of the pending model would cost, or null.
  double? get pendingPerUserTflops {
    final effC = s.pendingEffectiveCompute;
    if (effC == null) return null;
    final d = s.pendingDesign;
    return perUserTflops(d?.serveCompute ?? effC) * (d?.serveCostMult ?? startDesign.serveCostMult);
  }

  /// FLOPs that a data budget can use before returns diminish (Chinchilla-ish).
  double get dataOptimalCompute => chinchillaK * dataTokens * dataTokens;

  /// Raw training FLOPs → effective compute, after algorithmic multipliers and
  /// the data limit.
  double effectiveComputeOf(double rawFlops) {
    final c = rawFlops * trainEffMult;
    final cStar = dataOptimalCompute;
    if (c <= cStar) return c;
    return cStar * math.pow(c / cStar, dataLimitedExponent);
  }

  double ratingOf(double effectiveCompute) =>
      ratingBase +
      ratingPerDoubling *
          (math.log(effectiveCompute / startEffectiveCompute) / math.ln2) +
      ratingBonus;

  double get rating =>
      ratingOf(s.currentModel.effectiveCompute) + (s.currentModel.design?.ratingAdd ?? 0);

  /// Rating of the finished model waiting to ship, or null.
  double? get pendingRating {
    final effC = s.pendingEffectiveCompute;
    if (effC == null) return null;
    return ratingOf(effC) + (s.pendingDesign?.ratingAdd ?? 0);
  }

  double get demand => math.min(
    maxUsers,
    demandBase *
        math.pow(10, (rating - ratingBase) / demandRatingScale) *
        modelDemandMult *
        s.hype *
        reviewBuzz *
        (s.viralSecondsLeft > 0 ? viralDemandMult : 1),
  );

  /// People who want in but can't get capacity yet ("join the waitlist").
  double get waitlistUsers => math.max(0, demand - s.users);

  double get servedUsers => math.min(s.users, capacity);
  double get unservedUsers => math.max(0, s.users - capacity);
  bool get overloaded => s.users > capacity * 1.001;

  double get revenuePerSecond =>
      revenueScale * math.pow(servedUsers, revenueExponent) * arpuMult;
  double get arr => revenuePerSecond * secondsPerYear;

  /// Time compression of the running run, or of a run started now.
  double get runTimeScale => s.run?.timeScale ?? s.era.computeTimeScale;

  /// Run lengths the UI offers right now (real seconds).
  List<double> get runDurations => s.era.runDurations;

  /// Raw FLOPs per second a run at [fraction] gets from the training cluster.
  double trainingFlopsPerSecond(double fraction) =>
      trainingClusterTflops * fraction * 1e12 * runTimeScale;

  /// Raw FLOPs of a run started now at [fraction] for [durationSeconds].
  double plannedFlops(double fraction, double durationSeconds) =>
      trainingClusterTflops * fraction * 1e12 * s.era.computeTimeScale * durationSeconds;

  // --- Model design ------------------------------------------------------------

  /// The lab as the model-design rules see it: [rawFlops] is the planned
  /// run's raw FLOPs (default: half the cluster for the era's middle run).
  DesignContext designContextFor(double rawFlops) => DesignContext(
    clusterGpus: grid.training?.gpus ?? 0,
    networkGpuCap: networkCap,
    dataTokens: dataTokens,
    ownedResearch: s.ownedUpgrades,
    eraIndex: s.era.index,
    plannedCompute: rawFlops * trainEffMult,
  );

  DesignContext get designContext =>
      designContextFor(plannedFlops(0.5, runDurations[runDurations.length ~/ 2]));

  /// The setup the next run starts with: the last one, with anything no
  /// longer unlocked swapped for the safe default.
  ModelSpec get nextSpec => s.lastSpec.clampTo(designContext);

  /// What [spec] does for a run of [rawFlops].
  DesignEffects designEffects(ModelSpec spec, double rawFlops) =>
      evaluate(spec, designContextFor(rawFlops));

  /// Raw training FLOPs → effective compute for a designed run (design
  /// quality, training overhead and its data budget, then the data limit).
  double designedEffectiveCompute(double rawFlops, ModelSpec spec, [DesignEffects? e]) =>
      (e ?? designEffects(spec, rawFlops)).effectiveCompute(rawFlops * trainEffMult, dataTokens);

  /// Rating of a run of [rawFlops] with [spec] (before risks).
  double predictRatingForFlops(double rawFlops, ModelSpec spec) {
    final e = designEffects(spec, rawFlops);
    return ratingOf(designedEffectiveCompute(rawFlops, spec, e)) + e.ratingAdd;
  }

  /// Rating of a run started now at [fraction] for [durationSeconds] with
  /// [spec] (default: [nextSpec]), before risks.
  double predictRating(double fraction, double durationSeconds, {ModelSpec? spec}) =>
      predictRatingForFlops(plannedFlops(fraction, durationSeconds), spec ?? nextSpec);

  /// True if a run of [rawFlops] with [spec] hits the data wall.
  bool isDataLimited(double rawFlops, ModelSpec spec) {
    final e = designEffects(spec, rawFlops);
    final c = rawFlops * trainEffMult * e.cem / e.trainCostMult;
    return c > chinchillaK * math.pow(dataTokens * e.dataBudgetMult, 2);
  }

  bool get dataLimited {
    final run = s.run;
    if (run == null) return false;
    return isDataLimited(trainingFlopsPerSecond(run.fraction) * run.durationSeconds, run.spec);
  }

  RivalSnapshot? get nextRival =>
      s.rivalIndex < rivalLadder.length ? rivalLadder[s.rivalIndex] : null;

  /// What the placed GPU tiles cost.
  double get hardwareValue => grid.gpuValue;

  double get cloudRentCost =>
      math.max(500, hardwareValue * cloudRentCostFactor);

  bool isUnlocked(Era era) => era.index <= s.era.index;

  /// The next era and how close you are to it; null in the last era.
  EraGoal? get nextEraGoal {
    if (s.era.index + 1 >= Era.values.length) return null;
    final next = Era.values[s.era.index + 1];
    return switch (next) {
      Era.garage => null,
      Era.startup => EraGoal(next, 'compute', startupUnlockTflops, peakTflops),
      Era.smallLab => EraGoal(next, 'rating', smallLabUnlockRating, rating),
      Era.mediumLab => EraGoal(next, 'rating', mediumLabUnlockRating, rating),
      Era.bigLab => EraGoal(next, 'rating', bigLabUnlockRating, rating),
      Era.globalLab => EraGoal(next, 'rating', globalLabUnlockRating, rating),
    };
  }

  /// "Unlocks in Small lab: reach rating 1,000 (you're at 998)." Spells out
  /// the gate for the next era; later eras say which era comes first.
  String eraLockReason(Era era) {
    if (isUnlocked(era)) return 'Unlocked.';
    final goal = nextEraGoal;
    if (goal != null && goal.era == era) {
      return 'Unlocks in ${era.label}: ${goalText(goal)}.';
    }
    return 'Unlocks in ${era.label} (after ${Era.values[era.index - 1].label}).';
  }

  /// "reach rating 1,000 (you're at 998)" / "reach 3k users (you have 1.2k)"
  /// / "own 1.20 PFLOPS of GPUs (you have 450 TFLOPS)".
  static String goalText(EraGoal goal) => switch (goal.metric) {
    'users' =>
      'reach ${_num(goal.target)} users (you have ${_num(goal.current)})',
    'compute' =>
      'own ${tflopsText(goal.target)} of GPUs (you have ${tflopsText(goal.current)})',
    'rating' =>
      'reach rating ${_int(goal.target)} (you\'re at ${_int(goal.current.floorToDouble())})',
    _ => 'reach ${_money(goal.target)} ARR (you have ${_money(goal.current)})',
  };

  /// How to make progress on a gate, for hints.
  static String goalHint(String metric) => switch (metric) {
    'users' => 'release better models and add serving GPUs',
    'compute' => 'fill the room with faster GPUs; swap old cards and unneeded coolers for V100s',
    'rating' => 'train & release a better model',
    _ => 'grow revenue: more users, better pricing',
  };

  static String _int(double v) {
    final s = v.round().toString();
    final b = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
      b.write(s[i]);
    }
    return b.toString();
  }

  /// Can [r] be beaten now (its era reached, rating and users matched)?
  bool canBeat(RivalSnapshot r) =>
      isUnlocked(r.era) && rating >= r.rating && s.users >= r.users;

  // ---------------------------------------------------------------------------
  // Actions
  // ---------------------------------------------------------------------------

  // --- Rooms -----------------------------------------------------------------
  // You live in one room at a time. Moving to the next one takes every tile
  // with you (same layout, centred in the bigger floor); the old room is gone.

  RoomDef get currentRoom => s.room;

  /// The next room you can move to, or null in the last one.
  RoomDef? get nextRoom => roomAfter(s.roomId);

  /// True only for the room you're in.
  bool isRoomOwned(String roomId) => s.ownsRoom(roomId);

  /// The room you're in, as a list (kept for callers that loop over rooms).
  List<RoomDef> get ownedRooms => [currentRoom];

  /// Cell offset that centres [from]'s layout in [to] (deterministic: extra
  /// odd columns/rows go to the right/bottom).
  static (int, int) moveOffset(RoomDef from, RoomDef to) =>
      ((to.width - from.width) ~/ 2, (to.height - from.height) ~/ 2);

  /// The move checklist for [roomId]: the room's era (its goal) and the
  /// cash, both required, then the power limit the bigger building brings
  /// (info). Empty for rooms you can't move to at all (see
  /// [roomBlockReason]).
  List<Requirement> moveRequirements(String roomId) {
    final room = roomById(roomId);
    if (room == null || room.id != nextRoom?.id) return const [];
    final out = <Requirement>[];
    // Era: the room is part of its era, like its parts, power and research.
    final eraOk = isUnlocked(room.era);
    final goal = nextEraGoal;
    if (eraOk) {
      out.add(Requirement(
        kind: 'era',
        title: '${room.era.label} era',
        detail: 'reached',
        done: true,
        progress: 1,
      ));
    } else if (goal != null && goal.era == room.era) {
      out.add(Requirement(
        kind: 'era',
        title: '${room.era.label} era',
        detail: goalProgress(goal),
        hint: goalHint(goal.metric),
        done: false,
        progress: goal.progress,
        // A compute gate is built, not trained: nothing to open.
        action: goal.metric == 'compute' ? RequirementAction.none : RequirementAction.train,
      ));
    } else {
      out.add(Requirement(
        kind: 'era',
        title: '${room.era.label} era',
        detail: 'after ${Era.values[room.era.index - 1].label}',
        done: false,
        progress: 0,
      ));
    }
    final cashOk = s.money >= room.cost;
    out.add(Requirement(
      kind: 'cash',
      title: 'Cash',
      detail: cashOk ? _money(room.cost) : '${_money(s.money)} / ${_money(room.cost)}',
      hint: cashOk ? null : 'earn it by serving users',
      done: cashOk,
      progress: room.cost <= 0 ? 1 : (s.money / room.cost).clamp(0.0, 1.0),
    ));
    // Power (info): the bigger building's electrical service lifts the
    // power limit. Moving keeps your tier; buy the bigger supply after.
    if (room.maxPowerTier > currentRoom.maxPowerTier) {
      final top = powerTiers[room.maxPowerTier];
      out.add(Requirement(
        kind: 'power',
        title: 'Power limit',
        detail: '${_kw(powerTiers[currentRoom.maxPowerTier].capacityKw)} → '
            '${_kw(top.capacityKw)} (up to ${top.name})',
        done: true,
        progress: 1,
        required: false,
      ));
    }
    return out;
  }

  /// Peak GPU compute: "450 TFLOPS", "1.20 PFLOPS".
  static String tflopsText(double tflops) => tflops >= 1000
      ? '${(tflops / 1000).toStringAsFixed(2)} PFLOPS'
      : '${tflops.round()} TFLOPS';

  /// "1.2k / 3k users", "rating 998 / 1,000", "0.45 / 1.20 PFLOPS".
  static String goalProgress(EraGoal goal) => switch (goal.metric) {
    'users' => '${_num(goal.current)} / ${_num(goal.target)} users',
    'compute' => goal.target >= 1000
        ? '${(goal.current / 1000).toStringAsFixed(2)} / ${tflopsText(goal.target)}'
        : '${goal.current.round()} / ${tflopsText(goal.target)}',
    'rating' => 'rating ${_int(goal.current.floorToDouble())} / ${_int(goal.target)}',
    _ => '${_money(goal.current)} / ${_money(goal.target)}',
  };

  /// Why you can't move to [roomId] right now (one actionable sentence), or
  /// null if you can. Two gates: the room's era (a new place belongs to its
  /// era, like its parts and power) and its price. [moveRequirements] has
  /// the full checklist.
  String? roomBlockReason(String roomId) {
    final room = roomById(roomId);
    if (room == null) return 'Unknown room.';
    if (s.ownsRoom(roomId)) return 'You\'re already in the ${room.name}.';
    final i = roomIndex(roomId), cur = roomIndex(s.roomId);
    if (i < cur) return 'You moved out of the ${room.name}.';
    if (i > cur + 1) return 'Move to the ${nextRoom!.name} first.';
    if (!isUnlocked(room.era)) {
      final goal = nextEraGoal;
      if (goal != null && goal.era == room.era) {
        return 'Opens in the ${room.era.label} era: ${goalText(goal)}.';
      }
      return 'Opens in the ${room.era.label} era '
          '(after ${Era.values[room.era.index - 1].label}).';
    }
    if (s.money < room.cost) {
      return 'Costs ${_money(room.cost)}. You have ${_money(s.money)}.';
    }
    return null;
  }

  bool canBuyRoom(String roomId) => roomBlockReason(roomId) == null;

  /// [roomId] is the next room and its era is reached: only its price
  /// stands in the way.
  bool canMoveSoon(String roomId) =>
      roomId == nextRoom?.id && isUnlocked(roomById(roomId)!.era);

  /// Move to [roomId] (the next room, once its era is reached and you can
  /// pay for it): pay, carry every tile over with the same relative layout
  /// (centred, see [moveOffset]) and leave the old room behind. Training,
  /// users and upgrades carry on unchanged.
  bool moveTo(String roomId) {
    if (!canBuyRoom(roomId)) return false;
    final from = currentRoom;
    final to = roomById(roomId)!;
    final (ox, oy) = moveOffset(from, to);
    final old = s.grids[from.id]!;
    final cells = GameState.emptyGrid(to);
    for (var i = 0; i < old.length; i++) {
      final id = old[i];
      if (id == null) continue;
      final x = i % from.width + ox, y = i ~/ from.width + oy;
      cells[y * to.width + x] = id;
    }
    s.money -= to.cost;
    s.grids
      ..clear()
      ..[to.id] = cells;
    s.touchGrid();
    events.add(RoomMoved(from, to, (ox, oy)));
    return true;
  }

  // --- Tiles -----------------------------------------------------------------

  String? tileAt(String roomId, int x, int y) => s.tileAt(roomId, x, y);

  /// Era reached, required upgrades owned and power tier high enough.
  bool isTileUnlocked(TileDef t) => tileLockReason(t) == null;

  /// Why [t] is locked (era / upgrade / power tier), or null.
  String? tileLockReason(TileDef t) {
    if (!isUnlocked(t.era)) return eraLockReason(t.era);
    final missing = [
      for (final id in t.requires)
        if (!s.ownedUpgrades.contains(id))
          researchName(id),
    ];
    if (missing.isNotEmpty) return 'Research ${missing.join(' + ')} first.';
    if (s.powerTier < t.minPowerTier) {
      final need = powerTiers[t.minPowerTier].name;
      if (t.minPowerTier > currentRoom.maxPowerTier) {
        return 'Needs power: $need. Move to the '
            '${roomForPowerTier(t.minPowerTier).name} first.';
      }
      return 'Needs power: $need.';
    }
    return null;
  }

  /// Tiles for the tray in [roomId] (locked or not): every tile can go in
  /// any room once unlocked. The room's own era and newer first, then the
  /// older parts, each in content order.
  List<TileDef> tilesForRoom(String roomId) {
    final era = roomById(roomId)?.era.index ?? 0;
    return [
      for (final t in tiles)
        if (t.era.index >= era) t,
      for (final t in tiles)
        if (t.era.index < era) t,
    ];
  }

  /// A part from an era before [roomId]'s: placeable, grouped as "older".
  bool isOlderPart(TileDef t, String roomId) =>
      t.era.index < (roomById(roomId)?.era.index ?? 0);

  /// Human-readable reason [tileId] can't be placed at (x, y), or null.
  /// Checks, in order: the room you're in, bounds, empty cell, era /
  /// research / power tier unlocks, power headroom, money ([ignoreMoney]
  /// skips it). Never the room size: any unlocked tile goes anywhere.
  String? placeBlockReason(
    String roomId,
    int x,
    int y,
    String tileId, {
    bool ignoreMoney = false,
  }) => _blockReason(roomId, x, y, tileId, ignoreMoney: ignoreMoney);

  bool canPlace(String roomId, int x, int y, String tileId) =>
      placeBlockReason(roomId, x, y, tileId) == null;

  bool placeTile(String roomId, int x, int y, String tileId) {
    if (!canPlace(roomId, x, y, tileId)) return false;
    s.money -= tilePrice(tileById(tileId)!);
    s.setTile(roomId, x, y, tileId);
    return true;
  }

  // --- Build plans -------------------------------------------------------------
  // The build UI lets you plan several tiles (ghosts) and buy them together.
  // Each planned tile is checked as if the earlier ones were already done.

  /// What carrying out [plan] in order would cost now: each placement at its
  /// grown price (every planned GPU raises the next one's), each swap at the
  /// new tile's price minus the old one's [sellValue], as [replaceTile] does.
  double planCost(List<PlannedTile> plan) {
    final counts = Map.of(grid.counts);
    final swapped = <(int, int), String>{};
    var total = 0.0;
    for (final p in plan) {
      final t = tileById(p.tileId);
      if (t == null) continue;
      final n = counts[p.tileId] ?? 0;
      total += _priceWith(t, n);
      counts[p.tileId] = n + 1;
      if (p.replace) {
        final old = swapped[(p.x, p.y)] ?? tileAt(s.roomId, p.x, p.y);
        if (old != null) {
          total -= sellValue(old);
          counts[old] = (counts[old] ?? 1) - 1;
        }
      }
      swapped[(p.x, p.y)] = p.tileId;
    }
    return total;
  }

  /// Power [plan] adds once carried out (a swap adds only the difference).
  double planPowerKw(List<PlannedTile> plan) {
    var kw = 0.0;
    for (final p in plan) {
      final t = tileById(p.tileId);
      if (t == null) continue;
      kw += tilePowerKw(t);
      final old = p.replace ? tileById(tileAt(s.roomId, p.x, p.y) ?? '') : null;
      if (old != null) kw -= tilePowerKw(old);
    }
    return kw;
  }

  /// A what-if copy of this game with [plan] already carried out in
  /// [roomId] (no money spent). For checks and the heat / cluster preview;
  /// it shares nothing mutable with this game.
  Game withPlan(String roomId, List<PlannedTile> plan) {
    final copy = GameState(
      money: s.money,
      powerTier: s.powerTier,
      networkTier: s.networkTier,
      coolingTier: s.coolingTier,
      grids: {for (final e in s.grids.entries) e.key: List.of(e.value)},
      ownedUpgrades: Set.of(s.ownedUpgrades),
      openReleases: s.openReleases,
      era: s.era,
    );
    for (final p in plan) {
      if (p.replace || copy.tileAt(roomId, p.x, p.y) == null) {
        copy.setTile(roomId, p.x, p.y, p.tileId);
      }
    }
    return Game(copy);
  }

  /// Why [next] can't be added to [plan], or null: the cell isn't planned
  /// already, it's free (a swap: holds a different tile), the part is
  /// unlocked, the power cap holds with the plan included, and the money
  /// covers the plan's running total plus this one.
  String? planBlockReason(String roomId, List<PlannedTile> plan, PlannedTile next) =>
      planBlockReasonIn(withPlan(roomId, plan), roomId, plan, next);

  /// [planBlockReason] against a [preview] made by [withPlan] for [plan]
  /// (reuse it to check many cells against the same plan).
  String? planBlockReasonIn(
    Game preview,
    String roomId,
    List<PlannedTile> plan,
    PlannedTile next,
  ) {
    if (plan.any((p) => p.x == next.x && p.y == next.y)) {
      return 'That cell is already in your plan.';
    }
    final r = next.replace
        ? preview.replaceBlockReason(roomId, next.x, next.y, next.tileId, ignoreMoney: true)
        : preview.placeBlockReason(roomId, next.x, next.y, next.tileId, ignoreMoney: true);
    if (r != null) return r;
    final t = tileById(next.tileId)!;
    final total = planCost([...plan, next]);
    if (total > s.money + 1e-9) {
      return 'Not enough money for another ${t.name}: the plan would cost '
          '${_money(total)}, you have ${_money(s.money)}.';
    }
    return null;
  }

  /// Carries out [plan] in order, each tile through [placeTile] /
  /// [replaceTile] (so each is re-checked against money and power now).
  /// Returns the entries that couldn't be done.
  List<PlannedTile> placePlan(String roomId, List<PlannedTile> plan) => [
    for (final p in plan)
      if (!(p.replace
          ? replaceTile(roomId, p.x, p.y, p.tileId)
          : placeTile(roomId, p.x, p.y, p.tileId)))
        p,
  ];

  /// "Upgrade GPUs": swaps appended after [plan], oldest tier first and then
  /// tier by tier as the money lasts. Your GPUs are grouped by model,
  /// weakest (fewest TFLOPS) first. For each group the target is the
  /// unlocked GPU that adds the most TFLOPS across that group given the
  /// money left (as many swaps as it covers: grown price minus the sell
  /// refund each), ties going to the faster card; only GPUs strictly weaker
  /// than the target are swapped. When the money runs out part-way through
  /// a group it stops there; otherwise it moves on to the next group.
  /// Swaps [replaceBlockReason] blocks (the power cap) are skipped. Cells
  /// already in [plan] are left alone. Stops after [max] swaps. Empty when
  /// nothing is better or affordable.
  List<PlannedTile> upgradePlan(String roomId, {List<PlannedTile> plan = const [], int? max}) {
    final room = roomById(roomId);
    if (room == null || !s.ownsRoom(roomId)) return const [];
    final base = withPlan(roomId, plan);
    final planned = {for (final p in plan) (p.x, p.y)};
    // Your GPUs by model, weakest model first, row-major within a model.
    final groups = <String, List<(int, int)>>{};
    for (var y = 0; y < room.height; y++) {
      for (var x = 0; x < room.width; x++) {
        if (planned.contains((x, y))) continue;
        if (tileById(base.tileAt(roomId, x, y) ?? '') case final d? when d.isGpu) {
          (groups[d.id] ??= []).add((x, y));
        }
      }
    }
    final order = groups.keys.map((id) => tileById(id)!).toList()
      ..sort((a, b) {
        final c = a.tflops.compareTo(b.tflops);
        return c != 0 ? c : a.id.compareTo(b.id);
      });
    final candidates = [for (final t in tiles) if (t.isGpu && isTileUnlocked(t)) t];
    final out = <PlannedTile>[];
    for (final from in order) {
      if (max != null && out.length >= max) break;
      final full = [...plan, ...out];
      // Swaps of this group to [target] after [full], and whether money ran out.
      (List<PlannedTile>, bool) trySwaps(TileDef target) {
        final sim = withPlan(roomId, full);
        final swaps = <PlannedTile>[];
        var broke = false;
        for (final (x, y) in groups[from.id]!) {
          if (max != null && out.length + swaps.length >= max) break;
          if (sim.replaceBlockReason(roomId, x, y, target.id, ignoreMoney: true) != null) continue;
          final swap = PlannedTile(x, y, target.id, replace: true);
          if (planCost([...full, ...swaps, swap]) > s.money + 1e-9) {
            broke = true;
            break;
          }
          swaps.add(swap);
          sim.s.setTile(roomId, x, y, target.id);
        }
        return (swaps, broke);
      }

      List<PlannedTile>? best;
      var bestBroke = false;
      var bestGain = 0.0;
      TileDef? bestTarget;
      for (final target in candidates) {
        if (target.tflops <= from.tflops) continue;
        final (swaps, broke) = trySwaps(target);
        if (swaps.isEmpty) continue;
        final gain = swaps.length * (target.tflops - from.tflops);
        if (gain > bestGain + 1e-9 ||
            (gain > bestGain - 1e-9 && target.tflops > (bestTarget?.tflops ?? 0))) {
          best = swaps;
          bestBroke = broke;
          bestGain = gain;
          bestTarget = target;
        }
      }
      if (best == null) {
        // Nothing better or affordable for this model; a newer group may
        // still be upgradeable only if money isn't the reason, so stop.
        if (candidates.any((t) => t.tflops > from.tflops)) break;
        continue;
      }
      out.addAll(best);
      if (bestBroke) break; // the money ran out part-way: stop here
    }
    return out;
  }

  /// Like [placeBlockReason] for swapping the tile at (x, y) for [tileId]:
  /// the old tile is sold for [sellValue] towards the price, and only the
  /// extra power is needed.
  String? replaceBlockReason(
    String roomId,
    int x,
    int y,
    String tileId, {
    bool ignoreMoney = false,
  }) {
    final old = tileAt(roomId, x, y);
    if (old == null) return 'There is nothing there to replace.';
    if (old == tileId) return 'That tile is already there.';
    return _blockReason(
      roomId,
      x,
      y,
      tileId,
      replacing: old,
      ignoreMoney: ignoreMoney,
    );
  }

  /// Sell the tile at (x, y) and put [tileId] in its place (e.g. a faster
  /// switch). Pays the difference.
  bool replaceTile(String roomId, int x, int y, String tileId) {
    if (replaceBlockReason(roomId, x, y, tileId) != null) return false;
    final old = tileById(tileAt(roomId, x, y)!)!;
    s.money += sellValue(old.id) - tilePrice(tileById(tileId)!);
    s.setTile(roomId, x, y, tileId);
    return true;
  }

  String? _blockReason(
    String roomId,
    int x,
    int y,
    String tileId, {
    String? replacing,
    bool ignoreMoney = false,
  }) {
    final tile = tileById(tileId);
    if (tile == null) return 'Unknown tile.';
    final room = roomById(roomId);
    if (room == null) return 'Unknown room.';
    if (!s.ownsRoom(roomId)) return 'You\'re not in the ${room.name}.';
    if (x < 0 || y < 0 || x >= room.width || y >= room.height) {
      return 'That spot is outside the ${room.name}.';
    }
    final here = tileAt(roomId, x, y);
    if (replacing == null && here != null) {
      return 'That spot is taken. Move or sell the '
          '${tileById(here)?.name ?? here} first.';
    }
    final locked = tileLockReason(tile);
    if (locked != null) return locked;
    final oldDef = replacing == null ? null : tileById(replacing);
    final needKw =
        tilePowerKw(tile) - (oldDef == null ? 0 : tilePowerKw(oldDef));
    final freeKw = powerCapKw - powerUsedKw;
    if (needKw > freeKw + 1e-9) {
      final how = powerNeedsMove
          ? 'Move to the ${roomForPowerTier(s.powerTier + 1).name} for more power.'
          : 'Tap ⚡ Power to upgrade.';
      return 'Not enough power: needs ${_kw(needKw)}, ${_kw(math.max(0, freeKw))} '
          'free. $how';
    }
    final price =
        tilePrice(tile) - (oldDef == null ? 0 : sellValue(oldDef.id));
    if (!ignoreMoney && s.money < price) {
      return 'Costs ${_money(price)}. You have ${_money(s.money)}.';
    }
    return null;
  }

  /// Moving is free. Moving onto an occupied cell swaps the two tiles.
  bool moveTile(String roomId, int fx, int fy, int tx, int ty) {
    final room = roomById(roomId);
    if (room == null || !s.ownsRoom(roomId)) return false;
    bool inside(int x, int y) =>
        x >= 0 && y >= 0 && x < room.width && y < room.height;
    if (!inside(fx, fy) || !inside(tx, ty) || (fx == tx && fy == ty)) {
      return false;
    }
    final a = tileAt(roomId, fx, fy);
    if (a == null) return false;
    final b = tileAt(roomId, tx, ty);
    final cells = s.grids[roomId]!;
    cells[ty * room.width + tx] = a;
    cells[fy * room.width + fx] = b;
    s.touchGrid();
    return true;
  }

  /// Selling refunds half the list price (the supply-crunch premium is
  /// gone once you've paid it).
  double sellValue(String tileId) => (tileById(tileId)?.cost ?? 0) * 0.5;

  /// Why the tile at (x, y) can't be sold, or null.
  String? sellBlockReason(String roomId, int x, int y) {
    final id = tileAt(roomId, x, y);
    if (id == null) return 'There is nothing there to sell.';
    final def = tileById(id)!;
    if (def.isGpu && (grid.rooms[roomId]?.gpuTiles ?? 0) <= 1) {
      return 'You can\'t sell your last GPU.';
    }
    return null;
  }

  bool sellTile(String roomId, int x, int y) {
    if (sellBlockReason(roomId, x, y) != null) return false;
    s.money += sellValue(tileAt(roomId, x, y)!);
    s.setTile(roomId, x, y, null);
    return true;
  }

  static String _kw(double kw) =>
      kw >= 1000
          ? '${(kw / 1000).toStringAsFixed(kw >= 1e5 ? 0 : 1)} MW'
          : '${kw.toStringAsFixed(kw >= 10 ? 0 : 2)} kW';

  static String _num(double v) {
    final a = v.abs();
    String f(double x) => x >= 10 || x == x.roundToDouble()
        ? x.toStringAsFixed(0)
        : x.toStringAsFixed(1);
    if (a >= 1e9) return '${f(v / 1e9)}B';
    if (a >= 1e6) return '${f(v / 1e6)}M';
    if (a >= 1e3) return '${f(v / 1e3)}k';
    return v.toStringAsFixed(0);
  }

  static String _money(double v) {
    final a = v.abs();
    if (a >= 1e9) return '\$${(v / 1e9).toStringAsFixed(2)}B';
    if (a >= 1e6) return '\$${(v / 1e6).toStringAsFixed(2)}M';
    if (a >= 1e3) return '\$${(v / 1e3).toStringAsFixed(1)}k';
    return '\$${v.toStringAsFixed(0)}';
  }

  bool buyNextPowerTier() {
    if (powerBlockReason() != null) return false;
    final next = nextPowerTier!;
    s.money -= next.cost;
    s.powerTier++;
    return true;
  }

  bool canBuyUpgrade(UpgradeDef u) =>
      !s.ownedUpgrades.contains(u.id) &&
      isUnlocked(u.era) &&
      u.requires.every(s.ownedUpgrades.contains) &&
      s.money >= u.cost;

  bool buyUpgrade(String id) {
    final u = researchById(id);
    if (u == null || !canBuyUpgrade(u)) return false;
    s.money -= u.cost;
    s.ownedUpgrades.add(id);
    return true;
  }

  bool get canStartTraining =>
      s.run == null && s.pendingEffectiveCompute == null;

  /// Start a run with [spec] (default: [nextSpec], the remembered setup).
  /// Locked choices are swapped for the safe default; the spec is
  /// remembered for the next run. [early] is the early-phase data emphasis
  /// (default: defaultPhaseOption for the spec); a locked one is swapped for
  /// the default too.
  bool startTraining({
    required double fraction,
    required double durationSeconds,
    ModelSpec? spec,
    PhaseOption? early,
  }) {
    if (!canStartTraining) return false;
    final used = (spec ?? s.lastSpec).clampTo(designContext);
    s.lastSpec = used;
    s.run = TrainingRun(
      fraction: fraction.clamp(0.05, 1.0),
      durationSeconds: durationSeconds,
      spec: used,
      timeScale: s.era.computeTimeScale,
      phaseChoices: {
        RunPhase.early: early != null && early.phase == RunPhase.early && isPhaseOptionUnlocked(early)
            ? early
            : defaultPhaseOption(RunPhase.early, used, phaseContext),
      },
    );
    return true;
  }

  /// The run's checkpoint waiting for a decision, or null.
  RunPhase? get awaitingPhase => s.run?.awaitingPhase;

  /// What the run-phase locks look at: owned research and the era (the
  /// same rules as the model-design slots).
  DesignContext get phaseContext => DesignContext(ownedResearch: s.ownedUpgrades, eraIndex: s.era.index);

  bool isPhaseOptionUnlocked(PhaseOption option) => phaseContext.isUnlocked(option);

  /// "Research X to unlock" / "Reach Big lab to unlock", or null.
  String? phaseLockReason(PhaseOption option) => phaseContext.lockReason(option);

  /// Answer the waiting checkpoint with [option]; false if it isn't for the
  /// phase the run is waiting at or the lab hasn't unlocked it.
  bool choosePhase(PhaseOption option) {
    final run = s.run;
    if (run == null || run.awaitingPhase != option.phase) return false;
    if (!isPhaseOptionUnlocked(option)) return false;
    run.choosePhase(option);
    return true;
  }

  void togglePauseTraining() {
    final run = s.run;
    if (run != null) run.paused = !run.paused;
  }

  void cancelTraining() => s.run = null;

  bool rentCloud() {
    if (s.cloudSecondsLeft > 0 || s.money < cloudRentCost) return false;
    s.money -= cloudRentCost;
    s.cloudSecondsLeft = cloudRentSeconds;
    return true;
  }

  /// Release the pending model. Returns false if there is nothing to release.
  bool release({required bool open, String stuntId = 'none', String? name}) {
    final effC = s.pendingEffectiveCompute;
    if (effC == null) return false;
    final stunt = launchStunts.firstWhere((l) => l.id == stuntId);
    if (!isUnlocked(stunt.era)) return false;

    final oldRating = rating;
    s.money -= s.money * stunt.costFraction;
    final success = _random() < stunt.successChance;

    final release = ModelRelease(
      name: name ?? 'Model ${s.releases.length}',
      effectiveCompute: effC,
      rating: pendingRating!,
      open: open,
      time: s.time,
      design: s.pendingDesign,
      review: reviewPending(open: open, stuntId: stunt.id, stuntSucceeded: success),
    );
    s.releases.add(release);
    s.pendingEffectiveCompute = null;
    s.pendingDesign = null;
    if (open) s.openReleases++;

    final improvement = math.max(0.0, release.rating - oldRating);
    final hypeBoost =
        (1 + improvement / hypePerRating) *
        (success ? stunt.hypeOnSuccess : stunt.hypeOnFail) *
        (open ? openSourceHypeMult : 1);
    // Hype doesn't compound release after release: a launch sets it to at
    // least its own boost (so spamming tiny releases doesn't run away).
    s.hype = math.min(maxHype, math.max(s.hype, hypeBoost));

    events.add(ModelReleased(release, stunt, success));
    return true;
  }

  void discardPending() {
    s.pendingEffectiveCompute = null;
    s.pendingDesign = null;
  }

  // ---------------------------------------------------------------------------
  // Simulation
  // ---------------------------------------------------------------------------

  void tick(double dt, {bool offline = false}) {
    s.time += dt;

    // Training.
    final run = s.run;
    if (run != null && !run.paused) {
      // Checkpoints (run_phases.dart) may hold the run for a decision.
      final trainDt = run.stepPhases(dt, offline: offline);
      run.computeFlops += trainingFlopsPerSecond(run.fraction) * trainDt;
      run.elapsedSeconds += trainDt;
      if (run.done) _finishRun(run);
    }

    // Users drift toward demand; overload churns the unserved.
    // Normally signups stop at capacity (a waitlist). A viral spike breaks
    // through it: users pile up to overflowAllowance × capacity, the service
    // falls over (OVERLOADED) and the unserved churn until you add capacity.
    final cap = capacity;
    final d = demand;
    final growthTarget = math.min(
      d,
      cap * (s.viralSecondsLeft > 0 ? overflowAllowance : 1.0),
    );
    if (s.users < growthTarget) {
      s.users += (growthTarget - s.users) * math.min(1.0, userGrowthRate * dt);
    } else if (s.users > d) {
      s.users -= (s.users - d) * math.min(1.0, userChurnRate * dt);
    }
    if (s.users > cap) {
      s.users -= (s.users - cap) * math.min(1.0, overloadChurnRate * dt);
      // Outside a spike the last stragglers give up too: settle exactly at
      // capacity so OVERLOADED ends cleanly.
      if (s.viralSecondsLeft == 0 &&
          s.users - cap < overloadSettleFraction * cap) {
        s.users = cap;
      }
    }

    s.money += revenuePerSecond * dt * (offline ? offlineEarningsRate : 1);

    // Decays and timers.
    s.hype = 1 + (s.hype - 1) * math.pow(0.5, dt / hypeHalfLifeSeconds);
    s.viralSecondsLeft = math.max(0, s.viralSecondsLeft - dt);
    s.cloudSecondsLeft = math.max(0, s.cloudSecondsLeft - dt);
    if (s.viralSecondsLeft == 0) {
      s.viralCooldownLeft = math.max(0, s.viralCooldownLeft - dt);
    }

    // Viral spike: only online, only once you've shipped something, not
    // right after the last one, and only when people are actually waiting.
    if (!offline &&
        s.viralSecondsLeft == 0 &&
        s.viralCooldownLeft == 0 &&
        demand > cap &&
        s.releases.length > 1 &&
        s.users >= 0.7 * cap &&
        _random() < viralChancePerSecond * dt) {
      s.viralSecondsLeft = viralDurationSeconds;
      s.viralCooldownLeft = viralCooldownSeconds;
      events.add(const ViralSpikeStarted());
    }

    // Era unlocks (one per tick at most).
    final goal = nextEraGoal;
    if (goal != null && goal.met) {
      s.era = goal.era;
      events.add(EraUnlocked(goal.era));
    }

    // Rival ladder. The live feed (news.dart) releases the next rival
    // before it can be beaten; it never changes who can be beaten.
    updateNews();
    while (nextRival != null && canBeat(nextRival!)) {
      events.add(RivalBeaten(nextRival!));
      s.rivalIndex++;
      updateNews();
    }
  }

  /// Evaluate the run's design against the lab as it is now, roll its risks
  /// with the seeded RNG and leave the model pending.
  void _finishRun(TrainingRun run) {
    final e = designEffects(run.spec, run.computeFlops);
    var cemHit = 1.0;
    final mishaps = <String>[];
    for (final r in e.risks) {
      if (_random() < r.chance) {
        cemHit *= r.cemMultOnHit;
        mishaps.add(riskHitText(r));
      }
    }
    final effC = e.effectiveCompute(run.computeFlops * trainEffMult * cemHit, dataTokens);
    final design = applyPhases(DesignOutcome(
      spec: run.spec,
      ratingAdd: e.ratingAdd,
      serveCostMult: e.serveCostMult,
      demandMult: e.demandMult,
      serveCompute: effC / (e.cem * cemHit),
      strengths: e.strengths,
      highlights: [
        ...mishaps,
        for (final n in e.notes)
          if (n.tone != NoteTone.neutral) n.text,
      ].take(4).toList(),
    ), run.phaseChoices);
    s.pendingEffectiveCompute = effC;
    s.pendingDesign = design;
    s.run = null;
    events.add(TrainingFinished(effC, pendingRating!, mishaps));
  }

  /// Advance by [seconds] in steps of at most [step] seconds.
  void advance(
    double seconds, {
    bool offline = false,
    double step = 1,
    void Function()? onStep,
  }) {
    var left = seconds;
    while (left > 0) {
      final dt = math.min(step, left);
      tick(dt, offline: offline);
      onStep?.call();
      left -= dt;
    }
  }

  /// Step size for offline catch-up: 1 s for short absences, 2 s for the
  /// full 2 h cap (≤ ~3.6k ticks; up to 10 s for longer spans). Deterministic:
  /// it depends only on [seconds].
  static double offlineStep(double seconds) =>
      (seconds / 3000).clamp(1.0, 10.0).floorToDouble();

  /// Catch up [seconds] of absence (capped at [offlineCapSeconds]): money,
  /// users and a running training run keep going; no viral spikes. A run
  /// that ends mid-step finishes on that step. [onStep] is for tools.
  OfflineReport applyOffline(double seconds, {void Function()? onStep}) {
    final capped = seconds.clamp(0.0, offlineCapSeconds);
    final moneyBefore = s.money;
    final usersBefore = s.users;
    final hadRun = s.run != null;
    advance(
      capped,
      offline: true,
      step: offlineStep(capped),
      onStep: onStep,
    );
    return OfflineReport(
      seconds: capped,
      moneyEarned: s.money - moneyBefore,
      usersBefore: usersBefore,
      usersAfter: s.users,
      trainingFinished: hadRun && s.run == null,
    );
  }

  /// Deterministic LCG so runs are reproducible and saveable.
  double _random() {
    s.rngState = (s.rngState * 1103515245 + 12345) & 0x7fffffff;
    return s.rngState / 0x7fffffff;
  }
}
