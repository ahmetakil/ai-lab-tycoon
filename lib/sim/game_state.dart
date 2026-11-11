import 'balance.dart';
import 'content.dart';

class TrainingRun {
  /// Fraction of effective compute committed to training (0..1).
  final double fraction;
  final double durationSeconds;

  /// Seconds of GPU work per real second, fixed when the run starts (its
  /// era's EraInfo.computeTimeScale).
  final double timeScale;
  double elapsedSeconds;
  double computeFlops; // raw accumulated FLOPs (before algorithmic multipliers)
  bool paused;

  TrainingRun({
    required this.fraction,
    required this.durationSeconds,
    this.timeScale = computeTimeScale,
    this.elapsedSeconds = 0,
    this.computeFlops = 0,
    this.paused = false,
  });

  bool get done => elapsedSeconds >= durationSeconds;
  double get progress => (elapsedSeconds / durationSeconds).clamp(0, 1);

  Map<String, dynamic> toJson() => {
    'fraction': fraction,
    'duration': durationSeconds,
    'scale': timeScale,
    'elapsed': elapsedSeconds,
    'flops': computeFlops,
    'paused': paused,
  };

  factory TrainingRun.fromJson(Map<String, dynamic> j) => TrainingRun(
    fraction: (j['fraction'] as num).toDouble(),
    durationSeconds: (j['duration'] as num).toDouble(),
    timeScale: (j['scale'] as num?)?.toDouble() ?? computeTimeScale,
    elapsedSeconds: (j['elapsed'] as num).toDouble(),
    computeFlops: (j['flops'] as num).toDouble(),
    paused: j['paused'] as bool? ?? false,
  );
}

class ModelRelease {
  final String name;
  final double effectiveCompute;
  final double rating;
  final bool open;
  final double time;

  const ModelRelease({
    required this.name,
    required this.effectiveCompute,
    required this.rating,
    required this.open,
    required this.time,
  });

  Map<String, dynamic> toJson() => {
    'name': name,
    'effC': effectiveCompute,
    'rating': rating,
    'open': open,
    'time': time,
  };

  factory ModelRelease.fromJson(Map<String, dynamic> j) => ModelRelease(
    name: j['name'] as String,
    effectiveCompute: (j['effC'] as num).toDouble(),
    rating: (j['rating'] as num).toDouble(),
    open: j['open'] as bool,
    time: (j['time'] as num).toDouble(),
  );
}

/// Current save format. Older saves load as a fresh game (see fromJson).
/// v3: six eras (v2 had three) and per-run time compression.
const saveVersion = 3;

/// Where the starting RTX 4090 (gpu_gamer) sits in the garage.
const startGpuCell = (1, 1);

/// Everything that must be saved. Derived values live in Game.
class GameState {
  double time; // total simulated seconds
  double money;
  double users;
  double hype; // multiplier ≥ 1, decays toward 1
  int powerTier; // index into powerTiers

  /// Owned rooms → row-major cells (width × height), null = empty. Mutate
  /// through [setTile] (or call [touchGrid] after editing a list directly) so
  /// Game's cached grid stats are recomputed.
  final Map<String, List<String?>> grids;
  Set<String> ownedUpgrades;
  int openReleases;
  TrainingRun? run;

  /// Finished run waiting for the player to choose how to release it.
  double? pendingEffectiveCompute;

  List<ModelRelease> releases;
  int rivalIndex; // first unbeaten rival in rivalLadder
  double viralSecondsLeft;
  double cloudSecondsLeft;

  /// Seconds until another viral spike may start (added after v1; default 0).
  double viralCooldownLeft;
  int rngState;
  Era era;
  String labName;

  /// True when this state replaced an older, incompatible save (not saved).
  /// The UI can show "fresh start" and skip offline progress.
  bool startedFromOldSave = false;

  /// Bumped on every grid change; Game caches grid stats against it (not saved).
  int gridRevision = 0;

  GameState({
    this.time = 0,
    this.money = startMoney,
    this.users = 0,
    this.hype = 1,
    this.powerTier = 0,
    Map<String, List<String?>>? grids,
    Set<String>? ownedUpgrades,
    this.openReleases = 0,
    this.run,
    this.pendingEffectiveCompute,
    List<ModelRelease>? releases,
    this.rivalIndex = 0,
    this.viralSecondsLeft = 0,
    this.cloudSecondsLeft = 0,
    this.viralCooldownLeft = 0,
    this.rngState = 12345,
    this.era = Era.garage,
    this.labName = 'Garage Labs',
  }) : grids = grids ?? startGrids(),
       ownedUpgrades = ownedUpgrades ?? {},
       releases =
           releases ??
           [
             const ModelRelease(
               name: 'Fine-tuned open model',
               effectiveCompute: startEffectiveCompute,
               rating: ratingBase,
               open: true,
               time: 0,
             ),
           ];

