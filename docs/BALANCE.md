# Balance notes

How the economy is tuned, what the bot measures, and why the numbers are what
they are. Knobs live in `lib/sim/balance.dart` (constants) and
`lib/sim/content.dart` (tiles, rooms, costs and effects). The grid rules are
in `docs/GRID.md` (final numbers at the end) and `lib/sim/grid.dart`. The
headless player is `lib/sim/bot.dart`; the report tool is
`tool/balance_sim.dart`.

```
dart run tool/balance_sim.dart [minutes=360] [--log-every=10] [--seed=12345]
    [--strategy=balanced|hardware-only|software-first|no-upgrades]
    [--layout=template|naive|random]
dart run tool/balance_sim.dart 720 --compare     # all strategies + layouts
```

## The bot (an "engaged human")

- Looks at the game every 3 s. It only uses choices the UI offers: 50% or 75%
  of the training cluster for training, and 1 m (Garage), 3 m (Startup and
  early Lab) or 10 m runs (Lab once rating ≥ 1300).
- Starts the next run as soon as one finishes. It releases a model only if it
  beats the current one. It releases open weights in the Garage (hype +
  community bonus) and closed from then on, always with a cryptic tweet.
- Viral spike while overloaded: rents cloud GPUs if they cost < 25% of cash,
  otherwise pauses training until the spike ends.
- Spending: it scores every option by Δprogress / $. Progress = predicted
  rating (from the training cluster) in compute doublings + log(users it
  could serve) + ½·log(ARPU). The options are each available upgrade, the
  next build step in each of its three newest rooms, a switch upgrade, a
  cooler upgrade, replacing a full room's weakest GPU tile, the next room and
  the next power tier. Grid options are valued by really applying them to the
  grid and undoing them (heat and clusters included). It buys the best
  affordable option, up to 12 per look. If something better is close, it saves
  for it, and waits longer the better the deal (60 s, up to 8 min max).

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

## Pacing (balanced bot, template layout, seed 12345)

| Milestone | Time | Target |
|---|---|---|
| First switch (with the 2nd GPU) / first fan (4th GPU) | 0h03 / 0h07 | first few minutes |
| Garage → **Startup** (3k users) | 0h09 | 8–12 min |
| Rivals beaten by 0h30 | 4 (Hugging Hands 0h06, GPT-ish-1 0h09, BURT 0h19, GPT-ish-2 0h23) | ≥ 2 in 20–30 min |
| Startup → **Lab** (rating 1100) | 0h45 | 35–50 min |
| Meenie, GPT-ish-3 | 0h45, 0h47 | |
| Mixtrawl 8x7B | 0h58 | |
| ChatGPT-ish (100M users) | 1h12 | |
| GPT-ish-4, Claudette 3.5 Sonata, DeepSleep-R1 | 1h18–1h20 | |
| Claudette 3.7 Sonata | 1h42 | |
| o-three, Grokk 3, GPT-ish-4.5 | 1h57–2h16 | |
| GPT-ish-5 (800M users) | 3h00 | |
| Gemeni 3 Pro, Amused Spark | 3h16, 3h26 | |
| GPT-ish-5.5 "Tater", Claudette Parable 5, Gemeni 4 Xenon, **GPT-ish-6 Astral (final)** | 3h58 | 4–6 h |

Rooms in that run: closet 0h14, colo 0h38, hall 0h53, campus 1h02,
gigasite 2h39. Seeds 1, 777, 4242 and 2026 give
Startup at 9 min (4242: 5 min, a lucky early viral spike plus cloud rental),
Lab at 43–47 min and the final rival at 3h56–4h04. The bot is a fast,
ROI-optimal player, so humans should land later, around 4.5–5.5 h.

Health stats (seed 12345; the other seeds are similar):
- Longest stretch with no purchase or release before the ladder is done:
  **9.5 min** (9.3–9.7 across seeds). Target < 10. It is the save-up for
  the first gigasite building (~$0.8B) after the gigawatt tier.
- OVERLOADED **8.9%** of the time, 3.8 points of it during viral spikes
  (14 spikes in 6 h).
- At the final rival: **1.5B users, $75B ARR, 1.1M H100-equivalents,
  ~0.9 GW**. Real 2026 figures: ChatGPT 1.2B WAU, OpenAI ARR $40–70B
  (disputed), one Stargate-class site is ~1M H100e at ~1.15 GW. Users never
  exceed `maxUsers`. Money never goes negative.
