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
    [--seeds=12345,1,777]
dart run tool/balance_sim.dart 600                          # the active player (default)
dart run tool/balance_sim.dart 600 --seeds=12345,1,777,2026,4242,99,31337   # milestones + room fill per seed
dart run tool/balance_sim.dart 900 --compare                # strategies, active
dart run tool/balance_sim.dart 2880 --schedule=casual       # sessions with offline gaps
dart run tool/balance_sim.dart 4320 --compare --schedule=casual
```

With `--schedule=casual`, `minutes` is wall-clock time (sessions plus offline
gaps) and the tool prints the timeline in wall-clock and sim time plus a
per-session table. Every run lists the idle stretches over 90 s (what the
bot was saving for) and ends with the room table: each room's GPU tiles,
cells and power (of the most its building takes in that era) when the next
room's era unlocks, and how long it had been at its wall (every cell used,
or no GPU fits the power left) by then (`RoomFill` in bot.dart, also in
`PlaythroughResult.roomFill`). `--phases` makes the bot specialize at
run-phase checkpoints instead of taking the all-rounder, among the options
its research and era have unlocked.

## Target: an active 6–8 h game (v6: a real garage, full rooms)

Not an idle clicker: a Game Dev Tycoon-style game you play. A full
playthrough, garage to the final rival, is 6–8 hours of active play (aim
~7h10), with a meaningful choice every 30–90 s and never two idle minutes.
Each room is where you spend its whole era: a room opens with its era, you
fill it, and the next era unlocks a few minutes after you run out of space.

| Milestone | Target | Active bot, seed 12345 | 7 seeds (median) |
|---|---|---|---|
| Startup | ~50 min | 0:50 | 0:49–0:51 (0:50) |
| Small lab | ~1h | 1:02 | 1:01–1:04 (1:02) |
| Medium lab | ~1h50 | 1:50 | 1:50–1:54 (1:51) |
| Big lab | ~3h20 | 3:22 | 3:19–3:28 (3:22) |
| Frontier | ~4h20 | 4:23 | 4:17–4:28 (4:21) |
| Final rival | 7–7h30 | **7:08** | 6:55–7:18 (7:07) |

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
with 2.5–12 h breaks) still works: final rival at 31h40 wall-clock after
5h30 of play over 7 sessions (vs 7h08 for the active player). The breaks
shave about 1h40 off the play because of the 2 h of 10%-rate earnings
each time, and the run that finishes while you're away.

**Fresh games get no catch-up.** A save from an older, incompatible version
loads as a fresh game (`GameState.startedFromOldSave`) and skips offline
progress (it used to hand a brand-new garage up to 2 h of earnings, $25k,
enough for four V100s in the first seconds). Reset game also puts the
playtest speed back to 1×. A real 2 h absence from a fresh garage now banks
about $2.3k (garage revenue is ×0.1).

## The bot (an "engaged human")

- Looks at the game every 4 s (`PlaySchedule.active.reactionSeconds`). It
  only uses choices the UI offers: 50% or 75% of the training cluster, and
  the era's three run lengths (`EraInfo.runDurations`). It answers a run-phase
  checkpoint at once (the default all-rounder pick, or specialized with
  `specializePhases`, only from the unlocked options).
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
- **Moving.** The next room is a candidate once its era is reached (then
  only its price stands in the way, `Game.canMoveSoon`); it's essential when
  the room is full. After a move it re-lays its tiles on the new plan (moves
  are free): best GPUs first, old-room coolers and anything without a spot
  are sold. It buys the parts of the newest room whose parts are unlocked.
- **Compute gates.** While the next era's gate is a compute target (the
  Startup), every GPU's peak TFLOPS toward it counts in the bot's score
  (`Bot.computeGoalWeight`), so it fills the garage and swaps old cards out
  even when users don't need the capacity.
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
| `startup` | Startup | 2018–19 | own 1.05 PFLOPS of GPUs (a full garage) | Server closet 7×7 |
| `smallLab` | Small lab | 2020–22 | rating 990 | Colocation cage 10×10 |
| `mediumLab` | Medium lab | 2023 | rating 1130 (just past GPT-ish-3) | Datacenter hall 14×14 |
| `bigLab` | Big lab | 2023–25 | rating 1260 (ChatGPT-ish) | Datacenter campus 18×18 |
| `globalLab` | Frontier lab | 2025–26 | rating 1490 (just under Grokk 3) | Gigawatt site 22×22 |

`Game.nextEraGoal` exposes the next gate (metric, target, progress) for the
UI (the always-visible goal strip, and `Game.eraLockReason`: "Unlocks in
Small lab: reach rating 990 (you're at 988)."). The gates unlock an era's
room, parts, power / network / cooling tiers and research. Moving needs the
room's era and then its price (`Game.roomBlockReason`: "Opens in the
Startup era: own 1.05 PFLOPS of GPUs (you have 640 TFLOPS)." before "Costs
$15.0k. You have $3.2k."). Eras unlock one per tick, and offline too. Rivals
carry an `era` and can't be beaten before you reach it, so an overpowered
model unlocks its rivals one era at a time.

The Startup gate is hardware, not users: the peak TFLOPS of the GPUs you
own (`startupUnlockTflops`, heat doesn't matter). It needs about 11 of the
garage's 16 cells in mostly V100s, so the garage is full before it opens,
and a viral spike (users pile up to 1.5× capacity) can't skip it.

**No deadlocks.** Every gate is reachable with the era's own power cap, rooms
and longest run (the bot's choice; v5 didn't recheck the middle run), as long
as you cool your GPUs: the `naive` layout (never a cooler) now stalls in the
Small lab, because it can no longer escape the heat by moving ahead of the
era. The rating gates sit below what that era's cluster and
data budget can reach: Small lab tops out near 1120–1165 depending on the books
corpus, Medium lab ~1340 with licensed data, Big lab ~1560. None of them needs
users or revenue, so a player who ships open weights (ARPU ×0.6) or never rents
cloud GPUs can't get stuck. Earlier drafts had a 1M-users Medium gate that only
cloud overflow could reach at the colo power cap, and a $10B ARR Frontier gate
the 150 MW Big lab couldn't reach; the playthrough tests guard against that.

### What each era unlocks

### Parents' garage (`garage`, 2017)
- room: Garage 4×4 ($0)
- power: Garage outlet 1.8 kW ($0), Upgraded electrical panel 10.0 kW ($3k)
- gpu: RTX 2060 (used) ($900, +25%/tile), RTX 4090 ($2k, +15%/tile), Used V100 ($3k, +10%/tile, needs mixed_precision)
- cooling: Box fan ($150), Window AC ($350)
- network: Copper Ethernet 1G, feeds 4 ($0); 10G copper, feeds 32 ($2k)
- research: Mixed precision (FP16) $800, Request batching $1.2k, KV cache $2.5k, LoRA fine-tuning $2k, Filtered web crawl $3k
- stunts: Quiet release, Cryptic tweet, Live demo
- runs: 30s / 1m / 2m at 5000× (1.7 d / 3.5 d / 6.9 d of compute)
- rivals: Tiny-Transformer (765), GPT-ish-1 (796)
### Startup (`startup`, 2018–19)
- room: Server closet 7×7 ($15k)
- power: 3-phase service 65.0 kW ($19k)
- gpu: DGX A100 (8× A100) ($58k, +10%/tile)
- cooling: Precision AC (CRAC) ($1.3k)
- network: 100G fiber, feeds 256 ($15k)
- research: Custom CUDA kernels $250k, Quantization (INT8) $310k, Public code dataset $410k, Deduplication & quality filters $610k, Data mixture optimisation $450k, Instruction tuning $410k
- stunts: 
- runs: 1m / 2m / 3m at 7200× (5.0 d / 10 d / 15 d of compute)
- rivals: BURT-Large (888), GPT-ish-2 (950)
### Small lab (`smallLab`, 2020–22)
- room: Colocation cage 10×10 ($800k)
- power: Leased colo circuits 500.0 kW ($140k)
- gpu: HGX H100 (8× H100) ($180k, +16%/tile)
- cooling: Rear-door heat exchanger ($2.8k)
- network: InfiniBand 400G, feeds 4096 ($230k)
- research: FlashAttention $2M, High-speed interconnect $420k, Liquid cooling $2M, Books & papers corpus $3M, Compute-optimal scaling $3M, FSDP / ZeRO sharding $4M
- stunts: Mystery model on the arena
- runs: 1m / 3m / 5m at 2100× (1.5 d / 4.4 d / 7.3 d of compute)
- rivals: Meenie (1085), GPT-ish-3 (1120)
### Medium lab (`mediumLab`, 2023)
- room: Datacenter hall 14×14 ($1.5M)
- power: Dedicated medium-voltage feed 2.0 MW ($488k), On-site substation 3.6 MW ($575k)
- gpu: H100 rack ($700k, +25%/tile), GB200 NVL72 ($3.4M, +25%/tile, needs liquid_cooling)
- cooling: Chiller unit ($9k), Direct liquid-cooling loop ($13k)
- network: InfiniBand spine, feeds 32768 ($1.8M)
- central cooling: Central chilled water −80/tile ($2M)
- research: Mixture of Experts $20M, RLHF $22M, 3D parallelism $34M, Distillation $40M, Paged KV cache $34M, Licensed data deals $2.2M
- design research: Grouped-query attention $16M, Sliding-window attention $30M, RoPE position interpolation $14M, Router load balancing $24M, Inference-aware scaling $11M, Pre-training mix in RL (PPO-ptx) $22M, Long-document data $24M, 4-bit weights (GPTQ/AWQ) $27M
- stunts: 
- runs: 1m / 3m / 5m at 4500× (3.1 d / 9.4 d / 16 d of compute)
- rivals: Mixtrawl 8x7B (1210), ChatGPT-ish (1260)
### Big lab (`bigLab`, 2023–25)
- room: Datacenter campus 18×18 ($7.5M)
- power: Power plant deal (PPA) 90.0 MW ($7.5M)
- gpu: B200 SuperPOD ($12M, +12%/tile, needs liquid_cooling), Vera Rubin NVL144 ($1.2M, +12%/tile, needs liquid_cooling), Rubin SuperPOD ($16M, +12%/tile, needs liquid_cooling)
- cooling: Cooling tower ($50k)
- network: NVLink fabric, feeds 131072 ($7M)
- central cooling: Evaporative cooling towers −250/tile ($6M); Facility liquid loop −450/tile ($11M)
- research: FP8 training $150M, Speculative decoding $1.1B, Synthetic data $910M, AI feedback (RLAIF) $480M, Long context (ring attention) $730M, Reasoning (RL on chain of thought) $1.2B
- design research: YaRN context extension $290M, Fine-grained experts $880M, Hybrid state-space layers $580M, Direct Preference Optimization $250M, Bigger reward models $440M
- stunts: Livestreamed keynote
- runs: 1m / 3m / 5m at 13000× (9.0 d / 27 d / 45 d of compute)
- rivals: GPT-ish-4 (1339), Claudette 3.5 Sonata (1373), DeepSleep-R1 (1378), Claudette 3.7 Sonata (1455), o-three (1463), Grokk 3 (1503), GPT-ish-4.5 (1506)
### Frontier lab (`globalLab`, 2025–26)
- room: Gigawatt site 22×22 ($20M)
- power: Gigawatt grid interconnect 1.0 GW ($74M), Restarted nuclear plant 2.0 GW ($147M), Multi-site cluster 4.0 GW ($290M)
- gpu: Rubin building ($36M, +3%/tile, needs liquid_cooling)
- cooling: Closed-loop dry coolers ($80k)
- network: Optical fabric, feeds 4194304 ($61M)
- central cooling: Dry-cooler farm −550/tile ($13M)
- research: Multi-token prediction $1.8B, Expert data (PhD annotators) $2.1B, Test-time compute scaling $6.6B, Agentic RL environments $11B, Prefill/decode disaggregation $3B
- design research: Adaptive thinking budgets $3.6B
- stunts: Big-game TV ad
- runs: 1m / 3m / 5m at 500× (0.3 d / 1.0 d / 1.7 d of compute)
- rivals: GPT-ish-5 (1512), Gemeni 3 Pro (1571), Amused Spark (1580), GPT-ish-5.5 "Tater" (1596), Claudette Parable 5 (1618), Gemeni 4 Xenon (1622), GPT-ish-6 Astral (1626)

The big parody labs (ClosedAI, Anthropomorphic) fight it out in Big lab with
DeepSleep and yAI. The frontier fight (GPT-ish-5 → GPT-ish-6 Astral, with
Gogol DeepThought's Gemeni and MetaMind's Amused Spark) is in the Frontier lab.
The rival ratings are unchanged: they come from real FLOPs through the game's
own formula.

## Pacing: active schedule (balanced bot, template layout)

v5 (a 4-minute garage, rooms bought ahead of their era) vs v6, seed 12345:

| Milestone | v5 active | v6 active | v6 casual (wall) |
|---|---|---|---|
| Startup | 0h04 | 0h50 | 0h50 |
| Small lab | 0h18 | 1h02 | 3h30 |
| Medium lab | 1h43 | 1h50 | 7h15 |
| Big lab | 3h51 | 3h22 | 10h48 |
| Frontier lab | 5h10 | 4h22 | 24h00 |
| Final rival | **6h38** | **7h07** | 31h40 |
| Longest idle | 1.7 min | 1.7 min | 1.7 min |

v6 active, seed 12345: 1,162 decisions to the final rival (one every 22 s),
92 releases, 46/48 upgrades, 51 viral spikes; at the final rival 4.2B
users, $53B ARR, 3.8M H100e, 3.1 GW. No stretch reaches 2 min; 62 pass 90 s
(102 min in all, mostly a 5-min run between checkpoints while saving). The
longest wait between two rival wins is 64 min (v5: 134 min).

Seeds (time to unlock, h:mm:ss; `--seeds=...`):

```
phases off (default bot)
seed  |  Startup | Small lab | Medium lab |  Big lab | Frontier | final    | idle max
12345 |  0:50:29 |  1:02:29 |  1:50:01 |  3:22:25 |  4:22:45 |  7:07:33 | 1.7m
1     |  0:50:45 |  1:02:37 |  1:52:37 |  3:21:33 |  4:19:21 |  7:16:05 | 1.7m
777   |  0:50:45 |  1:02:17 |  1:51:13 |  3:19:01 |  4:18:29 |  6:55:29 | 1.7m
2026  |  0:50:33 |  1:04:09 |  1:53:57 |  3:27:45 |  4:22:09 |  7:18:29 | 1.7m
4242  |  0:49:29 |  1:01:25 |  1:49:41 |  3:22:53 |  4:16:49 |  7:07:01 | 1.7m
99    |  0:50:17 |  1:01:45 |  1:51:41 |  3:20:21 |  4:21:01 |  7:00:45 | 1.7m
31337 |  0:49:49 |  1:01:53 |  1:49:41 |  3:23:25 |  4:27:57 |  7:07:57 | 1.7m
phases on (Bot(specializePhases: true))
12345 |  0:50:21 |  1:03:37 |  1:57:29 |  3:35:17 |  4:36:13 |  7:23:05 | 1.7m
1     |  0:51:41 |  1:02:45 |  1:53:25 |  3:32:45 |  4:38:25 |  7:38:41 | 1.7m
777   |  0:51:45 |  1:05:05 |  1:55:17 |  3:33:09 |  4:33:21 |  7:25:13 | 1.7m
2026  |  0:51:33 |  1:05:13 |  1:54:49 |  3:33:57 |  4:30:49 |  7:20:21 | 1.7m
4242  |  0:49:41 |  1:03:05 |  1:52:37 |  3:31:21 |  4:29:33 |  7:09:49 | 1.7m
99    |  0:49:57 |  1:03:37 |  1:53:57 |  3:27:41 |  4:30:37 |  7:24:33 | 1.7m
31337 |  0:49:45 |  1:02:21 |  1:52:21 |  3:31:09 |  4:32:05 |  7:19:05 | 1.7m
```

- Every seed finishes in 6h55–7h18 (phases on: 7h09–7h38) and none has a
  2-minute idle stretch. The Startup no longer depends on a lucky viral
  spike (v5: 2:28–4:06), since its gate is hardware.

### Room fill when the way out opens

Each room at the moment the next room's era unlocks (seed 12345; the
gigasite at the final rival). Power is of the most the building takes in
that era; "wall" is how long it had had no empty cell or no power for
another GPU (`RoomFill`).

| Room | Era in room | GPU tiles | Cells | Power | At the wall |
|---|---|---|---|---|---|
| Garage | 0:00–0:50 | 12 | 16/16 | 9.0 / 10 kW (90%) | 4.0 min |
| Server closet | 0:51–1:02 | 20 | 24/49 | 62 / 65 kW (96%) | 3.0 min |
| Colocation cage | 1:05–1:50 | 73 | 100/100 | 443 / 500 kW (89%) | 2.3 min |
| Datacenter hall | 1:52–3:22 | 132 | 156/196 | 3.6 / 3.6 MW (100%) | 0.3 min |
| Datacenter campus | 3:27–4:22 | 228 | 300/324 | 90 / 90 MW (100%) | none at exit (first hit 10 min before) |
| Gigawatt site | 4:24–7:07 | 350 | 411/484 | 3.1 / 4 GW (77%) | (last room) |

Over the 7 seeds: garage 16/16 cells, 90% power, 3.8–4.1 min at the wall;
closet 87–96%, 0–5.4 min; colo 100/100 cells (86–92% power), 0.6–9.1 min;
hall 96–100%, 0–13.6 min (one seed; the rest ≤4); campus 85–100%, not at
the wall at exit (it touches 90 MW ~10 min before on most seeds); gigasite
~77% at the final rival. v5 sat in a full colo (504 GPUs, 496/500 kW) from
0:48 to 1:43, and left the garage with 5–9 GPUs.

### The garage (v6)

About 50 minutes, every one of them with something to do (no idle stretch
over 90 s). Seed 12345:

- 0–20 min: the starting used RTX 2060, then three more (+25% each: the
  used market dries up). Mixed precision (FP16) at 2 min unlocks the V100
  for later. First box fan at ~10 min: past three cards the garage's free
  cooling (16) can't keep a 2060 (heat 6) cool. The outlet (1.8 kW) is full
  at ~16 min; the panel (10 kW) follows.
- 20–34 min: the first RTX 4090s and window ACs; Tiny-Transformer falls at
  25 min.
- 34–47 min: Used V100s ($3k, +10% each) once income passes ~$20/s;
  GPT-ish-1 at 42 min; batching, KV cache, LoRA and the web crawl along the
  way. All 16 cells are used at ~47 min.
- 47–50 min: old cards swapped for V100s; 1.05 PFLOPS opens the Startup.
- 22–24 releases (open weights) and two rivals; the first viral spikes.

Levers: garage revenue per user ×0.1 (`garageArpuMult`, a hobby project on
tips until you incorporate), the 2060 / 4090 / V100 supply crunch (25 / 15 /
10% per card), the V100's mixed-precision requirement and the 1.05 PFLOPS
gate. The garage keeps its 5000× time compression; the community bonus
for open releases now stops at 5 stacks (`openSourceCommunityMaxStacks`),
otherwise 40-odd garage releases made training ×7 more efficient and
skipped half the Small lab.

- Sensitive spots: the hall closes when RLHF ($22M) lands in a hall that's
  nearly full. The gate that keeps the hall filling is its size: the
  on-site substation is 3.6 MW, the most a hall bought at the racks' +25%
  crunch reaches by the time RLHF is affordable (at 4 MW the bot bought
  RLHF with the hall ~60% full; at 3 MW it waited 13–17 min). The colo's
  wall is the last Small-lab research (books, FSDP).

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
sess | wall start | sim start | len | era at start | ran away | 1st act | decisions (buy/rel) | idle max | rivals | eras
   0 |       0h00 |      0h00 |  60 | Parents' garage | -        |   0s   |  236 (37/29)        |   0.7m |      4 | Startup
   1 |       3h30 |      3h00 |  45 | Startup      | yes      |   0s   |  160 (106/8)        |   1.7m |      2 | Small lab
   2 |       7h15 |      5h45 |  30 | Small lab    | yes      |   0s   |   87 (44/10)        |   1.0m |      0 | Medium lab
   3 |      10h45 |      8h15 |  60 | Medium lab   | yes      |   0s   |  309 (224/14)       |   1.0m |      7 | Big lab
   4 |      24h00 |     11h15 |  60 | Big lab      | yes      |   0s   |  132 (54/8)         |   1.0m |      3 | Frontier lab
   5 |      27h30 |     14h15 |  45 | Frontier lab | yes      |   0s   |  118 (64/4)         |   1.0m |      3 |
   6 |      31h15 |     17h00 |  30 | Frontier lab | yes      |   0s   |   75 (43/2)         |   1.0m |      3 |
```

