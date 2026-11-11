import 'balance.dart';
import 'content.dart';

class TrainingRun {
  /// Fraction of effective compute committed to training (0..1).
  final double fraction;
  final double durationSeconds;
  double elapsedSeconds;
  double computeFlops; // raw accumulated FLOPs (before algorithmic multipliers)
  bool paused;

  TrainingRun({
    required this.fraction,
    required this.durationSeconds,
    this.elapsedSeconds = 0,
    this.computeFlops = 0,
    this.paused = false,
  });

  bool get done => elapsedSeconds >= durationSeconds;
  double get progress => (elapsedSeconds / durationSeconds).clamp(0, 1);

  Map<String, dynamic> toJson() => {
        'fraction': fraction,
        'duration': durationSeconds,
        'elapsed': elapsedSeconds,
        'flops': computeFlops,
        'paused': paused,
      };

  factory TrainingRun.fromJson(Map<String, dynamic> j) => TrainingRun(
        fraction: (j['fraction'] as num).toDouble(),
        durationSeconds: (j['duration'] as num).toDouble(),
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

/// Everything that must be saved. Derived values live in Game.
class GameState {
  double time; // total simulated seconds
  double money;
  double users;
  double hype; // multiplier ≥ 1, decays toward 1
  int powerTier; // index into powerTiers
  Map<String, int> hardwareCounts;
  Set<String> ownedUpgrades;
  int openReleases;
  TrainingRun? run;

  /// Finished run waiting for the player to choose how to release it.
  double? pendingEffectiveCompute;

  List<ModelRelease> releases;
  int rivalIndex; // first unbeaten rival in rivalLadder
  double viralSecondsLeft;
  double cloudSecondsLeft;
  int rngState;
  Era era;

  GameState({
    this.time = 0,
    this.money = startMoney,
    this.users = 0,
    this.hype = 1,
    this.powerTier = 0,
    Map<String, int>? hardwareCounts,
    Set<String>? ownedUpgrades,
    this.openReleases = 0,
    this.run,
    this.pendingEffectiveCompute,
    List<ModelRelease>? releases,
    this.rivalIndex = 0,
    this.viralSecondsLeft = 0,
    this.cloudSecondsLeft = 0,
    this.rngState = 12345,
    this.era = Era.garage,
  })  : hardwareCounts = hardwareCounts ?? {'gamer': 1},
        ownedUpgrades = ownedUpgrades ?? {},
        releases = releases ??
            [
              const ModelRelease(
                name: 'Fine-tuned open model',
                effectiveCompute: startEffectiveCompute,
                rating: ratingBase,
                open: true,
                time: 0,
              ),
            ];

  ModelRelease get currentModel => releases.last;

  Map<String, dynamic> toJson() => {
        'v': 1,
        'time': time,
        'money': money,
        'users': users,
        'hype': hype,
        'powerTier': powerTier,
        'hardware': hardwareCounts,
        'upgrades': ownedUpgrades.toList(),
        'openReleases': openReleases,
        'run': run?.toJson(),
        'pending': pendingEffectiveCompute,
        'releases': releases.map((r) => r.toJson()).toList(),
        'rivalIndex': rivalIndex,
        'viral': viralSecondsLeft,
        'cloud': cloudSecondsLeft,
        'rng': rngState,
        'era': era.name,
      };

  factory GameState.fromJson(Map<String, dynamic> j) => GameState(
        time: (j['time'] as num).toDouble(),
        money: (j['money'] as num).toDouble(),
        users: (j['users'] as num).toDouble(),
        hype: (j['hype'] as num).toDouble(),
        powerTier: j['powerTier'] as int,
        hardwareCounts: (j['hardware'] as Map)
            .map((k, v) => MapEntry(k as String, v as int)),
        ownedUpgrades: (j['upgrades'] as List).cast<String>().toSet(),
        openReleases: j['openReleases'] as int,
        run: j['run'] == null
            ? null
            : TrainingRun.fromJson(j['run'] as Map<String, dynamic>),
        pendingEffectiveCompute: (j['pending'] as num?)?.toDouble(),
        releases: (j['releases'] as List)
            .map((r) => ModelRelease.fromJson(r as Map<String, dynamic>))
            .toList(),
        rivalIndex: j['rivalIndex'] as int,
        viralSecondsLeft: (j['viral'] as num).toDouble(),
        cloudSecondsLeft: (j['cloud'] as num).toDouble(),
        rngState: j['rng'] as int,
        era: Era.values.byName(j['era'] as String),
      );
}
