// Headless player used by tool/balance_sim.dart and the sim tests.
// Pure Dart and deterministic. It plays like an engaged human: it looks at
// the game every few seconds, keeps a training run going, releases better
// models, handles viral crises and spends money on whatever buys the most
// progress per dollar (saving up when something good is close).
import 'dart:math' as math;

import 'balance.dart';
import 'content.dart';
import 'game.dart';
import 'game_state.dart';

enum BotStrategy {
  /// Scores every purchase by progress per dollar (hardware, power, software).
  balanced,

  /// GPUs and power. Buys no software or research upgrades; only data (you
  /// can't train without tokens) and the liquid cooling racks require.
  hardwareOnly,

  /// Literally no upgrades at all (hits the data wall almost immediately).
  noUpgrades,

  /// Buys every available upgrade first (saving for it), hardware with the rest.
  softwareFirst,
}

class Bot {
  final Game g;
  final BotStrategy strategy;

  /// Seconds between "looks at the screen".
  final double thinkEvery;

  /// Longest the bot will save up for one purchase.
  static const maxSaveSeconds = 480.0;

  /// Stats for balance reports.
  int purchases = 0;
  double lastMeaningfulAction = 0;
  double longestIdle = 0;
  double longestIdleStart = 0;

  double _nextThink = 0;
  bool _pausedForCrisis = false;

  Bot(this.g, {this.strategy = BotStrategy.balanced, this.thinkEvery = 3});

  void act() {
    if (g.s.time < _nextThink) return;
    _nextThink = g.s.time + thinkEvery;
    _release();
    _crisis();
    _train();
    _spend();
  }

  void _meaningful() {
    finish();
    lastMeaningfulAction = g.s.time;
  }

  /// Call at the end of a playthrough so a trailing idle stretch counts.
  void finish() {
    final idle = g.s.time - lastMeaningfulAction;
    if (idle > longestIdle) {
      longestIdle = idle;
      longestIdleStart = lastMeaningfulAction;
    }
  }

  // --- Releases --------------------------------------------------------------
  void _release() {
    final pending = g.s.pendingEffectiveCompute;
    if (pending == null) return;
    if (g.ratingOf(pending) > g.rating + 0.5) {
      // Open weights early for hype + community help; closed once revenue
      // matters.
      g.release(open: g.s.era == Era.garage, stuntId: 'cryptic_tweet');
      _meaningful();
    } else {
      g.discardPending();
    }
  }

  // --- Viral spikes ----------------------------------------------------------
  void _crisis() {
    final s = g.s;
    if (s.viralSecondsLeft > 0 && g.overloaded) {
      if (s.cloudSecondsLeft == 0 && g.cloudRentCost < 0.25 * s.money) {
        g.rentCloud();
      } else if (g.training && !_pausedForCrisis) {
        g.togglePauseTraining();
        _pausedForCrisis = true;
      }
    } else if (_pausedForCrisis && s.viralSecondsLeft == 0) {
      if (s.run != null && s.run!.paused) g.togglePauseTraining();
      _pausedForCrisis = false;
    }
  }

  // --- Training --------------------------------------------------------------
  /// Uses only the choices the UI offers (1m / 3m / 10m).
  double get runSeconds => switch (g.s.era) {
        Era.garage => 60.0,
        Era.startup => 180.0,
        Era.lab => g.rating < 1300 ? 180.0 : 600.0,
      };

  void _train() {
    if (!g.canStartTraining) return;
    // Keep enough serving compute for the users we have (plus some growth);
    // train with the rest, within sensible bounds.
    final need = math.min(g.demand, g.s.users * 1.2 + 10) *
        g.perUserTflops(g.s.currentModel.effectiveCompute);
    final spare = 1 - need / math.max(1e-9, g.effectiveTflops);
    // UI choices: 25% / 50% / 75%.
    g.startTraining(
        fraction: spare >= 0.75 ? 0.75 : 0.5, durationSeconds: runSeconds);
  }

  // --- Spending --------------------------------------------------------------

  /// Progress score: model rating (in compute doublings) + log of users we
  /// could serve + a little for revenue per user.
  double _value() {
    final r = g.predictRating(0.5, runSeconds);
    final effC = g.effectiveComputeOf(
        g.trainingFlopsPerSecond(0.5) * runSeconds);
    final demand = math.min(maxUsers,
        demandBase * math.pow(10, (r - ratingBase) / demandRatingScale));
    final cap = g.effectiveTflops * 0.5 /
        g.perUserTflops(math.max(effC, g.s.currentModel.effectiveCompute));
    return math.ln2 * r / ratingPerDoubling +
        math.log(math.max(1.0, math.min(demand, cap))) +
        0.5 * math.log(g.arpuMult);
  }

