# Model design

The player's idea: research unlocks *choices* you make when you build a model, not only
flat percentage boosts. Game Dev Tycoon's development stages are the reference.

Code: `lib/sim/model_design.dart` (pure Dart), `lib/ui/model_design/run_setup.dart`
(`RunSetupPanel`), `lib/ui/model_design/benchmark_strip.dart` (`BenchmarkStrip`).
Tests: `test/sim/model_design_test.dart`, `test/ui/run_setup_test.dart`.
Sources for every number: `docs/research/model_choices.md` (section numbers below refer to it).
**Design** marks a game number with no direct paper source.

## Principles
- There is no dominant pick. Every option has a cost that depends on the player's hardware
  (cluster size, network tier, data budget, serving capacity), which ties the grid to model design.
- Each option has a one-line, technically accurate blurb, and each effect an explanation line
  with a paper reference (short title + year).
- The game remembers the last setup (`ModelSpec` JSON), so starting a run stays one tap.
- The release card shows the benchmark profile and a headline such as "Code-heavy mix won
  coding" or "RL reasoning won math" (`strengthHeadline`).

## How effects combine

`evaluate(ModelSpec, DesignContext) → DesignEffects`. All terms are multiplicative except the
flat post-training rating.

```
effC       = dataLimited(C × cem / trainCostMult, dataTokens × dataBudgetMult)
rating     = ratingOf(effC) + ratingAdd            (Δ from cem alone = 23·log2(cem))
perUser    = perUserTflops(...) × serveCostMult
demand     = demand × demandMult
```

`C` is raw FLOPs × `Game.trainEffMult`. `dataLimited` is the existing Chinchilla-style limit
(`chinchillaK`, `dataLimitedExponent`). `ratingDelta` is the prediction against a plain run on the
same compute, including the data limit when `DesignContext.plannedCompute` is set.

The baseline (all multipliers 1.0, ratingAdd 0) is: dense, MHA, 4k, 20 tokens/param, a mix
with no code/books bonus, SFT, FP16. `ratingAdd` is reported relative to SFT, since the starting
model is already fine-tuned.

## Rules and numbers

### Model size vs training length (§1)
| Option | tok/param | Unlock | CEM | Δrating | Serving | Data budget |
|---|---|---|---|---|---|---|
| Big & short | 2 | — | 0.64 | −15 | ×3.16 | ×3.16 |
| Kaplan-style | 6 | — | 0.88 | −4 | ×1.83 | ×1.83 |
| Compute-optimal | 20 | `chinchilla_scaling` | 1.00 | 0 | ×1 | ×1 |
| Over-trained | 200 | `overtraining` | 0.64 | −15 | ×0.32 | ×0.32 |
| Edge model | 1000 | `overtraining`, Big lab | 0.27 | −43 | ×0.14 | ×0.14 |

`CEM = exp(−0.45·log10(r/20)²)` (fit to the Epoch refit of Chinchilla), `SERVE = sqrt(20/r)`
(N ∝ sqrt(C/r)). Tokens needed are `D = sqrt(C·r/6)`, so the data budget scales by `sqrt(20/r)`:
big & short eases the data wall, over-training hits it. A "Data wall" note fires when the run
wants more unique tokens than you have.

### Architecture (§2)
| Option | Unlock | CEM (fabric) | Serving (memory) |
|---|---|---|---|
| Dense | — | 1 | ×1 |
| MoE 8–16 experts | `moe` | 2 | ×1.2 |
| Fine-grained MoE | `fine_grained_moe` | 3 | ×1.35 |

Network gate: `CEM_eff = (1 + (CEM − 1) × gain) × commEff`.

| Network class (`networkGpuCap`) | gain | commEff | MoE / fine CEM |
|---|---|---|---|
| Ethernet (< 1024, i.e. ≤ 100G) | 0.25 | 0.6 | 0.75 / 0.90 (worse than dense) |
| InfiniBand (1024–32767) | 0.6 | 0.9 | 1.44 / 1.98 |
| Fat-tree / NVLink (≥ 32768) | 1.0 | 1.0 | 2.0 / 3.0 |