Final rival at 31h40 wall-clock, 5h30 of play in 7 sessions. The casual
schedule's numbers are no longer targets; the test only checks that it
finishes, that most of the game (60%+ of the active run) is still
played, and the idle limit.

## Strategies and placement

```
active, 15h00 cap
strategy / layout        | Startup      | Small lab    | Medium lab   | Big lab      | Frontier lab | final  | rivals
balanced / template     |  0h50        |  1h02        |  1h50        |  3h22        |  4h22        |  7h07 | 22/22
hardwareOnly / template |  0h56        |  1h20        |    —         |    —         |    —         |    —   |  5/22
noUpgrades / template   |    —         |    —         |    —         |    —         |    —         |    —   |  2/22
softwareFirst / template |  0h49        |  1h08        |  2h07        |  3h47        |  5h05        |  7h34 | 22/22
balanced / naive        |  1h08        |  1h38        |    —         |    —         |    —         |    —   |  5/22
balanced / random       |  0h57        |  1h15        |  2h08        |  3h41        |  4h45        |  7h18 | 22/22

casual, 72h00 cap
balanced / template     |  0h50        |  3h30        |  7h15        | 10h48        | 24h00        | 31h40 | 22/22
hardwareOnly / template |  0h56        |  3h35        |    —         |    —         |    —         |    —   |  5/22
noUpgrades / template   |    —         |    —         |    —         |    —         |    —         |    —   |  2/22
softwareFirst / template |  0h50        |  3h30        |  7h20        | 10h55        | 24h04        | 31h28 | 22/22
balanced / naive        |  3h30        |  3h57        |    —         |    —         |    —         |    —   |  5/22
balanced / random       |  0h50        |  3h30        |  7h20        |  7h40        | 24h00        | 31h33 | 22/22
```