- Training stays on one well-fed cluster: at the final rival the bot trains
  on the gigasite at 100% scaling efficiency, every room is a single cluster
  and heat costs < 10% of peak TFLOPS (all checked in the playthrough test).

## Placement matters (template vs naive vs random)

`--compare`, 12 h cap, seed 12345:

```
strategy / layout        | Startup | Lab    | rival 5 | rival 10 | rival 15 | final  | rivals | overload
balanced / template     |  0h09  |  0h45 |  0h45  |  1h20   |  2h16   |  3h58 | 22/22  | 9.2%
hardwareOnly / template |    —    |    —   |    —    |    —     |    —     |    —   |  1/22  | 0.1%
noUpgrades / template   |    —    |    —   |    —    |    —     |    —     |    —   |  1/22  | 0.9%
softwareFirst / template |  0h10  |  1h13 |  1h10  |  2h10   |  3h36   |  5h21 | 22/22  | 8.7%
balanced / naive        |  0h52  |    —   |    —    |    —     |    —     |    —   |  3/22  | 6.7%
balanced / random       |  0h11  |    —   |  1h21  |    —     |    —     |    —   |  5/22  | 6.9%
```

- **template** finishes at 3h58.
- **naive** (no switches, no coolers, random cells) trains on a single tile,
  so its model barely improves: Startup only at 0h52 and 3 rivals in 12 h.
  In the test at 3 h it trails the template by > 150 rating.
