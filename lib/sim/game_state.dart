import 'balance.dart';
import 'content.dart';
import 'model_design.dart';
import 'news.dart';
import 'run_phases.dart';

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

  /// The model design chosen when the run started.
  final ModelSpec spec;

  /// Phase decisions so far (run_phases.dart). The early one is set when
  /// the run starts; the others at their checkpoints.
  final PhaseChoices phaseChoices;

  /// Phases the game picked by default (no player decision).
  final Set<RunPhase> autoPhases;

  /// Seconds the run has waited at the current checkpoint.
  double phaseWaitSeconds;

  TrainingRun({
    required this.fraction,
    required this.durationSeconds,
    this.spec = const ModelSpec(),
    this.timeScale = computeTimeScale,
    this.elapsedSeconds = 0,
    this.computeFlops = 0,
    this.paused = false,
    PhaseChoices? phaseChoices,
    Set<RunPhase>? autoPhases,
    this.phaseWaitSeconds = 0,
  }) : phaseChoices = phaseChoices ?? {},
       autoPhases = autoPhases ?? {};

  bool get done => elapsedSeconds >= durationSeconds;
  double get progress => (elapsedSeconds / durationSeconds).clamp(0, 1);

  Map<String, dynamic> toJson() => {
    'fraction': fraction,
    'duration': durationSeconds,
    'scale': timeScale,
    'elapsed': elapsedSeconds,
    'flops': computeFlops,
    'paused': paused,
    'spec': spec.toJson(),
    'phases': phaseChoicesToJson(phaseChoices),
    if (autoPhases.isNotEmpty) 'autoPhases': [for (final p in autoPhases) p.name],
    if (phaseWaitSeconds > 0) 'phaseWait': phaseWaitSeconds,
  };

  factory TrainingRun.fromJson(Map<String, dynamic> j) => TrainingRun(
    spec: _specFrom(j['spec']),
    fraction: (j['fraction'] as num).toDouble(),
    durationSeconds: (j['duration'] as num).toDouble(),
    timeScale: (j['scale'] as num?)?.toDouble() ?? computeTimeScale,
    elapsedSeconds: (j['elapsed'] as num).toDouble(),
    computeFlops: (j['flops'] as num).toDouble(),
    paused: j['paused'] as bool? ?? false,
    phaseChoices: phaseChoicesFromJson(j['phases']),
    autoPhases: {
      for (final n in (j['autoPhases'] as List?) ?? const [])
        if (RunPhase.values.asNameMap()[n] case final p?) p,
    },
    phaseWaitSeconds: (j['phaseWait'] as num?)?.toDouble() ?? 0,
  );
}

ModelSpec _specFrom(Object? j) =>
    j is Map ? ModelSpec.fromJson(j.cast<String, dynamic>()) : const ModelSpec();

/// What a finished run's model design did, fixed when the run ends (the
/// design is evaluated against the lab as it was then). Kept on the pending
/// model and on the release, so serving and demand follow the *current*
/// model.
class DesignOutcome {
  final ModelSpec spec;

  /// Flat rating from post-training, relative to SFT (DesignEffects.ratingAdd).
  final double ratingAdd;

  /// Per-user serving TFLOPS multiplier (DesignEffects.serveCostMult).
  final double serveCostMult;

  /// User demand multiplier (DesignEffects.demandMult).
  final double demandMult;

  /// Effective compute without the design's quality multiplier: what sets
  /// the model's size for serving (a smarter design isn't a bigger model).
  final double serveCompute;

  final BenchmarkStrengths strengths;

  /// Short lines for the release card: risks that fired, the biggest effects.
  final List<String> highlights;

  /// The run's phase decisions, in phase order (empty for models trained
  /// before run phases).
  final List<PhaseOption> phases;

  const DesignOutcome({
    required this.spec,
    required this.ratingAdd,
    required this.serveCostMult,
    required this.demandMult,
    required this.serveCompute,
    this.strengths = const BenchmarkStrengths(),
    this.highlights = const [],
    this.phases = const [],
  });

  Map<String, dynamic> toJson() => {
    'spec': spec.toJson(),
    'ratingAdd': ratingAdd,
    'serve': serveCostMult,
    'demand': demandMult,
    'serveC': serveCompute,
    'bench': strengths.toJson(),
    'notes': highlights,
    if (phases.isNotEmpty) 'phases': [for (final p in phases) p.name],
  };

  /// Tolerant: missing fields default.
  static DesignOutcome? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final j = raw.cast<String, dynamic>();
    double n(String k, double d) => (j[k] as num?)?.toDouble() ?? d;
    final bench = j['bench'];
    return DesignOutcome(
      spec: _specFrom(j['spec']),
      ratingAdd: n('ratingAdd', 0),
      serveCostMult: n('serve', 1),
      demandMult: n('demand', 1),
      serveCompute: n('serveC', startEffectiveCompute),
      strengths: bench is Map
          ? BenchmarkStrengths.fromJson(bench.cast<String, dynamic>())
          : const BenchmarkStrengths(),
      highlights: (j['notes'] as List?)?.whereType<String>().toList() ?? const [],
      phases: [
        for (final n in (j['phases'] as List?) ?? const [])
          if (PhaseOption.values.asNameMap()[n] case final o?) o,
      ],
    );
  }
}