- **random** placement throttles the rooms (the heat puzzle): every era
  5–15 min late, the final rival ~11 min later in active play (v5: ~1 h;
  the garage's compute gate counts peak TFLOPS, so heat no longer delays
  the Startup). **naive** (no coolers at all) never reaches the Medium lab:
  the colo can't get to rating 1130 throttled, and moves wait for their era,
  so it can't outrun the heat any more.
- **hardware-only** stalls by the Small lab; **no-upgrades** never leaves
  the garage (no mixed precision means no V100s, and twelve RTX 4090s are
  only 0.96 PFLOPS); **software-first** finishes ~25 min later.
- **Bad model design** (huge under-trained base model, web only, 2k, no
  post-training) takes 4 h to fill the garage (its demand, hence income, is
  too low without hype) and stops at rating ~970 in the Startup
  (`playthrough_test.dart`). A player can change the design at any run.

## Why the numbers are what they are

**A real garage and full rooms (v6).** Playtest: "I can afford the server
closet within 3 minutes and never bought a third GPU; I should fill the
space and feel I need more." v5 let you buy any room with money alone, so
the bot left the garage at 4 min with 9 GPUs, the closet early, and then sat
55 min in a full colo waiting for $10–36M of Small-lab research. v6:

- **Rooms open with their era** (`Game.roomBlockReason`), then cost money.
- **The garage (~50 min).** Revenue per user ×0.1 in the garage era
  (`garageArpuMult`); you start on a used RTX 2060 (was an RTX 4090);
  supply crunch 25 / 15 / 10% per 2060 / 4090 / V100; the V100 needs mixed
  precision (its tensor cores are FP16); the panel is 10 kW (was 8, so a
  V100 garage with window ACs fits); the Startup gate is 1.05 PFLOPS of
  owned GPUs (was 3k users). Open-release community bonus capped at 5
  stacks.
