# Balance notes

How the economy is tuned, what the bot measures, and why the numbers are what
they are. Knobs live in `lib/sim/balance.dart` (constants) and
`lib/sim/content.dart` (costs and effects). The headless player is
`lib/sim/bot.dart`; the report tool is `tool/balance_sim.dart`.

```
dart run tool/balance_sim.dart [minutes=360] [--log-every=10] [--seed=12345]
    [--strategy=balanced|hardware-only|software-first|no-upgrades]
dart run tool/balance_sim.dart 720 --compare     # all strategies, summary only
```

## The bot (an "engaged human")

- Looks at the game every 3 s. It only uses choices the UI offers: 50% or 75%
  of compute for training, and 1 m (Garage), 3 m (Startup and early Lab) or
  10 m runs (Lab once rating ≥ 1300).
- Starts the next run as soon as one finishes. It releases a model only if it
  beats the current one. It releases open weights in the Garage (hype +
  community bonus) and closed from then on, always with a cryptic tweet.
- Viral spike while overloaded: rents cloud GPUs if they cost < 25% of cash,
  otherwise pauses training until the spike ends.
- Spending: it scores every option by Δprogress / $. Progress = predicted
  rating in compute doublings + log(users it could serve) + ½·log(ARPU). The
  options are each available upgrade, one more of the best GPU, and the next
  power tier (valued as the tier plus an equal spend on GPUs to fill it). It
  buys the best affordable option. If something better is close, it saves for
  it, and waits longer the better the deal (60 s, up to 8 min max).

## Pacing (balanced bot, seed 12345)

| Milestone | Time | Target |
|---|---|---|
| Garage → **Startup** (5k users) | 0h09 | 8–12 min |
| Rivals beaten by 0h30 | 4 (Hugging Hands 0h06, GPT-ish-1 0h09, BURT 0h16, GPT-ish-2 0h21) | ≥ 2 in 20–30 min |
| Startup → **Lab** (rating 1100) | 0h42 | 35–50 min |
| Meenie, GPT-ish-3 | 0h42 | |
| Mixtrawl 8x7B | 0h58 | |
| ChatGPT-ish (100M users) | 1h01 | |
| GPT-ish-4, Claudette 3.5 Sonata, DeepSleep-R1 | 1h13 | |
| Claudette 3.7 Sonata | 1h24 | |
| o-three, Grokk 3, GPT-ish-4.5 (viral spike + cloud) | 1h59 | |
| GPT-ish-5 (800M users) | 2h39 | |
| Gemeni 3 Pro | 2h59 | |
| Amused Spark (1B users) | 3h28 | |
| GPT-ish-5.5 "Tater" | 4h03 | |
| Claudette Parable 5, Gemeni 4 Xenon, **GPT-ish-6 Astral (final)** | 4h08 | 4–6 h |

Seeds 1, 777, 4242 and 2026 give Startup at 8–9 min, Lab at 43–45 min and the
final rival at 4h07–4h12. The bot is a fast, ROI-optimal player, so humans
should land later, around 4.5–5.5 h.

Health stats (seed 12345; the other seeds are similar):
- Longest stretch with no purchase or release before the ladder is done:
  **6.0 min** (6–8 min across seeds). Target < 10.
- OVERLOADED **8.8%** of the time, about 3.4 points of it during viral
  spikes (13 spikes in 6 h, so about 2–3 an hour). The rest is short
  launch-day crunches when a bigger model raises the serving cost per user.
- At the final rival: **1.6B users, $77B ARR, 1.2M H100-equivalents,
  ~1 GW**. Real 2026 figures: ChatGPT 1.2B WAU, OpenAI ARR $40–70B (disputed),
  one Stargate-class site is ~1M H100e at ~1.15 GW. Users never exceed
  `maxUsers` (5B; reached only in the post-ladder sandbox). Money never goes
  negative.
- Longest gap between rival wins: 40 min (36–63 min across seeds). Late gaps
  are 3–5 ten-minute training runs or a wait for the next viral spike.

## Strategy comparison (`--compare`, 12 h cap)

