# Balance notes

How the economy is tuned, what the bot measures, and why the numbers are what
they are. Knobs live in `lib/sim/balance.dart` (constants) and
`lib/sim/content.dart` (eras, tiles, rooms, costs and effects). The grid rules
are in `docs/GRID.md` and `lib/sim/grid.dart`. The headless player is
`lib/sim/bot.dart`; the report tool is `tool/balance_sim.dart`.

```
dart run tool/balance_sim.dart [minutes=360] [--log-every=10] [--seed=12345] [--dt=1]
    [--strategy=balanced|hardware-only|software-first|no-upgrades]
    [--layout=template|naive|random] [--schedule=continuous|casual]
dart run tool/balance_sim.dart 6000 --schedule=casual      # 2-3 day casual player
dart run tool/balance_sim.dart 3600 --compare              # strategies, continuous
dart run tool/balance_sim.dart 5760 --compare --schedule=casual
```

With `--schedule=casual`, `minutes` is wall-clock time (sessions plus offline
gaps) and the tool prints the timeline in wall-clock and sim time plus a
per-session table.

## Target: a 2–3 day casual game

The target player plays 3–4 sessions of 30–60 min a day and the game runs
offline in between (offline progress is capped at 8 h, unchanged).
`PlaySchedule.casual` (bot.dart) models one 24 h day:

| session | length | then offline |
|---|---|---|
| 1 | 60 min | 2.5 h |
| 2 | 45 min | 3 h |
| 3 | 30 min | 3 h |
| 4 | 60 min | 12.25 h night (8 h of it simulated) |

Gaps go through the real offline path (`Game.applyOffline`): money, users and
the running training run continue, there are no viral spikes, and the 8 h
cap applies. Offline catch-up runs in coarse steps (`Game.offlineStep`: 1 s
for short absences, up to 10 s for 8 h, ≤ ~3k ticks). It depends only on the
absence length, so it's deterministic. A test checks it against 1 s steps
(within 1%).

## The bot (an "engaged human")

- Looks at the game every 3 s (tests use 6–12 s and dt 3–6; the numbers barely
  move). It only uses choices the UI offers: 50% or 75% of the training
  cluster, and the era's three run lengths (`EraInfo.runDurations`).