- **Closet.** 3-phase service 65 kW (was 50); Startup research ×0.7, so it
  lands while the closet fills; DGX A100s +10% per server (was 5%).
- **Colo plateau gone.** Small-lab research ×0.1–0.25 (FlashAttention $2M,
  liquid cooling $2M, compute-optimal scaling $3M, books $3M, FSDP $4M):
  it's bought while the colo fills, so the Medium lab opens 0–9 min after
  the colo is full instead of 55. HGX H100s +16% per server (was 12%).
- **Hall.** The on-site substation is 3.6 MW (was 20) and the Medium lab's
  time compression 4500 (was 7500), so the Big-lab gate needs the full
  hall; racks +25% each (was 10%) so filling it takes most of the era;
  Medium research ×1.5 with RLHF at $22M, the last step before the gate.
- **Campus.** The PPA is 90 MW (was 300), which the campus fills by the
  Frontier; Big-lab research ×1.8 (synthetic data $910M).
- **Frontier.** Time compression 500 (was 1200): the gigasite does more of
  the last rivals' work, which puts the 45 extra garage minutes back
  without a plateau.

**The next tier is more bang for the buck, but hard to get (v6).** Every
newer tier delivers more per dollar at list price than the one before it,
in every category, with no exceptions (`content_test.dart` enforces it):

