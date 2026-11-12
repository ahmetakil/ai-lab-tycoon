# Balance notes

How the economy is tuned, what the bot measures, and why the numbers are what
they are. Knobs live in `lib/sim/balance.dart` (constants) and
`lib/sim/content.dart` (eras, tiles, rooms, costs and effects). The grid rules
are in `docs/GRID.md` and `lib/sim/grid.dart`. The headless player is
`lib/sim/bot.dart`; the report tool is `tool/balance_sim.dart`.

```
dart run tool/balance_sim.dart [minutes=360] [--log-every=10] [--seed=12345] [--dt=1]
    [--strategy=balanced|hardware-only|software-first|no-upgrades]
    [--layout=template|naive|random] [--schedule=active|casual] [--phases]
dart run tool/balance_sim.dart 600                          # the active player (default)
dart run tool/balance_sim.dart 900 --compare                # strategies, active
dart run tool/balance_sim.dart 2880 --schedule=casual       # sessions with offline gaps
dart run tool/balance_sim.dart 4320 --compare --schedule=casual
```

With `--schedule=casual`, `minutes` is wall-clock time (sessions plus offline
gaps) and the tool prints the timeline in wall-clock and sim time plus a
per-session table. Every run lists the idle stretches over 90 s (what the
bot was saving for). `--phases` makes the bot specialize at run-phase
checkpoints instead of taking the all-rounder.

## Target: an active 6–8 h game (v5)

Not an idle clicker: a Game Dev Tycoon-style game you play. A full
playthrough, garage to the final rival, is 6–8 hours of active play, with a
meaningful choice every 30–90 s and never two idle minutes.

| Milestone | Target | Active bot, seed 12345 | 7 seeds |
|---|---|---|---|
| Startup | 3–5 min | 4:06 | 2:28–4:06 |
| Small lab | 15–25 min | 18:37 | 17:53–18:45 |
| Medium lab | ~1h15–1h45 | 1:43 | 1:33–1:45 |
| Big lab | ~3h–3h45 | 3:51 | 3:25–3:51 |
| Frontier | ~4h30–5h15 | 5:10 | 4:40–5:10 |
| Final rival | 6–8 h | **6:38** | 6:27–6:59 |

`PlaySchedule.active` (bot.dart, the default everywhere) is continuous play;
the bot looks at the screen every 4 s, so it reacts within 0–4 s. Training
runs are 30 s / 1 m / 2 m in the garage, 1 m / 2 m / 3 m in the Startup and
1 m / 3 m / 5 m from the Small lab on (`EraInfo.runDurations`); each run has
two run-phase checkpoints (lib/sim/run_phases.dart, at 1/3 and 2/3), so a
5-min run asks for a call every ~100 s.

**Offline cap.** An absence earns at most 2 h (`offlineCapSeconds`), at 10%
of live revenue (`offlineEarningsRate`); users, hype and a running run tick
at full speed. The dialog says "Earnings capped at 2h away". Why 10%: the
mid-game is research-gated, so active play also mostly earns toward the next
research item, and full-rate offline money made 2 h away worth ~1h40–2h50
of play (forked runs from Small lab and Medium lab, seed 12345). At 25% it
was still ~60–100 min. At 10% a full absence banks ~12 min of income and is
worth ~10–75 min of play, typically ~30 (fork noise ±15 min). Idling helps
a little; playing is how you move forward.

**The casual schedule** (`PlaySchedule.casual`: 60/45/30/60 min sessions
with 2.5–12 h breaks) still works: final rival at 31h20 wall-clock after 5h30
of play over 7 sessions (vs 6h38 for the active player). The breaks shave
about an hour off the play because of the 2 h of 10%-rate earnings each
time, and the run that finishes while you're away.

## The bot (an "engaged human")

- Looks at the game every 4 s (`PlaySchedule.active.reactionSeconds`). It
  only uses choices the UI offers: 50% or 75% of the training cluster, and
  the era's three run lengths (`EraInfo.runDurations`). It answers a run-phase
  checkpoint at once (the default all-rounder pick, or specialized with
  `specializePhases`).
- **What counts as a decision** (idle stretches, `PlaythroughResult.decisions`):
  a purchase, a release, a new run, a checkpoint call, renting cloud GPUs,
  and pausing or resuming training for a viral spike.
