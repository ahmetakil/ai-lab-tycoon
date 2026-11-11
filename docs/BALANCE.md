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
  each available upgrade, the next build step in each of its three newest
  rooms, a switch upgrade, a cooler upgrade, and swapping a room's weakest GPU
  for its best one (when the room is full, or per kW when power is the limit).
  Also the next room and the next power tier. It buys the best affordable
  option, up to 12 per look. It saves for something better if it's close: up to
  4 min in the Garage, rising to 60 min at the Frontier, and never more than
  8 min inside a scheduled session (offline earnings pay for the big items).
  When growth is blocked (out of power, or out of floor space), the next power
  tier or room is "essential" and it saves for it however long it takes.

### Placement (`--layout`)

- **template** (default): each room gets a fixed plan, picked from a few
  repeating patterns: a line of switches with GPUs on both sides and coolers
  between the GPU pairs (G S G C), straight or staggered, plus a switch
  backbone across big rooms so every spine is one cluster. GPUs are filled in
  BFS order so each new GPU's switch chain links to the existing network
  (one cluster per room, checked in the tests). A cooler goes in only if the
  new GPU would run hot: the cheapest cooler that cools all its neighbours,
  else the strongest that fits the power. The switch is the cheapest one that
  can feed the room's whole planned cluster; when a cluster outgrows its
  switches anyway, it replaces the slow ones. Old rooms keep serving. Garage
  plan: 8 GPUs, 4 switches, 4 coolers in a 4×4.
- **naive**: GPUs only, on random empty cells. No switches, no coolers.
- **random**: buys about one switch and one cooler per two GPUs, but drops
  every tile on a random empty cell.

## Eras, gates and unlocks

| era (enum) | label | years | gate to enter | room |
|---|---|---|---|---|
| `garage` | Parents' garage | 2017 | start | Garage 4×4 |
| `startup` | Startup | 2018–19 | 3k users | Server closet 6×6 |
| `smallLab` | Small lab | 2020–22 | rating 1000 | Colocation cage 8×8 |
| `mediumLab` | Medium lab | 2023 | rating 1120 (GPT-ish-3) | Datacenter hall 12×12 |
| `bigLab` | Big lab | 2023–25 | rating 1260 (ChatGPT-ish) | Datacenter campus 12×12 |
| `globalLab` | Frontier lab | 2025–26 | rating 1500 (Grokk 3 class) | Gigawatt site 12×12 |