| Category | Value | Tiers, oldest → newest (v6) |
|---|---|---|
| GPUs | TFLOPS per $k | 2060 33 → 4090 40 → V100 42 → DGX A100 43 → HGX H100 44 → H100 rack 45 → GB200 48 → B200 pod 197 → Vera Rubin 215 → Rubin pod 219 → Rubin building 796 |
| Coolers | cooling per $k | fan 27 → window AC 29 → CRAC 31 → rear door 32 → chiller 33 → liquid loop 35 → tower 36 → dry coolers 38 |
| Network | GPUs fed per $k | 10G 16 → fiber 17 → IB 400G 18 → IB spine 18.2 → NVLink 18.7 → optical 68 |
| Central cooling | per-tile cooling per $M | chilled water 40 → towers 42 → liquid loop 43 → dry coolers 44 |
| Power | kW per $k | panel 3.3 → 3-phase 3.4 → colo 3.6 → MV feed 4.1 → substation 6.3 → PPA 12 → GW 13.5 → nuclear 13.6 → multi-site 13.8 |

v5 broke this in places: the hall racks (doubled in the first v6 draft to
slow the hall), almost every cooler (a CRAC was $13.8k for 40 cooling, a
tower $1.2M), fiber and NVLink, the late central-cooling plants, and the
3-phase / nuclear / multi-site power tiers. What makes a new tier hard to
get is a gate, never worse value:

