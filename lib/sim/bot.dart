// Headless player used by tool/balance_sim.dart and the sim tests.
// Pure Dart and deterministic. It plays like an engaged human: it looks at
// the game every few seconds, keeps a training run going, releases better
// models, handles viral crises and spends money on whatever buys the most
// progress per dollar (saving up when something good is close).
//
// Placement (BotLayout.template): each room gets a fixed plan of GPU and
// cooler cells (stripes of two GPUs with coolers between). Coolers go in only
// where a GPU runs hot. The whole room is one training cluster; the network
// tier is bought when it outgrows the cap, central cooling when it pays off
// (then spare cooler cells take GPUs too). After moving to the
// next room it re-lays its old tiles onto the new room's plan (moving tiles
// is free), best GPUs first.
import 'dart:math' as math;

import 'balance.dart';
import 'content.dart';
import 'game.dart';
import 'game_state.dart';
import 'model_design.dart';
import 'run_phases.dart';

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

/// How the bot places tiles.
enum BotLayout {
  /// Planned layout: GPU stripes with cooler lines, coolers where hot.
  template,

  /// GPUs only, dropped on random empty cells: no coolers.
  naive,

  /// Buys a similar mix of GPUs and coolers but drops each on a random
  /// empty cell.
  random,
}

enum _Role { gpu, cool }

/// A room's target layout.
class _Plan {
  final RoomDef room;
  final List<_Role?> roles;

  /// GPU cells in fill order (row-major).
  final List<int> gpuOrder;

  _Plan(this.room, this.roles, this.gpuOrder);
}

/// One grid write the bot wants to make.
class _Op {
  final String room;
  final int x, y;
  final String tile;
  final bool replace;
  const _Op(this.room, this.x, this.y, this.tile, {this.replace = false});
}

const _dirs = [(1, 0), (-1, 0), (0, 1), (0, -1)];

List<int> _neighbours(RoomDef r, int i) {
  final x = i % r.width, y = i ~/ r.width;
  return [
    for (final (dx, dy) in _dirs)
      if (x + dx >= 0 && x + dx < r.width && y + dy >= 0 && y + dy < r.height)
        (y + dy) * r.width + x + dx,
  ];
}

/// Picks the best phase/orientation of a repeating pattern for [room]:
/// stripes two GPUs wide with a cooler line between them (G G C), so every
/// GPU touches a cooler cell. (Where GPUs sit doesn't matter for training:
/// the whole room is one cluster.)
_Plan _makePlan(RoomDef room) {
  const pattern = [_Role.gpu, _Role.gpu, _Role.cool];
  _Plan? best;
  var bestScore = -1000000000;
  for (final transpose in [false, true]) {
    for (var phase = 0; phase < 3; phase++) {
      final roles = List<_Role?>.generate(room.cells, (i) {
        var a = i % room.width;
        if (transpose) a = i ~/ room.width;
        return pattern[(a + phase) % 3];
      });
      // Coolers next to no GPU do nothing.
      for (var i = 0; i < room.cells; i++) {
        if (roles[i] == _Role.cool &&
            !_neighbours(room, i).any((j) => roles[j] == _Role.gpu)) {
          roles[i] = null;
        }
      }
      final order = [
        for (var i = 0; i < room.cells; i++)
          if (roles[i] == _Role.gpu) i,
      ];
      var cooled = 0;
      for (final i in order) {
        if (_neighbours(room, i).any((j) => roles[j] == _Role.cool)) cooled++;
      }
      final score = order.length * 10 + cooled * 6;
      if (score > bestScore) {
        bestScore = score;
        best = _Plan(room, roles, order);
      }
    }
  }
  return best!;
}

final Map<String, _Plan> _plans = {for (final r in rooms) r.id: _makePlan(r)};

class Bot {
  final Game g;
  final BotStrategy strategy;
  final BotLayout layout;

  /// Seconds between "looks at the screen".
  final double thinkEvery;

  /// Longest the bot will save up for one purchase. Later eras have bigger
  /// one-off purchases (power tiers, frontier research), so a sensible
  /// player saves longer for them.
  /// On a play schedule the big one-offs come out of offline earnings, so
  /// in a session it never saves longer than 3 minutes.
  double get maxSaveSeconds =>
      sessionLeft.isInfinite ? _eraSaveSeconds : math.min(180.0, _eraSaveSeconds);

  double get _eraSaveSeconds => switch (g.s.era) {
    Era.garage => 45.0,
    Era.startup => 60.0,
    Era.smallLab => 75.0,
    Era.mediumLab => 75.0,
    Era.bigLab => 150.0,
    Era.globalLab => 300.0,
  };

  /// Seconds of active play left in the current session (infinite =
  /// continuous play) and the offline gap after it. Set by [runPlaythrough].
  double sessionLeft = double.infinity;
  double nextGap = 0;

  /// Stats for balance reports.
  int purchases = 0;

  /// Purchases + releases + training runs started.
  int decisions = 0;
  double lastMeaningfulAction = 0;
  double longestIdle = 0;
  double longestIdleStart = 0;

  /// What the last look saved for (a candidate label), for idle reports.
  String waitingFor = '';

  /// Every stretch over [idleLogOver] seconds without a decision: (start,
  /// length, era, what it was saving for).
  final List<(double, double, Era, String)> idleLog = [];
  static const idleLogOver = 90.0;

  double _nextThink = 0;
  bool _pausedForCrisis = false;

  /// If set, every run uses this model design (clamped to what's unlocked)
  /// instead of [ModelSpec.bestGuessFor]: for testing bad choices.
  final ModelSpec? fixedSpec;

  /// Answer run-phase checkpoints by what blocks progress instead of with
  /// the all-rounder defaults (see _decidePhase).
  final bool specializePhases;

  /// bestGuessFor per lab state (owned research, era, network tier, serving
  /// pressure, data budget bucket), so what-ifs stay cheap.
  final Map<String, ModelSpec> _specCache = {};

  /// The bot's own deterministic RNG (random placement), separate from the
  /// game's so it never changes game events.
  int _rng;

  Bot(
    this.g, {
    this.strategy = BotStrategy.balanced,
    this.layout = BotLayout.template,
    this.thinkEvery = 3,
    this.fixedSpec,
    this.specializePhases = false,
    int seed = 1,
  }) : _rng = seed & 0x7fffffff;

  /// Serving-cost weight for the design pick. Low when rating is what
  /// blocks progress (an era gate, or a rival whose users we already have):
  /// then it trades serving for rating (e.g. RL reasoning). Otherwise higher
  /// while capacity, not demand, limits users.
  double get _serveWeight {
    if (_ratingBlocks) return 4;
    return g.s.users >= 0.9 * g.capacity ? 23 : 6;
  }

  /// True when a better rating, not users, is what the next step needs.
  /// The first rival we can't beat yet (the ladder only advances on the
  /// next tick, so one we already match doesn't count).
  RivalSnapshot? get _rivalAhead {
    for (var i = g.s.rivalIndex; i < rivalLadder.length; i++) {
      if (!g.canBeat(rivalLadder[i])) return rivalLadder[i];
    }
    return null;
  }

  bool get _ratingBlocks {
    final goal = g.nextEraGoal;
    final rival = _rivalAhead;
    return (goal != null && goal.metric == 'rating' && !goal.met) ||
        (rival != null && g.isUnlocked(rival.era) && g.s.users >= rival.users && g.rating < rival.rating);
  }

  /// The model design the bot would pick now (what the run-setup panel's
  /// best options would be for a thoughtful player).
  ModelSpec get spec => specFor(g.plannedFlops(0.5, runSeconds));