```
strategy        | Startup | Lab    | rival 5 | rival 10 | rival 15 | final  | rivals | overload
balanced        |  0h09  |  0h42 |  0h42  |  1h13   |  1h59   |  4h08 | 22/22  | 9.9%
hardwareOnly    |  0h17  |    —   |    —    |    —     |    —     |    —   |  4/22  | 9.3%
noUpgrades      |  3h54  |    —   |    —    |    —     |    —     |    —   |  3/22  | 0.9%
softwareFirst   |  0h11  |  0h59 |  0h59  |  2h04   |  3h39   |  5h24 | 22/22  | 9.7%
```

- **balanced** finishes at 4h08.
- **software-first** (buys every upgrade first and saves for it) reaches Lab
  17 min later and the final rival 1h16 later. It under-invests in GPUs early,
  and expensive late research delays power and GPU buys.
- **hardware-only** buys no software or research upgrades. It still buys data
  (you can't train without tokens) and liquid cooling (racks need it). It
  never leaves Startup: with MFU stuck at 25% and no algorithmic gains, a full
  colo cage tops out around rating 1030–1040, below the 1100 Lab gate. After
  4 h it has 4 rivals against balanced's 22 (tested in
  `test/sim/playthrough_test.dart`). Buying the cheap FP16 and CUDA-kernel
  upgrades is enough to escape, so this is a strategy dead end, not a game
  deadlock.
- **no-upgrades** (not even data) hits the data wall at once (4B tokens
  saturate at ~5e18 FLOPs, rating ~750). It needs 3h54 just to reach Startup.

## Why the numbers are what they are

**Rival ratings are the game's own formula.** Each snapshot stores its real
estimated training FLOPs (Epoch AI via `docs/research/rival_labs.md`) and a
post-training bonus. Its rating is
`700 + 23·log2(FLOPs/1e18) + bonus`, the same as the player's `ratingOf`. A
test checks this. The bonuses track the player's research stack over time:
0 before 2023 → 60–80 (instruction tuning + RLHF era) → 105 (2024) → 150–215
(reasoning, 2025) → 225–240 (test-time and agentic RL, 2026). The player's
own maximum is 250. So beating GPT-ish-6 Astral needs roughly its effective
compute (~6–9e26) and a full post-training stack. FLOPs marked
`flopsInterpolated` (o-three, Gemeni 3 Pro, Amused Spark, Tater, Claudette
Parable 5, Gemeni 4 Xenon) have no public estimate and are interpolated between
neighbours.

**Users are the real figures** where they exist (WAU and MAU are mixed, as in
the research notes). The rest are interpolated and marked "interp." in
content.dart. Rating strictly increases along the ladder and years never go
backwards. Users mostly increase. The dips are labs with small consumer apps
(Anthropomorphic, yAI, DeepSleep). They act as pure rating gates; the test
allows dips down to 10% of the running maximum.

**Users fill to capacity; viral spikes overflow.** Signups used to keep
piling up to 1.5× capacity whenever demand > capacity, so the game was
OVERLOADED ~60% of the time. Now users stop at capacity (a waitlist, see
`Game.waitlistUsers`) and only a viral spike pushes past it. Overload churn
is 8%/s and settles at capacity, so OVERLOADED ends instead of fading out
asymptotically. Viral spikes need demand > capacity and have a 10-min
cooldown. A viral spike plus a cloud rental (serving ×2) lets you serve
about 2–3× capacity for 90 s, which is often how you overtake a rival's user
count. That's intended.

**Hype no longer compounds.** A release used to multiply hype, so one-minute
garage releases snowballed to 10×+ demand. Now hype becomes max(current,
boost), capped at 8.

**Hardware dominance chain.** Each newer part beats the older ones on both
TFLOPS/$ and TFLOPS/kW, so the power cap (not a pricing trap) pushes you up
the tech tree. Previously the bot filled a 150 MW plant with gaming GPUs.
Datacenter power is roughly all-in (host, network and cooling share):
H-class 1.3 kW, B-class 2.4 kW, R-class 3.4 kW. B-class needs liquid cooling
and a campus site, as GB200 racks do; R-class needs the power-plant tier.