- **Run length.** Active play takes the middle option in the Garage and
  Startup and the longest (5 min) from the Small lab on: a run's rating comes
  from its compute, so the longest run is the best model per minute. In a session it takes the
  middle one if it fits the session, else the longest run that finishes before
  it comes back. Whenever a shorter run already crosses the next rating gate
  or rival (the UI shows the predicted rating), it takes that one. Before
  closing the app (`Bot.leave`) it ships a finished model, resumes a paused
  run and starts the run that will finish while it's away.
- Releases a model only if it beats the current one: open weights in the
  Garage, closed later, always with a cryptic tweet.
- **Viral spike while overloaded.** It rents cloud GPUs only if the extra users
  would pass the next rival (and it costs < 25% of cash). Otherwise it pauses
  training until the spike ends (serving the crowd pays better).
- **Spending.** It scores every option by Δprogress / $ (predicted rating in
  compute doublings + log(users it could serve) + ½·log(ARPU)). The options:
  each available upgrade, the next build step in the room, a cooler upgrade,
  swapping the room's weakest GPU (and the training cluster's weakest) for
  its best one (when the room is full, or per kW when power is the limit),
  the next power, network and central-cooling tiers, and moving to the next
  room. It buys the best affordable
  option, up to 12 per look. It also considers the cheapest GPU the room
  sells (e.g. a Vera Rubin rack while a SuperPOD is out of reach), so one
  lumpy tile never stalls it. It saves for something better if it's close:
  up to 45 s in the Garage, 60 s in the Startup, 75 s in the Small and
  Medium labs, 150 s in the Big lab and 300 s at the Frontier (3 min max
  inside a scheduled session). Research may be saved for 6× as long when it's
  a far better deal than any GPU (a ×2 serving trick, RLHF); the run's
  checkpoints keep you busy meanwhile.
  When growth is blocked (out of power, the best GPU doesn't fit the
  headroom, or out of floor space), the next power tier or room is
  "essential" and it saves for it however long it takes; so is a network
  tier once runs would scale below 70%. A power tier past the building's
  limit (`RoomDef.maxPowerTier`) isn't a candidate: the move is, valued by
  that power (GPUs to fill it) and essential when the power would have
  been.
  been.

### Placement (`--layout`)

- **template** (default): each room gets a fixed plan: stripes two GPUs wide
  with a cooler column between them (G G C), so every GPU touches a cooler
  cell. (Where GPUs sit doesn't matter for training: the whole room is one
  cluster.) A cooler goes in only if the new GPU would run hot: the cheapest
  cooler that cools all its neighbours, else the strongest that fits the
  power. Once the plan is full and central cooling keeps a GPU cool without
  its cooler, spare cooler cells take GPUs too.
- **Moving.** The bot moves as soon as the next room is worth it (money is
  the only gate; before the room's era it values the extra floor for today's
  best GPU). After a move it re-lays its tiles on the new plan (moves are
  free): best GPUs first, old-room coolers and anything without a spot are
  sold. It buys the parts of the newest room whose parts are unlocked.
- **Network tier** is a candidate valued like any purchase (it lifts the
  scaling efficiency) and becomes essential when a run would scale below 70%.
  **Central cooling** is a candidate from the Medium lab (valued by the
  throttling it removes).
- It swaps the weakest GPU (anywhere, and separately the weakest in the
  training cluster) for its best one when the room is full or power is tight.
- **naive**: GPUs only, on random empty cells. No coolers.
- **random**: buys about one cooler per two GPUs but drops every tile on a
  random empty cell.

## Eras, gates and unlocks

| era (enum) | label | years | gate to enter | room |
|---|---|---|---|---|
| `garage` | Parents' garage | 2017 | start | Garage 4×4 |
| `startup` | Startup | 2018–19 | 3k users | Server closet 7×7 |
| `smallLab` | Small lab | 2020–22 | rating 1000 | Colocation cage 10×10 |
| `mediumLab` | Medium lab | 2023 | rating 1130 (just past GPT-ish-3) | Datacenter hall 14×14 |
| `bigLab` | Big lab | 2023–25 | rating 1260 (ChatGPT-ish) | Datacenter campus 18×18 |
| `globalLab` | Frontier lab | 2025–26 | rating 1490 (just under Grokk 3) | Gigawatt site 22×22 |

