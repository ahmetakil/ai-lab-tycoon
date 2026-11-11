// Grid physics: heat and per-tile throughput, computed from the room grid in
// GameState. Pure Dart and deterministic (cells row-major). Every GPU tile in
// the room is cabled into one training cluster (the network tier's cap sets
// how many GPUs it keeps fed); cooling is the spatial part. Rules:
// docs/GRID.md.
import 'dart:math' as math;

import 'content.dart';
import 'game_state.dart';

/// Lowest speed a throttling GPU tile runs at.
const minThrottleSpeed = 0.2;

/// Throttle slope: speed = max(0.2, 1 − netHeat / heat).
const throttleSlope = 1.0;

/// Live state of one placed tile, for the UI (red tint, cluster outline...).
class TileStatus {
  final TileDef def;

  /// GPU tiles: heat − ambient share − adjacent cooler shares. Negative means
  /// spare cooling. 0 for other tiles.
  final double netHeat;

  /// GPU throughput multiplier from heat (1 = cool, down to 0.3).
  final double speed;

  /// Cluster of a GPU tile (0: the room has one). Null for coolers.
  final int? clusterId;
  final bool inTrainingCluster;

  /// GPU tiles: tflops × speed × utilization (MFU).
  final double effectiveTflops;

  /// GPU tiles: this tile's share of the room's ambient cooling.
  final double ambientCooling;

  /// GPU tiles: heat the central cooling tier removes from it.
  final double plantCooling;

  /// GPU tiles: total cooling received from adjacent coolers.
  final double adjacentCooling;

  /// Cooling tiles: how many GPU tiles share it (0 = wasted).
  final int adjacentGpus;

  const TileStatus({
    required this.def,
    required this.netHeat,
    required this.speed,
    required this.clusterId,
    required this.inTrainingCluster,
    required this.effectiveTflops,
    this.ambientCooling = 0,
    this.plantCooling = 0,
    this.adjacentCooling = 0,
    this.adjacentGpus = 0,
  });

  bool get throttling => speed < 1;
}

/// Every GPU tile in the room, cabled overhead into one training cluster.
class Cluster {
  final int id;
  final String roomId;
  final List<(int x, int y)> gpuCells;

  /// GPU count (sum of gpusPerTile).
  final double gpus;

  /// Sum of tile TFLOPS after heat throttling, before utilization (MFU).
  final double rawTflops;

  /// Sum of tile TFLOPS ignoring heat.
  final double peakTflops;

  /// GPUs the network tier keeps fed. A lone tile is never over it (its GPUs
  /// share one box), so its cap is at least its own GPU count.
  final double gpuCap;

  /// 1 if gpus ≤ gpuCap, else sqrt(gpuCap / gpus).
  final double scalingEfficiency;
  final bool isTraining;

  /// rawTflops × utilization.
  final double effectiveTflops;

  const Cluster({
    required this.id,
    required this.roomId,
    required this.gpuCells,
    required this.gpus,
    required this.rawTflops,
    required this.peakTflops,
    required this.gpuCap,
    required this.scalingEfficiency,
    required this.isTraining,
    required this.effectiveTflops,
  });

  /// More than one tile, linked by cables.
  bool get networked => gpuCells.length > 1;

  /// More GPUs than the network tier keeps fed.
  bool get overCap => gpus > gpuCap;

  /// Compute this cluster delivers to a training run at 100%:
  /// effectiveTflops × scalingEfficiency.
  double get trainingTflops => effectiveTflops * scalingEfficiency;

  Cluster withUtilization(double utilization) => Cluster(
    id: id,
    roomId: roomId,
    gpuCells: gpuCells,
    gpus: gpus,
    rawTflops: rawTflops,
    peakTflops: peakTflops,
    gpuCap: gpuCap,
    scalingEfficiency: scalingEfficiency,
    isTraining: isTraining,
    effectiveTflops: rawTflops * utilization,
  );
}

double scalingEfficiencyFor(double gpus, double gpuCap) =>
    gpus <= gpuCap ? 1.0 : math.sqrt(gpuCap / gpus);

double throttleSpeed(double heat, double netHeat) =>
    netHeat <= 0 || heat <= 0
        ? 1.0
        : math.max(minThrottleSpeed, 1 - throttleSlope * netHeat / heat);

/// Per-room derived data (arrays are row-major, like the grid).
class RoomStats {
  final RoomDef room;
  final List<TileDef?> defs;
  final List<double> netHeat;
  final List<double> speed;
  final List<double> ambient;
  final List<double> plant;
  final List<double> adjCooling;
  final List<int> coolerGpus;

  /// Index into GridStats.clusters, or -1.
  final List<int> cluster;
  int gpuTiles = 0;

  RoomStats(this.room)
    : defs = List.filled(room.cells, null),
      netHeat = List.filled(room.cells, 0),
      speed = List.filled(room.cells, 1),
      ambient = List.filled(room.cells, 0),
      plant = List.filled(room.cells, 0),
      adjCooling = List.filled(room.cells, 0),
      coolerGpus = List.filled(room.cells, 0),
      cluster = List.filled(room.cells, -1);
}