  /// The design for a run of [flops] raw FLOPs.
  ModelSpec specFor(double flops) {
    final fixed = fixedSpec;
    if (fixed != null) return fixed.clampTo(g.designContext);
    // Users block a rival whose rating we already have: the cheapest to
    // serve setup that still clears its rating (a player keeps the rating
    // and trades the rest for capacity).
    final rival = _rivalAhead;
    if (rival != null &&
        g.isUnlocked(rival.era) &&
        g.rating >= rival.rating &&
        g.s.users < rival.users) {
      for (final w in const [23.0, 15.0, 10.0, 6.0]) {
        final sp = _specFor(w);
        if (g.predictRatingForFlops(flops, sp) >= rival.rating + 1) return sp;
      }
      return _specFor(4);
    }
    // A run that can't beat the current model is wasted: aim for rating.
    final sp = _specFor(_serveWeight);
    if (g.predictRatingForFlops(flops, sp) < g.rating + 1) return _specFor(4);
    return sp;
  }

  ModelSpec _specFor(double w) {
    final ctx = g.designContext;
    final key = [
      (g.s.ownedUpgrades.toList()..sort()).join(','),
      g.s.era.index,
      g.s.networkTier,
      w,
      (math.log(ctx.plannedCompute + 1) / math.log(ctx.dataTokens * ctx.dataTokens + 1) * 20).round(),
    ].join('|');
    // Chasing rating (lowest serving weight): demand counts for little too.
    return _specCache[key] ??= ModelSpec.bestGuessFor(ctx, serveWeight: w, demandWeight: w <= 4 ? 8 : 30);
  }


  void act() {
    // A checkpoint is a quick call: answer it right away (it holds the run).
    _decidePhase();
    if (g.s.time < _nextThink) return;
    _nextThink = g.s.time + thinkEvery;
    _release();
    _crisis();
    if (layout == BotLayout.template) _rearrange();
    // Spend first, then start the run: research bought now unlocks run-setup
    // options this run can use (a run's design is fixed when it starts).
    // Several purchases per look when money piles up (big new power tier).
    for (var i = 0; i < 12; i++) {
      if (!_spend()) break;
    }
    _train();
  }

  void _meaningful() {
    decisions++;
    finish();
    lastMeaningfulAction = g.s.time;
  }

  /// Starts an idle-stretch measurement fresh (e.g. at a session start).
  void resetIdleClock() => lastMeaningfulAction = g.s.time;

  /// What a player does right before closing the app for [gap] seconds:
  /// ship a finished model, resume a paused run and start the longest run
  /// that will finish while they're away.
  void leave(double gap) {
    sessionLeft = 0;
    nextGap = gap;
    _release();
    if (_pausedForCrisis && g.s.run != null && g.s.run!.paused) {
      g.togglePauseTraining();
    }
    _pausedForCrisis = false;
    _train();
  }

  /// Call at the end of a playthrough so a trailing idle stretch counts.
  void finish() {
    final idle = g.s.time - lastMeaningfulAction;
    if (idle > idleLogOver &&
        (idleLog.isEmpty || idleLog.last.$1 != lastMeaningfulAction)) {
      idleLog.add((lastMeaningfulAction, idle, g.s.era, waitingFor));
    }
    if (idle > longestIdle) {
      longestIdle = idle;
      longestIdleStart = lastMeaningfulAction;
    }
  }

  double _random() {
    _rng = (_rng * 1103515245 + 12345) & 0x7fffffff;
    return _rng / 0x7fffffff;
  }

  // --- Releases --------------------------------------------------------------
  void _release() {
    final pending = g.s.pendingEffectiveCompute;
    if (pending == null) return;
    // Ship a better model, or one that serves far more users without
    // dropping below the next rival's rating when users are what's missing.
    final rival = _rivalAhead;
    final cheaperForRival = rival != null &&
        g.isUnlocked(rival.era) &&
        g.s.users < rival.users &&
        g.pendingRating! >= rival.rating &&
        g.pendingPerUserTflops! < 0.7 * g.currentPerUserTflops;
    if (g.pendingRating! > g.rating + 0.5 || cheaperForRival) {
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
      // Cloud GPUs are pricey: rent only when the extra users would pass the
      // next rival (and it's cheap relative to cash). Otherwise pause
      // training until the spike ends (serving the crowd pays better).
      final rival = g.nextRival;
      final worthIt =
          rival != null &&
          g.canBeat(rival) == false &&
          g.rating >= rival.rating &&
          s.users < rival.users &&
          rival.users < 2 * overflowAllowance * g.capacity;
      if (worthIt &&
          s.cloudSecondsLeft == 0 &&
          g.cloudRentCost < 0.25 * s.money) {
        if (g.rentCloud()) _meaningful();
      } else if (g.training && !_pausedForCrisis) {
        // Pausing to serve the crowd is the spike's call (it's a choice).
        g.togglePauseTraining();
        _pausedForCrisis = true;
        _meaningful();
      }
    } else if (_pausedForCrisis && s.viralSecondsLeft == 0) {
      if (s.run != null && s.run!.paused) {
        g.togglePauseTraining();
        _meaningful();
      }
      _pausedForCrisis = false;
    }
  }

  // --- Run phases ------------------------------------------------------------
  /// Weights for a phase pick: the design pick's, except that serving cost
  /// always counts fully while capacity is what limits users (a phase pick
  /// can't make up lost capacity the way the design's rating can).
  (double, double) get _phaseWeights {
    final w = _serveWeight;
    final capLimited = g.s.users >= 0.9 * g.capacity;
    return (capLimited ? math.max(w, 23.0) : w, w <= 4 && !capLimited ? 8.0 : 30.0);
  }

  /// Checkpoints are answered at once (they hold the run). By default the
  /// bot matches the early data emphasis to its design and takes the
  /// all-rounder at the checkpoints, which only shape the benchmark profile;
  /// with [specializePhases] it trades rating, demand and serving by what
  /// blocks progress (for balance checks: tool/balance_sim.dart --phases).
  void _decidePhase() {
    final phase = g.awaitingPhase;
    if (phase == null) return;
    g.choosePhase(_phasePick(phase, g.s.run!.spec));
    // A checkpoint is a call the player makes mid-run (it holds the run).
    _meaningful();
  }

  PhaseOption _phasePick(RunPhase phase, ModelSpec spec) {
    final ctx = g.phaseContext;
    if (!specializePhases || fixedSpec != null) return defaultPhaseOption(phase, spec, ctx);
    final (sw, dw) = _phaseWeights;
    return bestPhaseOption(phase, spec: spec, ctx: ctx, serveWeight: sw, demandWeight: dw);
  }

  // --- Training --------------------------------------------------------------
  /// Uses only the run lengths the UI offers in this era. Continuous play
  /// takes the middle one early and the longest from the Small lab on. On a
  /// schedule it takes the middle one while the session has time for it, and
  /// otherwise the longest run that finishes before it comes back (so a run
  /// completes while it's away).
  double get runSeconds {
    final opts = g.runDurations;
    if (sessionLeft.isInfinite) {
      // Continuous play: quick runs while they're minutes long, the longest
      // once a lab has hours of work to do between releases anyway.
      return g.s.era.index >= Era.smallLab.index ? opts.last : opts[1];
    }
    if (sessionLeft >= opts[1]) return opts[1];
    final away = sessionLeft + math.min(nextGap, offlineCapSeconds);
    return opts.lastWhere((d) => d <= away, orElse: () => opts.first);
  }

  /// The default run length, unless a shorter one already crosses the next
  /// rating gate or the next rival (the UI shows the predicted rating): then
  /// the shortest such run, so the unlock happens while you're playing. In a
  /// session it may also go longer (up to what fits) to cross it.
  double _runFor(double fraction) {
    final def = runSeconds;
    var target = double.infinity;
    final goal = g.nextEraGoal;
    if (goal != null && goal.metric == 'rating' && !goal.met) {
      target = goal.target;
    }
    final rival = g.nextRival;
    if (rival != null &&
        g.isUnlocked(rival.era) &&
        g.s.users >= rival.users &&
        rival.rating > g.rating) {
      target = math.min(target, rival.rating);
    }
    if (target.isInfinite) return def;
    final limit = math.max(def, sessionLeft.isInfinite ? def : sessionLeft);
    for (final d in g.runDurations) {
      if (d > limit) break;
      if (g.predictRating(fraction, d, spec: specFor(g.plannedFlops(fraction, d))) >= target + 0.5) return d;
    }
    return def;
  }

