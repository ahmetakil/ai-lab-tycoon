// Tunable economy constants. Change these, then run `dart run tool/balance_sim.dart`
// (and `--compare`). Reasoning and the current pacing table: docs/BALANCE.md.

/// The game calendar: 1 real second = this many in-world seconds, so one real
/// minute is a day and a real-world year is ~6 h of play (2017 → 2026 is
/// about two and a half days). Training runs use their era's own, gentler
/// compression (EraInfo.computeTimeScale: 1440 in the garage, 120 at the
/// frontier) so late runs last hours but stay realistic in FLOPs.
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
/// Early on users are demand-limited, so demandBase mostly paces the Garage
/// and Startup eras; later demand dwarfs capacity and stops mattering.
/// × the model design's demand multiplier (the garage default design, 2k
/// context, is ×0.92: 98 × 0.92 ≈ the old 90).
const demandBase = 98.0;
const demandRatingScale = 87.0;

/// Per-second rate at which users move toward demand.
const userGrowthRate = 0.03;
const userChurnRate = 0.01;

/// Unserved users (over capacity) leave at this per-second rate.
const overloadChurnRate = 0.08;

/// Once the unserved excess is below this fraction of capacity, users settle
/// at capacity (so OVERLOADED ends instead of decaying forever).
const overloadSettleFraction = 0.02;

/// Normally signups stop at capacity (a waitlist). During a viral spike users
/// pile up to this multiple of capacity, which is what OVERLOADED means.
const overflowAllowance = 1.5;

/// Hard ceiling on demand: roughly everyone online. ("You ran out of humans.")
const maxUsers = 5e9;

/// Serving cost per user in effective TFLOPS, grows with model size:
/// perUser = servingBase * (effectiveCompute / 1e18)^servingExponent
/// (÷ serving upgrades, × the model design's serving multiplier: the garage
/// default design, Kaplan-sized with 2k context, is ×1.30, so 0.0115 × 1.30
/// ≈ the old 0.015). Late-game users are capacity-limited, so servingBase
/// is the main knob for the users side of the rival ladder and final ARR.
const servingBase = 0.0115;
const servingExponent = 0.36;

/// revenue/s = revenueScale * servedUsers^revenueExponent * arpuMult
/// (an exponent < 1 models early high-value clients → cheap mass market).
const revenueScale = 1.0;
const revenueExponent = 0.66;

// --- Releases ------------------------------------------------------------------
/// Hype boost from a release: 1 + improvement/hypePerRating, times stunt.
const hypePerRating = 60.0;
const hypeHalfLifeSeconds = 120.0;

/// Hype ceiling (a release sets hype to max(current, boost), capped here).
const maxHype = 8.0;

const openSourceArpuMult = 0.6;
const openSourceHypeMult = 1.6;
const openSourceCommunityTrainBonus =
    1.05; // permanent, stacks per open release

// --- Events --------------------------------------------------------------------
/// Chance per second of a viral spike while users ≥ 70% of capacity and
/// demand exceeds capacity, once the cooldown has run out.
const viralChancePerSecond = 1 / 900;

/// Quiet time after a spike ends before another can start.
const viralCooldownSeconds = 600.0;
const viralDemandMult = 4.0;
const viralDurationSeconds = 90.0;

/// Renting cloud GPUs: doubles serving capacity for this long, costs
/// cloudRentCostFactor × (hardware value) — expensive on purpose.
const cloudRentSeconds = 90.0;
const cloudRentCostFactor = 0.08;

/// Offline progress cap.
const offlineCapSeconds = 8 * 3600.0;

// --- GPU supply crunch ---------------------------------------------------------
/// Each GPU tile you already own of a type makes the next one pricier
/// (TileDef.priceGrowth), up to this multiple of list price. New GPU
/// generations arrive at list price, so every era starts with a cheap ramp.
const maxSupplyPremium = 4.0;

// --- Era unlocks -----------------------------------------------------------------
// One condition per era, alternating users / rating / money so each era asks
// for something different. Users are bounded by serving capacity, i.e. by the
// power tiers of the era you're in, so every gate is reachable with that
// era's own room and tiers (checked by the playthrough tests). Moving to the
// next room only costs money and doesn't need the era; the era still unlocks
// the new parts, power and network tiers and research.

/// Garage → Startup: people use it (one maxed-out garage serves ~4k).
const startupUnlockUsers = 3e3;

/// Startup → Small lab: model quality, between GPT-ish-2 and Meenie. A full
/// server closet + startup software gets there.
const smallLabUnlockRating = 990.0;

/// Small lab → Medium lab: just past GPT-ish-3 (1120). Needs a full colo cage
/// of H100 servers on InfiniBand and the small-lab data work (the books
/// corpus lifts the data cap past it), so it asks for most of the era.
const mediumLabUnlockRating = 1130.0;

/// Medium lab → Big lab: a GPT-ish-4-class model (between ChatGPT-ish and
/// GPT-ish-4). Needs a datacenter hall and RLHF.
const bigLabUnlockRating = 1260.0;

/// Big lab → Frontier lab: a reasoning-era model (between o-three and
/// Grokk 3). Rating, not users or revenue: it's paced by training runs, a
/// full campus on the power-plant tier with reasoning RL reaches it, and a
/// lab that ships open weights (less revenue per user) is never locked out.
/// (1490: a few points under Grokk 3 so the unlock lands on day 2's evening
/// session rather than the morning after.)
const globalLabUnlockRating = 1490.0;