`Game.nextEraGoal` exposes the next gate (metric, target, progress) for the
UI (the always-visible goal strip, and `Game.eraLockReason`: "Unlocks in
Small lab: reach rating 1,000 (you're at 998)."). The gates unlock an era's
parts, power / network / cooling tiers and research; moving to its room only
needs the room's price. Eras unlock one per tick, and offline too (a users gate can fill while
you're away). Rivals carry an `era` and can't be beaten before you reach it, so
an overpowered model unlocks its rivals one era at a time.

**No deadlocks.** Every gate is reachable with the era's own power cap, rooms
and longest run (the bot's choice; v5 didn't recheck the middle run). The rating gates sit below what that era's cluster and
data budget can reach: Small lab tops out near 1120–1165 depending on the books
corpus, Medium lab ~1340 with licensed data, Big lab ~1560. None of them needs
users or revenue, so a player who ships open weights (ARPU ×0.6) or never rents
cloud GPUs can't get stuck. Earlier drafts had a 1M-users Medium gate that only
cloud overflow could reach at the colo power cap, and a $10B ARR Frontier gate
the 150 MW Big lab couldn't reach; the playthrough tests guard against that.

### What each era unlocks

### Parents' garage (`garage`, 2017)
- room: Garage 4×4 ($0)
- power: Garage outlet 1.8 kW ($0), Upgraded electrical panel 8.0 kW ($3k)
- gpu: RTX 2060 (used) ($900), RTX 4090 ($2k), Used V100 ($3k)
- cooling: Box fan ($120), Window AC ($500)
- network: Copper Ethernet 1G, feeds 4 ($0); 10G copper, feeds 32 ($1.5k)
- research: Mixed precision (FP16) $800, Request batching $1.2k, KV cache $2.5k, LoRA fine-tuning $2k, Filtered web crawl $3k
- stunts: Quiet release, Cryptic tweet, Live demo
- runs: 30s / 1m / 2m at 5000× (1.7 d / 3.5 d / 6.9 d of compute)
- rivals: Tiny-Transformer (765), GPT-ish-1 (796)
### Startup (`startup`, 2018–19)
- room: Server closet 7×7 ($15k)
- power: 3-phase service 50.0 kW ($46.6k)
- gpu: DGX A100 (8× A100) ($57.5k, +5%/tile)
- cooling: Precision AC (CRAC) ($13.8k)
- network: 100G fiber, feeds 256 ($40k)
- research: Custom CUDA kernels $351k, Quantization (INT8) $439k, Public code dataset $585k, Deduplication & quality filters $878k, Data mixture optimisation $645k, Instruction tuning $585k
- stunts: 
- runs: 1m / 2m / 3m at 7200× (5.0 d / 10 d / 15 d of compute)
- rivals: BURT-Large (888), GPT-ish-2 (950)
### Small lab (`smallLab`, 2020–22)
- room: Colocation cage 10×10 ($800k)
- power: Leased colo circuits 500.0 kW ($164k)
- gpu: HGX H100 (8× H100) ($180k, +12%/tile)
- cooling: Rear-door heat exchanger ($48k)
- network: InfiniBand 400G, feeds 4096 ($300k)
- research: FlashAttention $10M, High-speed interconnect $420k, Liquid cooling $20.1M, Books & papers corpus $36M, Compute-optimal scaling $24.9M, FSDP / ZeRO sharding $36M
- stunts: Mystery model on the arena
- runs: 1m / 3m / 5m at 2100× (1.5 d / 4.4 d / 7.3 d of compute)
- rivals: Meenie (1085), GPT-ish-3 (1120)
### Medium lab (`mediumLab`, 2023)
- room: Datacenter hall 14×14 ($1.5M)
- power: Dedicated medium-voltage feed 2.0 MW ($488k), On-site substation 20.0 MW ($575k)
- gpu: H100 rack ($464k, +10%/tile), GB200 NVL72 ($2.3M, +10%/tile)
- cooling: Chiller unit ($120k), Direct liquid-cooling loop ($200k)
- network: InfiniBand spine, feeds 32768 ($2.2M)
- central cooling: Central chilled water −80/tile ($579k)
- research: Mixture of Experts $13.5M, RLHF $18M, 3D parallelism $22.5M, Distillation $27M, Paged KV cache $22.5M, Licensed data deals $1.4M
- design research: Grouped-query attention $10.8M, Sliding-window attention $19.8M, RoPE position interpolation $9M, Router load balancing $16.2M, Inference-aware scaling $7.2M, Pre-training mix in RL (PPO-ptx) $14.4M, Long-document data $16.2M, 4-bit weights (GPTQ/AWQ) $18M
- stunts: 
- runs: 1m / 3m / 5m at 7500× (5.2 d / 16 d / 26 d of compute)
- rivals: Mixtrawl 8x7B (1210), ChatGPT-ish (1260)
### Big lab (`bigLab`, 2023–25)
- room: Datacenter campus 18×18 ($7.5M)
- power: Power plant deal (PPA) 300.0 MW ($2.4M)
- gpu: B200 SuperPOD ($11.7M, +12%/tile), Vera Rubin NVL144 ($1.2M, +12%/tile), Rubin SuperPOD ($16.4M, +12%/tile)
- cooling: Cooling tower ($1.2M)
- network: NVLink fabric, feeds 131072 ($26.6M)
- central cooling: Evaporative cooling towers −250/tile ($10M); Facility liquid loop −450/tile ($24.2M)
- research: FP8 training $81M, Speculative decoding $608M, Synthetic data $810M, AI feedback (RLAIF) $270M, Long context (ring attention) $405M, Reasoning (RL on chain of thought) $675M
- design research: YaRN context extension $162M, Fine-grained experts $486M, Hybrid state-space layers $324M, Direct Preference Optimization $135M, Bigger reward models $243M
- stunts: Livestreamed keynote
- runs: 1m / 3m / 5m at 13000× (9.0 d / 27 d / 45 d of compute)
- rivals: GPT-ish-4 (1339), Claudette 3.5 Sonata (1373), DeepSleep-R1 (1378), Claudette 3.7 Sonata (1455), o-three (1463), Grokk 3 (1503), GPT-ish-4.5 (1506)
### Frontier lab (`globalLab`, 2025–26)
- room: Gigawatt site 22×22 ($20M)
- power: Gigawatt grid interconnect 1.0 GW ($14.4M), Restarted nuclear plant 2.0 GW ($90.9M), Multi-site cluster 4.0 GW ($300M)
- gpu: Rubin building ($36M, +3%/tile)
- cooling: Closed-loop dry coolers ($1.1M)
- network: Optical fabric, feeds 4194304 ($61.4M)
- central cooling: Dry-cooler farm −550/tile ($14.5M)
- research: Multi-token prediction $1.8B, Expert data (PhD annotators) $2.1B, Test-time compute scaling $6.6B, Agentic RL environments $10.5B, Prefill/decode disaggregation $3B
- design research: Adaptive thinking budgets $3.6B
- stunts: Big-game TV ad
- runs: 1m / 3m / 5m at 1200× (0.8 d / 2.5 d / 4.2 d of compute)
- rivals: GPT-ish-5 (1512), Gemeni 3 Pro (1571), Amused Spark (1580), GPT-ish-5.5 "Tater" (1596), Claudette Parable 5 (1618), Gemeni 4 Xenon (1622), GPT-ish-6 Astral (1626)

The big parody labs (ClosedAI, Anthropomorphic) fight it out in Big lab with
DeepSleep and yAI. The frontier fight (GPT-ish-5 → GPT-ish-6 Astral, with
Gogol DeepThought's Gemeni and MetaMind's Amused Spark) is in the Frontier lab.
The rival ratings are unchanged: they come from real FLOPs through the game's
own formula.

## Pacing: active schedule (balanced bot, template layout)

Before (v4, 2–3 day idle design) vs after (v5), seed 12345:

| Milestone | v4 continuous | v4 casual (wall) | v5 active | v5 casual (wall) |
|---|---|---|---|---|
| Startup | 0h12 | 0h12 | 0h04 | 0h04 |
| Small lab | 0h58 | 0h58 | 0h18 | 0h18 |
| Medium lab | 3h15 | 7h15 | 1h43 | 3h55 |
| Big lab | 13h52 | 24h00 | 3h51 | 7h18 |
| Frontier lab | 29h48 | 31h15 | 5h10 | 24h00 |
| Final rival | 44h19 | 58h45 | **6h38** | 31h20 |
| Longest idle | 79.7 min | 13.8 min (in session) | **1.7 min** | 1.7 min |

v5 active, seed 12345: 813 decisions to the final rival (one every 29 s),
78 releases, 44/48 upgrades, 71 viral spikes; at the final rival 1.27B
users, $29B ARR, 2.6M H100e, 2.1 GW. No stretch reaches 2 min; 62 pass 90 s
(102 min in all, mostly a 5-min run between checkpoints while saving).

Seeds (time to unlock, h:mm:ss):

```
phases off (default bot)
seed  | Startup  | Small lab | Medium lab | Big lab  | Frontier | final    | idle max
12345 | 0:04:06  | 0:18:37  | 1:43:21  | 3:51:05  | 5:10:49  | 6:38:42  | 1.7m
1     | 0:04:06  | 0:18:29  | 1:45:37  | 3:37:57  | 5:04:29  | 6:51:13  | 1.7m
777   | 0:04:06  | 0:18:45  | 1:44:17  | 3:40:17  | 5:06:05  | 6:33:06  | 1.7m
2026  | 0:04:06  | 0:18:29  | 1:44:13  | 3:40:49  | 5:10:25  | 6:59:45  | 1.7m
4242  | 0:02:28  | 0:17:53  | 1:33:17  | 3:25:41  | 4:40:33  | 6:27:21  | 1.7m
99    | 0:03:36  | 0:18:21  | 1:44:41  | 3:42:53  | 4:52:01  | 6:43:21  | 1.7m
31337 | 0:02:36  | 0:18:25  | 1:39:45  | 3:42:37  | 4:51:01  | 6:35:21  | 1.7m
phases on (Bot(specializePhases: true))
12345 | 0:04:08  | 0:18:49  | 1:48:49  | 3:44:33  | 5:15:09  | 7:00:50  | 1.7m
1     | 0:04:08  | 0:18:53  | 1:45:49  | 3:43:13  | 5:10:01  | 6:47:01  | 1.7m
777   | 0:04:08  | 0:18:57  | 1:44:17  | 3:34:53  | 5:00:37  | 7:15:37  | 1.7m
2026  | 0:04:08  | 0:18:41  | 1:44:21  | 3:51:09  | 5:37:33  | 7:20:25  | 1.7m
4242  | 0:03:41  | 0:17:41  | 1:42:41  | 3:39:41  | 5:09:57  | 6:55:35  | 1.7m
99    | 0:03:39  | 0:18:33  | 1:44:49  | 3:47:45  | 5:17:41  | 7:03:41  | 1.7m
31337 | 0:03:44  | 0:18:17  | 1:44:05  | 3:44:49  | 5:24:13  | 7:16:13  | 1.7m
```

- Every seed finishes in 6h27–6h59 (phases on: 6h47–7h20) and none has a
  2-minute idle stretch.
- Outliers: a lucky early viral spike gets seeds 4242 and 31337 to 3k users
  (Startup) in ~2.5 min. Big lab lands a few minutes past 3h45 on 12345
  (3h51), 2026 with phases (3h51); the Frontier past 5h15 on 2026, 99 and
  31337 with phases (5h17–5h37).
- Sensitive spots: the end of the Small lab (the 500 kW colo cap fills at
  rating ~1120, then the gate waits on Small-lab research; flash attention's
  price sets that wait) and Big-lab research (×0.25 vs ×0.3 of the old price
  moves the Frontier by ~45 min).

### What model design changed in the balance

- **Start unchanged.** The garage default design (dense, full attention, 2k,
  Kaplan-sized, web crawl, SFT, FP16) serves at ×1.30 and demand ×0.92;
  `servingBase` 0.015 → 0.0115 and `demandBase` 90 → 98 absorb that. It also
  costs ~3 rating (Kaplan sizing), so the Small-lab gate is 990 (was 1000).
- **No double counting.** `moe`, `chinchilla_scaling`, `quantization`,
  `long_context` and `reasoning` only unlock options now; `rlhf` keeps its
  ARPU (+20%) and the RLHF choice gives the rating (up to +70, +81 with bigger
  reward models).
- **Late serving.** GQA ×0.7, sliding window ×0.6, hybrid SSM ×0.5 (the KV
  cache is only part of decode cost), INT8 ×0.55, INT4 ×0.35 and
  compute-optimal sizing all stack, so speculative decoding went ×1.8 → ×1.3
  and disaggregated serving ×1.4 → ×1.2. RL reasoning serves at ×6 (×2.5 with
  adaptive thinking) and adds +50 rating: the late game is a real trade
  between rating and users.
- **Network.** MoE needs a fabric: below an InfiniBand-spine-class network
  (32,768 GPUs) its gain shrinks, and a cluster more than 2× over the network
  tier's cap counts one network class lower.
- **Bad designs lose.** A bot locked to a huge, under-trained dense base model
  (2 tok/param, web only, 2k, no post-training) beats fewer than half the
  rivals, reaches the Medium lab 6+ hours later and never finishes
  (`playthrough_test.dart`). Extreme RL is worse than plain SFT.

### How the bot designs models

`ModelSpec.bestGuessFor` with a serving weight that follows what blocks
progress: 4 (demand weight 8) when rating blocks an era gate or rival, 23 when
capacity-limited, else 6. If a rival needs users and we already have its
rating, the cheapest-to-serve design that still clears it, and it ships such
a cheaper model even if it isn't the top-rated one. It spends before starting
a run (the design is fixed at the start, so research bought first can be
used) and never starts a run predicted below its current model unless users
are the goal.


## Pacing: casual schedule

Seed 12345, 2 h offline cap at 10% earnings:

```
sess | wall start | sim start | len | era at start | ran away | decisions (buy/rel) | idle max | rivals | eras
   0 |       0h00 |      0h00 |  60 | Parents' garage | -     |  200 (100/15)       |   1.0m |      5 | Startup, Small lab
   1 |       3h30 |      3h00 |  45 | Small lab    | yes      |  137 (83/8)         |   1.7m |      1 | Medium lab
   2 |       7h15 |      5h45 |  30 | Medium lab   | yes      |   55 (10/8)         |   1.1m |      1 | Big lab
   3 |      10h45 |      8h15 |  60 | Big lab      | yes      |  123 (42/11)        |   1.2m |      6 |
   4 |      24h00 |     11h15 |  60 | Big lab      | yes      |  138 (51/14)        |   1.7m |      4 | Frontier lab
   5 |      27h30 |     14h15 |  45 | Frontier lab | yes      |  113 (60/3)         |   0.9m |      4 |
   6 |      31h15 |     17h00 |  30 | Frontier lab | yes      |   23 (15/2)         |   0.7m |      1 |
```

Final rival at 31h20 wall-clock, 5h30 of play in 7 sessions. The casual
schedule's numbers are no longer targets; the test only checks that it
finishes, that most of the game is still played, and the idle limit.

## Strategies and placement

```
active, 15h00 cap
strategy / layout        | Startup | Small lab | Medium lab | Big lab | Frontier lab | final | rivals
balanced / template      |  0h04   |  0h18     |  1h43      |  3h51   |  5h10        | 6h38  | 22/22
hardwareOnly / template  |  0h07   |    —      |    —       |    —    |    —         |   —   |  4/22
noUpgrades / template    |  0h10   |    —      |    —       |    —    |    —         |   —   |  2/22
softwareFirst / template |  0h05   |  0h22     |  1h52      |  3h48   |  5h41        | 7h54  | 22/22
balanced / naive         |  0h05   |  0h33     |  1h27      |  4h22   |  5h42        | 7h39  | 22/22
balanced / random        |  0h04   |  0h30     |  1h55      |  4h13   |  5h54        | 7h46  | 22/22

casual, 72h00 cap
balanced / template      |  0h04   |  0h18     |  3h55      |  7h18   | 24h00        | 31h20 | 22/22
hardwareOnly / template  |  0h07   |  0h55     |    —       |    —    |    —         |   —   |  4/22
noUpgrades / template    |  0h10   |    —      |    —       |    —    |    —         |   —   |  2/22
softwareFirst / template |  0h05   |  0h21     |  4h02      | 10h51   | 24h14        | 28h13 | 22/22
balanced / naive         |  0h05   |  0h27     |  3h35      |  7h18   | 24h13        | 31h20 | 22/22
balanced / random        |  0h04   |  0h29     |  3h56      |  7h20   | 24h05        | 31h15 | 22/22
```

- **naive** (no coolers) and **random** placement throttle the early rooms
  (the heat puzzle): Small lab 12–15 min late and the final rival about an
  hour later in active play. On the casual schedule they catch up by the
  end (the finish waits for the same session).
- **hardware-only** stalls by the Small lab; **no-upgrades** stays in the
  Startup; **software-first** finishes ~1h15 later.
- **Bad model design** (huge under-trained base model, web only, 2k, no
  post-training) never reaches the Startup's 3k users: its demand is too low
  without hype (`playthrough_test.dart`). Harsher than v4, where it reached
  the Medium lab hours late; a player can change the design at any run.

## Why the numbers are what they are

**Active pacing (v5).** `activePace` = 3 in balance.dart: revenue, user
growth and churn, overload churn and viral chance are ×3, hype half-life
(40 s), viral spikes (30 s, 200 s cooldown) and cloud rental (30 s) ÷3. The
calendar (`computeTimeScale` = 4320: one real minute is three days) keeps ARR
reading as before. The rest is in content prices, chosen by one rule: **a
one-off that blocks growth costs about a minute of income when you need
it.** In the idle design big items were sized for offline lumps (a power
tier ~10 min of revenue, research up to hours), which in active play means
long stretches of watching the money counter. So:

- Power tiers, network tiers and central cooling cost ~1 min of the income
  you have when the previous cap fills (×0.02–0.2 of v4; the PPA 300 MW tier
  ×0.02, the gigawatt interconnect ×0.04).
- Rooms stay real choices: colo ×0.4, hall ×0.5, campus ×0.25, gigasite
  ×0.05. Cheaper rooms let the bot skip the heat puzzle by moving early, and
  naive placement stopped mattering.
- Research is the pacing gate: an era's research costs about what you earn
  in 1–3 min at the point it should be bought, so it arrives as income grows,
  not after a long save. Startup ×1.5, Small lab ×3 (flash attention ×4, data
  mixture ×0.43, high-speed interconnect ×0.1: it gates InfiniBand, without
  which runs scale at 60%), Medium ×0.18, Big ×0.27, Frontier ×0.3 (design
  research in model_design.dart scales with its era).
- GPU tiles keep the "newer beats older per $ and per kW" chain: A100 servers
  ×1.15, H100 servers ×1.2, Medium racks ×0.8, Big-lab pods and racks ×0.3
  with a 12%/tile supply crunch (was 9%: cheap first tiles at era entry, ×4
  later), Rubin buildings ×0.12.
- Granularity: Vera Rubin racks are also sold for the campus and Rubin
  SuperPODs for the gigasite, so each era's entry has a tile you can afford.

**Time compression per era.** Runs use their era's `EraInfo.computeTimeScale`,
fixed when the run starts (saved as `TrainingRun.timeScale`): 5000 in the
Garage, 7200, 2400, 7500, 13000 and 1200 at the Frontier. The longest run of
each era is 4 days to 6 weeks of compute, so a bigger cluster, not a longer
wait, makes a better model. It's no longer monotonic: it is also the knob
for how much hardware each era's rating gate needs (Small lab 2400 makes the
colo's power cap meet the 1130 gate; Big lab 13000 keeps the campus era from
crawling).

**GPU supply crunch.** Each GPU tile of a type you already own makes the next
one pricier (`TileDef.priceGrowth`, 3–12% compounding, capped at
`maxSupplyPremium` = ×4 list; selling refunds half of list). List prices keep
the "newer GPU beats older per $ and per kW" chain. Every new generation
arrives at list price, so an era unlock feels like relief. The crunch stretches
each era without lumps: there's always a next GPU to buy, just pricier.

**Power tiers** cost ~1 min of revenue at the moment the previous cap fills
(v4: ~10 min, sized for offline lumps). **Research is the pacing gate** (see
"Active pacing"): Medium lab $7–27M, Big lab $81–810M, Frontier $1.8–10.5B.

**Revenue and serving.** `revenue = users^0.7` (unchanged) and
`servingExponent` 0.3 → 0.33 (bigger models cost a little more to serve).
Users per MW must stay high enough for the rival user counts at each era's
power cap: at 0.42 the 150 MW Big lab served only ~80M users, and o-three's
400M was impossible. Quantization is ×2 (INT8/INT4); paged KV cache is ×2.4.

**Data budget.** 4B start × web crawl 50 × code 3 × books & papers 2 ×
licensed 16 × synthetic 4 ≈ 77T tokens, data-optimal up to ~1.7e27 FLOPs as
before, but spread so each era has its data step. Synthetic data used to be the
only big multiplier, and the Medium lab hit a hard data wall below its gate.

**Room space.** See "One place at a time" below. The colo tier is 500 kW and
the plant tier 300 MW; the gigasite building is ~8k Rubin GPUs ($36M in
v5), so each era has enough floor and power for a steady stream of GPU
purchases.

**One place at a time (v4).** Capacity comes from one room, so each room
holds the previous one's layout plus about 1.5× more floor (4×4, 7×7,
10×10, 14×14, 18×18, 22×22). Moves cost only money: rooms are priced so an
early move is a real choice (the closet's $15k is a garage-era purchase,
the gigasite's $20M a late Big-lab one). Room free cooling per cell went down
(closet 2.5, colo 5, hall 18, campus 40, gigasite 70) so moving early doesn't
solve heat by itself; central cooling (80 / 250 / 450 / 550 heat per GPU
tile) covers the late rooms without making coolers worthless. Throttling is
`max(0.2, 1 − netHeat/heat)` (was 0.3 and 0.7×).

**Network as a tier (v4).** All GPUs in the room are one cluster. The tier
ladder (4 → 32 → 256 → 4k → 32k → 131k → 4M GPUs) is priced so each step is
bought when its era's cluster outgrows the previous one (v5: copper 10G $1.5k
in the garage, InfiniBand 400G $300k, spine $2.2M, NVLink $27M, optical
$61M).