- **Era** (every tier), **research** (V100: mixed precision; rear door,
  liquid loop, GB200 and every later GPU: liquid cooling; InfiniBand:
  high-speed interconnect; NVLink and optical: 3D parallelism) and the
  **power tier** a tile needs (`minPowerTier`).
- **A steeper supply crunch** per unit owned (`priceGrowth`): 2060 25%,
  4090 15%, V100 10%, DGX A100 10%, HGX H100 16%, hall racks 25%, Big-lab
  pods and racks 12%, Rubin buildings 3%; the cap is ×4 list. The old tier
  stays the one you can afford now; the new one is what you save for.
- **A big upfront price**: the late power tiers ($7.5M PPA, $74M gigawatt,
  $147M nuclear, $290M multi-site) are saved for, but each still buys more
  kW per dollar than the last.
- **The building**: each room's electrical service caps the power tier
  (and so the GPUs) it can take.

Coolers are now cheap next to their era's income (a cooling tower is $50k);
what limits them is their power draw (a tower burns 200 kW) and the cells
they take from GPUs.

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
  ×0.05. (In v5 cheaper rooms let the bot skip the heat puzzle by moving
  early; v6 moves wait for the era.)
- Research is the pacing gate: an era's research costs about what you earn
  in 1–3 min at the point it should be bought, so it arrives as income grows,
  not after a long save. Startup ×1.5, Small lab ×3 (flash attention ×4, data
  mixture ×0.43, high-speed interconnect ×0.1: it gates InfiniBand, without
  which runs scale at 60%), Medium ×0.18, Big ×0.27, Frontier ×0.3 (design
  research in model_design.dart scales with its era). v6 rescales Startup,
  Small, Medium and Big research (see "A real garage and full rooms").