- **Run length.** Continuous play takes the middle option in the Garage and
  Startup and the longest from the Small lab on. In a session it takes the
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
  option, up to 12 per look. It saves for something better if it's close: up to
  4 min in the Garage, rising to 60 min at the Frontier, and never more than
  8 min inside a scheduled session (offline earnings pay for the big items).
  When growth is blocked (out of power, the best GPU doesn't fit the
  headroom, or out of floor space), the next power tier or room is
  "essential" and it saves for it however long it takes; so is a network
  tier once runs would scale below 70%.

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
and *middle* run length. The rating gates sit below what that era's cluster and
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
- runs: 1m / 3m / 10m at 1440× (1.0 d / 3.0 d / 10 d of compute)
- rivals: Tiny-Transformer (765), GPT-ish-1 (796)
### Startup (`startup`, 2018–19)
- room: Server closet 7×7 ($15k)
- power: Office with 3-phase power 50.0 kW ($60k)
- gpu: DGX A100 (8× A100) ($50k, +5%/tile)
- cooling: Precision AC (CRAC) ($12k)
- network: 100G fiber, feeds 256 ($40k)
- research: Custom CUDA kernels $234k, Quantization (INT8/INT4) $292.5k, Public code dataset $390k, Deduplication & quality filters $585k, Data mixture optimisation $1.5M, Instruction tuning $390k
- stunts: 
- runs: 3m / 10m / 30m at 1440× (3.0 d / 10 d / 30 d of compute)
- rivals: BURT-Large (888), GPT-ish-2 (950)
### Small lab (`smallLab`, 2020–22)
- room: Colocation cage 10×10 ($2M)
- power: Colocation cage 500.0 kW ($1M)
- gpu: HGX H100 (8× H100) ($150k, +12%/tile)
- cooling: Rear-door heat exchanger ($40k)
- network: InfiniBand 400G, feeds 4096 ($1.5M)
- research: FlashAttention $2.5M, High-speed interconnect $4.2M, Liquid cooling $6.7M, Books & papers corpus $12M, Compute-optimal scaling $8.3M, FSDP / ZeRO sharding $12M
- stunts: Mystery model on the arena
- runs: 10m / 30m / 1h at 480× (3.3 d / 10 d / 20 d of compute)
- rivals: Meenie (1085), GPT-ish-3 (1120)
### Medium lab (`mediumLab`, 2023)
- room: Datacenter hall 14×14 ($3M)
- power: Datacenter hall 2.0 MW ($4M), Datacenter campus 20.0 MW ($7M)
- gpu: H100 rack ($580k, +10%/tile), GB200 NVL72 ($2.9M, +10%/tile)
- cooling: Chiller unit ($150k), Direct liquid-cooling loop ($250k)
- network: InfiniBand spine, feeds 32768 ($15M)
- central cooling: Central chilled water −80/tile ($3M)
- research: Mixture of Experts $75M, RLHF $100M, 3D parallelism $125M, Distillation $150M, Paged KV cache $125M, Licensed data deals $8M
- stunts: 
- runs: 30m / 1h / 3h at 180× (3.8 d / 7.5 d / 23 d of compute)
- rivals: Mixtrawl 8x7B (1210), ChatGPT-ish (1260)
### Big lab (`bigLab`, 2023–25)
- room: Datacenter campus 18×18 ($30M)
- power: Dedicated power plant deal 300.0 MW ($120M)
- gpu: B200 SuperPOD ($39M, +9%/tile), Vera Rubin NVL144 ($3.9M, +9%/tile), Rubin SuperPOD ($54.6M, +9%/tile)
- cooling: Cooling tower ($4M)
- network: NVLink fabric, feeds 131072 ($200M)
- central cooling: Evaporative cooling towers −250/tile ($40M); Facility liquid loop −450/tile ($150M)
- research: FP8 training $300M, Speculative decoding $2.3B, Synthetic data $3B, AI feedback (RLAIF) $1B, Long context (ring attention) $1.5B, Reasoning (RL on chain of thought) $2.5B
- stunts: Livestreamed keynote
- runs: 1h / 3h / 6h at 72× (3.0 d / 9.0 d / 18 d of compute)
- rivals: GPT-ish-4 (1339), Claudette 3.5 Sonata (1373), DeepSleep-R1 (1378), Claudette 3.7 Sonata (1455), o-three (1463), Grokk 3 (1503), GPT-ish-4.5 (1506)
### Frontier lab (`globalLab`, 2025–26)
- room: Gigawatt site 22×22 ($400M)
- power: Gigawatt campus 1.0 GW ($350M), Restarted nuclear plant 2.0 GW ($1B), Multi-site cluster 4.0 GW ($2B)
- gpu: Rubin building ($300M, +3%/tile)
- cooling: Closed-loop dry coolers ($9M)
- network: Optical fabric, feeds 4194304 ($1.5B)
- central cooling: Dry-cooler farm −550/tile ($800M)
- research: Multi-token prediction $6B, Expert data (PhD annotators) $7B, Test-time compute scaling $22B, Agentic RL environments $35B, Prefill/decode disaggregation $10B
- stunts: Big-game TV ad
- runs: 2h / 4h / 8h at 40× (3.3 d / 6.7 d / 13 d of compute)
- rivals: GPT-ish-5 (1512), Gemeni 3 Pro (1571), Amused Spark (1580), GPT-ish-5.5 "Tater" (1596), Claudette Parable 5 (1618), Gemeni 4 Xenon (1622), GPT-ish-6 Astral (1626)

The big parody labs (ClosedAI, Anthropomorphic) fight it out in Big lab with
DeepSleep and yAI. The frontier fight (GPT-ish-5 → GPT-ish-6 Astral, with
Gogol DeepThought's Gemeni and MetaMind's Amused Spark) is in the Frontier lab.
The rival ratings are unchanged: they come from real FLOPs through the game's
own formula.

## Pacing: casual schedule (balanced bot, template layout, seed 12345)

Since v4 (one place at a time, network and central cooling tiers, money-only
moves, bigger rooms).

| Milestone | Wall-clock | (sim) | Target |
|---|---|---|---|
| Startup | 0h12 | 0h12 | ~12 min |
| Small lab | 0h53 | 0h53 | ~1 h |
| Medium lab | 7h15 | 7h15 | ~7–14 h |
| Big lab | 24h00 | 19h45 | ~24–32 h |
| Frontier lab | 34h45 | 30h30 | ~35–50 h |
| Final rival (GPT-ish-6 Astral) | **55h15** | 46h45 | ~50–70 h |