**Power limits per place.** Power tiers are named after the supply
(3-phase service, leased colo circuits, medium-voltage feed, on-site
substation, PPA, gigawatt grid interconnect), never a place, and each room's
electrical service caps the tier you can buy there: garage 8 kW, closet
50 kW, colo 500 kW, hall 20 MW, campus 1 GW, gigasite 4 GW. Moving buys no
power; you keep your tier. The campus takes the gigawatt interconnect
(suggested: 300 MW) because the Frontier's first push happens there: at
300 MW the bot must buy the $400M gigasite before the $350M tier and the
final rival slips to 72h on seeds 12345 and 777. Before, you could buy the
colo tier in the closet; now you move to the colo ($2M) first, which only
reorders the early spend (eras land at the same times).

**Power tiers retuned for one room (v4; v5 prices are in "Active pacing").**
A move fills the old cap at once, so
tiers are cheaper relative to revenue: office 50 kW (was 40), campus $7M,
power plant $120M, gigawatt $350M, nuclear $1B, multi-site $2B. Also books
corpus $12M, test-time compute $22B, expert data +23 rating, Frontier time
compression 40 (8 h = 13 days of compute), Medium-lab gate 1130 and
Frontier gate 1490.

**Live rival feed.** `lib/sim/news.dart` only decides when a rival appears
on the leaderboard (in ladder order: the next rival always, plus up to two
more on a per-era game-time drip, from reached eras only) and posts flavour
news. It uses no RNG and doesn't touch `canBeat`, so pacing is identical
with and without it. v5 drips a rival every 1 min (garage) to 20 min (Medium
lab) of game time and flavour news every 2–20 min, so the board moves while
you play.

**Unchanged from v2:** the grid rules, rival ratings and users, hype cap 8,
overload settle, cloud rental cost factor. (v5 changed the time-based
demand/hype/viral numbers, see "Active pacing", and the offline cap.)