  void _train() {
    if (!g.canStartTraining) return;
    // Keep enough serving compute for the users we have (plus some growth);
    // train with the rest of the training cluster.
    final need =
        math.min(g.demand, g.s.users * 1.2 + 10) * g.currentPerUserTflops;
    final cluster = g.trainingCluster?.effectiveTflops ?? 0;
    final spare = (g.effectiveTflops - need) / math.max(1e-9, cluster);
    // UI choices: 25% / 50% / 75%.
    final fraction = spare >= 0.75 ? 0.75 : 0.5;
    final duration = _runFor(fraction);
    final sp = specFor(g.plannedFlops(fraction, duration));
    if (g.startTraining(
      fraction: fraction,
      durationSeconds: duration,
      spec: sp,
      early: _phasePick(RunPhase.early, sp),
    )) {
      _meaningful();
    }
  }

  // --- Layout helpers ----------------------------------------------------------

  /// Moves (free) any tile that sits on a cell planned for another kind onto
  /// a free cell of its kind, e.g. the starting GPU.
  void _rearrange() {
    final room = g.currentRoom;
    final plan = _plans[room.id]!;
    final cells = g.s.grids[room.id]!;
    for (var i = 0; i < room.cells; i++) {
      final def = cells[i] == null ? null : tileById(cells[i]!);
      if (def == null) continue;
      final role = _roleOf(def);
      if (plan.roles[i] == role) continue;
      // GPUs the bundle put on spare cooler cells (central cooling) stay.
      if (role == _Role.gpu && plan.roles[i] == _Role.cool) continue;
      final order =
          role == _Role.gpu
              ? plan.gpuOrder
              : [for (var j = 0; j < room.cells; j++) j];
      final to =
          order
              .where((j) => cells[j] == null && plan.roles[j] == role)
              .firstOrNull;
      if (to == null) continue;
      g.moveTile(
        room.id,
        i % room.width,
        i ~/ room.width,
        to % room.width,
        to ~/ room.width,
      );
    }
  }

  static _Role _roleOf(TileDef t) => t.isGpu ? _Role.gpu : _Role.cool;

  /// Parts sold for this room (a sensible player doesn't buy garage GPUs for
  /// a datacenter), or, after moving ahead of the era, for the newest earlier
  /// room whose parts are unlocked.
  Iterable<TileDef> _unlocked(String roomId, TileKind kind) {
    for (var i = roomIndex(roomId); i >= 0; i--) {
      final id = rooms[i].id;
      final ts = tiles.where((t) => t.kind == kind && t.nativeTo(id) && g.isTileUnlocked(t)).toList();
      if (ts.isNotEmpty) return ts;
    }
    return const [];
  }

  /// Power is nearly used up: adding GPUs needs a better tier or better
  /// GPUs per kW.
  bool get _powerTight => g.powerCapKw - g.powerUsedKw < 0.25 * g.powerCapKw;

  /// Best GPU tile for a room by TFLOPS per dollar, or per kW when power is
  /// the bottleneck.
  TileDef? _bestGpu(String roomId, {bool perKw = false}) {
    double score(TileDef t) =>
        perKw ? t.tflopsPerKw : t.tflops / g.tilePrice(t);
    TileDef? best;
    for (final t in _unlocked(roomId, TileKind.gpu)) {
      if (best == null || score(t) > score(best)) best = t;
    }
    return best;
  }

  /// The cheapest GPU tile sold for a room right now, if it isn't the best
  /// one: what you buy while the big tile (a SuperPOD, a whole building) is
  /// out of reach. Active play never stalls on one lumpy purchase.
  TileDef? _smallerGpu(String roomId) {
    final best = _bestGpu(roomId);
    TileDef? cheap;
    for (final t in _unlocked(roomId, TileKind.gpu)) {
      if (cheap == null || g.tilePrice(t) < g.tilePrice(cheap)) cheap = t;
    }
    return cheap == null || cheap == best || g.tilePrice(cheap) >= g.tilePrice(best!) ? null : cheap;
  }

  String? _at(String roomId, int i) => g.s.grids[roomId]![i];

  (int, int) _xy(String roomId, int i) {
    final w = roomById(roomId)!.width;
    return (i % w, i ~/ w);
  }

  /// Apply [ops] as raw grid writes, run [f], then undo them.
  T _whatIf<T>(List<_Op> ops, T Function() f) {
    final undo = <(String, int, int, String?)>[];
    for (final op in ops) {
      undo.add((op.room, op.x, op.y, g.s.tileAt(op.room, op.x, op.y)));
      g.s.setTile(op.room, op.x, op.y, op.tile);
    }
    try {
      return f();
    } finally {
      for (final (r, x, y, id) in undo.reversed) {
        g.s.setTile(r, x, y, id);
      }
    }
  }

  int _gpuTiles() => g.s.grids[g.s.roomId]!
      .where((id) => id != null && tileById(id)!.isGpu)
      .length;

  double _opsCost(List<_Op> ops) => ops.fold(0.0, (a, op) {
    final old = g.s.tileAt(op.room, op.x, op.y);
    return a +
        g.tilePrice(tileById(op.tile)!) -
        (op.replace && old != null ? g.sellValue(old) : 0);
  });

  double _opsKw(List<_Op> ops) => ops.fold(0.0, (a, op) {
    final old = g.s.tileAt(op.room, op.x, op.y);
    return a +
        g.tilePowerKw(tileById(op.tile)!) -
        (op.replace && old != null ? g.tilePowerKw(tileById(old)!) : 0);
  });

  bool _execute(List<_Op> ops) {
    var any = false;
    for (final op in ops) {
      final ok =
          op.replace
              ? g.replaceTile(op.room, op.x, op.y, op.tile)
              : g.placeTile(op.room, op.x, op.y, op.tile);
      if (!ok) break;
      any = true;
    }
    return any;
  }

  /// Cooler for [cell] in a room after [ops]: the cheapest one that cools all
  /// its GPU neighbours, else the strongest that fits the power budget.
  TileDef? _pickCooler(
    String roomId,
    int cell,
    List<_Op> ops, {
    double kwBudget = double.infinity,
  }) {
    final room = roomById(roomId)!;
    final coolers =
        _unlocked(roomId, TileKind.cooling).toList()
          ..sort((a, b) => a.cost.compareTo(b.cost));
    final (x, y) = _xy(roomId, cell);
    final replace = _at(roomId, cell) != null;
    TileDef? strongest;
    for (final c in coolers) {
      if (c.powerKw > kwBudget) continue;
      if (strongest == null || c.cooling > strongest.cooling) strongest = c;
      final cool = _whatIf(
        [...ops, _Op(roomId, x, y, c.id, replace: replace)],
        () {
          for (final j in _neighbours(room, cell)) {
            final (nx, ny) = _xy(roomId, j);
            final st = g.tileStatus(roomId, nx, ny);
            if (st != null && st.def.isGpu && st.netHeat > 0) return false;
          }
          return true;
        },
      );
      if (cool) return c;
    }
    return strongest;
  }

  // --- Building candidates -------------------------------------------------

