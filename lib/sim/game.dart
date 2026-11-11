import 'dart:math' as math;

import 'balance.dart';
import 'content.dart';
import 'game_state.dart';
import 'grid.dart';

export 'grid.dart' show TileStatus, Cluster;

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
  const TrainingFinished(this.effectiveCompute, this.predictedRating);
}

class ModelReleased extends GameEvent {
  final ModelRelease release;
  final LaunchStunt stunt;
  final bool stuntSucceeded;
  const ModelReleased(this.release, this.stunt, this.stuntSucceeded);
}

class OfflineReport {
  final double seconds;
  final double moneyEarned;
  final double usersBefore;
  final double usersAfter;
  final bool trainingFinished;
  const OfflineReport({
    required this.seconds,
    required this.moneyEarned,
    required this.usersBefore,
    required this.usersAfter,
    required this.trainingFinished,
  });
}

/// The whole simulation. Pure Dart, deterministic for a given seed.
class Game {
  final GameState s;
  final List<GameEvent> events = [];

  Game([GameState? state]) : s = state ?? GameState();

  // ---------------------------------------------------------------------------
  // Derived values
  // ---------------------------------------------------------------------------

  Iterable<Effects> get _effects => upgrades
      .where((u) => s.ownedUpgrades.contains(u.id))
      .map((u) => u.effects);

  double get utilization => math.min(
    maxUtilization,
    baseUtilization + _effects.fold(0.0, (a, e) => a + e.utilizationAdd),
  );

  double get trainEffMult =>
      _effects.fold(1.0, (a, e) => a * e.trainEffMult) *
      math.pow(openSourceCommunityTrainBonus, s.openReleases);

  double get serveEffMult => _effects.fold(1.0, (a, e) => a * e.serveEffMult);
  double get dataTokens =>
      startDataTokens * _effects.fold(1.0, (a, e) => a * e.dataMult);
  double get ratingBonus => _effects.fold(0.0, (a, e) => a + e.ratingAdd);
  double get arpuMult =>
      _effects.fold(1.0, (a, e) => a * e.arpuMult) *
      (s.currentModel.open ? openSourceArpuMult : 1);
  double get powerMult => _effects.fold(1.0, (a, e) => a * e.powerMult);

  // --- Grid ------------------------------------------------------------------

  GridStats? _grid;
  int _gridRevision = -1;

  /// Derived grid data, recomputed only when the grid changes
  /// (GameState.gridRevision). Utilization is applied on top, so upgrades
  /// don't invalidate it.
  GridStats get grid {
    if (_grid == null || _gridRevision != s.gridRevision) {
      _grid = computeGridStats(s);
      _gridRevision = s.gridRevision;
    }
    return _grid!;
  }

  /// Sum of GPU tile TFLOPS ignoring heat.
  double get peakTflops => grid.peakTflops;

  /// Sum of GPU tile TFLOPS after heat throttling (before utilization).
  double get rawTflops => grid.rawTflops;
  double get effectiveTflops => rawTflops * utilization;

  /// GPUs across all rooms (a server tile counts 8, a rack 32–72...).
  double get totalGpus => grid.totalGpus;

  /// The cluster that trains: the best effective TFLOPS × scaling efficiency
  /// across all rooms. Null only with no GPUs at all.
  Cluster? get trainingCluster => grid.training?.withUtilization(utilization);

