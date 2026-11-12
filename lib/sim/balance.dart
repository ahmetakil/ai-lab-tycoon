// Tunable economy constants. Change these, then run `dart run tool/balance_sim.dart`
// (and `--compare`). Reasoning and the current pacing table: docs/BALANCE.md.

/// How much faster the active game runs than the old 2–3 day idle design
/// (v5). Every per-second rate (revenue, user growth and churn, hype decay,
/// viral spikes) is the old one × [activePace] and every timer ÷ it, so the
/// economy plays the same in fewer minutes. Late eras compress further
/// because runs are now minutes long (EraInfo.runDurations).
const activePace = 3.0;

/// The game calendar: 1 real second = this many in-world seconds (one real
/// minute is [activePace] days). It sets ARR: revenue/s is × [activePace],
/// so ARR reads the same as in the old idle design. Training runs use their
/// era's own compression (EraInfo.computeTimeScale).
const computeTimeScale = 1440.0 * activePace;

/// Game seconds per in-world year, used to show annualized revenue (ARR).
const secondsPerYear = 365 * 86400 / computeTimeScale;

const startMoney = 500.0;

/// Revenue per user in the Parents' garage: a hobby project lives on tips
/// and the odd sponsor. The Startup era (you incorporate and sell plans)
/// lifts it to 1. This is the garage's pace knob: at full rate a garage
/// card cost seconds of income and the garage was over in 4 minutes.
const garageArpuMult = 0.09;

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
const userGrowthRate = 0.03 * activePace;
const userChurnRate = 0.01 * activePace;

/// Unserved users (over capacity) leave at this per-second rate.
const overloadChurnRate = 0.08 * activePace;

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
const revenueScale = activePace;
const revenueExponent = 0.66;

// --- Releases ------------------------------------------------------------------
/// Hype boost from a release: 1 + improvement/hypePerRating, times stunt.
const hypePerRating = 60.0;
const hypeHalfLifeSeconds = 120.0 / activePace;

/// Hype ceiling (a release sets hype to max(current, boost), capped here).
const maxHype = 8.0;

const openSourceArpuMult = 0.6;
const openSourceHypeMult = 1.6;
const openSourceCommunityTrainBonus =
    1.05; // permanent, stacks per open release up to the cap below

/// The community bonus stacks for this many open releases at most (×1.28).
/// Uncapped, the 40-odd small open releases of a long garage stacked to ×7
/// training efficiency and skipped most of the next eras.
const openSourceCommunityMaxStacks = 5;

// --- Events --------------------------------------------------------------------
/// Chance per second of a viral spike while users ≥ 70% of capacity and
/// demand exceeds capacity, once the cooldown has run out.
const viralChancePerSecond = activePace / 900;

/// Quiet time after a spike ends before another can start.
const viralCooldownSeconds = 600.0 / activePace;
const viralDemandMult = 4.0;
const viralDurationSeconds = 90.0 / activePace;

/// Renting cloud GPUs: doubles serving capacity for this long, costs
/// cloudRentCostFactor × (hardware value) — expensive on purpose.
const cloudRentSeconds = 90.0 / activePace;
const cloudRentCostFactor = 0.08;

/// Offline progress cap per absence ("Earnings capped at 2h away").
const offlineCapSeconds = 2 * 3600.0;

/// While you're away the lab earns at this fraction of its live rate (users,
/// hype and a running run still tick at full speed). Mid-game progress is
/// research-gated, so full-rate offline money made 2 h away worth ~2 h of
/// play; at 10% a full absence banks ~12 min of income, worth roughly 10–75
/// (typically ~30) min of active play (docs/BALANCE.md, "Offline cap").
const offlineEarningsRate = 0.1;

// --- GPU supply crunch ---------------------------------------------------------
/// Each GPU tile you already own of a type makes the next one pricier
/// (TileDef.priceGrowth), up to this multiple of list price. New GPU
/// generations arrive at list price, so every era starts with a cheap ramp.
const maxSupplyPremium = 4.0;

// --- Era unlocks -----------------------------------------------------------------
// The garage asks for hardware (a full garage), every later era for a model
// rating. Users are bounded by serving capacity, i.e. by the
// power tiers of the era you're in, so every gate is reachable with that
// era's own room and tiers (checked by the playthrough tests). An era also
// opens its room: moving needs the era and the room's price, so each room
// is where you spend its whole era (fill it, then feel the walls).

/// Garage → Startup: a garage full of fast GPUs (peak TFLOPS of the GPUs
/// you own). 12 used V100s are 1.5 PFLOPS, the most the garage holds. The
/// bot fills all 16 cells at ~45 min with a mix of cards, then swaps two
/// old ones for V100s and crosses this at ~49 min: you feel the walls a few
/// minutes before the way out opens. Hardware, not users: a viral spike
/// can't skip it.
const startupUnlockTflops = 1050.0;

/// Startup → Small lab: model quality, between GPT-ish-2 and Meenie. A full
/// server closet + startup software gets there.
const smallLabUnlockRating = 990.0;

/// Small lab → Medium lab: just past GPT-ish-3 (1120). Needs a full colo cage
/// of H100 servers on InfiniBand and the small-lab data work (the books
/// corpus lifts the data cap past it), so it asks for most of the era.
const mediumLabUnlockRating = 1130.0;

/// Medium lab → Big lab: a GPT-ish-4-class model (between ChatGPT-ish and
/// GPT-ish-4). Needs a full datacenter hall (the 4 MW substation tier) and
/// RLHF; their prices and the Medium lab's time compression set the era.
const bigLabUnlockRating = 1260.0;

/// Big lab → Frontier lab: a reasoning-era model (between o-three and
/// Grokk 3). Rating, not users or revenue: it's paced by training runs, a
/// full campus on the power-plant tier with reasoning RL reaches it, and a
/// lab that ships open weights (less revenue per user) is never locked out.
/// (1490: a few points under Grokk 3 so the unlock lands on day 2's evening
/// session rather than the morning after.)
const globalLabUnlockRating = 1490.0;
