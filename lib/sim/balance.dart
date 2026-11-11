// Tunable economy constants. Change these, then run `dart run tool/balance_sim.dart`.

/// Compute time compression: 1 real second of play = this many seconds of GPU
/// work. 1440 means one real minute ≈ one day of compute, which keeps FLOP
/// totals in roughly real-world ranges (garage run ≈ 1e18, frontier ≈ 1e25+).
const computeTimeScale = 1440.0;

/// Game seconds per in-world year, used to show annualized revenue (ARR).
const secondsPerYear = 365 * 86400 / computeTimeScale;

const startMoney = 500.0;

// --- Utilization (MFU) ------------------------------------------------------
const baseUtilization = 0.25;
const maxUtilization = 0.75;

// --- Data / scaling ---------------------------------------------------------
/// Starting data budget in tokens (roughly "Wikipedia").
const startDataTokens = 4e9;

/// Chinchilla-style: a data budget of D tokens is "fully used" by about
/// k * D^2 FLOPs. (From C ≈ 6ND and D ≈ 20N → C ≈ 0.3 D².)
const chinchillaK = 0.3;

/// Exponent applied to compute beyond the data-optimal amount. <1 means
/// diminishing returns when you are data-limited.
const dataLimitedExponent = 0.35;

// --- Model rating (an Arena-style score) -------------------------------------
/// The model you start with (a fine-tuned open model).
const startEffectiveCompute = 1e18;
const ratingBase = 700.0;
const ratingPerDoubling = 23.0;

// --- Users & revenue ---------------------------------------------------------
/// demand = demandBase * 10^((rating - ratingBase) / demandRatingScale)
const demandBase = 50.0;
const demandRatingScale = 87.0;

/// Per-second rate at which users move toward demand.
const userGrowthRate = 0.03;
const userChurnRate = 0.01;

/// Unserved users (over capacity) leave at this per-second rate.
const overloadChurnRate = 0.04;

/// Users can pile up to this multiple of capacity before signups stall.
const overflowAllowance = 1.5;

/// Hard ceiling on demand: roughly everyone online. ("You ran out of humans.")
const maxUsers = 5e9;

/// Serving cost per user in effective TFLOPS, grows with model size:
/// perUser = servingBase * (effectiveCompute / 1e18)^servingExponent
const servingBase = 0.2;
const servingExponent = 0.2;

/// revenue/s = revenueScale * servedUsers^revenueExponent * arpuMult
/// (an exponent < 1 models early high-value clients → cheap mass market).
const revenueScale = 1.0;
const revenueExponent = 0.7;

// --- Releases ------------------------------------------------------------------
/// Hype boost from a release: 1 + improvement/hypePerRating, times stunt.
const hypePerRating = 60.0;
const hypeHalfLifeSeconds = 120.0;

const openSourceArpuMult = 0.6;
const openSourceHypeMult = 1.6;
const openSourceCommunityTrainBonus = 1.05; // permanent, stacks per open release

// --- Events --------------------------------------------------------------------
/// Chance per second of a viral spike while demand ≥ 70% of capacity.
const viralChancePerSecond = 1 / 300;
const viralDemandMult = 4.0;
const viralDurationSeconds = 90.0;

/// Renting cloud GPUs: doubles serving capacity for this long, costs
/// cloudRentCostFactor × (hardware value) — expensive on purpose.
const cloudRentSeconds = 90.0;
const cloudRentCostFactor = 0.08;

/// Offline progress cap.
const offlineCapSeconds = 8 * 3600.0;

// --- Era unlocks -----------------------------------------------------------------
const startupUnlockUsers = 5e3;
/// Lab unlocks on model quality (a "GPT-2 class" model), not users — users
/// are power-capped in the Startup era, so a users gate would deadlock.
const labUnlockRating = 1080.0;