A badly oversubscribed cluster (`clusterGpus > 2 × networkGpuCap`, scaling efficiency below
~70%) drops one class; mild oversubscription only costs the game's scaling efficiency. commEff is Design,
from DeepSeek-V3's ~1:1 compute:communication ratio. Without `router_balancing` there is a 25%
**routing-collapse** risk (a `DesignRisk` the game rolls) that drops the MoE CEM to 1.2.

### Attention (§3)
| Option | Unlock | CEM | Serving | KV growth per context tier | Long-context strength |
|---|---|---|---|---|---|
| Full (MHA) | — | 1.00 | ×1 | ×1.4 | ×1 |
| GQA | `gqa` | 0.99 | ×0.7 | ×1.15 | ×1 |
| Sliding window | `sliding_window` | 0.96 | ×0.6 | ×1.05 | ×0.8 |
| Hybrid SSM | `ssm_hybrid` | 1.02 | ×0.5 | ×1.03 | ×0.92 |

### Context length (§4)
Tiers: 2k (−1), 4k (0), 8k (1), 32k (2), 128k (3), 1M (4).

| Option | Unlock | Training | Demand (full effectiveness) |
|---|---|---|---|
| 2k | — | ×1 | ×0.92 |
| 4k | Startup era | ×1 | ×1 |
| 8k | `flash_attention` | ×1.06 | ×1.08 |
| 32k | `rope_scaling` | ×1.12 | ×1.24 |
| 128k | `yarn` | ×1.18 | ×1.40 |
| 1M | `long_context` + `yarn` | ×1.24 | ×1.64 |

- `DEMAND = 1 + 0.08 × log2(ctx/4k) × eff`, `TRAIN = 1 + 0.06 × tier`,
  `SERVE = kvGrowth(attention)^tier`. Long-context strength `1 + 0.25 × tier × eff`.
- Effectiveness: 1 up to 8k. At 32k: 0.5 without `long_data`, 0.8 with it, 1 with it and `yarn`.
  At 128k+: 0.25 without `long_data`, 1 with it.
- **Long context without long data**: CEM ×0.95 at 32k, ×0.9 at 128k+ (RULER, Fu 2024).
- **Long context on MHA**: 1M serves ×3.8 vs ×1.75 on GQA.

### Data mix (§5)
| Preset | web/code/books/synthetic | Unlock | CEM | Coding | Data budget |
|---|---|---|---|---|---|
| Web crawl | 90/5/5/0 | — | 1.03 | ×1.0 | ×1 |
| Web + code | 70/25/5/0 | `code_data` | 1.11 | ×1.57 | ×1 |
| Balanced | 60/20/20/0 | `code_data`, `books_papers` | 1.13 | ×1.43 | ×1 |
| Code-heavy | 30/55/15/0 | `code_data` | 1.13 | ×2.43 | ×1 |
| Synthetic-augmented | 40/20/15/25 | `synthetic_data` | 1.12 | ×1.43 | ×1.17 |
| Mostly synthetic | 15/10/5/70 | `synthetic_data` | 0.74 | ×1.03 | ×2.17 |

- `CEM_code = 1 + 0.4 × min(code, 0.3)`, ×`(1 − 0.6 × (code − 0.5))` past 50% code (knowledge
  and chat penalty). `CEM_books = 1 + 0.25 × min(books, 0.2)` (Design).
- Synthetic tokens count at half value on top of the real pool:
  `budget × (1 + 0.5 × s/(1 − s))`. Helpful only when data-limited.
- **Model collapse** (synthetic > 50%, replacing real data): CEM ×0.7, demand ×0.9, chat ×0.75.