Moves (money only, so about an era early): closet 0h11, colo and hall 3h30,
campus 7h15, gigasite 24h00. 11 sessions, 8h45 of active play. At the final
rival: 3.3B users, $39B ARR, 1.6M H100e, 1.3 GW.

```
sess | wall start | sim start | len | era at start | ran away | 1st act | decisions (buy/rel) | idle max | rivals | eras
   0 |       0h00 |      0h00 |  60 | Parents' garage | -        |   0s   |   45 (26/9)         |   5.4m |      4 | Startup, Small lab
   1 |       3h30 |      3h30 |  45 | Small lab    | yes      |   0s   |   67 (63/2)         |   6.7m |      2 | 
   2 |       7h15 |      7h15 |  30 | Small lab    | yes      |   0s   |   34 (32/1)         |   5.3m |      0 | Medium lab
   3 |      10h45 |     10h45 |  60 | Medium lab   | yes      |   0s   |   30 (28/1)         |   7.0m |      1 | 
   4 |      24h00 |     19h45 |  60 | Medium lab   | yes      |   0s   |   41 (39/1)         |   5.2m |      1 | Big lab
   5 |      27h30 |     23h15 |  45 | Big lab      | yes      |   0s   |   20 (18/1)         |  11.3m |      5 | 
   6 |      31h15 |     27h00 |  30 | Big lab      | yes      |   0s   |   15 (13/1)         |   7.0m |      0 | 
   7 |      34h45 |     30h30 |  60 | Big lab      | yes      |   0s   |   30 (28/1)         |   5.7m |      0 | Frontier lab
   8 |      48h00 |     39h30 |  60 | Frontier lab | yes      |   0s   |   71 (69/1)         |  11.1m |      5 | 
   9 |      51h30 |     43h00 |  45 | Frontier lab | yes      |   0s   |   10 (9/0)          |   6.9m |      0 | 
  10 |      55h15 |     46h45 |  30 | Frontier lab | yes      |   0s   |   11 (9/1)          |   0.0m |      4 |
```

- **Longest active stretch with nothing to do: 11.3 min** (session 5, Big
  lab, saving for research). Target ~10; every other session ≤ 11.1 min,
  median ~6.5 min.
- Seeds 1, 777, 2026 and 4242 give the same milestones (Startup 0h09–0h12,
  Small lab 0h49–0h56, final 55h15 for all five seeds); max idle 11.3–13.5
  min.
- Sensitive spot: the final rivals are a few rating points apart, so a
  change that costs ~2 rating points at the end of day 3's evening session
  pushes the finish to the next morning (72h). Re-check seeds after any
  late-game change.


## Pacing: continuous play (no gaps)

Startup 0h12, Small lab 0h53, Medium lab 3h03, Big lab 10h28, Frontier
33h27; 19/22 rivals by 46h09 and the last three around 58–62h (seed 12345,
1 s / 3 s; the test runs it coarser and checks < casual + 8 h). Continuous
play is now about as fast as casual: the frontier is data-limited and paced
by 8 h runs, and offline earns at full rate. That's deliberate for a casual
idle game (and it needs ~60 h of active play against ~9 h for the casual
player).


## Strategies and placement

```
continuous, 60h00 cap
strategy / layout        | Startup      | Small lab    | Medium lab   | Big lab      | Frontier lab | final  | rivals
balanced / template     |  0h12        |  0h53        |  3h03        | 10h28        | 33h27        |    —   | 19/22
hardwareOnly / template |  0h12        |    —         |    —         |    —         |    —         |    —   |  4/22
noUpgrades / template   |  1h51        |    —         |    —         |    —         |    —         |    —   |  2/22
softwareFirst / template |  0h11        |  1h25        |  4h47        | 12h12        | 35h11        |    —   | 19/22
balanced / naive        |  0h12        |  1h09        |  4h31        | 15h08        | 40h00        |    —   | 19/22
balanced / random       |  0h12        |  1h09        |  4h28        | 11h55        | 36h46        |    —   | 19/22

casual, 96h00 cap
strategy / layout        | Startup      | Small lab    | Medium lab   | Big lab      | Frontier lab | final  | rivals
balanced / template     |  0h12        |  0h53        |  7h15        | 24h00        | 34h45        | 55h15 | 22/22
hardwareOnly / template |  0h12        |  4h11        |    —         |    —         |    —         |    —   |  5/22
noUpgrades / template   |  7h16        |    —         |    —         |    —         |    —         |    —   |  2/22
softwareFirst / template |  0h11        |  3h40        | 10h45        | 24h00        | 48h00        | 58h45 | 22/22
balanced / naive        |  0h12        |  3h30        |  7h15        | 24h00        | 34h45        | 72h00 | 22/22
balanced / random       |  0h12        |  3h30        |  7h15        | 24h00        | 34h45        | 58h45 | 22/22
```

