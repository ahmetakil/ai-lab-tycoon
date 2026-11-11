// Headless player used by tool/balance_sim.dart and the sim tests.
// Pure Dart and deterministic. It plays like an engaged human: it looks at
// the game every few seconds, keeps a training run going, releases better
// models, handles viral crises and spends money on whatever buys the most
// progress per dollar (saving up when something good is close).
//
// Placement (BotLayout.template): each room gets a fixed plan of GPU,
// switch and cooler cells (rows/columns of switches with GPUs on both sides
// and coolers between, or a staggered version of it), filled in an order that
// keeps everything in one cluster. Coolers go in only where a GPU runs hot,
// and switches are upgraded when a cluster outgrows them.
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

/// How the bot places tiles.
enum BotLayout {
  /// Planned layout: switch spines, GPUs beside them, coolers where hot.
  template,

  /// GPUs only, dropped on random empty cells: no switches, no coolers.
  naive,

  /// Buys a similar mix of GPUs, switches and coolers but drops each on a
  /// random empty cell.
  random,
}

enum _Role { gpu, net, cool }

/// A room's target layout.
class _Plan {
  final RoomDef room;
  final List<_Role?> roles;

  /// GPU cells in fill order (each one touches a switch reachable from the
  /// earlier ones).
  final List<int> gpuOrder;

  /// BFS parent of each planned cell (−1 = root).
  final List<int> parent;

  _Plan(this.room, this.roles, this.gpuOrder, this.parent);
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

/// Picks the best of a few repeating patterns for [room]: a row or column of
/// switches with a GPU line on each side and a cooler line between pairs
/// (G S G C), straight or staggered row to row, optionally with a
/// perpendicular switch backbone that links the spines into one cluster.
_Plan _makePlan(RoomDef room) {
  const pattern = [_Role.gpu, _Role.net, _Role.gpu, _Role.cool];
  _Plan? best;
  var bestScore = -1000000000;
  for (final transpose in [false, true]) {
    for (var phase = 0; phase < 4; phase++) {
      for (var stagger = 0; stagger < 4; stagger++) {
        for (final backbone in [-1, 0, 1, 2]) {
          final len = transpose ? room.width : room.height;
          final bRow = switch (backbone) {
            0 => 0,
            1 => len ~/ 2,
            2 => len - 1,
            _ => -1,
          };
          final roles = List<_Role?>.generate(room.cells, (i) {
            var a = i % room.width, b = i ~/ room.width;
            if (transpose) (a, b) = (b, a);
            if (b == bRow) return _Role.net;
            return pattern[(a + phase + stagger * (b % 2)) % 4];
          });
          // GPUs that can't reach a switch become coolers (or nothing);
          // coolers next to no GPU are dropped.
          for (var i = 0; i < room.cells; i++) {
            if (roles[i] != _Role.gpu) continue;
            final n = _neighbours(room, i);
            if (!n.any((j) => roles[j] == _Role.net)) {
              roles[i] =
                  n.any((j) => roles[j] == _Role.gpu) ? _Role.cool : null;
            }
          }
          for (var i = 0; i < room.cells; i++) {
            if (roles[i] == _Role.cool &&
                !_neighbours(room, i).any((j) => roles[j] == _Role.gpu)) {
              roles[i] = null;
            }
          }
          final plan = _order(room, roles);
          var cooled = 0;
          for (final i in plan.gpuOrder) {
            if (_neighbours(room, i).any((j) => roles[j] == _Role.cool)) {
              cooled++;
            }
          }
          final roots =
              [
                for (var i = 0; i < room.cells; i++)
                  if (roles[i] != null &&
                      roles[i] != _Role.cool &&
                      plan.parent[i] < 0)
                    i,
              ].length;
          // Split clusters are what the template is meant to avoid.
          final score =
              plan.gpuOrder.length * 10 + cooled * 4 - (roots - 1) * 1000;
          if (score > bestScore) {
            bestScore = score;
            best = plan;
          }
        }
      }
    }
  }
  return best!;
}

/// BFS over GPU and switch cells (GPU–switch and switch–switch links) to get
/// a fill order that grows one connected cluster.
_Plan _order(RoomDef room, List<_Role?> roles) {
  final parent = List<int>.filled(room.cells, -1);
  final seen = List<bool>.filled(room.cells, false);
  final gpuOrder = <int>[];
  for (var start = 0; start < room.cells; start++) {
    if (roles[start] != _Role.gpu || seen[start]) continue;
    final queue = [start];
    seen[start] = true;
    for (var q = 0; q < queue.length; q++) {
      final i = queue[q];
      if (roles[i] == _Role.gpu) gpuOrder.add(i);
      for (final j in _neighbours(room, i)) {
        if (seen[j] || roles[j] == null || roles[j] == _Role.cool) continue;
        // GPU–GPU adjacency doesn't link.
        if (roles[i] == _Role.gpu && roles[j] == _Role.gpu) continue;
        seen[j] = true;
        parent[j] = i;
        queue.add(j);
      }
    }
  }
  return _Plan(room, roles, gpuOrder, parent);
}

final Map<String, _Plan> _plans = {for (final r in rooms) r.id: _makePlan(r)};

class Bot {
  final Game g;
  final BotStrategy strategy;
  final BotLayout layout;

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