/// Everything derived from the grids. Utilization-free, so it only needs
/// recomputing when the grid itself changes.
class GridStats {
  final Map<String, RoomStats> rooms = {};

  /// Clusters across all rooms with effectiveTflops at utilization 1.
  final List<Cluster> clusters = [];
  int trainingIndex = -1;
  double peakTflops = 0;
  double rawTflops = 0;
  double gpuPowerKw = 0;
  double otherPowerKw = 0;
  double totalGpus = 0;
  double gpuValue = 0;
  double tileValue = 0;

  /// Placed tiles per tile id, across all rooms.
  final Map<String, int> counts = {};

  Cluster? get training => trainingIndex < 0 ? null : clusters[trainingIndex];
}

const _dirs = [(1, 0), (-1, 0), (0, 1), (0, -1)];

/// [gpuCap]: GPUs the network tier keeps fed. [plantPerTile]: heat the
/// central cooling tier removes from every GPU tile.
GridStats computeGridStats(GameState s, double gpuCap, [double plantPerTile = 0]) {
  final out = GridStats();
  for (final room in rooms) {
    final cells = s.grids[room.id];
    if (cells == null) continue;
    final rs = RoomStats(room);
    out.rooms[room.id] = rs;
    final w = room.width, h = room.height;
    for (var i = 0; i < room.cells; i++) {
      final id = cells[i];
      final def = id == null ? null : tileById(id);
      rs.defs[i] = def;
      if (def == null) continue;
      out.counts[def.id] = (out.counts[def.id] ?? 0) + 1;
      out.tileValue += def.cost;
      if (def.isGpu) {
        rs.gpuTiles++;
        out.gpuPowerKw += def.powerKw;
        out.gpuValue += def.cost;
        out.totalGpus += def.gpusPerTile;
        out.peakTflops += def.tflops;
      } else {
        out.otherPowerKw += def.powerKw;
      }
    }
    int? at(int x, int y) =>
        x < 0 || y < 0 || x >= w || y >= h ? null : y * w + x;

    // --- Heat ---------------------------------------------------------------
    final ambientShare =
        rs.gpuTiles == 0 ? 0.0 : room.ambientTotal / rs.gpuTiles;
    for (var i = 0; i < room.cells; i++) {
      final def = rs.defs[i];
      if (def == null || !def.isCooling) continue;
      final x = i % w, y = i ~/ w;
      final nbrs = <int>[];
      for (final (dx, dy) in _dirs) {
        final j = at(x + dx, y + dy);
        if (j != null && rs.defs[j]?.isGpu == true) nbrs.add(j);
      }
      rs.coolerGpus[i] = nbrs.length;
      for (final j in nbrs) {
        rs.adjCooling[j] += def.cooling / nbrs.length;
      }
    }
    for (var i = 0; i < room.cells; i++) {
      final def = rs.defs[i];
      if (def == null || !def.isGpu) continue;
      rs.ambient[i] = ambientShare;
      rs.plant[i] = plantPerTile;
      rs.netHeat[i] = def.heat - ambientShare - plantPerTile - rs.adjCooling[i];
      rs.speed[i] = throttleSpeed(def.heat, rs.netHeat[i]);
      out.rawTflops += def.tflops * rs.speed[i];
    }

    // --- The cluster: every GPU tile, cabled overhead ----------------------
    final list = [
      for (var i = 0; i < room.cells; i++)
        if (rs.defs[i]?.isGpu == true) i,
    ];
    if (list.isEmpty) continue;
    final idx = out.clusters.length;
    var raw = 0.0, peak = 0.0, gpus = 0.0;
    for (final i in list) {
      final d = rs.defs[i]!;
      raw += d.tflops * rs.speed[i];
      peak += d.tflops;
      gpus += d.gpusPerTile;
      rs.cluster[i] = idx;
    }
    // One tile's GPUs share a box: a lone tile always trains at full speed.
    final cap = list.length == 1 ? math.max(gpuCap, gpus) : gpuCap;
    out.clusters.add(
      Cluster(
        id: idx,
        roomId: room.id,
        gpuCells: [for (final i in list) (i % w, i ~/ w)],
        gpus: gpus,
        rawTflops: raw,
        peakTflops: peak,
        gpuCap: cap,
        scalingEfficiency: scalingEfficiencyFor(gpus, cap),
        isTraining: false,
        effectiveTflops: raw,
      ),
    );
  }

  // Training cluster: best rawTflops × scaling efficiency.
  var best = -1.0;
  for (var i = 0; i < out.clusters.length; i++) {
    final c = out.clusters[i];
    final v = c.rawTflops * c.scalingEfficiency;
    if (v > best) {
      best = v;
      out.trainingIndex = i;
    }
  }
  if (out.trainingIndex >= 0) {
    final c = out.clusters[out.trainingIndex];
    out.clusters[out.trainingIndex] = Cluster(
      id: c.id,
      roomId: c.roomId,
      gpuCells: c.gpuCells,
      gpus: c.gpus,
      rawTflops: c.rawTflops,
      peakTflops: c.peakTflops,
      gpuCap: c.gpuCap,
      scalingEfficiency: c.scalingEfficiency,
      isTraining: true,
      effectiveTflops: c.effectiveTflops,
    );
  }
  return out;
}