### Post-training (§7)
| Method | Unlock | Rating (vs SFT) | Train | Serving | Demand |
|---|---|---|---|---|---|
| Base model | — | −60 | ×1 | ×1 | ×0.3 |
| SFT | — | 0 (absolute +60) | ×1.01 | ×1 | ×1 |
| RLHF | `rlhf` | +70·g(x) | +4%·k | ×1 | ×(1 + 0.1·g) |
| DPO | `dpo` | +63·g(x), d* ×0.8 | +1.2%·k | ×1 | ×(1 + 0.1·g) |
| RL reasoning | `reasoning` | +50 + 70·g(x) | +14%·k | ×6 (×2.5 with `adaptive_thinking`) | ×1.25 (and ×(1 + 0.1·g)) |

- **RL strength** k ∈ {0.5, 1, 1.5, 2, 3} × the reward model's sweet spot d*. `x = k/d*`,
  `g(x) = x(1 − ln x)` (Gao 2022, normalised): g(1) = 1, g(0.5) = 0.85, g(2) = 0.61,
  g(3) = −0.30, so **Extreme RL is worse than plain SFT** (reward hacking).
- `reward_model_scaling` moves d* to 1.5 and raises the bonus by 15%.
- **Alignment tax** (without `ppo_ptx`): `−15 × (1 − min(1, N/50B))`, N = sqrt(C/(6r)).
- RL reasoning: math ×3, coding ×2; the +50 is halved if the base model is below rating 1000.
  Answers are often ~10× longer (Chen 2024), but not every request needs long thinking: ×6
  serving is the game's blend (Design), and +50 replaces the old flat +60 reasoning upgrade.

### Serving precision (§8)
| Option | Unlock | Serving | CEM |
|---|---|---|---|
| FP16 | — | ×1 | 1 |
| INT8 | `quantization` | ×0.55 | 1 |
| INT4 | `int4_weights` | ×0.35 | `0.97 − 0.08 × max(0, log10(r/20))` |

**INT4 on an over-trained model**: 0.89 at r = 200, 0.83 at r = 1000 (Kumar 2024). The doc's
0.03 slope was steepened to 0.08 so the mistake is visible.

### Benchmark profile
Relative strengths (1.0 = dense SFT on the web mix): coding `(0.6 + 2·code)/0.7`, math
`(0.7 + 0.8·code + 0.8·books + 0.4·synthetic)/0.78`, chat (post-training, code > 30% and
collapse penalties), long context (see above). Reasoning multiplies math and coding.

### Bot auto-pick
`ModelSpec.bestGuessFor(ctx)` runs coordinate ascent (3 passes over all slots) on
`designScore = ratingDelta + 30·log2(demand) − 6·log2(serve) + E[risk]`. Raise `serveWeight`
when capacity-limited, so the bot picks over-training or INT4.

## Run phases (mid-run decisions)
Game Dev Tycoon's development stages, for training runs. Code: `lib/sim/run_phases.dart`
(pure Dart), `lib/ui/model_design/run_phases_ui.dart` (`PhaseDecisionCard`, `PhaseTrack`,
`PhaseChoicesLine`, `EarlyFocusPicker`). Tests: `test/sim/run_phases_test.dart`,
`test/ui/run_phases_test.dart`.

A run has three phases. The early data emphasis is picked in the run setup ("Data mix" row).
The other two are **checkpoints** at fixed fractions of the run (1/3 and 2/3, so they
survive pacing changes). At a checkpoint the run holds (no compute is added) and the
checkpoint card asks once, so there are at most 2 prompts per run. With no answer the default
lands after `phaseDecisionTimeout` (10 s of sim time). Offline it lands at once, so a
checkpoint never blocks offline progress.

| Phase | Option | Benchmarks | Rating | Demand | Serving | Source |
|---|---|---|---|---|---|---|
| Early mix | **Web** | chat ×1.06, coding/math ×0.97 | | | | FineWeb, Penedo 2024 |
| | Code | coding ×1.2, math ×1.05, chat ×0.95 | | | | To Code, or Not To Code, Aryabumi 2024 |
| | Math | math ×1.25, coding ×1.03, chat ×0.95 | | | | DeepSeekMath, Shao 2024 |
| Annealing (1/3) | **Quality data** | coding, math, chat ×1.04 | | | | MiniCPM (WSD), Hu 2024 |
| | Long context | long context ×1.3 | −1 | ×1.04 | ×1.03 | Effective Long-Context Scaling, Xiong 2023 |
| | Reasoning | math ×1.2, coding ×1.1, chat ×0.96 | +1 | ×0.97 | | Llama 3 Herd of Models, Dubey 2024 |
| Post-training (2/3) | **Helpful** | chat ×1.1 | | | | InstructGPT, Ouyang 2022 |
| | Safety | chat ×0.94 | −3 | ×1.07 | | XSTest, Röttger 2023 |
| | Reasoning RL | math ×1.25, coding ×1.15, chat ×0.97 | +2 | | ×1.05 | DeepSeek-R1, 2025 |