  /// The bot's own deterministic RNG (random placement), separate from the
  /// game's so it never changes game events.
  int _rng;

  Bot(
    this.g, {
    this.strategy = BotStrategy.balanced,
    this.layout = BotLayout.template,
    this.thinkEvery = 3,
    int seed = 1,
  }) : _rng = seed & 0x7fffffff;

  void act() {
    if (g.s.time < _nextThink) return;
    _nextThink = g.s.time + thinkEvery;
    _release();
    _crisis();
    if (layout == BotLayout.template) _rearrange();
    _train();
    // Several purchases per look when money piles up (big new power tier).
    for (var i = 0; i < 12; i++) {
      if (!_spend()) break;
    }
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

  double _random() {
    _rng = (_rng * 1103515245 + 12345) & 0x7fffffff;
    return _rng / 0x7fffffff;
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
    // train with the rest of the training cluster.
    final need =
        math.min(g.demand, g.s.users * 1.2 + 10) *
        g.perUserTflops(g.s.currentModel.effectiveCompute);
    final cluster = g.trainingCluster?.effectiveTflops ?? 0;
    final spare = (g.effectiveTflops - need) / math.max(1e-9, cluster);
    // UI choices: 25% / 50% / 75%.
    g.startTraining(
      fraction: spare >= 0.75 ? 0.75 : 0.5,
      durationSeconds: runSeconds,
    );
  }

  // --- Layout helpers ----------------------------------------------------------

  /// Moves (free) any tile that sits on a cell planned for another kind onto
  /// a free cell of its kind, e.g. the starting GPU.
  void _rearrange() {
    for (final room in g.ownedRooms) {
      final plan = _plans[room.id]!;
      final cells = g.s.grids[room.id]!;
      for (var i = 0; i < room.cells; i++) {
        final def = cells[i] == null ? null : tileById(cells[i]!);
        if (def == null) continue;
        final role = _roleOf(def);
        if (plan.roles[i] == role) continue;
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
  }

  static _Role _roleOf(TileDef t) => switch (t.kind) {
    TileKind.gpu => _Role.gpu,
    TileKind.network => _Role.net,
    TileKind.cooling => _Role.cool,
  };

  Iterable<TileDef> _unlocked(String roomId, TileKind kind) => tiles.where(
    (t) => t.kind == kind && t.rooms.contains(roomId) && g.isTileUnlocked(t),
  );

  /// Best GPU tile for a room by TFLOPS per dollar.
  TileDef? _bestGpu(String roomId) {
    TileDef? best;
    for (final t in _unlocked(roomId, TileKind.gpu)) {
      if (best == null || t.tflops / t.cost > best.tflops / best.cost) {
        best = t;
      }
    }
    return best;
  }

  /// Cheapest switch that can feed the room's whole planned cluster, else
  /// the biggest available.
  TileDef? _bestSwitch(String roomId) {
    final gpu = _bestGpu(roomId);
    final need = _plans[roomId]!.gpuOrder.length * (gpu?.gpusPerTile ?? 1);
    final all = _unlocked(roomId, TileKind.network).toList();
    if (all.isEmpty) return null;
    final enough =
        all.where((t) => t.gpuCap >= need).toList()
          ..sort((a, b) => a.cost.compareTo(b.cost));
    if (enough.isNotEmpty) return enough.first;
    all.sort((a, b) => b.gpuCap.compareTo(a.gpuCap));
    return all.first;
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

  double _opsCost(List<_Op> ops) => ops.fold(0.0, (a, op) {
    final old = g.s.tileAt(op.room, op.x, op.y);
    return a +
        tileById(op.tile)!.cost -
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

  /// Next GPU for [roomId] with the switches and cooler it needs.
  List<_Op>? _templateBundle(String roomId) {
    final plan = _plans[roomId]!;
    final room = plan.room;
    final gpu = _bestGpu(roomId);
    if (gpu == null) return null;
    final slot = plan.gpuOrder.where((i) => _at(roomId, i) == null).firstOrNull;
    if (slot == null) return null;
    final ops = <_Op>[];
    final sw = _bestSwitch(roomId);
    // Switch chain from this slot back to the placed network.
    var p = plan.parent[slot];
    while (p >= 0 && plan.roles[p] == _Role.net && _at(roomId, p) == null) {
      if (sw == null) return null;
      final (x, y) = _xy(roomId, p);
      ops.add(_Op(roomId, x, y, sw.id));
      p = plan.parent[p];
    }
    // The very first GPU of a room still gets its switch, ready for the next.
    if (p < 0 && sw != null) {
      final s0 =
          _neighbours(
            room,
            slot,
          ).where((j) => plan.roles[j] == _Role.net).firstOrNull;
      if (s0 != null && _at(roomId, s0) == null) {
        final (x, y) = _xy(roomId, s0);
        ops.add(_Op(roomId, x, y, sw.id));
      }
    }
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

  List<int> _emptyCells(String roomId) => [
    for (var i = 0; i < roomById(roomId)!.cells; i++)
      if (_at(roomId, i) == null) i,
  ];

  int _pickRandom(List<int> xs) =>
      xs[math.min(xs.length - 1, (_random() * xs.length).floor())];

  /// GPU (and for BotLayout.random a switch/cooler) on random empty cells.
  List<_Op>? _randomBundle(String roomId) {
    final gpu = _bestGpu(roomId);
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
      final counts = {for (final k in TileKind.values) k: 0};
      for (final id in g.s.grids[roomId]!) {
        final kind = id == null ? null : tileById(id)!.kind;
        if (kind != null) counts[kind] = counts[kind]! + 1;
      }
      final gpus = counts[TileKind.gpu]! + 1;
      final sw = _bestSwitch(roomId);
      if (sw != null && counts[TileKind.network]! < gpus / 2) add(sw);
      final coolers =
          _unlocked(roomId, TileKind.cooling).toList()
            ..sort((a, b) => a.cost.compareTo(b.cost));
      if (coolers.isNotEmpty && counts[TileKind.cooling]! < gpus / 2) {
        add(coolers.first);
      }
    }
    return ops;
  }

  /// Replace a room's weakest GPU tile with its best one (when it's full).
  List<_Op>? _replaceWorstGpu(String roomId) {
    final best = _bestGpu(roomId);
    if (best == null) return null;
    final cells = g.s.grids[roomId]!;
    var worst = -1;
    for (var i = 0; i < cells.length; i++) {
      final d = cells[i] == null ? null : tileById(cells[i]!);
      if (d == null || !d.isGpu) continue;
      if (worst < 0 || d.tflops < tileById(cells[worst]!)!.tflops) worst = i;
    }
    if (worst < 0 || best.tflops < 1.4 * tileById(cells[worst]!)!.tflops) {
      return null;
    }
    final (x, y) = _xy(roomId, worst);
    return [_Op(roomId, x, y, best.id, replace: true)];
  }

  /// Upgrade the slow switches of a room's biggest cluster when it has
  /// outgrown them.
  List<_Op>? _switchUpgrade(String roomId) {
    final cs = g.clusters(roomId).where((c) => c.networked).toList();
    if (cs.isEmpty) return null;
    cs.sort((a, b) => b.gpus.compareTo(a.gpus));
    final c = cs.first;
    if (c.gpus <= c.gpuCap) return null;
    final sw = _bestSwitch(roomId);
    if (sw == null || sw.gpuCap <= c.gpuCap) return null;
    return [
      for (final (x, y) in c.switchCells)
        if (tileById(g.s.tileAt(roomId, x, y)!)!.gpuCap < sw.gpuCap)
          _Op(roomId, x, y, sw.id, replace: true),
    ];
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
  double _value({double extraTrain = 0, double extraTotal = 0}) {
    final train = g.trainingClusterTflops + extraTrain;
    final flops = train * 0.5 * 1e12 * computeTimeScale * runSeconds;
    final effC = g.effectiveComputeOf(flops);
    final r = g.ratingOf(effC);
    final demand = math.min(
      maxUsers,
      demandBase * math.pow(10, (r - ratingBase) / demandRatingScale),
    );
    final serving = g.effectiveTflops + extraTotal - 0.5 * train;
    final cap =
        math.max(0.0, serving) /
        g.perUserTflops(math.max(effC, g.s.currentModel.effectiveCompute));
    return math.ln2 * r / ratingPerDoubling +
        math.log(math.max(1.0, math.min(demand, cap))) +
        0.5 * math.log(g.arpuMult);
  }

  List<UpgradeDef> get _availableUpgrades =>
      upgrades
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

  /// Returns true if it bought something.
  bool _spend() {
    final s = g.s;
    final v0 = _value();
    final cands = <_Cand>[];

    final headroom = g.powerCapKw - g.powerUsedKw;
    final powerTight = headroom < 0.25 * g.powerCapKw;
    // Upgrades that gate GPU tiles (liquid cooling) count as infrastructure,
    // so even the hardware-only bot buys them, plus data.
    final hwPrereqs = {
      for (final t in tiles)
        if (t.isGpu) ...t.requires,
    };
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
      // Unlocking better tiles is worth something too.
      if (hwPrereqs.contains(u.id) ||
          tiles.any((t) => t.requires.contains(u.id))) {
        dv += 0.05;
      }
      cands.add(
        _Cand(u.cost, dv, () => g.buyUpgrade(u.id), upgrade: true, label: u.id),
      );
    }

    // Grid work, in each owned room.
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

    final owned = g.ownedRooms;
    var roomsFull = true;
    for (final room in owned.reversed.take(3)) {
      final bundle =
          layout == BotLayout.template
              ? _templateBundle(room.id)
              : _randomBundle(room.id);
      if (bundle != null) roomsFull = false;
      addOps(bundle);
      if (bundle == null) addOps(_replaceWorstGpu(room.id));
      if (layout != BotLayout.naive) addOps(_switchUpgrade(room.id));
      if (layout == BotLayout.template) addOps(_heatFix(room.id));
    }

    // The best GPU we could place anywhere (for valuing power and rooms).
    TileDef? bestGpu;
    for (final r in owned) {
      final t = _bestGpu(r.id);
      if (t != null && (bestGpu == null || t.tflops > bestGpu.tflops)) {
        bestGpu = t;
      }
    }

    // Next room: worth it when it can hold better or more GPUs.
    final nextRoom = rooms.where((r) => !s.ownsRoom(r.id)).firstOrNull;
    if (nextRoom != null &&
        g.isUnlocked(nextRoom.era) &&
        s.powerTier >= nextRoom.minPowerTier) {
      final t =
          _bestGpu(nextRoom.id) ??
          tiles.where((t) => t.isGpu && t.rooms.contains(nextRoom.id)).first;
      final k = math.min(
        math.min(
          _plans[nextRoom.id]!.gpuOrder.length.toDouble(),
          (headroom / g.tilePowerKw(t)).floorToDouble(),
        ),
        math.max(1.0, (nextRoom.cost / t.cost).floorToDouble()),
      );
      if (k >= 1 && g.isTileUnlocked(t)) {
        cands.add(
          _Cand(
            nextRoom.cost,
            _virtualDv(t, k, v0),
            () => g.buyRoom(nextRoom.id),
          ),
        );
      }
    }

    // Power: worth it if we're nearly full (or out of floor space, since the
    // next room needs it). Value it as "tier + an equal spend on GPUs to
    // fill it".
    final next = g.nextPowerTier;
    if (bestGpu != null &&
        next != null &&
        g.isUnlocked(next.era) &&
        (powerTight || roomsFull)) {
      final unitKw = g.tilePowerKw(bestGpu);
      final k =
          math
              .max(
                1.0,
                math.min(
                  (next.capacityKw - g.powerUsedKw) / unitKw,
                  next.cost / bestGpu.cost,
                ),
              )
              .floorToDouble();
      cands.add(
        _Cand(next.cost, _virtualDv(bestGpu, k, v0), g.buyNextPowerTier),
      );
    }

    if (cands.isEmpty) return false;

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
        if (u.cost < s.money + 600 * g.revenuePerSecond) return false;
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
      final patience = (60 + 150 * (math.log(math.max(1.0, ratio)) / math.ln2))
          .clamp(60.0, maxSaveSeconds);
      if (wait < patience) return false;
    }
    return false;
  }
}

class _Cand {
  final double cost;
  final double dv;
  final bool Function() buy;
  final bool upgrade;
  final String label;
  _Cand(this.cost, this.dv, this.buy, {this.upgrade = false, this.label = ''});
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
  double minMoney = double.infinity;
  double usersAtFinish = 0;
  double arrAtFinish = 0;
  double h100eAtFinish = 0;
  double powerKwAtFinish = 0;

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
}) {
  final g = Game(GameState(rngState: seed));
  final bot = Bot(g, strategy: strategy, layout: layout, seed: seed);
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
          break;
      }
      onEvent?.call(g, e);
    }
    g.events.clear();
    onTick?.call(g);
    if (r.ladderDone && !idleFrozen) {
      r.usersAtFinish = g.s.users;
      r.arrAtFinish = g.arr;
      r.h100eAtFinish = g.peakTflops / 990;
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

/// The template plan for a room as text (G = GPU, S = switch, C = cooler),
/// for debugging and tests.
String describePlan(String roomId) {
  final plan = _plans[roomId]!;
  final b = StringBuffer();
  for (var y = 0; y < plan.room.height; y++) {
    for (var x = 0; x < plan.room.width; x++) {
      b.write(switch (plan.roles[y * plan.room.width + x]) {
        _Role.gpu => 'G',
        _Role.net => 'S',
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