  /// Next GPU for [roomId] on the plan, with the cooler it needs.
  List<_Op>? _templateBundle(String roomId, {TileDef? gpuOverride}) {
    final plan = _plans[roomId]!;
    final room = plan.room;
    final gpu = gpuOverride ?? _bestGpu(roomId);
    if (gpu == null) return null;
    var slot = plan.gpuOrder.where((i) => _at(roomId, i) == null).firstOrNull;
    if (slot == null) {
      // Plan full: with central cooling, a GPU may not need its cooler cell.
      for (var i = 0; i < room.cells && slot == null; i++) {
        if (plan.roles[i] == _Role.gpu || _at(roomId, i) != null) continue;
        final (x, y) = _xy(roomId, i);
        final cool = _whatIf(
          [_Op(roomId, x, y, gpu.id)],
          () => g.tileStatus(roomId, x, y)!.netHeat <= 0,
        );
        if (cool) slot = i;
      }
      if (slot == null) return null;
    }
    final ops = <_Op>[];
    final (gx, gy) = _xy(roomId, slot);
    ops.add(_Op(roomId, gx, gy, gpu.id));
    // A cooler if it would run hot.
    final hot = _whatIf(ops, () => g.tileStatus(roomId, gx, gy)!.netHeat > 0);
    if (hot) {
      final c =
          _neighbours(room, slot)
              .where(
                (j) => plan.roles[j] == _Role.cool && _at(roomId, j) == null,
              )
              .firstOrNull;
      if (c != null) {
        final kwLeft = g.powerCapKw - g.powerUsedKw - _opsKw(ops);
        final cooler = _pickCooler(roomId, c, ops, kwBudget: kwLeft);
        if (cooler != null) {
          final (x, y) = _xy(roomId, c);
          ops.add(_Op(roomId, x, y, cooler.id));
        }
      }
    }
    return ops;
  }

  /// After a move: lay every tile out again on the new room's plan (moves
  /// are free). GPUs fill the plan's slots best-first, so they stay one
  /// block; coolers go next to GPUs. The old room's coolers are sold (the new
  /// room's free cooling beats them); leftovers go on spare cells, or are
  /// sold if there's no floor left.
  void _relayout() {
    final room = g.currentRoom;
    final plan = _plans[room.id]!;
    final cells = g.s.grids[room.id]!;
    final gpus = <TileDef>[], cools = <TileDef>[];
    for (final id in cells) {
      final d = id == null ? null : tileById(id);
      if (d == null) continue;
      if (d.isCooling && !d.nativeTo(room.id)) {
        g.s.money += g.sellValue(d.id);
        continue;
      }
      (d.isGpu ? gpus : cools).add(d);
    }
    gpus.sort((a, b) => b.tflops.compareTo(a.tflops));
    cools.sort((a, b) => b.cooling.compareTo(a.cooling));
    final out = List<String?>.filled(room.cells, null);
    var gi = 0;
    for (final slot in plan.gpuOrder) {
      if (gi >= gpus.length) break;
      out[slot] = gpus[gi++].id;
    }
    for (var i = 0; i < room.cells && cools.isNotEmpty; i++) {
      if (plan.roles[i] != _Role.cool || out[i] != null) continue;
      if (_neighbours(room, i).any((j) => tileById(out[j] ?? '')?.isGpu == true)) {
        out[i] = cools.removeAt(0).id;
      }
    }
    for (final t in [...gpus.skip(gi), ...cools]) {
      final to =
          [for (var i = 0; i < room.cells; i++) i]
              .where((i) => out[i] == null && plan.roles[i] == null)
              .firstOrNull ??
          [for (var i = 0; i < room.cells; i++) i]
              .where((i) => out[i] == null)
              .firstOrNull;
      if (to != null) {
        out[to] = t.id;
      } else {
        g.s.money += g.sellValue(t.id);
      }
    }
    g.s.grids[room.id] = out;
    g.s.touchGrid();
  }

  List<int> _emptyCells(String roomId) => [
    for (var i = 0; i < roomById(roomId)!.cells; i++)
      if (_at(roomId, i) == null) i,
  ];

  int _pickRandom(List<int> xs) =>
      xs[math.min(xs.length - 1, (_random() * xs.length).floor())];

  /// GPU (and for BotLayout.random a cooler) on random empty cells.
  List<_Op>? _randomBundle(String roomId, {TileDef? gpuOverride}) {
    final gpu = gpuOverride ?? _bestGpu(roomId);
    if (gpu == null) return null;
    final empty = _emptyCells(roomId);
    if (empty.isEmpty) return null;
    final ops = <_Op>[];
    void add(TileDef t) {
      if (empty.isEmpty) return;
      final i = _pickRandom(empty);
      empty.remove(i);
      final (x, y) = _xy(roomId, i);
      ops.add(_Op(roomId, x, y, t.id));
    }

    add(gpu);
    if (layout == BotLayout.random) {
      var gpus = 1, coolers = 0;
      for (final id in g.s.grids[roomId]!) {
        final d = id == null ? null : tileById(id)!;
        if (d == null) continue;
        if (d.isGpu) gpus++;
        if (d.isCooling) coolers++;
      }
      final cs =
          _unlocked(roomId, TileKind.cooling).toList()
            ..sort((a, b) => a.cost.compareTo(b.cost));
      if (cs.isNotEmpty && coolers < gpus / 2) add(cs.first);
    }
    return ops;
  }

  /// Replace a room's weakest GPU tile with its best one (when it's full, or
  /// when power is the limit: then the best per kW). [inCluster] looks only
  /// at the training cluster, where a better GPU also speeds up training.
  List<_Op>? _replaceWorstGpu(
    String roomId, {
    bool inCluster = false,
    TileDef? gpuOverride,
  }) {
    final best = gpuOverride ?? _bestGpu(roomId, perKw: _powerTight);
    if (best == null) return null;
    final room = roomById(roomId)!;
    final cells = g.s.grids[roomId]!;
    final train = inCluster ? g.trainingCluster : null;
    if (inCluster && train == null) return null;
    final allowed = train == null
        ? null
        : {for (final (x, y) in train.gpuCells) y * room.width + x};
    var worst = -1;
    for (var i = 0; i < cells.length; i++) {
      final d = cells[i] == null ? null : tileById(cells[i]!);
      if (d == null || !d.isGpu) continue;
      if (allowed != null && !allowed.contains(i)) continue;
      if (worst < 0 || d.tflops < tileById(cells[worst]!)!.tflops) worst = i;
    }
    if (worst < 0 || best.tflops < 1.4 * tileById(cells[worst]!)!.tflops) {
      return null;
    }
    final (x, y) = _xy(roomId, worst);
    return [_Op(roomId, x, y, best.id, replace: true)];
  }

  /// Cool (or better cool) the hottest GPU in a room via its planned cooler
  /// cell.
  List<_Op>? _heatFix(String roomId) {
    final plan = _plans[roomId]!;
    final room = plan.room;
    var hottest = -1;
    var worstSpeed = 0.97;
    for (var i = 0; i < room.cells; i++) {
      final (x, y) = _xy(roomId, i);
      final st = g.tileStatus(roomId, x, y);
      if (st == null || !st.def.isGpu || st.speed >= worstSpeed) continue;
      if (!_neighbours(room, i).any((j) => plan.roles[j] == _Role.cool)) {
        continue;
      }
      worstSpeed = st.speed;
      hottest = i;
    }
    if (hottest < 0) return null;
    for (final j in _neighbours(room, hottest)) {
      if (plan.roles[j] != _Role.cool) continue;
      final cur = _at(roomId, j);
      final curDef = cur == null ? null : tileById(cur);
      if (curDef != null && !curDef.isCooling) continue;
      final kwLeft =
          g.powerCapKw - g.powerUsedKw + (curDef == null ? 0 : curDef.powerKw);
      final c = _pickCooler(roomId, j, const [], kwBudget: kwLeft);
      if (c == null || (curDef != null && c.cooling <= curDef.cooling)) {
        continue;
      }
      final (x, y) = _xy(roomId, j);
      return [_Op(roomId, x, y, c.id, replace: curDef != null)];
    }
    return null;
  }

  // --- Spending --------------------------------------------------------------