- **naive** (no coolers) throttles hard in the garage → colo (the heat
  puzzle): Small lab 2h40 late, final 72h (+17h).
- **random** scatters its coolers: Small lab 2h40 late, final 58h45 (+3h30).
  Central cooling from the Medium lab on makes late rooms about capacity, so
  bad placement mostly costs the early game. That's the intended design.
- **hardware-only** (no software/research beyond data and liquid cooling)
  never leaves the Small lab. **no-upgrades** stays in the Startup.
- **software-first** finishes too, a session later.


## Why the numbers are what they are

**Time compression per era.** `computeTimeScale` (1440: one real minute is
a day) stays the game calendar and sets ARR, and 2017 → 2026 is ~55 h of
play at that rate, which is also why a 2–3 day game fits the history.
Training runs instead use their era's `EraInfo.computeTimeScale`, fixed when
the run starts (saved as `TrainingRun.timeScale`): 1440 in the Garage and
Startup, 480, 180, 72 and 36 at the Frontier. Runs get longer (1 min in the
Garage, 8 h at the Frontier, so one finishes while you're away). The longest
run of each era is still 10–30 days of compute, so a bigger cluster, not a
longer wait, makes a better model, and late clusters are realistic (~0.5–1M
GPUs). With one scale, an 8 h run would equal a year of compute, and one gigasite
tile could train GPT-ish-6.

**GPU supply crunch.** Each GPU tile of a type you already own makes the next
one pricier (`TileDef.priceGrowth`, 3–12% compounding, capped at
`maxSupplyPremium` = ×4 list; selling refunds half of list). List prices keep
the "newer GPU beats older per $ and per kW" chain. Every new generation
arrives at list price, so an era unlock feels like relief. The crunch stretches
each era without lumps: there's always a next GPU to buy, just pricier.

**Power tiers cost ~10 min of revenue** at the moment the previous cap fills
(colo $1M … gigawatt $600M). A power-blocked session has nothing to do, so
those must never be long saves. **Research is the big sink** ($75–150M in Medium
lab, $1–3B in Big lab, $6–35B at the Frontier). It's bought on return from
offline earnings and never blocks GPU purchases.

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
the plant tier 300 MW; the gigasite building is ~8k Rubin GPUs at $300M, so
each era has enough floor and power for in-session GPU purchases between
offline lumps.

**One place at a time (v4).** Capacity comes from one room, so each room
holds the previous one's layout plus about 1.5× more floor (4×4, 7×7,
10×10, 14×14, 18×18, 22×22). Moves cost only money: rooms are priced so an
early move is a real choice (the closet's $15k is a garage-era purchase,
the gigasite's $400M a Big-lab one). Room free cooling per cell went down
(closet 2.5, colo 5, hall 18, campus 40, gigasite 70) so moving early doesn't
solve heat by itself; central cooling (80 / 250 / 450 / 550 heat per GPU
tile) covers the late rooms without making coolers worthless. Throttling is
`max(0.2, 1 − netHeat/heat)` (was 0.3 and 0.7×).

**Network as a tier (v4).** All GPUs in the room are one cluster. The tier
ladder (4 → 32 → 256 → 4k → 32k → 131k → 4M GPUs) is priced so each step is
bought when its era's cluster outgrows the previous one (copper 10G $1.5k in
the garage, InfiniBand spine $15M, NVLink $200M, optical $1.5B).

**Power tiers retuned for one room.** A move fills the old cap at once, so
tiers are cheaper relative to revenue: office 50 kW (was 40), campus $7M,
power plant $120M, gigawatt $350M, nuclear $1B, multi-site $2B. Also books
corpus $12M, test-time compute $22B, expert data +23 rating, Frontier time
compression 40 (8 h = 13 days of compute), Medium-lab gate 1130 and
Frontier gate 1490.

**Unchanged from v2:** the grid rules, demand/hype/viral numbers, rival
ratings and users, hype cap 8, overload settle, cloud rental cost, the 8 h
offline cap.