- GPU tiles keep the "newer beats older per $ and per kW" chain (v6:
  every category, see above): A100 servers
  ×1.15, H100 servers ×1.2, Medium racks ×0.8, Big-lab pods and racks ×0.3
  with a 12%/tile supply crunch (was 9%: cheap first tiles at era entry, ×4
  later), Rubin buildings ×0.12.
- Granularity: Vera Rubin racks are also sold for the campus and Rubin
  SuperPODs for the gigasite, so each era's entry has a tile you can afford.

**Time compression per era.** Runs use their era's `EraInfo.computeTimeScale`,
fixed when the run starts (saved as `TrainingRun.timeScale`): 5000 in the
Garage, 7200, 2100, 4500, 13000 and 500 at the Frontier (v6). The longest run of
each era is 4 days to 6 weeks of compute, so a bigger cluster, not a longer
wait, makes a better model. It's no longer monotonic: it is also the knob
for how much hardware each era's rating gate needs (Small lab 2400 makes the
colo's power cap meet the 1130 gate; Medium lab 4500 makes the full 3.6 MW
hall meet the 1260 gate; Big lab 13000 keeps the campus era from
crawling).

**GPU supply crunch.** Each GPU tile of a type you already own makes the next
one pricier (`TileDef.priceGrowth`, 3–12% compounding, capped at
`maxSupplyPremium` = ×4 list; selling refunds half of list). List prices keep
the "newer GPU beats older per $ and per kW" chain. Every new generation
arrives at list price, so an era unlock feels like relief. The crunch stretches
each era without lumps: there's always a next GPU to buy, just pricier.