  List<UpgradeDef> get _availableUpgrades => upgrades
      .where((u) =>
          !g.s.ownedUpgrades.contains(u.id) &&
          g.isUnlocked(u.era) &&
          u.requires.every(g.s.ownedUpgrades.contains))
      .toList();

  HardwareDef? get _bestHardware {
    HardwareDef? best;
    for (final h in hardware) {
      if (!g.isHardwareAvailable(h)) continue;
      if (best == null || h.tflops / h.cost > best.tflops / best.cost) {
        best = h;
      }
    }
    return best;
  }

  void _spend() {
    final s = g.s;
    final v0 = _value();
    final cands = <_Cand>[];

    final headroom = g.powerCapKw - g.powerUsedKw;
    final powerTight = headroom < 0.25 * g.powerCapKw;
    // Upgrades that gate hardware (liquid cooling) count as infrastructure,
    // so even the hardware-only bot buys them, plus data.
    final hwPrereqs = {for (final h in hardware) ...h.requires};
    for (final u in _availableUpgrades) {
      if (strategy == BotStrategy.noUpgrades) break;
      if (strategy == BotStrategy.hardwareOnly &&
          u.category != UpgradeCategory.data &&
          !hwPrereqs.contains(u.id)) {
        continue;
      }
      s.ownedUpgrades.add(u.id);
      var dv = _value() - v0;
      s.ownedUpgrades.remove(u.id);
      // Power savings = more GPUs under the same cap.
      if (u.effects.powerMult < 1) {
        dv += 2 * math.log(1 / u.effects.powerMult) * (powerTight ? 1 : 0.3);
      }
      cands.add(_Cand(u.cost, dv, () => g.buyUpgrade(u.id), upgrade: true));
    }

    final h = _bestHardware;
    if (h != null) {
      final unitKw = h.powerKw * g.powerMult;
      if (headroom >= unitKw) {
        s.hardwareCounts[h.id] = (s.hardwareCounts[h.id] ?? 0) + 1;
        final dv = _value() - v0;
        s.hardwareCounts[h.id] = s.hardwareCounts[h.id]! - 1;
        cands.add(_Cand(h.cost, dv, () {
          final n = g.maxBuyable(h);
          return n > 0 && g.buyHardware(h.id, n);
        }));
      }
      // Power: worth it if we're nearly full. Value = filling part of the new
      // headroom with the best card we could afford soon.
      final next = g.nextPowerTier;
      if (next != null && g.isUnlocked(next.era) && powerTight) {
        // Value it as "tier + an equal spend on cards to fill it".
        final k = math
            .max(1.0, math.min((next.capacityKw - g.powerUsedKw) / unitKw,
                next.cost / h.cost))
            .floorToDouble();
        final before = s.hardwareCounts[h.id] ?? 0;
        s.hardwareCounts[h.id] = before + k.toInt();
        final dv = _value() - v0;
        s.hardwareCounts[h.id] = before;
        // Pay for the tier now, fill it with cards over the next minutes.
        cands.add(_Cand(next.cost, dv, g.buyNextPowerTier));
      }
    }

    if (cands.isEmpty) return;

    if (strategy == BotStrategy.softwareFirst) {
      final ups = cands.where((c) => c.upgrade && c.dv > 0).toList()
        ..sort((a, b) => a.cost.compareTo(b.cost));
      if (ups.isNotEmpty) {
        final u = ups.first;
        if (s.money >= u.cost) {
          if (u.buy()) {
            purchases++;
            _meaningful();
          }
          return;
        }
        // Save unless it's hopelessly far away.
        if (u.cost < s.money + 600 * g.revenuePerSecond) return;
      }
    }

    cands.removeWhere((c) => c.dv <= 1e-9);
    if (cands.isEmpty) return;
    cands.sort((a, b) => (b.dv / b.cost).compareTo(a.dv / a.cost));
    // Best affordable option, as the yardstick for "worth saving for".
    final affordable = cands.where((c) => s.money >= c.cost).firstOrNull;
    for (final c in cands) {
      if (s.money >= c.cost) {
        if (c.buy()) {
          purchases++;
          _meaningful();
        }
        return;
      }
      // Not affordable yet: save for it if it's close, and wait longer the
      // better a deal it is compared with what we could buy right now.
      final wait = (c.cost - s.money) / math.max(1e-9, g.revenuePerSecond);
      final ratio = affordable == null
          ? 8.0
          : (c.dv / c.cost) / (affordable.dv / affordable.cost);
      final patience =
          (60 + 150 * (math.log(math.max(1.0, ratio)) / math.ln2))
              .clamp(60.0, maxSaveSeconds);
      if (wait < patience) return;
    }
  }
}