  /// Progress score: model rating (in compute doublings) + log of users we
  /// could serve + a little for revenue per user. [extraTrain] / [extraTotal]
  /// add hypothetical effective TFLOPS (to the training cluster / overall).
  /// The design this look's what-ifs assume (set at the start of [_spend]),
  /// so a hypothetical purchase doesn't also flip the design choice.
  ModelSpec? _lookSpec;

  double _value({double extraTrain = 0, double extraTotal = 0, bool ratingOnly = false, ModelSpec? design}) {
    final train = g.trainingClusterTflops + extraTrain;
    final flops =
        train * 0.5 * 1e12 * g.s.era.computeTimeScale * runSeconds;
    final sp = design ?? _lookSpec ?? spec;
    final e = g.designEffects(sp, flops);
    final effC = g.designedEffectiveCompute(flops, sp, e);
    // The early data emphasis is fixed at the start, so its default (the
    // Tuned mix once researched) counts toward the run's rating.
    var r = g.ratingOf(effC) + e.ratingAdd + defaultPhaseOption(RunPhase.early, sp, g.phaseContext).rating;
    // Risks at their expected rating cost.
    for (final risk in e.risks) {
      r += risk.chance * ratingPerDoubling * math.log(risk.cemMultOnHit) / math.ln2;
    }
    final demand = math.min(
      maxUsers,
      demandBase * math.pow(10, (r - ratingBase) / demandRatingScale) * e.demandMult,
    );
    // Like Game.servingTflops: the run takes its share of the cluster's
    // compute before scaling losses (the loss is wasted, not served).
    final clusterEff = (g.trainingCluster?.effectiveTflops ?? 0) + extraTrain;
    final serving = g.effectiveTflops + extraTotal - 0.5 * clusterEff;
    final cap =
        math.max(0.0, serving) /
        (g.perUserTflops(effC / e.cem) * e.serveCostMult);
    if (ratingOnly) return math.ln2 * r / ratingPerDoubling;
    return math.ln2 * r / ratingPerDoubling +
        math.log(math.max(1.0, math.min(demand, cap))) +
        0.5 * math.log(g.arpuMult) +
        _computeGoalValue(extraTotal);
  }

  /// A compute gate (the Startup era: own N PFLOPS of GPUs) counts GPU
  /// TFLOPS toward it, so the bot fills the room and swaps old cards out
  /// even when users don't need the capacity.
  double _computeGoalValue(double extraEffective) {
    final goal = g.nextEraGoal;
    if (goal == null || goal.metric != 'compute') return 0;
    final peak = g.peakTflops + extraEffective / g.utilization;
    return computeGoalWeight * math.log(math.max(1.0, math.min(goal.target, peak)));
  }

  /// How much a compute gate weighs against rating and users.
  static const computeGoalWeight = 3.0;

  List<UpgradeDef> get _availableUpgrades =>
      allUpgrades
          .where(
            (u) =>
                !g.s.ownedUpgrades.contains(u.id) &&
                g.isUnlocked(u.era) &&
                u.requires.every(g.s.ownedUpgrades.contains),
          )
          .toList();

  /// Hypothetical: [k] tiles of [t] joining the training cluster.
  double _virtualDv(TileDef t, double k, double v0) {
    final add = k * t.tflops * g.utilization;
    return _value(extraTrain: add, extraTotal: add) - v0;
  }

  static bool _noEffects(Effects e) =>
      e.utilizationAdd == 0 &&
      e.trainEffMult == 1 &&
      e.serveEffMult == 1 &&
      e.dataMult == 1 &&
      e.ratingAdd == 0 &&
      e.arpuMult == 1 &&
      e.powerMult == 1;

