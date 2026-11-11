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

  /// Seconds until another viral spike may start (added after v1; default 0).
  double viralCooldownLeft;
  int rngState;
  Era era;
  String labName;

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
    this.viralCooldownLeft = 0,
    this.rngState = 12345,
    this.era = Era.garage,
    this.labName = 'Garage Labs',
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
        'viralCd': viralCooldownLeft,
        'rng': rngState,
        'era': era.name,
        'labName': labName,
      };

  /// Tolerant of older saves: every field added after v1 (and most others)
  /// falls back to a default, and unknown hardware/upgrade ids are dropped.
  factory GameState.fromJson(Map<String, dynamic> j) {
    double num_(String k, double d) => (j[k] as num?)?.toDouble() ?? d;
    final hw = (j['hardware'] as Map?)
        ?.map((k, v) => MapEntry(k as String, (v as num).toInt()));
    final hardwareIds = hardware.map((h) => h.id).toSet();
    final upgradeIds = upgrades.map((u) => u.id).toSet();
    final eraName = j['era'] as String?;
    return GameState(
      time: num_('time', 0),
      money: num_('money', startMoney),
      users: num_('users', 0),
      hype: num_('hype', 1),
      powerTier: ((j['powerTier'] as num?)?.toInt() ?? 0)
          .clamp(0, powerTiers.length - 1),
      hardwareCounts: hw == null
          ? null
          : (Map.of(hw)..removeWhere((k, _) => !hardwareIds.contains(k))),
      ownedUpgrades: (j['upgrades'] as List?)
          ?.cast<String>()
          .where(upgradeIds.contains)
          .toSet(),
      openReleases: (j['openReleases'] as num?)?.toInt() ?? 0,
      run: j['run'] == null
          ? null
          : TrainingRun.fromJson(j['run'] as Map<String, dynamic>),
      pendingEffectiveCompute: (j['pending'] as num?)?.toDouble(),
      releases: (j['releases'] as List?)
          ?.map((r) => ModelRelease.fromJson(r as Map<String, dynamic>))
          .toList(),
      rivalIndex: ((j['rivalIndex'] as num?)?.toInt() ?? 0)
          .clamp(0, rivalLadder.length),
      viralSecondsLeft: num_('viral', 0),
      cloudSecondsLeft: num_('cloud', 0),
      viralCooldownLeft: num_('viralCd', 0),
      rngState: (j['rng'] as num?)?.toInt() ?? 12345,
      era: Era.values.asNameMap()[eraName] ?? Era.garage,
      labName: j['labName'] as String? ?? 'Garage Labs',
    );
  }
}