class ModelRelease {
  final String name;
  final double effectiveCompute;
  final double rating;
  final bool open;
  final double time;

  /// The design it was trained with; null for the starting model.
  final DesignOutcome? design;

  const ModelRelease({
    required this.name,
    required this.effectiveCompute,
    required this.rating,
    required this.open,
    required this.time,
    this.design,
  });

  Map<String, dynamic> toJson() => {
    'name': name,
    'effC': effectiveCompute,
    'rating': rating,
    'open': open,
    'time': time,
    if (design != null) 'design': design!.toJson(),
  };

  factory ModelRelease.fromJson(Map<String, dynamic> j) => ModelRelease(
    name: j['name'] as String,
    effectiveCompute: (j['effC'] as num).toDouble(),
    rating: (j['rating'] as num).toDouble(),
    open: j['open'] as bool,
    time: (j['time'] as num).toDouble(),
    design: DesignOutcome.fromJson(j['design']),
  );
}

/// Current save format. Older saves load as a fresh game (see fromJson).
/// v3: six eras (v2 had three) and per-run time compression.
/// v4: one room at a time (you move, your tiles come with you); network and
/// central cooling are global tiers (no switch tiles). Model design (run
/// specs, design outcomes) added optional fields to v4, no bump.
const saveVersion = 4;

/// Where the starting RTX 4090 (gpu_gamer) sits in the garage.
const startGpuCell = (1, 1);

/// Everything that must be saved. Derived values live in Game.
class GameState {
  double time; // total simulated seconds
  double money;
  double users;
  double hype; // multiplier ≥ 1, decays toward 1
  int powerTier; // index into powerTiers
  int networkTier; // index into networkTiers
  int coolingTier; // index into coolingTiers

  /// The room you're in → its row-major cells (width × height), null =
  /// empty. Always exactly one entry: moving (Game.moveTo) replaces it. Mutate
  /// through [setTile] (or call [touchGrid] after editing a list directly) so
  /// Game's cached grid stats are recomputed.
  final Map<String, List<String?>> grids;
  Set<String> ownedUpgrades;
  int openReleases;
  TrainingRun? run;

  /// Finished run waiting for the player to choose how to release it.
  double? pendingEffectiveCompute;

  /// The pending model's design outcome (null for a pending model from a
  /// save made before model design, or set directly by tests).
  DesignOutcome? pendingDesign;

  /// The model design the last run used; the next run starts from it, so
  /// starting a run stays one tap.
  ModelSpec lastSpec;

  List<ModelRelease> releases;
  int rivalIndex; // first unbeaten rival in rivalLadder

  /// Live rival feed (news.dart): rivals released so far (a prefix of
  /// rivalLadder), when the last one came out, flavour lines posted, when
  /// the last one was posted, and the news log (oldest first, capped).
  int rivalsReleased;
  double lastRivalReleaseAt;
  int flavourShown;
  double lastFlavourAt;
  List<NewsItem> news;
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

  /// Bumped on every grid change; Game caches grid stats against it (and the
  /// network and cooling tiers). Not saved.
  int gridRevision = 0;

  GameState({
    this.time = 0,
    this.money = startMoney,
    this.users = 0,
    this.hype = 1,
    this.powerTier = 0,
    this.networkTier = 0,
    this.coolingTier = 0,
    Map<String, List<String?>>? grids,
    Set<String>? ownedUpgrades,
    this.openReleases = 0,
    this.run,
    this.pendingEffectiveCompute,
    this.pendingDesign,
    this.lastSpec = const ModelSpec(),
    List<ModelRelease>? releases,
    this.rivalIndex = 0,
    this.rivalsReleased = 1,
    this.lastRivalReleaseAt = 0,
    this.flavourShown = 0,
    this.lastFlavourAt = 0,
    List<NewsItem>? news,
    this.viralSecondsLeft = 0,
    this.cloudSecondsLeft = 0,
    this.viralCooldownLeft = 0,
    this.rngState = 12345,
    this.era = Era.garage,
    this.labName = 'Garage Labs',
  }) : assert(grids == null || grids.length == 1, 'one room at a time'),
       grids = grids ?? startGrids(),
       ownedUpgrades = ownedUpgrades ?? {},
       news = news ?? [],
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

  /// Id of the room you're in.
  String get roomId => grids.keys.first;
  RoomDef get room => roomById(roomId)!;

  /// True only for the room you're in.
  bool ownsRoom(String roomId) => grids.containsKey(roomId);

  /// Tile id at (x, y) of the current room, or null (empty / another room /
  /// out of bounds).
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