class _Cand {
  final double cost;
  final double dv;
  final bool Function() buy;
  final bool upgrade;
  _Cand(this.cost, this.dv, this.buy, {this.upgrade = false});
}

/// Summary of a headless playthrough.
class PlaythroughResult {
  final BotStrategy strategy;
  final Game game;
  final Map<Era, double> eraTimes = {};
  final List<(RivalSnapshot, double)> rivalTimes = [];
  int viralSpikes = 0;
  int releases = 0;
  double overloadedSeconds = 0;
  double overloadedViralSeconds = 0;
  double maxUsersSeen = 0;
  double longestIdle = 0;
  double longestIdleStart = 0;
  double minMoney = double.infinity;
  double usersAtFinish = 0;
  double arrAtFinish = 0;
  double h100eAtFinish = 0;
  double powerKwAtFinish = 0;

  PlaythroughResult(this.strategy, this.game);

  bool get ladderDone => game.s.rivalIndex >= rivalLadder.length;
  double get seconds => game.s.time;
  double get overloadedFraction =>
      seconds == 0 ? 0 : overloadedSeconds / seconds;
  double? get finishTime => ladderDone ? rivalTimes.last.$2 : null;

  /// Longest wait between consecutive rival wins (from t=0).
  double get longestRivalGap {
    var prev = 0.0, gap = 0.0;
    for (final (_, t) in rivalTimes) {
      gap = math.max(gap, t - prev);
      prev = t;
    }
    return gap;
  }
}

/// Plays [maxSeconds] (or until the ladder is done when [stopWhenDone]).
/// [onEvent] sees every sim event with the game, e.g. for logging.
PlaythroughResult runPlaythrough({
  BotStrategy strategy = BotStrategy.balanced,
  double maxSeconds = 8 * 3600,
  double dt = 1,
  bool stopWhenDone = true,
  void Function(Game g, GameEvent e)? onEvent,
  void Function(Game g)? onTick,
  int seed = 12345,
}) {
  final g = Game(GameState(rngState: seed));
  final bot = Bot(g, strategy: strategy);
  final r = PlaythroughResult(strategy, g);
  r.eraTimes[Era.garage] = 0;
  var idleFrozen = false;
  while (g.s.time < maxSeconds) {
    bot.act();
    g.tick(dt);
    if (g.overloaded) {
      r.overloadedSeconds += dt;
      if (g.s.viralSecondsLeft > 0) r.overloadedViralSeconds += dt;
    }
    r.maxUsersSeen = math.max(r.maxUsersSeen, g.s.users);
    r.minMoney = math.min(r.minMoney, g.s.money);
    for (final e in g.events) {
      switch (e) {
        case EraUnlocked(:final era):
          r.eraTimes[era] = g.s.time;
        case RivalBeaten(:final rival):
          r.rivalTimes.add((rival, g.s.time));
        case ViralSpikeStarted():
          r.viralSpikes++;
        case ModelReleased():
          r.releases++;
        case TrainingFinished():
          break;
      }
      onEvent?.call(g, e);
    }
    g.events.clear();
    onTick?.call(g);
    if (r.ladderDone && !idleFrozen) {
      r.usersAtFinish = g.s.users;
      r.arrAtFinish = g.arr;
      r.h100eAtFinish = hardware.fold(
          0.0, (a, h) => a + (g.s.hardwareCounts[h.id] ?? 0) * h.tflops / 990);
      r.powerKwAtFinish = g.powerUsedKw;
      // Dead stretches only matter while there is a ladder to climb.
      bot.finish();
      r.longestIdle = bot.longestIdle;
      r.longestIdleStart = bot.longestIdleStart;
      idleFrozen = true;
    }
    if (stopWhenDone && r.ladderDone) break;
  }
  if (!idleFrozen) {
    bot.finish();
    r.longestIdle = bot.longestIdle;
    r.longestIdleStart = bot.longestIdleStart;
  }
  return r;
}