`Game.nextEraGoal` exposes the next gate (metric, target, progress) for the
UI. Eras unlock one per tick, and offline too (a users gate can fill while
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
- network: Home router ($150), 5 Gbit switch ($600), 10 GbE switch ($3k)
- research: Mixed precision (FP16) $800, Request batching $1k, KV cache $3k, LoRA fine-tuning $2k, Filtered web crawl $3k
- stunts: Quiet release, Cryptic tweet, Live demo
- runs: 1m / 3m / 10m at 1440× (1.0 d / 3.0 d / 10 d of compute)
- rivals: Tiny-Transformer (765), GPT-ish-1 (796)
### Startup (`startup`, 2018–19)
- room: Server closet 6×6 ($15k)
- power: Office with 3-phase power 40.0 kW ($60k)
- gpu: DGX A100 (8× A100) ($50k, +5%/tile)
- cooling: Precision AC (CRAC) ($12k)
- network: 100G Ethernet ($20k)
- research: Custom CUDA kernels $234k, Quantization (INT8/INT4) $293k, Public code dataset $390k, Deduplication & quality filters $585k, Data mixture optimisation $1.5M, Instruction tuning $390k
- stunts: 
- runs: 3m / 10m / 30m at 1440× (3.0 d / 10 d / 30 d of compute)
- rivals: BURT-Large (888), GPT-ish-2 (950)
### Small lab (`smallLab`, 2020–22)
- room: Colocation cage 8×8 ($2.0M)
- power: Colocation cage 500.0 kW ($1.0M)
- gpu: HGX H100 (8× H100) ($150k, +12%/tile)
- cooling: Rear-door heat exchanger ($40k)
- network: InfiniBand NDR 400G ($60k)
- research: FlashAttention $2.5M, High-speed interconnect $4.2M, Liquid cooling $6.7M, Books & papers corpus $20M, Compute-optimal scaling $8.3M, FSDP / ZeRO sharding $12M
- stunts: Mystery model on the arena
- runs: 10m / 30m / 1h at 480× (3.3 d / 10 d / 20 d of compute)
- rivals: Meenie (1085), GPT-ish-3 (1120)
### Medium lab (`mediumLab`, 2023)
- room: Datacenter hall 12×12 ($3.0M)
- power: Datacenter hall 2.0 MW ($4.0M), Datacenter campus 20.0 MW ($12M)
- gpu: H100 rack ($580k, +10%/tile), GB200 NVL72 ($2.9M, +10%/tile)
- cooling: Chiller plant ($150k), Direct liquid-cooling loop ($250k)
- network: InfiniBand spine ($1.0M)
- research: Mixture of Experts $75M, RLHF $100M, 3D parallelism $125M, Distillation $150M, Paged KV cache $125M, Licensed data deals $8.0M
- stunts: 
- runs: 30m / 1h / 3h at 180× (3.8 d / 7.5 d / 23 d of compute)
- rivals: Mixtrawl 8x7B (1210), ChatGPT-ish (1260)
### Big lab (`bigLab`, 2023–25)
- room: Datacenter campus 12×12 ($30M)
- power: Dedicated power plant deal 300.0 MW ($250M)
- gpu: B200 SuperPOD ($39M, +9%/tile), Vera Rubin NVL144 ($3.9M, +9%/tile), Rubin SuperPOD ($55M, +9%/tile)
- cooling: Cooling tower ($4.0M)
- network: NVLink fabric ($5.0M)
- research: FP8 training $300M, Speculative decoding $2.3B, Synthetic data $3.0B, AI feedback (RLAIF) $1.0B, Long context (ring attention) $1.5B, Reasoning (RL on chain of thought) $2.5B
- stunts: Livestreamed keynote
- runs: 1h / 3h / 6h at 72× (3.0 d / 9.0 d / 18 d of compute)
- rivals: GPT-ish-4 (1339), Claudette 3.5 Sonata (1373), DeepSleep-R1 (1378), Claudette 3.7 Sonata (1455), o-three (1463), Grokk 3 (1503), GPT-ish-4.5 (1506)
### Frontier lab (`globalLab`, 2025–26)
- room: Gigawatt site 12×12 ($400M)
- power: Gigawatt campus 1.0 GW ($600M), Restarted nuclear plant 2.0 GW ($2.0B), Multi-site cluster 4.0 GW ($5.0B)
- gpu: Rubin building ($300M, +3%/tile)
- cooling: Closed-loop dry coolers ($9.0M)
- network: Optical fabric ($30M)
- research: Multi-token prediction $6.0B, Expert data (PhD annotators) $7.0B, Test-time compute scaling $28B, Agentic RL environments $35B, Prefill/decode disaggregation $10B
- stunts: Big-game TV ad
- runs: 2h / 4h / 8h at 36× (3.0 d / 6.0 d / 12 d of compute)
- rivals: GPT-ish-5 (1512), Gemeni 3 Pro (1571), Amused Spark (1580), GPT-ish-5.5 "Tater" (1596), Claudette Parable 5 (1618), Gemeni 4 Xenon (1622), GPT-ish-6 Astral (1626)

The big parody labs (ClosedAI, Anthropomorphic) fight it out in Big lab with
DeepSleep and yAI. The frontier fight (GPT-ish-5 → GPT-ish-6 Astral, with
Gogol DeepThought's Gemeni and MetaMind's Amused Spark) is in the Frontier lab.
The rival ratings are unchanged: they come from real FLOPs through the game's
own formula.

## Pacing: casual schedule (balanced bot, template layout, seed 12345)

| Milestone | Wall-clock | (sim) | Target |
|---|---|---|---|
| Startup | 0h12 | 0h12 | ~10–15 min, first session |
| Small lab | 0h48 | 0h48 | ~1–2 h |
| Medium lab | 7h15 | 7h15 | ~8–14 h |
| Big lab | 24h00 | 19h45 | ~24–32 h |
| Frontier lab | 34h45 | 30h30 | ~40–50 h |
| Final rival (GPT-ish-6 Astral) | **51h30** | 43h00 | ~50–70 h |

Rivals (wall-clock): Tiny-Transformer 0h09, GPT-ish-1 0h12, BURT and
GPT-ish-2 0h35, Meenie 4h00, GPT-ish-3 7h15, Mixtrawl 10h45, ChatGPT-ish 24h00,
GPT-ish-4 → o-three 27h30, Grokk 3 / GPT-ish-4.5 / GPT-ish-5 34h45,
Gemeni 3 Pro / Amused Spark / Tater 48h00, the last three 51h30. That's 10
sessions and 8h15 of active play.

Off target: Frontier lab arrives about 5 h early (on day 2's evening session,
not after night 2), and Medium lab ~45 min before the 8 h mark. Pushing
Frontier past night 2 left Big lab's last day-2 session with nothing to do
(power full, waiting for a run). Idle sessions were judged worse than an early
unlock.

```
sess | wall start | sim start | len | era at start | ran away | 1st act | decisions (buy/rel) | idle max | rivals | eras
   0 |       0h00 |      0h00 |  60 | Parents' garage | -        |   0s   |   51 (32/9) |   8.4m |      4 | Startup, Small lab
   1 |       3h30 |      3h30 |  45 | Small lab    | yes      |   0s   |   81 (77/2) |  10.8m |      1 | 
   2 |       7h15 |      7h15 |  30 | Small lab    | yes      |   0s   |   80 (78/1) |  11.3m |      1 | Medium lab
   3 |      10h45 |     10h45 |  60 | Medium lab   | yes      |   0s   |   39 (37/1) |   8.9m |      1 | 
   4 |      24h00 |     19h45 |  60 | Medium lab   | yes      |   0s   |   98 (96/1) |   5.2m |      1 | Big lab
   5 |      27h30 |     23h15 |  45 | Big lab      | yes      |   0s   |   14 (12/1) |   8.0m |      5 | 
   6 |      31h15 |     27h00 |  30 | Big lab      | yes      |   0s   |   22 (20/1) |   6.3m |      0 | 
   7 |      34h45 |     30h30 |  60 | Big lab      | yes      |   0s   |   38 (36/1) |   7.0m |      3 | Frontier lab
   8 |      48h00 |     39h30 |  60 | Frontier lab | yes      |   0s   |   50 (48/1) |   8.7m |      3 | 
   9 |      51h30 |     43h00 |  45 | Frontier lab | yes      |   0s   |    2 (1/0) |   0.3m |      3 |
```

- **Longest active stretch with nothing to buy or do: 11.3 min** (session 3,
  saving for the campus power tier). Target < 10; every other session is ≤ 9 min.
- Every session from the second on has a decision in its first second. A
  finished training run waits on return in 9 of 10 sessions, and decisions per
  session have a median of 50. The 2 in the last session is the final rival
  falling a minute in.
- Seeds 1, 777 and 2026 give the identical timeline (max idle 10.8–11.3 min).
  Seed 4242 is a session faster early (Medium 4h00, Big 10h45), Frontier
  48h00, final 58h45, max idle 14.2 min.
- At the final rival: 2.6B users, $41B ARR, 1.7M H100e, 1.4 GW.

## Pacing: continuous play (no gaps)

Startup 0h12, Small lab 0h48, Medium lab 3h01, Big lab 10h26, Frontier
27h07, final rival **46h20** (seed 12345, 1 s / 3 s). So non-stop play beats the
casual player by about 5 h of wall-clock but needs ~46 h of active play,
against ~8 h for the casual player. Offline earns at full rate, so playing
non-stop is no big advantage. That's deliberate for a casual idle game.
The catch: a continuous player hits long save-ups (longest stretch with nothing
to buy: ~2.9 h, late Frontier lab), because the big research items are sized for
offline earnings.

## Strategies and placement

```
continuous, 60h00 cap
strategy / layout        | Startup      | Small lab    | Medium lab   | Big lab      | Frontier lab | final  | rivals
balanced / template     |  0h12        |  0h48        |  3h01        | 10h26        | 27h07        | 46h20 | 22/22
hardwareOnly / template |  0h14        |    —         |    —         |    —         |    —         |    —   |  4/22
noUpgrades / template   |  0h18        |    —         |    —         |    —         |    —         |    —   |  2/22
softwareFirst / template |  0h15        |  1h22        |  3h38        | 11h05        | 29h26        | 46h57 | 22/22
balanced / naive        |    —         |    —         |    —         |    —         |    —         |    —   |  1/22
balanced / random       |  0h16        |    —         |    —         |    —         |    —         |    —   |  4/22

casual, 96h00 cap
strategy / layout        | Startup      | Small lab    | Medium lab   | Big lab      | Frontier lab | final  | rivals
balanced / template     |  0h12        |  0h48        |  7h15        | 24h00        | 34h45        | 51h30 | 22/22
hardwareOnly / template |  0h14        |  4h11        |    —         |    —         |    —         |    —   |  5/22
noUpgrades / template   |  0h18        |    —         |    —         |    —         |    —         |    —   |  2/22
softwareFirst / template |  0h15        |  3h40        |  7h15        | 24h00        | 34h45        | 58h45 | 22/22
balanced / naive        |  3h36        | 10h45        |    —         |    —         |    —         |    —   |  4/22
balanced / random       |  0h16        |  4h11        | 10h45        | 27h30        |    —         |    —   | 13/22
```

- **naive** (no switches, no coolers) trains on single tiles: on the casual
  schedule it's stuck in the Small lab with 4 rivals after 4 days.
- **random** scatters switches and coolers: one era and ~5 rivals behind at
  40 h, 13/22 after 4 days.
- **hardware-only** (no software/research beyond data and liquid cooling)
  never leaves the Small lab. **no-upgrades** stays in the Startup.
- **software-first** finishes too, 7 h later on the casual schedule.

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

**Room space.** The hall and campus grew to 12×12 and the colo tier to
500 kW, and the plant tier to 300 MW. The gigasite building is ~8k Rubin GPUs at
$300M, so each era has enough floor and power for in-session GPU purchases
between offline lumps.

**Unchanged from v2:** the grid rules, demand/hype/viral numbers, rival
ratings and users, hype cap 8, overload settle, cloud rental cost, the 8 h
offline cap.