  /// Returns true if it bought something.
  bool _spend() {
    final s = g.s;
    _lookSpec = null;
    final flops0 = g.plannedFlops(0.5, runSeconds);
    _lookSpec = specFor(flops0);
    final v0 = _value();
    final cands = <_Cand>[];

    final headroom = g.powerCapKw - g.powerUsedKw;
    final powerTight = headroom < 0.25 * g.powerCapKw;
    // Upgrades that gate GPU tiles (liquid cooling) count as infrastructure,
    // so even the hardware-only bot buys them, plus data.
    final hwPrereqs = {
      for (final t in tiles)
        if (t.isGpu) ...t.requires,
      for (final n in networkTiers) ...n.requires,
      for (final c in coolingTiers) ...c.requires,
    };
    final gpuNow = _bestGpu(g.currentRoom.id);
    for (final u in _availableUpgrades) {
      if (strategy == BotStrategy.noUpgrades) break;
      if (strategy == BotStrategy.hardwareOnly &&
          u.category != UpgradeCategory.data &&
          !hwPrereqs.contains(u.id)) {
        continue;
      }
      // Research that unlocks a run-setup option: while rating is what
      // blocks, value it by the rating it adds (a pricier-to-serve but
      // smarter model, e.g. RL reasoning, is then worth it).
      final designUnlock = _ratingBlocks &&
          (optionsUnlockedBy(u.id).isNotEmpty ||
              designResearchModifiers.containsKey(u.id) ||
              phaseOptionsUnlockedBy(u.id).isNotEmpty);
      final r0 = designUnlock ? _value(ratingOnly: true) : 0.0;
      s.ownedUpgrades.add(u.id);
      // With the research, the design may change too: take the better of
      // keeping this look's design and re-picking it.
      final respec = specFor(flops0);
      var dv = math.max(_value(), _value(design: respec)) - v0;
      if (designUnlock) {
        dv = math.max(dv, math.max(_value(ratingOnly: true), _value(ratingOnly: true, design: respec)) - r0);
      }
      // Research whose only job is to make a speculative GPU (the sci-fi
      // tiers past Rubin) the room's best buy: worth at least what an equal
      // spend on that GPU adds, like a power tier. (Earlier eras are tuned
      // around the flat bonus below.)
      final unlocked = _noEffects(u.effects) ? _bestGpu(g.currentRoom.id) : null;
      s.ownedUpgrades.remove(u.id);
      if (unlocked != null && unlocked != gpuNow && unlocked.speculative) {
        dv = math.max(dv, _virtualDv(unlocked, math.max(1.0, (u.cost / g.tilePrice(unlocked)).floorToDouble()), v0));
      }
      // Power savings = more GPUs under the same cap.
      if (u.effects.powerMult < 1) {
        dv += 2 * math.log(1 / u.effects.powerMult) * (powerTight ? 1 : 0.3);
      }
      // Unlocking better tiles is worth something too.
      if (hwPrereqs.contains(u.id)) {
        dv += 0.05;
      }
      cands.add(
        _Cand(u.cost, dv, () => g.buyUpgrade(u.id), upgrade: true, label: u.id),
      );
    }

    // Grid work in the room.
    void addOps(List<_Op>? ops) {
      if (ops == null || ops.isEmpty) return;
      if (_opsKw(ops) > headroom + 1e-9) return;
      final dv = _whatIf(ops, _value) - v0;
      final cost = _opsCost(ops);
      if (cost <= 0) return;
      cands.add(
        _Cand(
          cost,
          dv,
          () => _execute(ops),
          label: ops.map((o) => o.tile).join('+'),
        ),
      );
    }

    final room = g.currentRoom;
    final bundle =
        layout == BotLayout.template
            ? _templateBundle(room.id)
            : _randomBundle(room.id);
    final smaller = _smallerGpu(room.id);
    final roomsFull = bundle == null;
    addOps(bundle);
    if (smaller != null && !roomsFull) {
      addOps(
        layout == BotLayout.template
            ? _templateBundle(room.id, gpuOverride: smaller)
            : _randomBundle(room.id, gpuOverride: smaller),
      );
    }
    if (roomsFull || _powerTight) {
      addOps(_replaceWorstGpu(room.id));
      addOps(_replaceWorstGpu(room.id, inCluster: true));
      if (smaller != null) addOps(_replaceWorstGpu(room.id, gpuOverride: smaller));
    }
    if (layout == BotLayout.template) addOps(_heatFix(room.id));

    // Central cooling tier: worth it when GPUs throttle (or to free cooler
    // cells for GPUs once the plan is full).
    final cool = g.nextCoolingTier;
    if (cool != null &&
        g.isUnlocked(cool.era) &&
        cool.requires.every(s.ownedUpgrades.contains)) {
      s.coolingTier++;
      var dv = _value() - v0;
      s.coolingTier--;
      if (roomsFull) dv += 0.05;
      cands.add(_Cand(cool.cost, dv, g.buyNextCoolingTier, label: 'cooling'));
    }

    // Network tier: worth it once the training cluster outgrows the cap.
    final net = g.nextNetworkTier;
    if (net != null &&
        g.isUnlocked(net.era) &&
        net.requires.every(s.ownedUpgrades.contains)) {
      s.networkTier++;
      final dv = _value() - v0;
      s.networkTier--;
      final c = g.trainingCluster;
      cands.add(
        _Cand(
          net.cost,
          dv,
          g.buyNextNetworkTier,
          label: 'network',
          // A cluster far past the cap wastes most of a run: fix it first.
          essential: c != null && c.scalingEfficiency < 0.7,
        ),
      );
    }

    // The best GPU we could place (for valuing power and the next room).
    final bestGpu = _bestGpu(room.id);
    final nextRoom = g.nextRoom;

    // Power: worth it if we're nearly full (or out of floor space, since the
    // next room's GPUs will want it). Value it as "tier + an equal spend on
    // GPUs to fill it". A tier past this building's electrical service needs
    // the move first: then the move carries the power's value.
    final next = g.nextPowerTier;
    final powerNeedsMove = g.powerNeedsMove;
    // Just moved into a building made for more: the tier it's built around.
    final roomBase = _roomPowerFloor[room.id] ?? 0;
    // The next room is unlocked and its GPUs will want the power this
    // building can still take.
    final roomNeedsPower = nextRoom != null &&
        g.isUnlocked(nextRoom.era) &&
        s.powerTier < room.maxPowerTier;
    // Out of power: no GPU bundle fits in the headroom any more.
    final blocked = !cands.any((c) => c.label.contains('gpu_') ||
        c.label.contains('srv_') ||
        c.label.contains('rack_') ||
        c.label.contains('pod_') ||
        c.label.contains('bldg_'));
    // A tier a better speculative GPU needs (the fusion PPA for the
    // cryo-logic vaults), valued with that GPU even before power is tight.
    TileDef? powerGpu;
    if (next != null && !powerNeedsMove && g.isUnlocked(next.era)) {
      s.powerTier++;
      final t = _bestGpu(room.id);
      s.powerTier--;
      if (t != null && t != bestGpu && t.speculative) powerGpu = t;
    }
    final wantPower = bestGpu != null &&
        next != null &&
        g.isUnlocked(next.era) &&
        (powerTight ||
            powerGpu != null ||
            roomsFull ||
            roomNeedsPower ||
            // Moved ahead of the power: the room's own tier, or the best GPU
            // doesn't fit in what's left.
            s.powerTier < roomBase ||
            g.tilePowerKw(bestGpu) > headroom);
    final powerEssential = wantPower &&
        (blocked || (roomsFull && roomNeedsPower) || g.tilePowerKw(bestGpu) > headroom);
    double powerK(double capKw, TileDef gpu, double cost) => math
        .max(
          1.0,
          math.min((capKw - g.powerUsedKw) / g.tilePowerKw(gpu), cost / g.tilePrice(gpu)),
        )
        .floorToDouble();

    // Next room: worth it when it can hold better or more GPUs. It opens
    // with its era (then it costs money). Moving takes everything along;
    // the template bot then re-lays it on the new plan.
    if (nextRoom != null && g.canMoveSoon(nextRoom.id)) {
      final native = _bestGpu(nextRoom.id);
      final t = native ?? bestGpu;
      if (t != null) {
        final k = math.min(
          math.min(
            (_plans[nextRoom.id]!.gpuOrder.length - _gpuTiles()).toDouble(),
            (headroom / g.tilePowerKw(t)).floorToDouble(),
          ),
          math.max(1.0, (nextRoom.cost / g.tilePrice(t)).floorToDouble()),
        );
        var dv = k >= 1 ? _virtualDv(t, k, v0) : 0.0;
        // The power tier this building can't take: moving is its first
        // step, so the move carries the tier's value (GPUs to fill it with
        // the money of both).
        if (wantPower && powerNeedsMove) {
          final both = next.cost + nextRoom.cost;
          final pk = powerK(next.capacityKw, bestGpu, both);
          dv = math.max(dv, _virtualDv(bestGpu, pk, v0));
        }
        if (dv > 0) {
          cands.add(
            _Cand(
              nextRoom.cost,
              dv,
              () {
                if (!g.moveTo(nextRoom.id)) return false;
                if (layout == BotLayout.template) _relayout();
                return true;
              },
              label: 'move:${nextRoom.id}',
              essential: (roomsFull && g.isUnlocked(nextRoom.era)) ||
                  (powerNeedsMove && powerEssential),
            ),
          );
        }
      }
    }

    if (wantPower && !powerNeedsMove) {
      cands.add(
        _Cand(
          next.cost,
          _virtualDv(powerGpu ?? bestGpu, powerK(next.capacityKw, powerGpu ?? bestGpu, next.cost), v0),
          g.buyNextPowerTier,
          label: 'power:${next.id}',
          essential: powerEssential,
        ),
      );
    }

    if (cands.isEmpty) {
      waitingFor = '(nothing to buy)';
      return false;
    }

    if (strategy == BotStrategy.softwareFirst) {
      final ups =
          cands.where((c) => c.upgrade && c.dv > 0).toList()
            ..sort((a, b) => a.cost.compareTo(b.cost));
      if (ups.isNotEmpty) {
        final u = ups.first;
        if (s.money >= u.cost) {
          if (u.buy()) {
            purchases++;
            _meaningful();
            return true;
          }
          return false;
        }
        // Save unless it's hopelessly far away.
        if (u.cost < s.money + 200 * g.revenuePerSecond) return false;
      }
    }

    cands.removeWhere((c) => c.dv <= 1e-9);
    if (cands.isEmpty) return false;
    cands.sort((a, b) => (b.dv / b.cost).compareTo(a.dv / a.cost));
    // Best affordable option, as the yardstick for "worth saving for".
    final affordable = cands.where((c) => s.money >= c.cost).firstOrNull;
    for (final c in cands) {
      if (s.money >= c.cost) {
        if (c.buy()) {
          purchases++;
          _meaningful();
          return true;
        }
        return false;
      }
      // Not affordable yet: save for it if it's close, and wait longer the
      // better a deal it is compared with what we could buy right now.
      final wait = (c.cost - s.money) / math.max(1e-9, g.revenuePerSecond);
      final ratio =
          affordable == null
              ? 8.0
              : (c.dv / c.cost) / (affordable.dv / affordable.cost);
      // Research that's a far better deal than any GPU (a ×2 serving trick,
      // RLHF) is worth a longer save than hardware: up to 6× as long. In
      // active play the run's checkpoints keep you busy meanwhile.
      final k = c.upgrade ? 6.0 : 1.0;
      final patience =
          ((60 + 150 * (math.log(math.max(1.0, ratio)) / math.ln2)) *
                  k *
                  maxSaveSeconds /
                  480)
              .clamp(20.0, k * maxSaveSeconds);
      if (wait < patience || c.essential) {
        waitingFor = c.label;
        return false;
      }
    }
    waitingFor = '(nothing worth saving for)';
    return false;
  }
}