  /// Clusters in one room (lone unnetworked GPU tiles are clusters of one).
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
      adjacentCooling: rs.adjCooling[i],
      adjacentGpus: rs.coolerGpus[i],
    );
  }

  /// Power one tile draws (GPU tiles get upgrade savings like liquid cooling).
  double tilePowerKw(TileDef t) => t.isGpu ? t.powerKw * powerMult : t.powerKw;

  /// GPU tiles (× upgrade savings) plus cooling and network gear.
  double get powerUsedKw => grid.gpuPowerKw * powerMult + grid.otherPowerKw;
  double get powerCapKw => powerTiers[s.powerTier].capacityKw;
  PowerDef? get nextPowerTier =>
      s.powerTier + 1 < powerTiers.length ? powerTiers[s.powerTier + 1] : null;

  bool get training => s.run != null && !s.run!.paused;

  /// Training compute actually delivered (after the cluster's scaling
  /// efficiency).
  double get trainingTflops =>
      training ? trainingClusterTflops * s.run!.fraction : 0;

  /// Every GPU not committed to training serves users: other clusters, lone
  /// GPUs and the training cluster's unused fraction.
  double get servingTflops =>
      effectiveTflops -
      (training ? _trainingClusterEffective * s.run!.fraction : 0) +
      (s.cloudSecondsLeft > 0 ? effectiveTflops : 0);

  double perUserTflops(double effectiveCompute) =>
      servingBase *
      math.pow(effectiveCompute / startEffectiveCompute, servingExponent) /
      serveEffMult;

  double get capacity =>
      servingTflops / perUserTflops(s.currentModel.effectiveCompute);

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

  double get rating => ratingOf(s.currentModel.effectiveCompute);

  double get demand => math.min(
    maxUsers,
    demandBase *
        math.pow(10, (rating - ratingBase) / demandRatingScale) *
        s.hype *
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

  /// Raw FLOPs per second a run at [fraction] gets from the training cluster.
  double trainingFlopsPerSecond(double fraction) =>
      trainingClusterTflops * fraction * 1e12 * computeTimeScale;

  double predictRating(double fraction, double durationSeconds) => ratingOf(
    effectiveComputeOf(trainingFlopsPerSecond(fraction) * durationSeconds),
  );

  bool get dataLimited {
    final run = s.run;
    if (run == null) return false;
    final projected =
        trainingFlopsPerSecond(run.fraction) * run.durationSeconds;
    return projected * trainEffMult > dataOptimalCompute;
  }

  RivalSnapshot? get nextRival =>
      s.rivalIndex < rivalLadder.length ? rivalLadder[s.rivalIndex] : null;

  /// What the placed GPU tiles cost.
  double get hardwareValue => grid.gpuValue;

  double get cloudRentCost =>
      math.max(500, hardwareValue * cloudRentCostFactor);

  bool isUnlocked(Era era) => era.index <= s.era.index;

  // ---------------------------------------------------------------------------
  // Actions
  // ---------------------------------------------------------------------------

  // --- Rooms -----------------------------------------------------------------

  bool isRoomOwned(String roomId) => s.ownsRoom(roomId);

  List<RoomDef> get ownedRooms => [
    for (final r in rooms)
      if (s.ownsRoom(r.id)) r,
  ];

  /// Why [roomId] can't be bought right now, or null if it can.
  String? roomBlockReason(String roomId) {
    final room = roomById(roomId);
    if (room == null) return 'Unknown room.';
    if (s.ownsRoom(roomId)) return 'You already have the ${room.name}.';
    if (!isUnlocked(room.era)) return 'Unlocks in the ${room.era.label} era.';
    if (s.powerTier < room.minPowerTier) {
      return 'Needs the ${powerTiers[room.minPowerTier].name} power tier.';
    }
    if (s.money < room.cost) {
      return 'Costs ${_money(room.cost)}. You have ${_money(s.money)}.';
    }
    return null;
  }

  bool canBuyRoom(String roomId) => roomBlockReason(roomId) == null;

  bool buyRoom(String roomId) {
    if (!canBuyRoom(roomId)) return false;
    final room = roomById(roomId)!;
    s.money -= room.cost;
    s.grids[roomId] = GameState.emptyGrid(room);
    s.touchGrid();
    return true;
  }

  // --- Tiles -----------------------------------------------------------------

  String? tileAt(String roomId, int x, int y) => s.tileAt(roomId, x, y);

  /// Era reached, required upgrades owned and power tier high enough.
  bool isTileUnlocked(TileDef t) => tileLockReason(t) == null;

  /// Why [t] is locked (era / upgrade / power tier), or null.
  String? tileLockReason(TileDef t) {
    if (!isUnlocked(t.era)) return 'Unlocks in the ${t.era.label} era.';
    final missing = [
      for (final id in t.requires)
        if (!s.ownedUpgrades.contains(id))
          upgrades.firstWhere((u) => u.id == id).name,
    ];
    if (missing.isNotEmpty) return 'Requires ${missing.join(' + ')}.';
    if (s.powerTier < t.minPowerTier) {
      return 'Needs the ${powerTiers[t.minPowerTier].name} power tier.';
    }
    return null;
  }

  /// Tiles that can go in [roomId] (locked or not), in content order.
  List<TileDef> tilesForRoom(String roomId) => [
    for (final t in tiles)
      if (t.rooms.contains(roomId)) t,
  ];

  /// Human-readable reason [tileId] can't be placed at (x, y), or null.
  /// Checks, in order: room owned, bounds, empty cell, allowed room, era /
  /// upgrades / power tier, power headroom, money ([ignoreMoney] skips it).
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
    s.money -= tileById(tileId)!.cost;
    s.setTile(roomId, x, y, tileId);
    return true;
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
    s.money += sellValue(old.id) - tileById(tileId)!.cost;
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
    if (!s.ownsRoom(roomId)) return 'Buy the ${room.name} first.';
    if (x < 0 || y < 0 || x >= room.width || y >= room.height) {
      return 'That spot is outside the ${room.name}.';
    }
    final here = tileAt(roomId, x, y);
    if (replacing == null && here != null) {
      return 'That spot is taken. Move or sell the '
          '${tileById(here)?.name ?? here} first.';
    }
    if (!tile.rooms.contains(roomId)) {
      final where = [
        for (final r in rooms)
          if (tile.rooms.contains(r.id)) r.name,
      ].join(' or ');
      return '${tile.name} doesn\'t fit in the ${room.name}. It goes in the '
          '$where.';
    }
    final locked = tileLockReason(tile);
    if (locked != null) return locked;
    final oldDef = replacing == null ? null : tileById(replacing);
    final needKw =
        tilePowerKw(tile) - (oldDef == null ? 0 : tilePowerKw(oldDef));
    final freeKw = powerCapKw - powerUsedKw;
    if (needKw > freeKw + 1e-9) {
      return 'Not enough power: needs ${_kw(needKw)}, ${_kw(math.max(0, freeKw))} '
          'free. Upgrade your power supply.';
    }
    final price = tile.cost - (oldDef == null ? 0 : sellValue(oldDef.id));
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

  /// Selling refunds half the price.
  double sellValue(String tileId) => (tileById(tileId)?.cost ?? 0) * 0.5;

  /// Why the tile at (x, y) can't be sold, or null.
  String? sellBlockReason(String roomId, int x, int y) {
    final id = tileAt(roomId, x, y);
    if (id == null) return 'There is nothing there to sell.';
    final def = tileById(id)!;
    if (def.isGpu && grid.rooms.values.fold(0, (a, r) => a + r.gpuTiles) <= 1) {
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

  static String _money(double v) {
    final a = v.abs();
    if (a >= 1e9) return '\$${(v / 1e9).toStringAsFixed(2)}B';
    if (a >= 1e6) return '\$${(v / 1e6).toStringAsFixed(2)}M';
    if (a >= 1e3) return '\$${(v / 1e3).toStringAsFixed(1)}k';
    return '\$${v.toStringAsFixed(0)}';
  }

  bool buyNextPowerTier() {
    final next = nextPowerTier;
    if (next == null || !isUnlocked(next.era) || s.money < next.cost) {
      return false;
    }
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
    final u = upgrades.firstWhere((u) => u.id == id);
    if (!canBuyUpgrade(u)) return false;
    s.money -= u.cost;
    s.ownedUpgrades.add(id);
    return true;
  }

  bool get canStartTraining =>
      s.run == null && s.pendingEffectiveCompute == null;

  bool startTraining({
    required double fraction,
    required double durationSeconds,
  }) {
    if (!canStartTraining) return false;
    s.run = TrainingRun(
      fraction: fraction.clamp(0.05, 1.0),
      durationSeconds: durationSeconds,
    );
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

    final oldRating = rating;
    s.money -= s.money * stunt.costFraction;
    final success = _random() < stunt.successChance;

    final release = ModelRelease(
      name: name ?? 'Model ${s.releases.length}',
      effectiveCompute: effC,
      rating: ratingOf(effC),
      open: open,
      time: s.time,
    );
    s.releases.add(release);
    s.pendingEffectiveCompute = null;
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

  void discardPending() => s.pendingEffectiveCompute = null;

  // ---------------------------------------------------------------------------
  // Simulation
  // ---------------------------------------------------------------------------

  void tick(double dt, {bool offline = false}) {
    s.time += dt;

    // Training.
    final run = s.run;
    if (run != null && !run.paused) {
      run.computeFlops += trainingFlopsPerSecond(run.fraction) * dt;
      run.elapsedSeconds += dt;
      if (run.done) {
        final effC = effectiveComputeOf(run.computeFlops);
        s.pendingEffectiveCompute = effC;
        s.run = null;
        events.add(TrainingFinished(effC, ratingOf(effC)));
      }
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

    s.money += revenuePerSecond * dt;

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

    // Era unlocks.
    if (s.era == Era.garage && s.users >= startupUnlockUsers) {
      s.era = Era.startup;
      events.add(const EraUnlocked(Era.startup));
    }
    if (s.era == Era.startup && rating >= labUnlockRating) {
      s.era = Era.lab;
      events.add(const EraUnlocked(Era.lab));
    }

    // Rival ladder.
    while (nextRival != null &&
        rating >= nextRival!.rating &&
        s.users >= nextRival!.users) {
      events.add(RivalBeaten(nextRival!));
      s.rivalIndex++;
    }
  }

  /// Advance by [seconds] in 1-second steps.
  void advance(double seconds, {bool offline = false}) {
    var left = seconds;
    while (left > 0) {
      final dt = math.min(1.0, left);
      tick(dt, offline: offline);
      left -= dt;
    }
  }

  OfflineReport applyOffline(double seconds) {
    final capped = seconds.clamp(0.0, offlineCapSeconds);
    final moneyBefore = s.money;
    final usersBefore = s.users;
    final hadRun = s.run != null;
    advance(capped, offline: true);
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