**Two-ended economy.** Early users are demand-limited, so `demandBase` (90)
paces the Garage and Startup. Late users are capacity-limited, so
`servingBase` (0.0135) paces the users side of the ladder and sets the final
ARR. Serving cost grows as `effC^0.3`, so bigger models genuinely cost more to
serve, and the serving upgrades (batching → distillation → MTP) are how you
keep up. Startup-era upgrades were made pricier (MoE $1.5M, colo $2.5M,
RLHF moved to the Lab era, where it belongs historically). Otherwise the
Startup economy snowballed and Lab arrived at ~20 min.

**Data wall.** Tokens: 4B start × crawl 50 × code 3 × synthetic 50 × licensed
2.5 ≈ 75T tokens (frontier-realistic). That is data-optimal up to ~1.7e27
FLOPs. Mid-game "data-limited" phases happen just before each data upgrade.
The final rungs need agentic RL and test-time compute, not just more GPUs.

**Power-tier save-ups stay under ~8 min.** Each tier costs about 5–8 min of
the revenue you have when you hit the previous cap. A tier is bought as soon
as it's affordable, then filled with GPUs.

**Post-ladder sandbox.** The restarted-nuclear (2 GW) and multi-site (4 GW)
tiers come after the final rival. By 8 h the bot runs ~6.6M H100e on 4 GW,
the scale of each US major's whole fleet (2.6–3.7M H100e, 3–4 GW).

## Tool output (`dart run tool/balance_sim.dart`, 6 h, balanced)