All numbers are **Design**, set to the direction of the cited result.

- **Defaults** (bold) only shape the benchmark profile. The early default follows the design:
  a code-heavy mix gets Code and RL reasoning gets Math. A lab that never decides plays exactly
  as it did before run phases.
- **Balance**: on the bot's design score (`rating + 30·log2 demand − 6·log2 serve`) every
  option sits within about ±2 rating of zero. Over 10 casual-schedule seeds the bot finishes
  at a mean of ~61 h on the defaults and ~63 h when it specializes by what blocks it
  (`dart run tool/balance_sim.dart --phases`).
- **Effects** apply when the run ends (`applyPhases` on the `DesignOutcome`): strengths
  multiply, rating adds to `ratingAdd`, serving and demand multiply. `DesignOutcome.phases`
  carries the picks to the release. `phaseAwareHeadline` credits a phase when it, not the
  design, won the best benchmark ("Annealed on math & code won math").
- **Saves**: `TrainingRun` stores `phases`, `autoPhases` and `phaseWait`; `DesignOutcome` stores
  `phases`. All of them are optional, so older v4 saves load. An old in-flight run gets the
  early default and asks at the next checkpoint it has already passed.
- **Bot**: answers a checkpoint the tick it appears. By default it takes the defaults (with the
  early mix matched to its design). `Bot(specializePhases: true)` picks with `bestPhaseOption`,
  using the design weights; serving counts fully while it's capacity-limited.

## Research
New entries in `designUpgrades` (identity `Effects`; their value is the option they unlock):

| id | Name | Era | Cost | Track | Requires | Unlocks / changes |
|---|---|---|---|---|---|---|
| `gqa` | Grouped-query attention | Medium lab | 60M | Pre-training | — | GQA |
| `sliding_window` | Sliding-window attention | Medium lab | 110M | Pre-training | gqa | Sliding window |
| `rope_scaling` | RoPE position interpolation | Medium lab | 50M | Pre-training | flash_attention | 32k |
| `router_balancing` | Router load balancing | Medium lab | 90M | Pre-training | moe | removes collapse risk |
| `overtraining` | Inference-aware scaling | Medium lab | 40M | Pre-training | chinchilla_scaling | 200 / 1000 tok/param |
| `ppo_ptx` | Pre-training mix in RL | Medium lab | 80M | Post-training | rlhf | removes alignment tax |
| `long_data` | Long-document data | Medium lab | 90M | Data | — | long-context effectiveness |
| `int4_weights` | 4-bit weights (GPTQ/AWQ) | Medium lab | 100M | Infrastructure | quantization | INT4 |
| `yarn` | YaRN context extension | Big lab | 600M | Pre-training | rope_scaling | 128k (1M with long_context) |
| `fine_grained_moe` | Fine-grained experts | Big lab | 1.8B | Pre-training | moe | Fine-grained MoE |
| `ssm_hybrid` | Hybrid state-space layers | Big lab | 1.2B | Pre-training | gqa | Hybrid SSM |
| `dpo` | Direct Preference Optimization | Big lab | 500M | Post-training | rlhf | DPO |
| `reward_model_scaling` | Bigger reward models | Big lab | 900M | Post-training | rlhf | RL sweet spot ×1.5 |
| `adaptive_thinking` | Adaptive thinking budgets | Frontier lab | 12B | Post-training | reasoning | reasoning serving ×2.5 |

