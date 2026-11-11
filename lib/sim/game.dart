import 'dart:math' as math;

import 'balance.dart';
import 'content.dart';
import 'game_state.dart';

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

  Iterable<Effects> get _effects =>
      upgrades.where((u) => s.ownedUpgrades.contains(u.id)).map((u) => u.effects);

  double get utilization => math.min(
      maxUtilization,
      baseUtilization +
          _effects.fold(0.0, (a, e) => a + e.utilizationAdd));

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

  double get rawTflops => hardware.fold(
      0.0, (a, h) => a + (s.hardwareCounts[h.id] ?? 0) * h.tflops);
  double get effectiveTflops => rawTflops * utilization;

  double get powerUsedKw =>
      hardware.fold(0.0, (a, h) => a + (s.hardwareCounts[h.id] ?? 0) * h.powerKw) *
      powerMult;
  double get powerCapKw => powerTiers[s.powerTier].capacityKw;
  PowerDef? get nextPowerTier =>
      s.powerTier + 1 < powerTiers.length ? powerTiers[s.powerTier + 1] : null;

  bool get training => s.run != null && !s.run!.paused;
  double get trainingTflops => training ? effectiveTflops * s.run!.fraction : 0;
  double get servingTflops =>
      (effectiveTflops - trainingTflops) +
      (s.cloudSecondsLeft > 0 ? effectiveTflops : 0);

  double perUserTflops(double effectiveCompute) =>
      servingBase *
      math.pow(effectiveCompute / startEffectiveCompute, servingExponent) /
      serveEffMult;

  double get capacity => servingTflops / perUserTflops(s.currentModel.effectiveCompute);

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
      (s.viralSecondsLeft > 0 ? viralDemandMult : 1));

  double get servedUsers => math.min(s.users, capacity);
  double get unservedUsers => math.max(0, s.users - capacity);
  bool get overloaded => s.users > capacity * 1.001;

  double get revenuePerSecond =>
      revenueScale * math.pow(servedUsers, revenueExponent) * arpuMult;
  double get arr => revenuePerSecond * secondsPerYear;

  /// Raw FLOPs per second committed to training at a given fraction.
  double trainingFlopsPerSecond(double fraction) =>
      effectiveTflops * fraction * 1e12 * computeTimeScale;

  double predictRating(double fraction, double durationSeconds) => ratingOf(
      effectiveComputeOf(trainingFlopsPerSecond(fraction) * durationSeconds));

  bool get dataLimited {
    final run = s.run;
    if (run == null) return false;
    final projected = trainingFlopsPerSecond(run.fraction) * run.durationSeconds;
    return projected * trainEffMult > dataOptimalCompute;
  }

  RivalSnapshot? get nextRival =>
      s.rivalIndex < rivalLadder.length ? rivalLadder[s.rivalIndex] : null;

  double get hardwareValue => hardware.fold(
      0.0, (a, h) => a + (s.hardwareCounts[h.id] ?? 0) * h.cost);

  double get cloudRentCost => math.max(500, hardwareValue * cloudRentCostFactor);

  bool isUnlocked(Era era) => era.index <= s.era.index;

  // ---------------------------------------------------------------------------
  // Actions
  // ---------------------------------------------------------------------------

  /// Max units of [h] you can buy right now (limited by money and power).
  int maxBuyable(HardwareDef h) {
    if (!isUnlocked(h.era)) return 0;
    final byMoney = (s.money / h.cost).floor();
    final headroom = powerCapKw - powerUsedKw;
    final byPower = (headroom / (h.powerKw * powerMult) + 1e-9).floor();
    return math.max(0, math.min(byMoney, byPower));
  }

  bool buyHardware(String id, [int count = 1]) {
    final h = hardware.firstWhere((h) => h.id == id);
    if (count <= 0 || maxBuyable(h) < count) return false;
    s.money -= h.cost * count;
    s.hardwareCounts[id] = (s.hardwareCounts[id] ?? 0) + count;
    return true;
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

  bool get canStartTraining => s.run == null && s.pendingEffectiveCompute == null;

  bool startTraining({required double fraction, required double durationSeconds}) {
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
    final hypeBoost = (1 + improvement / hypePerRating) *
        (success ? stunt.hypeOnSuccess : stunt.hypeOnFail) *
        (open ? openSourceHypeMult : 1);
    s.hype = math.max(1.0, s.hype * hypeBoost);

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
    // Signups are throttled once you're far over capacity: people hit errors
    // and stop arriving, so users settle at most overflowAllowance × capacity.
    final cap = capacity;
    final d = demand;
    final growthTarget = math.min(d, cap * overflowAllowance);
    if (s.users < growthTarget) {
      s.users += (growthTarget - s.users) * math.min(1.0, userGrowthRate * dt);
    } else if (s.users > d) {
      s.users -= (s.users - d) * math.min(1.0, userChurnRate * dt);
    }
    if (s.users > cap) {
      s.users -= (s.users - cap) * math.min(1.0, overloadChurnRate * dt);
    }

    s.money += revenuePerSecond * dt;

    // Decays and timers.
    s.hype = 1 + (s.hype - 1) * math.pow(0.5, dt / hypeHalfLifeSeconds);
    s.viralSecondsLeft = math.max(0, s.viralSecondsLeft - dt);
    s.cloudSecondsLeft = math.max(0, s.cloudSecondsLeft - dt);

    // Viral spike: only online, only once you've shipped something.
    if (!offline &&
        s.viralSecondsLeft == 0 &&
        s.releases.length > 1 &&
        s.users >= 0.7 * cap &&
        _random() < viralChancePerSecond * dt) {
      s.viralSecondsLeft = viralDurationSeconds;
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