/// The power tier the bot buys as soon as it can after moving into each
/// room (the room's own tier; the campus starts on the substation it was
/// planned with in the hall).
const _roomPowerFloor = {'closet': 2, 'colo': 3, 'hall': 4, 'campus': 5, 'gigasite': 7};

class _Cand {
  final double cost;
  final double dv;
  final bool Function() buy;
  final bool upgrade;
  final String label;

  /// The obvious next step when growth is blocked (power tier when out of
  /// power, next room when out of floor space): saved for however long it
  /// takes.
  final bool essential;
  _Cand(
    this.cost,
    this.dv,
    this.buy, {
    this.upgrade = false,
    this.label = '',
    this.essential = false,
  });
}

/// Summary of a headless playthrough.
class PlaythroughResult {
  final BotStrategy strategy;
  final BotLayout layout;
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

  /// Stretches over [Bot.idleLogOver] without a decision (see [Bot.idleLog]).
  List<(double, double, Era, String)> idleLog = const [];

  /// Purchases, releases, runs started, checkpoint calls and viral-spike
  /// responses (the bot's meaningful decisions), up to the final rival.
  int decisions = 0;
  double minMoney = double.infinity;
  double usersAtFinish = 0;
  double arrAtFinish = 0;
  double h100eAtFinish = 0;
  double powerKwAtFinish = 0;

  /// Each room's fill when its way out opened (continuous runs only).
  final RoomFill roomFill = RoomFill();

  /// Scheduled runs only: the sessions, wall-clock length and the simulated
  /// (in-game) time at the final rival.
  final List<SessionStats> sessions = [];
  double? wallSeconds;
  double? simFinishTime;

  PlaythroughResult(
    this.strategy,
    this.game, {
    this.layout = BotLayout.template,
  });

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

/// Each room's fill when the next room's era unlocks (the way out opens),
/// and how long it had sat at its wall by then.
class RoomFill {
  final Map<String, RoomSnap> snaps = {};
  String? _room;
  double? _wallSince;
  double? _firstWall;
  double _enteredAt = 0;

  /// The most power you could have here now: the building's top tier
  /// among the eras you've reached.
  static double capKw(Game g, [Era? era]) {
    final reached = (era ?? g.s.era).index;
    var i = g.currentRoom.maxPowerTier;
    while (i > 0 && powerTiers[i].era.index > reached) {
      i--;
    }
    return powerTiers[i].capacityKw;
  }

  /// The room is at its wall: no empty cell, or no GPU sold for it fits in
  /// the power left under [capKw].
  static bool atWall(Game g) {
    final room = g.currentRoom;
    final cells = g.s.grids[room.id]!;
    final used = cells.where((c) => c != null).length;
    if (used >= room.cells) return true;
    final left = capKw(g) - g.powerUsedKw;
    return !tiles.any((t) =>
        t.isGpu && t.nativeTo(room.id) && g.isUnlocked(t.era) && g.tilePowerKw(t) <= left);
  }

  void onTick(Game g) {
    final id = g.currentRoom.id;
    if (id != _room) {
      _room = id;
      _wallSince = null;
      _firstWall = null;
      _enteredAt = g.s.time;
    }
    if (atWall(g)) {
      _wallSince ??= g.s.time;
      _firstWall ??= g.s.time;
    } else {
      _wallSince = null;
    }
  }

  void onEvent(Game g, GameEvent e) {
    if (e case EraUnlocked(:final era)) {
      final next = g.nextRoom;
      if (next != null && next.era == era) _snap(g, exit: true);
    }
  }

  void _snap(Game g, {required bool exit}) {
    final room = g.currentRoom;
    final cells = g.s.grids[room.id]!;
    final wall = atWall(g) ? (_wallSince ?? g.s.time) : null;
    snaps[room.id] = RoomSnap(
      room,
      enteredAt: _room == room.id ? _enteredAt : g.s.time,
      at: g.s.time,
      exit: exit,
      gpuTiles: g.grid.rooms[room.id]?.gpuTiles ?? 0,
      cellsUsed: cells.where((c) => c != null).length,
      powerKw: g.powerUsedKw,
      // At an exit the era just moved on: the cap of the era it was.
      capKw: capKw(g, exit ? Era.values[g.s.era.index - 1] : null),
      wallSeconds: wall == null ? null : g.s.time - wall,
      firstWallSeconds: _room == room.id && _firstWall != null ? g.s.time - _firstWall! : null,
    );
  }

  /// The last room has no way out: its fill at the final rival (or the end
  /// of the run).
  void finish(Game g) {
    if (!snaps.containsKey(g.currentRoom.id)) _snap(g, exit: false);
  }
}

class RoomSnap {
  final RoomDef room;
  final double enteredAt, at, powerKw, capKw;
  final bool exit;
  final int gpuTiles, cellsUsed;
  final double? wallSeconds;

  /// Since the room first hit its wall (it may have dipped below it since,
  /// e.g. while swapping GPUs).
  final double? firstWallSeconds;
  RoomSnap(
    this.room, {
    required this.enteredAt,
    required this.at,
    required this.exit,
    required this.gpuTiles,
    required this.cellsUsed,
    required this.powerKw,
    required this.capKw,
    required this.wallSeconds,
    required this.firstWallSeconds,
  });
}

/// Plays [maxSeconds] (or until the ladder is done when [stopWhenDone]).
/// [onEvent] sees every sim event with the game, e.g. for logging.
PlaythroughResult runPlaythrough({
  BotStrategy strategy = BotStrategy.balanced,
  BotLayout layout = BotLayout.template,
  double maxSeconds = 8 * 3600,
  double dt = 1,
  bool stopWhenDone = true,
  void Function(Game g, GameEvent e)? onEvent,
  void Function(Game g)? onTick,
  int seed = 12345,
  double thinkEvery = 4,
  ModelSpec? fixedSpec,
  bool specializePhases = false,
}) {
  final g = Game(GameState(rngState: seed));
  final bot = Bot(
    g,
    strategy: strategy,
    layout: layout,
    seed: seed,
    thinkEvery: thinkEvery,
    fixedSpec: fixedSpec,
    specializePhases: specializePhases,
  );
  final r = PlaythroughResult(strategy, g, layout: layout);
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
        case RoomMoved():
          break;
      }
      r.roomFill.onEvent(g, e);
      onEvent?.call(g, e);
    }
    g.events.clear();
    r.roomFill.onTick(g);
    onTick?.call(g);
    if (r.ladderDone && !idleFrozen) {
      r.roomFill.finish(g);
      r.usersAtFinish = g.s.users;
      r.arrAtFinish = g.arr;
      r.h100eAtFinish = g.peakTflops / 990;
      r.powerKwAtFinish = g.powerUsedKw;
      // Dead stretches only matter while there is a ladder to climb.
      bot.finish();
      r.longestIdle = bot.longestIdle;
      r.longestIdleStart = bot.longestIdleStart;
      r.idleLog = List.of(bot.idleLog);
      r.decisions = bot.decisions;
      idleFrozen = true;
    }
    if (stopWhenDone && r.ladderDone) break;
  }
  r.roomFill.finish(g);
  if (!idleFrozen) {
    bot.finish();
    r.longestIdle = bot.longestIdle;
    r.longestIdleStart = bot.longestIdleStart;
    r.idleLog = List.of(bot.idleLog);
    r.decisions = bot.decisions;
  }
  return r;
}

/// A repeating day of play sessions: (active seconds, offline gap after it).
/// An empty [day] is continuous play: one endless session, no offline gaps
/// (played by [runPlaythrough]).
class PlaySchedule {
  final String name;
  final List<(double, double)> day;

  /// Seconds between the bot's looks at the screen, i.e. its reaction delay
  /// (a decision waits 0–[reactionSeconds] after it becomes possible).
  final double reactionSeconds;
  const PlaySchedule(this.name, this.day, {this.reactionSeconds = 3});

  bool get continuous => day.isEmpty;