- **random** buys a similar mix of switches and coolers but scatters them:
  most GPUs never touch a switch and coolers sit next to nothing. It reaches
  Startup on time (serving doesn't need a network) but never Lab: 5 rivals in
  12 h.
- **software-first** reaches Lab 28 min later and the final rival 1h23 later.
- **hardware-only** buys no software or research upgrades (only data and the
  liquid cooling racks need). It no longer even leaves the Garage: a 4×4
  garage holds 8 GPUs, and with MFU stuck at 25% and no batching it can't
  serve the 3k users Startup needs. Buying the $1.2k batching upgrade is
  enough to escape, so this is a strategy dead end, not a game deadlock.
- **no-upgrades** hits the data wall at once and stays in the Garage.

## What changed with the grid (v2)

- Startup now unlocks at **3k users** (was 5k): the garage physically holds
  ~8 GPUs once it has switches and coolers, against ~13 in the old shop.
- `servingBase` 0.0135 → 0.015, colo tier $2.5M → $2M, gigawatt tier
  $750M → $450M, test-time compute stays $2.5B, agentic RL $6B → $8B.
- Rooms cost: closet $10k, colo $200k, hall $1.5M, campus $15M, gigasite
  $50M, each gated by its power tier (office, colo, hall, campus, gigawatt).
- Extra tile `pod_r_class` (R-class pod, campus, power-plant tier): without
  it the campus was full of B-class pods from ~2h15 with nothing to buy until
  the gigasite.

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

**Hardware dominance chain.** Each newer GPU tile beats the older ones on
both TFLOPS/$ and TFLOPS/kW (the Old gaming GPU is the one deliberate trap:
cheapest up front, worse on everything else), so the power cap and floor
space, not a pricing trap, push you up the tech tree. Per-GPU power is
roughly all-in: H-class 1.25–1.3 kW, B-class 2.35–2.4 kW, R-class 3.3–3.4 kW.
B-class needs liquid cooling and a campus site, as GB200 racks do; R-class
needs the power-plant tier.

**Two-ended economy.** Early users are demand-limited, so `demandBase` (90)
paces the Garage and Startup. Late users are capacity-limited, so
`servingBase` (0.015; was 0.0135 before the grid) paces the users side of the ladder and sets the final
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
tiers come after the final rival. The gigasite holds 66 building tiles
(~1.1M R-class GPUs, ~3 GW), so 4 GW is never quite filled; by 6 h the bot
runs ~2.5M H100e on 2 GW.

## Tool output (`dart run tool/balance_sim.dart`, 6 h, balanced)

```
strategy: balanced, layout: template

time  | money      | rev/s     | ARR        | users      | rating | GPUs    | power kW        | util | train cluster          | rooms | era
 0h00 |        501 |      1.20 |      26.3k |       2.70 |    700 |    1.00 |    0.45/   1.80 | 0.25 | 1.00 GPU garage 100%   |     1 | Garage
 0h06  >>> BEAT Hugging Hands Collective Tiny-Transformer (2017)
 0h09  >>> ERA: Startup
 0h09  >>> BEAT ClosedAI GPT-ish-1 (2018)
 0h10 |        965 |       181 |      3.97M |       3.5k |    809 |    8.00 |    7.68/   8.00 | 0.33 | 8.00 GPU garage 100%   |     1 | Startup
 0h19  >>> BEAT Gogol DeepThought BURT-Large (2018)
 0h20 |      43.1k |      1.0k |     22.53M |      20.1k |    889 |      32 |      25/     40 | 0.33 | 24 GPU closet 100%     |     2 | Startup
 0h21  !!! viral spike (capacity 34.4k, users 28.7k)
 0h23  >>> BEAT ClosedAI GPT-ish-2 (2019)
 0h30 |     236.5k |      4.4k |     95.49M |     158.2k |    999 |      56 |      39/     40 | 0.55 | 48 GPU closet 100%     |     2 | Startup
 0h34  !!! viral spike (capacity 141.3k, users 141.3k)
 0h40 |      37.2k |      8.9k |    194.35M |     436.7k |   1014 |      96 |      87/    250 | 0.55 | 40 GPU colo 100%       |     3 | Startup
 0h45  >>> ERA: Lab
 0h45  >>> BEAT Gogol DeepThought Meenie (2020)
 0h47  >>> BEAT ClosedAI GPT-ish-3 (2020)
 0h50 |      1.20M |     43.8k |    959.89M |      3.30M |   1142 |     216 |     250/    250 | 0.55 | 104 GPU colo 100%      |     3 | Lab
 0h54  !!! viral spike (capacity 16.53M, users 13.04M)
 0h58  >>> BEAT Mistrawl Mixtrawl 8x7B (2023)
 1h00 |      1.28M |    178.1k |      3.90B |     24.42M |   1235 |    1.2k |    2.0k/  20.0k | 0.66 | 864 GPU hall 100%      |     4 | Lab
 1h10 |     21.48M |    344.6k |      7.55B |     62.71M |   1297 |    3.1k |    6.0k/  20.0k | 0.66 | 2.7k GPU hall 100%     |     5 | Lab
 1h12  >>> BEAT ClosedAI ChatGPT-ish (2023)
 1h18  >>> BEAT ClosedAI GPT-ish-4 (2023)
 1h20 |      6.36M |    608.7k |     13.33B |    141.35M |   1364 |    9.2k |   18.4k/  20.0k | 0.66 | 6.1k GPU campus 100%   |     5 | Lab
 1h20  >>> BEAT Anthropomorphic Claudette 3.5 Sonata (2024)
 1h20  >>> BEAT DeepSleep DeepSleep-R1 (2025)
 1h30 |     21.09M |    569.7k |     12.48B |    128.59M |   1425 |   10.8k |   22.6k/ 150.0k | 0.66 | 7.2k GPU campus 100%   |     5 | Lab
 1h35  !!! viral spike (capacity 149.90M, users 140.23M)
 1h40 |     41.12M |    738.0k |     16.16B |    186.15M |   1445 |   16.9k |   41.3k/ 150.0k | 0.66 | 13.3k GPU campus 100%  |     5 | Lab
 1h42  >>> BEAT Anthropomorphic Claudette 3.7 Sonata (2025)
 1h50 |     60.42M |    825.5k |     18.08B |    218.44M |   1470 |   24.1k |   62.9k/ 150.0k | 0.66 | 20.5k GPU campus 100%  |     5 | Lab data-limited
 1h57  !!! viral spike (capacity 232.29M, users 229.96M)
 1h57  >>> BEAT ClosedAI o-three (2025)
 2h00 |     24.24M |    923.5k |     20.23B |    256.42M |   1491 |   33.3k |   90.3k/ 150.0k | 0.66 | 29.7k GPU campus 100%  |     5 | Lab
 2h03  >>> BEAT yAI Grokk 3 (2025)
 2h10 |     61.45M |    998.3k |     21.86B |    286.58M |   1505 |   42.5k |  117.7k/ 150.0k | 0.66 | 38.9k GPU campus 100%  |     5 | Lab
 2h16  !!! viral spike (capacity 301.78M, users 297.71M)
 2h16  >>> BEAT ClosedAI GPT-ish-4.5 (2025)
 2h20 |    273.78M |     1.04M |     22.67B |    301.78M |   1516 |   49.7k |  139.7k/ 150.0k | 0.66 | 46.1k GPU campus 100%  |     5 | Lab
 2h30 |    336.57M |     1.31M |     28.62B |    306.14M |   1532 |   49.7k |  146.8k/ 150.0k | 0.66 | 46.1k GPU campus 100%  |     5 | Lab
 2h37  !!! viral spike (capacity 302.15M, users 302.15M)
 2h40 |    131.18M |     1.42M |     31.20B |    302.15M |   1553 |   49.7k |  146.8k/  1.00M | 0.66 | 46.1k GPU campus 100%  |     6 | Lab
 2h50 |    203.39M |     2.01M |     44.07B |    495.02M |   1553 |   66.1k |  192.8k/  1.00M | 0.66 | 46.1k GPU campus 100%  |     6 | Lab
 3h00 |    771.34M |     2.57M |     56.33B |    702.81M |   1553 |   82.4k |  238.8k/  1.00M | 0.66 | 46.1k GPU campus 100%  |     6 | Lab
 3h00  >>> BEAT ClosedAI GPT-ish-5 (2025)
 3h10 |    168.19M |     3.32M |     72.64B |      1.01B |   1558 |  131.6k |  376.7k/  1.00M | 0.66 | 81.9k GPU gigasite 100% |     6 | Lab
 3h16  >>> BEAT Gogol DeepThought Gemeni 3 Pro (2025)
 3h20 |    583.14M |     3.41M |     74.60B |      1.05B |   1574 |  164.4k |  468.8k/  1.00M | 0.66 | 114.7k GPU gigasite 100% |     6 | Lab data-limited
 3h26  >>> BEAT MetaMind Labs Amused Spark (2026)
 3h30 |    195.91M |     3.64M |     79.76B |      1.16B |   1586 |  213.5k |  607.0k/  1.00M | 0.66 | 163.8k GPU gigasite 100% |     6 | Lab data-limited
 3h33  !!! viral spike (capacity 1.24B, users 1.22B)
 3h40 |    161.96M |     4.01M |     87.91B |      1.33B |   1590 |  262.7k |  745.1k/  1.00M | 0.66 | 213.0k GPU gigasite 100% |     6 | Lab data-limited
 3h50 |    190.56M |     4.38M |     95.84B |      1.50B |   1593 |  311.8k |  883.3k/  1.00M | 0.66 | 262.1k GPU gigasite 100% |     6 | Lab data-limited
 3h50  !!! viral spike (capacity 1.52B, users 1.52B)
 3h58  >>> BEAT ClosedAI GPT-ish-5.5 "Tater" (2026)
 3h58  >>> BEAT Anthropomorphic Claudette Parable 5 (2026)
 3h58  >>> BEAT Gogol DeepThought Gemeni 4 Xenon (2026)
 3h58  >>> BEAT ClosedAI GPT-ish-6 Astral (2026)
 4h00 |    391.97M |     3.40M |     74.48B |      1.05B |   1630 |  311.8k |  883.3k/  1.00M | 0.66 | 262.1k GPU gigasite 100% |     6 | Lab data-limited
 4h05  !!! viral spike (capacity 1.10B, users 1.10B)
 4h10 |    973.36M |     3.62M |     79.22B |      1.14B |   1630 |  344.6k |  977.5k/  1.00M | 0.66 | 294.9k GPU gigasite 100% |     6 | Lab data-limited
 4h19  !!! viral spike (capacity 1.13B, users 1.13B)
 4h20 |    646.01M |     5.05M |    110.66B |      1.84B |   1631 |  344.6k |  977.5k/  2.00M | 0.66 | 294.9k GPU gigasite 100% |     6 | Lab data-limited
 4h30 |    566.92M |     3.89M |     85.26B |      1.27B |   1631 |  393.7k |   1.12M/  2.00M | 0.66 | 344.1k GPU gigasite 100% |     6 | Lab data-limited
 4h40 |    481.70M |     4.16M |     91.01B |      1.39B |   1633 |  442.9k |   1.25M/  2.00M | 0.66 | 393.2k GPU gigasite 100% |     6 | Lab data-limited
 4h50 |    606.40M |     4.40M |     96.47B |      1.52B |   1634 |  492.0k |   1.39M/  2.00M | 0.66 | 442.4k GPU gigasite 100% |     6 | Lab data-limited
 5h00 |     57.20M |     4.67M |    102.28B |      1.65B |   1636 |  557.6k |   1.58M/  2.00M | 0.66 | 507.9k GPU gigasite 100% |     6 | Lab data-limited
 5h10 |    410.86M |     4.94M |    108.28B |      1.79B |   1637 |  606.7k |   1.72M/  2.00M | 0.66 | 557.1k GPU gigasite 100% |     6 | Lab data-limited
 5h18  !!! viral spike (capacity 1.90B, users 1.90B)
 5h20 |    409.31M |     5.23M |    114.62B |      3.16B |   1638 |  672.3k |   1.90M/  2.00M | 0.66 | 622.6k GPU gigasite 100% |     6 | Lab OVERLOADED data-limited
 5h30 |      1.97B |     5.35M |    117.19B |      2.00B |   1639 |  705.0k |   1.99M/  2.00M | 0.66 | 655.4k GPU gigasite 100% |     6 | Lab data-limited
 5h40 |      5.17B |     5.32M |    116.56B |      1.99B |   1640 |  705.0k |   1.99M/  2.00M | 0.66 | 655.4k GPU gigasite 100% |     6 | Lab data-limited
 5h40  !!! viral spike (capacity 1.99B, users 1.99B)
 5h50 |    710.05M |     6.39M |    139.87B |      1.99B |   1675 |  705.0k |   1.99M/  2.00M | 0.66 | 655.4k GPU gigasite 100% |     6 | Lab data-limited
 5h58  !!! viral spike (capacity 1.99B, users 1.99B)
 6h00 |      4.77B |     9.92M |    217.14B |      4.05B |   1675 |  705.0k |   1.99M/  2.00M | 0.66 | 655.4k GPU gigasite 100% |     6 | Lab OVERLOADED data-limited

=== summary (balanced, template) ===
era Garage    0h00
era Startup   0h09
era Lab       0h45
rival  0h06  Hugging Hands Collective Tiny-Transformer (2017)
rival  0h09  ClosedAI GPT-ish-1 (2018)
rival  0h19  Gogol DeepThought BURT-Large (2018)
rival  0h23  ClosedAI GPT-ish-2 (2019)
rival  0h45  Gogol DeepThought Meenie (2020)
rival  0h47  ClosedAI GPT-ish-3 (2020)
rival  0h58  Mistrawl Mixtrawl 8x7B (2023)
rival  1h12  ClosedAI ChatGPT-ish (2023)
rival  1h18  ClosedAI GPT-ish-4 (2023)
rival  1h20  Anthropomorphic Claudette 3.5 Sonata (2024)
rival  1h20  DeepSleep DeepSleep-R1 (2025)
rival  1h42  Anthropomorphic Claudette 3.7 Sonata (2025)
rival  1h57  ClosedAI o-three (2025)
rival  2h03  yAI Grokk 3 (2025)
rival  2h16  ClosedAI GPT-ish-4.5 (2025)
rival  3h00  ClosedAI GPT-ish-5 (2025)
rival  3h16  Gogol DeepThought Gemeni 3 Pro (2025)
rival  3h26  MetaMind Labs Amused Spark (2026)
rival  3h58  ClosedAI GPT-ish-5.5 "Tater" (2026)
rival  3h58  Anthropomorphic Claudette Parable 5 (2026)
rival  3h58  Gogol DeepThought Gemeni 4 Xenon (2026)
rival  3h58  ClosedAI GPT-ish-6 Astral (2026)
rivals beaten: 22/22; upgrades: 29/29; releases: 47; viral spikes: 14
overloaded 8.9% of the time (3.8% during viral spikes); longest stretch without a purchase/release: 9.5 min (from  2h38)
at the final rival: 1.48B users, ARR 75.34B, 1.10M H100-equivalents, 883 MW
longest gap between rival wins: 44 min
max users 4.05B (cap 5.00B); final money 4.77B, ARR 217.14B; power 1.99M kW; H100e 2.49M
```