**Power tiers** cost ~1 min of revenue at the moment the previous cap fills
(v4: ~10 min, sized for offline lumps). **Research is the pacing gate** (see
"Active pacing"): Startup $250–610k, Small lab $0.4–6M, Medium lab $2–40M,
Big lab $130M–1.1B, Frontier $1.8–10.5B (v6).

**Revenue and serving.** `revenue = users^0.7` (unchanged) and
`servingExponent` 0.3 → 0.33 (bigger models cost a little more to serve).
Users per MW must stay high enough for the rival user counts at each era's
power cap: at 0.42 the 150 MW Big lab served only ~80M users, and o-three's
400M was impossible. Quantization is ×2 (INT8/INT4); paged KV cache is ×2.4.

**Data budget.** 4B start × web crawl 50 × code 3 × books & papers 2 ×
licensed 16 × synthetic 4 ≈ 77T tokens, data-optimal up to ~1.7e27 FLOPs as
before, but spread so each era has its data step. Synthetic data used to be the
only big multiplier, and the Medium lab hit a hard data wall below its gate.

**Room space.** See "One place at a time" below. The colo tier is 500 kW, the
substation 3.6 MW and the plant tier 90 MW (v6: sized to what each era fills); the gigasite building is ~8k Rubin GPUs ($36M in
v5), so each era has enough floor and power for a steady stream of GPU
purchases.

**One place at a time (v4).** Capacity comes from one room, so each room
holds the previous one's layout plus about 1.5× more floor (4×4, 7×7,
10×10, 14×14, 18×18, 22×22). v6: a room opens with its era, then costs
money (v4–v5 moves cost only money, so the bot skipped ahead of the era and
left rooms half used). Room free cooling per cell went down
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
electrical service caps the tier you can buy there: garage 10 kW, closet
65 kW, colo 500 kW, hall 3.6 MW, campus 1 GW (90 MW in the Big lab: the
gigawatt tier is a Frontier part), gigasite 4 GW (v6). Moving buys no
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