  /// The default: an engaged player who keeps playing (Game Dev
  /// Tycoon-style) and reacts within a few seconds. No offline gaps.
  static const active = PlaySchedule('active', [], reactionSeconds: 4);

  /// A casual player on a 24 h day: four sessions (60, 45, 30 and 60 min)
  /// with 2.5–3 h breaks, then a 12 h night. Offline progress stops at
  /// [offlineCapSeconds] (2 h), so most of each break earns nothing.
  static const casual = PlaySchedule('casual', [
    (60 * 60, 2.5 * 3600),
    (45 * 60, 3 * 3600),
    (30 * 60, 3 * 3600),
    (60 * 60, 12.25 * 3600),
  ]);

  static PlaySchedule byName(String name) => switch (name) {
    'casual' => casual,
    'active' || 'continuous' => active,
    _ => throw ArgumentError('unknown schedule $name'),
  };
}

/// One active session of a scheduled playthrough.
class SessionStats {
  final int index;
  final double wallStart;
  final double simStart;
  final double length;
  final Era eraAtStart;

  /// A training run ended during the offline gap before this session.
  final bool runFinishedAway;
  int decisions = 0;
  int purchases = 0;
  int releases = 0;
  double longestIdle = 0;

  /// Seconds from the session start to the first decision (∞ = none).
  double firstDecisionAfter = double.infinity;
  int rivalsBeaten = 0;
  final List<Era> erasUnlocked = [];

  SessionStats(
    this.index,
    this.wallStart,
    this.simStart,
    this.length,
    this.eraAtStart, {
    this.runFinishedAway = false,
  });
}

/// Plays [schedule] for [maxWallSeconds] of wall-clock time (sessions plus
/// offline gaps). Active play ticks at [dt]; each gap goes through the real
/// offline path ([Game.applyOffline], capped at [offlineCapSeconds]). The
/// result's era and rival times are wall-clock (an offline unlock counts when
/// it happens). A continuous schedule (the default, [PlaySchedule.active])
/// is one endless session via [runPlaythrough]. [thinkEvery] defaults to the
/// schedule's reaction delay.
PlaythroughResult runSchedule({
  PlaySchedule schedule = PlaySchedule.active,
  BotStrategy strategy = BotStrategy.balanced,
  BotLayout layout = BotLayout.template,
  double maxWallSeconds = 12 * 3600,
  double dt = 1,
  bool stopWhenDone = true,
  void Function(Game g, GameEvent e, double wall)? onEvent,
  void Function(Game g, SessionStats s)? onSession,
  void Function(Game g, double wall)? onTick,
  int seed = 12345,
  double? thinkEvery,
  ModelSpec? fixedSpec,
  bool specializePhases = false,
}) {
  thinkEvery ??= schedule.reactionSeconds;
  if (schedule.continuous) {
    return runPlaythrough(
      strategy: strategy,
      layout: layout,
      maxSeconds: maxWallSeconds,
      dt: dt,
      stopWhenDone: stopWhenDone,
      onEvent: onEvent == null ? null : (g, e) => onEvent(g, e, g.s.time),
      onTick: onTick == null ? null : (g) => onTick(g, g.s.time),
      seed: seed,
      thinkEvery: thinkEvery,
      fixedSpec: fixedSpec,
      specializePhases: specializePhases,
    );
  }
  final g = Game(GameState(rngState: seed));
  final bot = Bot(
    g,
    strategy: strategy,
    layout: layout,
    seed: seed,
    thinkEvery: thinkEvery,
    fixedSpec: fixedSpec,
    specializePhases: specializePhases,
  );
  final r = PlaythroughResult(strategy, g, layout: layout);
  r.eraTimes[Era.garage] = 0;
  var wall = 0.0;
  SessionStats? cur;

  void collect(double wallNow) {
    for (final e in g.events) {
      switch (e) {
        case EraUnlocked(:final era):
          r.eraTimes[era] = wallNow;
          cur?.erasUnlocked.add(era);
        case RivalBeaten(:final rival):
          r.rivalTimes.add((rival, wallNow));
          if (cur != null) cur.rivalsBeaten++;
        case ViralSpikeStarted():
          r.viralSpikes++;
        case ModelReleased():
          r.releases++;
        case TrainingFinished():
        case RoomMoved():
          break;
      }
      onEvent?.call(g, e, wallNow);
    }
    g.events.clear();
    r.maxUsersSeen = math.max(r.maxUsersSeen, g.s.users);
    r.minMoney = math.min(r.minMoney, g.s.money);
    if (r.ladderDone && r.simFinishTime == null) {
      r.simFinishTime = g.s.time;
      r.usersAtFinish = g.s.users;
      r.arrAtFinish = g.arr;
      r.h100eAtFinish = g.peakTflops / 990;
      r.powerKwAtFinish = g.powerUsedKw;
    }
  }

  var runFinishedAway = false;
  var i = 0;
  while (wall < maxWallSeconds && !(stopWhenDone && r.ladderDone)) {
    final (active, gap) = schedule.day[i % schedule.day.length];
    final session = SessionStats(
      i,
      wall,
      g.s.time,
      active,
      g.s.era,
      runFinishedAway: runFinishedAway,
    );
    cur = session;
    final ladderWasDone = r.ladderDone;
    final d0 = bot.decisions, p0 = bot.purchases, rel0 = r.releases;
    bot.longestIdle = 0;
    bot.resetIdleClock();
    final t0 = g.s.time;
    while (g.s.time - t0 < active - 1e-9) {
      bot.sessionLeft = active - (g.s.time - t0);
      bot.nextGap = gap;
      final before = bot.decisions;
      bot.act();
      if (bot.decisions > before &&
          session.firstDecisionAfter.isInfinite) {
        session.firstDecisionAfter = g.s.time - t0;
      }
      final step = math.min(dt, active - (g.s.time - t0));
      g.tick(step);
      wall += step;
      if (g.overloaded) {
        r.overloadedSeconds += step;
        if (g.s.viralSecondsLeft > 0) r.overloadedViralSeconds += step;
      }
      collect(wall);
      onTick?.call(g, wall);
      if (stopWhenDone && r.ladderDone) break;
    }
    bot.finish();
    session.longestIdle = bot.longestIdle;
    // Bot.decisions also counts what leave() does below; that belongs to the
    // session too (the last thing you do before closing the app).
    bot.leave(gap);
    collect(wall);
    session.decisions = bot.decisions - d0;
    session.purchases = bot.purchases - p0;
    session.releases = r.releases - rel0;
    r.sessions.add(session);
    onSession?.call(g, session);
    if (!ladderWasDone && session.longestIdle > r.longestIdle) {
      r.longestIdle = session.longestIdle;
      r.longestIdleStart = session.wallStart;
    }
    if (stopWhenDone && r.ladderDone) break;
    // Offline gap.
    final simStart = g.s.time, wallStart = wall;
    final hadRun = g.s.run != null;
    g.applyOffline(gap, onStep: () => collect(wallStart + g.s.time - simStart));
    runFinishedAway = hadRun && g.s.run == null;
    wall = wallStart + gap;
    cur = null;
    i++;
  }
  r.wallSeconds = wall;
  r.idleLog = List.of(bot.idleLog);
  r.decisions = bot.decisions;
  return r;
}

/// The template plan for a room as text (G = GPU, C = cooler),
/// for debugging and tests.
String describePlan(String roomId) {
  final plan = _plans[roomId]!;
  final b = StringBuffer();
  for (var y = 0; y < plan.room.height; y++) {
    for (var x = 0; x < plan.room.width; x++) {
      b.write(switch (plan.roles[y * plan.room.width + x]) {
        _Role.gpu => 'G',
        _Role.cool => 'C',
        null => '.',
      });
    }
    b.writeln();
  }
  return b.toString();
}

/// GPU cells in a room's template plan.
int planGpuSlots(String roomId) => _plans[roomId]!.gpuOrder.length;