Existing ids reused as unlocks: `moe`, `chinchilla_scaling`, `flash_attention`, `long_context`,
`code_data`, `books_papers`, `synthetic_data`, `rlhf`, `reasoning`, `quantization`.

`ResearchTrack` (preTraining, postTraining, data, infrastructure) and `researchTracks` map
every id in `upgrades` and `designUpgrades` to a track (`trackOf(id)`).
`optionsUnlockedBy(id)` and `designResearchModifiers` give the "Unlocks: ..." text for cards.

## Integration (wired in)

### State (`lib/sim/game_state.dart`)
- `GameState.lastSpec`: the setup the last run used (`'spec'`); the next run starts from it, so
  "Start training" stays one tap.
- `TrainingRun.spec`: fixed when the run starts.
- `DesignOutcome` (spec, `ratingAdd`, `serveCostMult`, `demandMult`, `serveCompute`, `strengths`,
  `highlights`): evaluated when the run ends, kept on `GameState.pendingDesign` and then on
  `ModelRelease.design`, so serving and demand follow the *current* model. The starting model has
  none and counts as the garage default design (`Game.startDesign`).
- Saves stay v4: every new field is optional; `ownedUpgrades` accepts `designUpgrades` ids.

### Game (`lib/sim/game.dart`)
- Effects iterate `allUpgrades` (`upgrades` + `designUpgrades`).
- `designContext` / `designContextFor(rawFlops)`: cluster GPUs, `networkCap` (the network tier's GPU
  cap; all GPUs in the room are one cluster), data tokens, research, era, planned compute.
- `startTraining({fraction, durationSeconds, ModelSpec? spec})`: default `lastSpec`, clamped to
  what's unlocked.
- Run end: `evaluate(run.spec, ...)`, risks rolled with the seeded RNG (a hit multiplies effective
  compute and is reported in `TrainingFinished.mishaps`), effective compute through the design's
  data budget.
- `rating` / `pendingRating` add the design's `ratingAdd`; `demand` × `demandMult`;
  `currentPerUserTflops` = `perUserTflops(serveCompute) × serveCostMult` (a smarter design isn't a
  bigger model).
- `predictRating(fraction, duration, {spec})`, `predictRatingForFlops(flops, spec)`,
  `isDataLimited(flops, spec)`.
- The `moe`, `chinchilla_scaling`, `quantization`, `long_context` and `reasoning` upgrades are now
  unlock-only (identity effects); `rlhf` keeps only its ARPU (its rating is the RLHF choice).
- `servingBase` 0.0115 and `demandBase` 98 absorb the garage default's ×1.30 serving and ×0.92
  demand, so the start of the game plays as before.

### UI
- Training panel (`lib/ui/screens/overview_screen.dart`): a "Model design" summary row (spec and
  headline serving/demand, warnings count) opens `RunSetupPanel`; the predicted rating uses the
  spec. The run card names the spec; the "Training complete" card shows highlights and a
  `BenchmarkStrip`.
- Release dialog (`lib/ui/moments/release_card.dart`): `BenchmarkStrip` with `strengthHeadline`
  under the share card; the headline also goes in the post text.
- Research (`lib/ui/screens/research_screen.dart`): tabs by `ResearchTrack` (plus "Available now");
  cards list "Run setup · <slot>: <option>" from `optionsUnlockedBy` / `designResearchModifiers`.

### Bot (`lib/sim/bot.dart`)
`ModelSpec.bestGuessFor(ctx, serveWeight: w)` with `w` by what blocks progress: 4 (and demand
weight 8) when rating blocks an era gate or rival, 23 when capacity-limited, else 6. When a rival
needs users and we already have its rating, the cheapest-to-serve setup that still clears it. It
spends before starting a run (a run's design is fixed at the start), values design research by the
rating it unlocks while rating blocks, counts risks at their expected rating, and ships a cheaper
model that keeps the rival's rating when users are what's missing. `Bot(fixedSpec:)` /
`runSchedule(fixedSpec:)` force one design (the bad-design test).
