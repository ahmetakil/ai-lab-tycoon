// Grid physics: heat, network clusters and per-tile throughput, computed from
// the room grids in GameState. Pure Dart and deterministic (rooms in content
// order, cells row-major). Rules: docs/GRID.md ("Final numbers" at the end).
import 'dart:math' as math;

import 'content.dart';
import 'game_state.dart';

/// Lowest speed a throttling GPU tile runs at.
const minThrottleSpeed = 0.3;

/// Throttle slope: speed = max(0.3, 1 − 0.7 × netHeat / heat).
const throttleSlope = 0.7;

/// Live state of one placed tile, for the UI (red tint, cluster outline...).
class TileStatus {
  final TileDef def;

  /// GPU tiles: heat − ambient share − adjacent cooler shares. Negative means
  /// spare cooling. 0 for other tiles.
  final double netHeat;

  /// GPU throughput multiplier from heat (1 = cool, down to 0.3).
  final double speed;

  /// Cluster of a GPU tile (every GPU tile has one; a lone, unnetworked GPU
  /// is a cluster of itself) or of a switch that touches at least one GPU.
  final int? clusterId;
  final bool inTrainingCluster;

  /// GPU tiles: tflops × speed × utilization (MFU).
  final double effectiveTflops;

  /// GPU tiles: this tile's share of the room's ambient cooling.
  final double ambientCooling;

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
    this.adjacentCooling = 0,
    this.adjacentGpus = 0,
  });

  bool get throttling => speed < 1;
}

/// A group of GPU tiles joined through switches (or a single lone GPU tile).
class Cluster {
  final int id;
  final String roomId;
  final List<(int x, int y)> gpuCells;
  final List<(int x, int y)> switchCells;

  /// GPU count (sum of gpusPerTile).
  final double gpus;

  /// Sum of tile TFLOPS after heat throttling, before utilization (MFU).
  final double rawTflops;

  /// Sum of tile TFLOPS ignoring heat.
  final double peakTflops;

  /// GPUs the slowest switch can keep fed (= gpus for a lone tile).
  final double gpuCap;

  /// Id of the slowest switch (the bottleneck); null for a lone tile.
  final String? bottleneckTileId;

  /// 1 if gpus ≤ gpuCap, else sqrt(gpuCap / gpus).
  final double scalingEfficiency;
  final bool isTraining;

  /// rawTflops × utilization.
  final double effectiveTflops;

  const Cluster({
    required this.id,
    required this.roomId,
    required this.gpuCells,
    required this.switchCells,
    required this.gpus,
    required this.rawTflops,
    required this.peakTflops,
    required this.gpuCap,
    required this.bottleneckTileId,
    required this.scalingEfficiency,
    required this.isTraining,
    required this.effectiveTflops,
  });

  bool get networked => switchCells.isNotEmpty;

  /// Compute this cluster delivers to a training run at 100%:
  /// effectiveTflops × scalingEfficiency.
  double get trainingTflops => effectiveTflops * scalingEfficiency;

  Cluster withUtilization(double utilization) => Cluster(
    id: id,
    roomId: roomId,
    gpuCells: gpuCells,
    switchCells: switchCells,
    gpus: gpus,
    rawTflops: rawTflops,
    peakTflops: peakTflops,
    gpuCap: gpuCap,
    bottleneckTileId: bottleneckTileId,
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

GridStats computeGridStats(GameState s) {
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
      rs.netHeat[i] = def.heat - ambientShare - rs.adjCooling[i];
      rs.speed[i] = throttleSpeed(def.heat, rs.netHeat[i]);
      out.rawTflops += def.tflops * rs.speed[i];
    }

    // --- Clusters (union-find over switches and the GPUs they touch) -------
    final parent = List<int>.generate(room.cells, (i) => i);
    int find(int i) {
      while (parent[i] != i) {
        parent[i] = parent[parent[i]];
        i = parent[i];
      }
      return i;
    }

    void union(int a, int b) {
      final ra = find(a), rb = find(b);
      if (ra == rb) return;
      // Smaller index wins: deterministic roots.
      if (ra < rb) {
        parent[rb] = ra;
      } else {
        parent[ra] = rb;
      }
    }

    for (var i = 0; i < room.cells; i++) {
      final def = rs.defs[i];
      if (def == null || !def.isNetwork) continue;
      final x = i % w, y = i ~/ w;
      for (final (dx, dy) in _dirs) {
        final j = at(x + dx, y + dy);
        if (j == null) continue;
        final nd = rs.defs[j];
        // Switch–switch links; GPU–switch attachments (a GPU touching two
        // switch networks therefore joins them).
        if (nd != null && (nd.isNetwork || nd.isGpu)) union(i, j);
      }
    }
    final rootToCluster = <int, _ClusterBuild>{};
    for (var i = 0; i < room.cells; i++) {
      final def = rs.defs[i];
      if (def == null || def.isCooling) continue;
      rootToCluster.putIfAbsent(find(i), () => _ClusterBuild()).add(i, def);
    }
    for (final b in rootToCluster.values) {
      if (b.gpuCells.isEmpty) continue; // a switch network with no GPUs
      final idx = out.clusters.length;
      var raw = 0.0, peak = 0.0;
      for (final i in b.gpuCells) {
        raw += rs.defs[i]!.tflops * rs.speed[i];
        peak += rs.defs[i]!.tflops;
        rs.cluster[i] = idx;
      }
      for (final i in b.switchCells) {
        rs.cluster[i] = idx;
      }
      final cap = b.switchCells.isEmpty ? b.gpus : b.minCap;
      out.clusters.add(
        Cluster(
          id: idx,
          roomId: room.id,
          gpuCells: [for (final i in b.gpuCells) (i % w, i ~/ w)],
          switchCells: [for (final i in b.switchCells) (i % w, i ~/ w)],
          gpus: b.gpus,
          rawTflops: raw,
          peakTflops: peak,
          gpuCap: cap,
          bottleneckTileId: b.switchCells.isEmpty ? null : b.minCapId,
          scalingEfficiency: scalingEfficiencyFor(b.gpus, cap),
          isTraining: false,
          effectiveTflops: raw,
        ),
      );
    }
  }

  // Training cluster: best rawTflops × scaling efficiency across all rooms.
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
      switchCells: c.switchCells,
      gpus: c.gpus,
      rawTflops: c.rawTflops,
      peakTflops: c.peakTflops,
      gpuCap: c.gpuCap,
      bottleneckTileId: c.bottleneckTileId,
      scalingEfficiency: c.scalingEfficiency,
      isTraining: true,
      effectiveTflops: c.effectiveTflops,
    );
  }
  return out;
}

class _ClusterBuild {
  final gpuCells = <int>[];
  final switchCells = <int>[];
  double gpus = 0;
  double minCap = double.infinity;
  String? minCapId;

  void add(int i, TileDef def) {
    if (def.isGpu) {
      gpuCells.add(i);
      gpus += def.gpusPerTile;
    } else {
      switchCells.add(i);
      if (def.gpuCap < minCap) {
        minCap = def.gpuCap;
        minCapId = def.id;
      }
    }
  }
}