```
strategy: balanced

time  | money      | rev/s     | ARR        | users      | rating | GPUs    | power kW        | util | era
 0h00 |        501 |      1.20 |      26.3k |       2.70 |    700 |    1.00 |    0.45/   1.80 | 0.25 | Garage
 0h06  >>> BEAT Hugging Hands Collective Tiny-Transformer (2017)
 0h09  >>> BEAT ClosedAI GPT-ish-1 (2018)
 0h09  >>> ERA: Startup
 0h10 |       1.9k |       237 |      5.19M |       5.1k |    821 |      13 |    6.45/   8.00 | 0.33 | Startup
 0h16  >>> BEAT Gogol DeepThought BURT-Large (2018)
 0h20 |       9.8k |      2.7k |     58.81M |      79.2k |    945 |      59 |      39/     40 | 0.43 | Startup
 0h21  >>> BEAT ClosedAI GPT-ish-2 (2019)
 0h22  !!! viral spike (capacity 197.0k, users 172.0k)
 0h30 |     238.3k |      5.1k |    111.15M |     196.6k |   1046 |      71 |      40/     40 | 0.50 | Startup
 0h36  !!! viral spike (capacity 203.8k, users 203.8k)
 0h40 |      40.4k |     13.1k |    286.40M |     759.9k |   1078 |     339 |     199/    250 | 0.55 | Startup
 0h42  >>> ERA: Lab
 0h42  >>> BEAT Gogol DeepThought Meenie (2020)
 0h42  >>> BEAT ClosedAI GPT-ish-3 (2020)
 0h50 |     127.5k |     41.1k |    900.78M |      3.01M |   1150 |     509 |     344/   2.0k | 0.55 | Lab data-limited
 0h56  !!! viral spike (capacity 41.88M, users 34.37M)
 0h58  >>> BEAT Mistrawl Mixtrawl 8x7B (2023)
 1h00 |      1.19M |    388.2k |      8.50B |     74.35M |   1248 |    3.6k |    5.2k/  20.0k | 0.66 | Lab
 1h01  >>> BEAT ClosedAI ChatGPT-ish (2023)
 1h10 |      2.26M |    750.5k |     16.44B |    190.66M |   1319 |   10.3k |   18.9k/  20.0k | 0.66 | Lab
 1h13  >>> BEAT ClosedAI GPT-ish-4 (2023)
 1h13  >>> BEAT Anthropomorphic Claudette 3.5 Sonata (2024)
 1h13  >>> BEAT DeepSleep DeepSleep-R1 (2025)
 1h20 |    104.50M |    425.4k |      9.32B |     84.72M |   1445 |   10.8k |   20.0k/  20.0k | 0.66 | Lab
 1h24  >>> BEAT Anthropomorphic Claudette 3.7 Sonata (2025)
 1h30 |      1.69M |    557.5k |     12.21B |    124.68M |   1458 |   15.1k |   32.4k/ 150.0k | 0.66 | Lab
 1h36  !!! viral spike (capacity 156.70M, users 153.18M)
 1h40 |      2.24M |    744.5k |     16.31B |    188.49M |   1474 |   22.8k |   54.6k/ 150.0k | 0.66 | Lab
 1h50 |      2.61M |    858.9k |     18.81B |    231.17M |   1494 |   31.1k |   78.7k/ 150.0k | 0.66 | Lab
 1h58  !!! viral spike (capacity 281.90M, users 277.45M)
 1h59  >>> BEAT ClosedAI o-three (2025)
 1h59  >>> BEAT yAI Grokk 3 (2025)
 1h59  >>> BEAT ClosedAI GPT-ish-4.5 (2025)
 2h00 |      4.97M |     1.65M |     36.21B |    659.43M |   1507 |   41.9k |  109.8k/ 150.0k | 0.66 | Lab OVERLOADED
 2h10 |      3.45M |     1.14M |     25.01B |    347.31M |   1519 |   54.3k |  145.7k/ 150.0k | 0.66 | Lab
 2h17  !!! viral spike (capacity 337.97M, users 347.23M)
 2h20 |    343.60M |     1.40M |     30.67B |    353.89M |   1536 |   55.8k |  150.0k/ 150.0k | 0.66 | Lab OVERLOADED
 2h30 |    641.67M |     1.54M |     33.63B |    336.36M |   1557 |   55.8k |  150.0k/ 150.0k | 0.66 | Lab
 2h38  !!! viral spike (capacity 427.47M, users 420.61M)
 2h39  >>> BEAT ClosedAI GPT-ish-5 (2025)
 2h40 |      9.18M |     3.05M |     66.88B |      1.01B |   1557 |   73.0k |  199.5k/  1.00M | 0.66 | Lab OVERLOADED
 2h50 |      6.70M |     2.23M |     48.81B |    572.80M |   1560 |   95.7k |  265.3k/  1.00M | 0.66 | Lab
 2h59  >>> BEAT Gogol DeepThought Gemeni 3 Pro (2025)
 3h00 |      7.39M |     2.45M |     53.67B |    655.88M |   1572 |  120.4k |  336.8k/  1.00M | 0.66 | Lab
 3h10 |      8.12M |     2.70M |     59.07B |    752.25M |   1581 |  147.9k |  416.1k/  1.00M | 0.66 | Lab data-limited
 3h20 |      8.97M |     2.99M |     65.39B |    869.86M |   1586 |  178.4k |  504.3k/  1.00M | 0.66 | Lab data-limited
 3h28  >>> BEAT MetaMind Labs Amused Spark (2026)
 3h30 |     10.04M |     3.34M |     73.12B |      1.02B |   1588 |  212.7k |  603.3k/  1.00M | 0.66 | Lab data-limited
 3h34  !!! viral spike (capacity 1.10B, users 1.09B)
 3h40 |     11.24M |     3.74M |     82.01B |      1.20B |   1591 |  254.4k |  723.9k/  1.00M | 0.66 | Lab data-limited
 3h50 |     12.38M |     4.12M |     90.31B |      1.38B |   1593 |  297.1k |  847.3k/  1.00M | 0.66 | Lab data-limited
 3h52  !!! viral spike (capacity 1.41B, users 1.45B)
 4h00 |     13.68M |     4.56M |     99.84B |      1.59B |   1595 |  348.3k |  995.4k/  1.00M | 0.66 | Lab data-limited
 4h03  >>> BEAT ClosedAI GPT-ish-5.5 "Tater" (2026)
 4h06  !!! viral spike (capacity 1.58B, users 1.58B)
 4h08  >>> BEAT Anthropomorphic Claudette Parable 5 (2026)
 4h08  >>> BEAT Gogol DeepThought Gemeni 4 Xenon (2026)
 4h08  >>> BEAT ClosedAI GPT-ish-6 Astral (2026)
 4h10 |    297.94M |     3.54M |     77.43B |      1.11B |   1632 |  349.9k | 1000.0k/  1.00M | 0.66 | Lab data-limited
 4h20 |      2.42B |     3.54M |     77.43B |      1.11B |   1632 |  349.9k | 1000.0k/  1.00M | 0.66 | Lab data-limited
 4h21  !!! viral spike (capacity 1.11B, users 1.11B)
 4h30 |     11.43M |     3.80M |     83.17B |      1.23B |   1633 |  391.5k |   1.12M/  2.00M | 0.66 | Lab data-limited
 4h40 |     12.17M |     4.06M |     88.83B |      1.35B |   1634 |  434.4k |   1.24M/  2.00M | 0.66 | Lab data-limited
 4h50 |     13.02M |     4.32M |     94.63B |      1.47B |   1635 |  480.1k |   1.38M/  2.00M | 0.66 | Lab data-limited
 5h00 |     13.82M |     4.59M |    100.58B |      1.61B |   1636 |  528.8k |   1.52M/  2.00M | 0.66 | Lab data-limited
 5h10 |     14.66M |     4.87M |    106.67B |      1.75B |   1637 |  580.4k |   1.67M/  2.00M | 0.66 | Lab data-limited
 5h19  !!! viral spike (capacity 1.90B, users 1.89B)
 5h20 |     21.28M |     7.19M |    157.38B |      3.05B |   1638 |  635.4k |   1.82M/  2.00M | 0.66 | Lab data-limited
 5h30 |    130.45M |     5.47M |    119.71B |      2.06B |   1640 |  696.0k |   2.00M/  2.00M | 0.66 | Lab data-limited
 5h40 |      3.41B |     5.45M |    119.33B |      2.05B |   1640 |  696.0k |   2.00M/  2.00M | 0.66 | Lab data-limited
 5h42  !!! viral spike (capacity 2.05B, users 2.05B)
 5h50 |      1.13B |     6.54M |    143.20B |      2.05B |   1675 |  696.0k |   2.00M/  2.00M | 0.66 | Lab data-limited
 6h00 |      5.05B |     6.54M |    143.20B |      2.05B |   1675 |  696.0k |   2.00M/  2.00M | 0.66 | Lab data-limited

=== summary (balanced) ===
era Garage    0h00
era Startup   0h09
era Lab       0h42
rival  0h06  Hugging Hands Collective Tiny-Transformer (2017)
rival  0h09  ClosedAI GPT-ish-1 (2018)
rival  0h16  Gogol DeepThought BURT-Large (2018)
rival  0h21  ClosedAI GPT-ish-2 (2019)
rival  0h42  Gogol DeepThought Meenie (2020)
rival  0h42  ClosedAI GPT-ish-3 (2020)
rival  0h58  Mistrawl Mixtrawl 8x7B (2023)
rival  1h01  ClosedAI ChatGPT-ish (2023)
rival  1h13  ClosedAI GPT-ish-4 (2023)
rival  1h13  Anthropomorphic Claudette 3.5 Sonata (2024)
rival  1h13  DeepSleep DeepSleep-R1 (2025)
rival  1h24  Anthropomorphic Claudette 3.7 Sonata (2025)
rival  1h59  ClosedAI o-three (2025)
rival  1h59  yAI Grokk 3 (2025)
rival  1h59  ClosedAI GPT-ish-4.5 (2025)
rival  2h39  ClosedAI GPT-ish-5 (2025)
rival  2h59  Gogol DeepThought Gemeni 3 Pro (2025)
rival  3h28  MetaMind Labs Amused Spark (2026)
rival  4h03  ClosedAI GPT-ish-5.5 "Tater" (2026)
rival  4h08  Anthropomorphic Claudette Parable 5 (2026)
rival  4h08  Gogol DeepThought Gemeni 4 Xenon (2026)
rival  4h08  ClosedAI GPT-ish-6 Astral (2026)
rivals beaten: 22/22; upgrades: 29/29; releases: 49; viral spikes: 13
overloaded 8.8% of the time (3.4% during viral spikes); longest stretch without a purchase/release: 6.0 min (from  1h15)
at the final rival: 1.63B users, ARR 77.43B, 1.22M H100-equivalents, 1000 MW
longest gap between rival wins: 40 min
max users 4.34B (cap 5.00B); final money 5.05B, ARR 143.20B; power 2.00M kW; H100e 2.44M
```