  /// The starting layout: a garage with one RTX 4090 (gpu_gamer).
  static Map<String, List<String?>> startGrids() {
    final room = roomById('garage')!;
    final garage = emptyGrid(room);
    garage[startGpuCell.$2 * room.width + startGpuCell.$1] = 'gpu_gamer';
    return {'garage': garage};
  }

  static List<String?> emptyGrid(RoomDef room) => List<String?>.filled(room.cells, null);

  ModelRelease get currentModel => releases.last;

  bool ownsRoom(String roomId) => grids.containsKey(roomId);

  /// Tile id at (x, y) of an owned room, or null (empty / not owned / out of
  /// bounds).
  String? tileAt(String roomId, int x, int y) {
    final room = roomById(roomId);
    final cells = grids[roomId];
    if (room == null || cells == null) return null;
    if (x < 0 || y < 0 || x >= room.width || y >= room.height) return null;
    return cells[y * room.width + x];
  }

  /// Raw grid write (no money/power checks). Game's actions are the checked
  /// way to change the grid; this is for them, tests and the bot's what-ifs.
  void setTile(String roomId, int x, int y, String? tileId) {
    final room = roomById(roomId)!;
    grids[roomId]![y * room.width + x] = tileId;
    gridRevision++;
  }

  /// Call after mutating [grids] directly.
  void touchGrid() => gridRevision++;

  /// Count of each tile id across all rooms.
  Map<String, int> get tileCounts {
    final out = <String, int>{};
    for (final room in rooms) {
      for (final id in grids[room.id] ?? const <String?>[]) {
        if (id != null) out[id] = (out[id] ?? 0) + 1;
      }
    }
    return out;
  }

  Map<String, dynamic> toJson() => {
    'v': saveVersion,
    'time': time,
    'money': money,
    'users': users,
    'hype': hype,
    'powerTier': powerTier,
    'grids': {
      for (final r in rooms)
        if (grids.containsKey(r.id)) r.id: grids[r.id],
    },
    'upgrades': ownedUpgrades.toList(),
    'openReleases': openReleases,
    'run': run?.toJson(),
    'pending': pendingEffectiveCompute,
    'releases': releases.map((r) => r.toJson()).toList(),
    'rivalIndex': rivalIndex,
    'viral': viralSecondsLeft,
    'cloud': cloudSecondsLeft,
    'viralCd': viralCooldownLeft,
    'rng': rngState,
    'era': era.name,
    'labName': labName,
  };

  /// v3 saves load tolerantly (unknown ids dropped, missing fields default).
  /// Anything older (v1 menu shop, v2 three-era grid) becomes a fresh game with
  /// [startedFromOldSave] set.
  factory GameState.fromJson(Map<String, dynamic> j) {
    if ((j['v'] as num?)?.toInt() != saveVersion) {
      return GameState()..startedFromOldSave = true;
    }
    double num_(String k, double d) => (j[k] as num?)?.toDouble() ?? d;
    final upgradeIds = upgrades.map((u) => u.id).toSet();
    final eraName = j['era'] as String?;
    Map<String, List<String?>>? grids;
    final rawGrids = j['grids'];
    if (rawGrids is Map) {
      grids = {};
      for (final room in rooms) {
        final list = rawGrids[room.id];
        if (list is! List) continue;
        grids[room.id] = [
          for (var i = 0; i < room.cells; i++)
            i < list.length &&
                    list[i] is String &&
                    tileById(list[i] as String)?.rooms.contains(room.id) == true
                ? list[i] as String
                : null,
        ];
      }
      if (!grids.containsKey('garage')) {
        grids['garage'] = emptyGrid(roomById('garage')!);
      }
    }
    return GameState(
      time: num_('time', 0),
      money: num_('money', startMoney),
      users: num_('users', 0),
      hype: num_('hype', 1),
      powerTier: ((j['powerTier'] as num?)?.toInt() ?? 0).clamp(0, powerTiers.length - 1),
      grids: grids,
      ownedUpgrades: (j['upgrades'] as List?)?.cast<String>().where(upgradeIds.contains).toSet(),
      openReleases: (j['openReleases'] as num?)?.toInt() ?? 0,
      run: j['run'] == null ? null : TrainingRun.fromJson(j['run'] as Map<String, dynamic>),
      pendingEffectiveCompute: (j['pending'] as num?)?.toDouble(),
      releases:
          (j['releases'] as List?)
              ?.map((r) => ModelRelease.fromJson(r as Map<String, dynamic>))
              .toList(),
      rivalIndex: ((j['rivalIndex'] as num?)?.toInt() ?? 0).clamp(0, rivalLadder.length),
      viralSecondsLeft: num_('viral', 0),
      cloudSecondsLeft: num_('cloud', 0),
      viralCooldownLeft: num_('viralCd', 0),
      rngState: (j['rng'] as num?)?.toInt() ?? 12345,
      era: Era.values.asNameMap()[eraName] ?? Era.garage,
      labName: j['labName'] as String? ?? 'Garage Labs',
    );
  }
}
