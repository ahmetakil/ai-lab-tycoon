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

An oversubscribed cluster (`clusterGpus > networkGpuCap`) drops one class. commEff is Design,
from DeepSeek-V3's ~1:1 compute:communication ratio. Without `router_balancing` there is a 25%
**routing-collapse** risk (a `DesignRisk` the game rolls) that drops the MoE CEM to 1.2.

### Attention (§3)
| Option | Unlock | CEM | Serving | KV growth per context tier | Long-context strength |
|---|---|---|---|---|---|
| Full (MHA) | — | 1.00 | ×1 | ×1.4 | ×1 |
| GQA | `gqa` | 0.99 | ×0.5 | ×1.15 | ×1 |
| Sliding window | `sliding_window` | 0.96 | ×0.4 | ×1.05 | ×0.8 |
| Hybrid SSM | `ssm_hybrid` | 1.02 | ×0.35 | ×1.03 | ×0.92 |

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
| RL reasoning | `reasoning` | +40 + 70·g(x) | +14%·k | ×10 (×4 with `adaptive_thinking`) | ×1.25 (and ×(1 + 0.1·g)) |

- **RL strength** k ∈ {0.5, 1, 1.5, 2, 3} × the reward model's sweet spot d*. `x = k/d*`,
  `g(x) = x(1 − ln x)` (Gao 2022, normalised): g(1) = 1, g(0.5) = 0.85, g(2) = 0.61,
  g(3) = −0.30, so **Extreme RL is worse than plain SFT** (reward hacking).
- `reward_model_scaling` moves d* to 1.5 and raises the bonus by 15%.
- **Alignment tax** (without `ppo_ptx`): `−15 × (1 − min(1, N/50B))`, N = sqrt(C/(6r)).
- RL reasoning: math ×3, coding ×2; the +40 is halved if the base model is below rating 1000.

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
| `adaptive_thinking` | Adaptive thinking budgets | Frontier lab | 12B | Post-training | reasoning | reasoning serving ×4 |

Existing ids reused as unlocks: `moe`, `chinchilla_scaling`, `flash_attention`, `long_context`,
`code_data`, `books_papers`, `synthetic_data`, `rlhf`, `reasoning`, `quantization`.

`ResearchTrack` (preTraining, postTraining, data, infrastructure) and `researchTracks` map
every id in `upgrades` and `designUpgrades` to a track (`trackOf(id)`).
`optionsUnlockedBy(id)` and `designResearchModifiers` give the "Unlocks: ..." text for cards.

## Integration

Everything lives in new files. Wiring it in is a small diff:

### `lib/sim/game_state.dart`
1. `GameState`: add `ModelSpec lastSpec` (default `const ModelSpec()`), saved as `'spec'` with
   `lastSpec.toJson()`, loaded with `ModelSpec.fromJson` (tolerant; missing = default).
2. `TrainingRun`: add `final ModelSpec spec` (JSON key `'spec'`, default `const ModelSpec()`).
3. Store the finished run's spec until release: `ModelSpec? pendingSpec` next to
   `pendingEffectiveCompute` (key `'pendingSpec'`).
4. `ModelRelease`: add `ModelSpec spec` and `BenchmarkStrengths strengths` (keys `'spec'`,
   `'bench'`, both optional on load), plus `double serveCostMult` and `double demandMult`
   (keys `'serve'`, `'demand'`, default 1) so serving and demand follow the *current* model.
5. `fromJson`: accept `designUpgrades` ids in `ownedUpgrades` (the filter currently uses
   `upgrades` only).

No save-version bump is needed: every new field defaults.

### `lib/sim/game.dart`
1. `_effects` and `buyUpgrade`/`canBuyUpgrade`: iterate `[...upgrades, ...designUpgrades]`
   (or add `allUpgrades` to content.dart).
2. Add `DesignContext get designContext => DesignContext(clusterGpus: grid.training?.gpus ?? 0,
   networkGpuCap: grid.training?.gpuCap ?? 0, dataTokens: dataTokens, ownedResearch:
   s.ownedUpgrades, eraIndex: s.era.index, plannedCompute: <raw FLOPs of a default run> ×
   trainEffMult)`. Use whatever the new grid exposes as the bottleneck switch's GPU cap.
3. `startTraining({..., ModelSpec? spec})`: `spec = (spec ?? s.lastSpec).clampTo(designContext)`,
   store it on the run and in `s.lastSpec`.
4. Run end (`tick`): replace `effectiveComputeOf(run.computeFlops)` with
   `evaluate(run.spec, designContext).effectiveCompute(run.computeFlops * trainEffMult, dataTokens)`.
   Roll `effects.risks` with `_random()`; on a hit multiply effC by `risk.cemMultOnHit` and emit
   an event (e.g. "Router collapse: half the experts idle").
5. `release`: rating = `ratingOf(effC) + effects.ratingAdd`; store spec, strengths, serve and
   demand multipliers on the `ModelRelease`.
6. `perUserTflops`: multiply by `currentModel.serveCostMult`. Feed it the effC without the design
   CEM (`effC / cem`, or store the raw size) so a smarter design doesn't also look bigger.
7. `demand`: multiply by `currentModel.demandMult`.
8. `predictRating(fraction, duration, {ModelSpec? spec})`: same formula as step 4 plus `ratingAdd`.
9. **Avoid double counting.** Set these existing upgrade effects to identity, because the design
   choice now carries them: `moe` (trainEff 2.5, serve 1.5), `chinchilla_scaling` (trainEff 1.3),
   `quantization` (serve 2), `long_context` (rating 10, ARPU 1.25: keep ARPU if wanted),
   `reasoning` (rating 60, serve 0.6). Keep `instruction_tuning`, `rlhf`, `rlaif` and the data
   upgrades as they are, or retune. Then run `dart run tool/balance_sim.dart 240`: expect an early
   ~−4 rating and ×1.3 serving (Kaplan-style 2k model) and a bigger post-training swing later.

### Training panel
Show `RunSetupPanel(spec: draft, ctx: game.designContext, onChanged: setDraft)` above the
fraction/duration controls, seeded with `game.s.lastSpec.clampTo(ctx)`. Start the run with
`controller.act((g) => g.startTraining(fraction: f, durationSeconds: d, spec: draft))`.
Keep it collapsible ("Model design ▸") so a run stays one tap. The panel lays out side by side at
≥ 900 px (`runSetupWideBreakpoint`).

### Release card
Add `BenchmarkStrip(strengths: release.strengths, headline: strengthHeadline(release.spec,
release.strengths))` under the existing cherry-picked benchmarks (`lib/ui/moments/release_card.dart`),
and optionally `Tag`s for the spec (e.g. "MoE", "128k", "RL reasoning").

### Bot (`lib/sim/bot.dart`)
Pass `spec: ModelSpec.bestGuessFor(game.designContext, serveWeight: overloaded ? 15 : 6)` to
`startTraining`, and include the `designUpgrades` in its research candidates. Value them through
the CEM of the option they unlock, e.g. `designScore` of `bestGuessFor` with the id added to
`ownedResearch` minus without.

### Research screen (`lib/ui/screens/research_screen.dart`)
Tab by `ResearchTrack.values` (`trackOf(u.id)`) over `[...upgrades, ...designUpgrades]`. For a
design upgrade, show "Unlocks: <option labels>" from `optionsUnlockedBy(u.id)`, or
`designResearchModifiers[u.id]`, in place of the effects line.