  /// Count of each placed tile id.
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
    'networkTier': networkTier,
    'coolingTier': coolingTier,
    'grids': {
      for (final r in rooms)
        if (grids.containsKey(r.id)) r.id: grids[r.id],
    },
    'upgrades': ownedUpgrades.toList(),
    'openReleases': openReleases,
    'run': run?.toJson(),
    'pending': pendingEffectiveCompute,
    if (pendingDesign != null) 'pendingDesign': pendingDesign!.toJson(),
    'spec': lastSpec.toJson(),
    'releases': releases.map((r) => r.toJson()).toList(),
    'rivalIndex': rivalIndex,
    'rivalsReleased': rivalsReleased,
    'rivalReleaseAt': lastRivalReleaseAt,
    'flavourShown': flavourShown,
    'flavourAt': lastFlavourAt,
    'news': news.map((n) => n.toJson()).toList(),
    'viral': viralSecondsLeft,
    'cloud': cloudSecondsLeft,
    'viralCd': viralCooldownLeft,
    'rng': rngState,
    'era': era.name,
    'labName': labName,
  };

  /// v4 saves load tolerantly (unknown ids dropped, missing fields default).
  /// Anything older (v1 menu shop, v2 three-era grid, v3 with several rooms
  /// at once) becomes a fresh game with [startedFromOldSave] set.
  factory GameState.fromJson(Map<String, dynamic> j) {
    if ((j['v'] as num?)?.toInt() != saveVersion) {
      return GameState()..startedFromOldSave = true;
    }
    double num_(String k, double d) => (j[k] as num?)?.toDouble() ?? d;
    final upgradeIds = allUpgrades.map((u) => u.id).toSet();
    final eraName = j['era'] as String?;
    Map<String, List<String?>>? grids;
    final rawGrids = j['grids'];
    if (rawGrids is Map) {
      // One room; if a save somehow holds several, the latest one wins.
      for (final room in rooms.reversed) {
        final list = rawGrids[room.id];
        if (list is! List) continue;
        grids = {
          room.id: [
            for (var i = 0; i < room.cells; i++)
              i < list.length &&
                      list[i] is String &&
                      tileById(list[i] as String) != null
                  ? list[i] as String
                  : null,
          ],
        };
        break;
      }
    }
    final time = num_('time', 0);
    final rivalIndex = ((j['rivalIndex'] as num?)?.toInt() ?? 0).clamp(0, rivalLadder.length);
    final era = Era.values.asNameMap()[eraName] ?? Era.garage;
    // Saves from before the rival feed derive it from progress: everything
    // up to the next rival is out, and earlier eras' gossip is skipped.
    final hasFeed = j.containsKey('rivalsReleased');
    return GameState(
      time: time,
      money: num_('money', startMoney),
      users: num_('users', 0),
      hype: num_('hype', 1),
      powerTier: ((j['powerTier'] as num?)?.toInt() ?? 0).clamp(0, powerTiers.length - 1),
      networkTier: ((j['networkTier'] as num?)?.toInt() ?? 0).clamp(0, networkTiers.length - 1),
      coolingTier: ((j['coolingTier'] as num?)?.toInt() ?? 0).clamp(0, coolingTiers.length - 1),
      grids: grids,
      ownedUpgrades: (j['upgrades'] as List?)?.cast<String>().where(upgradeIds.contains).toSet(),
      openReleases: (j['openReleases'] as num?)?.toInt() ?? 0,
      run: j['run'] == null ? null : TrainingRun.fromJson(j['run'] as Map<String, dynamic>),
      pendingEffectiveCompute: (j['pending'] as num?)?.toDouble(),
      pendingDesign: DesignOutcome.fromJson(j['pendingDesign']),
      lastSpec: _specFrom(j['spec']),
      releases:
          (j['releases'] as List?)
              ?.map((r) => ModelRelease.fromJson(r as Map<String, dynamic>))
              .toList(),
      rivalIndex: rivalIndex,
      rivalsReleased:
          hasFeed
              ? ((j['rivalsReleased'] as num?)?.toInt() ?? 0).clamp(0, rivalLadder.length)
              : (rivalIndex + 1).clamp(0, rivalLadder.length),
      lastRivalReleaseAt: hasFeed ? num_('rivalReleaseAt', 0) : time,
      flavourShown:
          hasFeed
              ? ((j['flavourShown'] as num?)?.toInt() ?? 0).clamp(0, flavourNews.length)
              : flavourBefore(era),
      lastFlavourAt: hasFeed ? num_('flavourAt', 0) : time,
      news: [
        for (final n in (j['news'] as List?) ?? const [])
          if (NewsItem.fromJson(n) case final item?) item,
      ],
      viralSecondsLeft: num_('viral', 0),
      cloudSecondsLeft: num_('cloud', 0),
      viralCooldownLeft: num_('viralCd', 0),
      rngState: (j['rng'] as num?)?.toInt() ?? 12345,
      era: era,
      labName: j['labName'] as String? ?? 'Garage Labs',
    );
  }
}
