# Model-design choices: what the literature says, and game rules

Compiled 2026-11-11 for the model-design pass in `docs/MODEL_DESIGN.md`. Each section lists the
options a player can pick, what papers report, the failure modes of bad picks, and a proposed rule.
Figures quoted from a paper were checked against the arXiv abstract or full text. **Derived**
means my own arithmetic from a paper's fitted formula. **Design** means a game number with no
direct paper source, picked to fit the direction of the evidence.

## How to plug these into the current sim

The sim already scores a model as `rating = ratingBase + ratingPerDoubling * log2(effC / 1e18)`
(`lib/sim/balance.dart`, 23 rating per doubling). Most papers report gains as "the same loss with X×
less compute", so the cleanest shared unit is a **compute-equivalent multiplier (CEM)**:

```
effC_final = rawFLOPs × MFU × Π(CEM_i)          Δrating = 23 × log2(Π CEM_i)
servingPerUser = existing formula × Π(SERVE_i)   (FLOPs per token and memory per user)
demand        = existing formula × Π(DEMAND_i)
```

So a CEM of 2.0 is worth +23 rating, and a CEM of 0.5 costs −23. Each rule below gives its CEM,
SERVE and DEMAND terms, plus any training-time (TRAIN) or hardware gate.

---

## 1. Model size vs training tokens

**Options (in order):** "Big & short" (~2–5 tokens/param, GPT-3 era) → **Compute-optimal**
(~20 tokens/param) → "Over-trained" (~100–200) → "Edge model" (1,000+).

**Literature**
- Kaplan et al. fit `N_opt ∝ C^0.73`: spend most new compute on parameters and stop well before
  convergence. GPT-3 (175B, 300B tokens, ~1.7 tok/param) followed this.
- Hoffmann et al. ("Chinchilla") found N and D should scale equally, at about 20 tokens/param.
  Chinchilla (70B, 1.4T tokens) used the same compute as Gopher (280B, 300B tokens) and beat it
  "uniformly and significantly"; its MMLU score of 67.5% was more than 7 points above Gopher's.
- The gap is mostly explained by methodology: Kaplan counted non-embedding parameters, used small
  models, and didn't tune warmup or the LR schedule per run (Pearce 2024; Porian 2024).
- Chinchilla's parametric fit (Approach 3) is contested. Besiroglu et al. (Epoch) refit it as
  `L = 1.8172 + 482.01/N^0.3478 + 2085.43/D^0.3658`, which implies ~20 tok/param and agrees with
  Chinchilla's other two methods. The original fit implied ~70 tok/param.
- Over-training is deliberate when inference matters. Llama 3 trained its smaller models "much
  longer than is compute-optimal" on ~15T tokens (~1,900 tok/param for 8B). Sardana et al. show
  that with ~1B+ requests, smaller-and-longer is cheaper overall, and quality keeps improving out
  to 10,000 tok/param. Gadre et al. show over-trained runs stay predictable (they predicted a run
  32× over-trained).

**Iso-compute valley (derived from the Epoch fit at 1e23 FLOP):** this is the share of compute that
is "useful" compared with a compute-optimal run of the same size.

| tokens/param | 1 | 2 | 5 | 10 | 20 | 50 | 100 | 200 | 500 | 1000 |
|---|---|---|---|---|---|---|---|---|---|---|
| efficiency | 0.47 | 0.64 | 0.85 | 0.96 | 1.00 | 0.92 | 0.79 | 0.62 | 0.41 | 0.28 |

The valley is flat near the optimum (5–50 costs ≤15%) and steep at the extremes.

**Bad choices:** under-training wastes up to half the compute (the Gopher/GPT-3 failure). Extreme
over-training also needs D = r·N tokens, which hits the data wall (§5) and makes the model harder
to quantize (§8, Kumar 2024).

**Game rule**
- `CEM_size = exp(−0.45 × (log10(r / 20))²)`, where r is tokens per parameter. This fits the table
  within ~5% from r = 1 to 2,000.
- `SERVE_size = sqrt(20 / r)`: at fixed compute N ∝ sqrt(C / r), and serving FLOPs ∝ N. So r = 200
  serves about 3.2× cheaper and costs about 0.62× CEM (≈ −16 rating).
- Tokens needed = r × N. If that exceeds the data budget, apply the repetition rule in §5.
- This is the core "no dominant pick" lever: frontier labs with weak serving pick 20, and
  serving-limited labs pick 100–200.

Sources: Kaplan 2020 [2001.08361](https://arxiv.org/abs/2001.08361); Hoffmann 2022
[2203.15556](https://arxiv.org/abs/2203.15556); Besiroglu 2024 [2404.10102](https://arxiv.org/abs/2404.10102);
Pearce 2024 [2406.12907](https://arxiv.org/abs/2406.12907); Porian 2024 [2406.19146](https://arxiv.org/abs/2406.19146);
Sardana 2023 [2401.00448](https://arxiv.org/abs/2401.00448); Gadre 2024 [2403.08540](https://arxiv.org/abs/2403.08540);
Grattafiori (Llama 3) 2024 [2407.21783](https://arxiv.org/abs/2407.21783).

---

## 2. Dense vs Mixture-of-Experts

**Options:** Dense → coarse MoE (8–16 experts, top-1 or top-2: Switch, GShard, Mixtral) →
fine-grained MoE with shared experts (DeepSeekMoE, DeepSeek-V3: 256 routed experts, 8 active).

**Literature (quality per FLOP)**
- Switch Transformer: "up to 7× increases in pre-training speed with the same computational
  resources" over T5-Base and T5-Large, and a 4× speedup over T5-XXL at the trillion-parameter scale.
- GShard: a 600B-parameter MoE translation model trained on 2,048 TPU v3 chips in 4 days.
- Mixtral 8x7B has 47B total and 13B active parameters, and matches or beats Llama 2 70B
  (~5× fewer active parameters).
- DeepSeekMoE 16B matches LLaMA2 7B at "about 40% of computations" (≈2.5×). At 145B it matches
  DeepSeek 67B at 28.5% of the compute (≈3.5×).
- DeepSeek-V3 has 671B total and 37B active parameters, trained in 2.788M H800 GPU-hours.
- **Contested:** how the gain scales. Clark 2022 fit unified routed scaling laws, and Krajewski 2024
  found the dense/MoE gap *widens* with scale for fine-grained MoE. A CEM of ~2–4× for modern MoE is
  a fair middle reading. The 7× Switch figure is a best case at small scale.

**Costs**
- *Memory:* all experts must sit in memory, so serving memory scales with total parameters
  (Mixtral ×3.6 vs active; V3 ×18). Serving FLOPs scale with *active* parameters.
- *Network:* expert parallelism needs all-to-all traffic. In DeepSeek-V3, cross-node expert traffic
  gave "an inefficient computation-to-communication ratio of approximately 1:1". They capped each
  token at 4 nodes because NVLink (160 GB/s) is ~3.2× faster than their InfiniBand (50 GB/s), and
  wrote DualPipe to hide the traffic.

**Bad choices / failure modes**
- *Routing collapse:* the router converges onto a few experts (Shazeer 2017). Fixes are auxiliary
  balance losses (Switch, GShard) or DeepSeek-V3's auxiliary-loss-free bias.
- *Token dropping:* experts have a capacity factor, and overflow tokens skip the layer. A higher
  capacity factor wastes compute and memory (Switch).
- *Instability and poor fine-tuning:* ST-MoE adds a router z-loss for stability and notes that
  sparse models fine-tune less reliably.

**Game rule**
- `CEM_moe`: Dense 1.0, coarse MoE 2.0, fine-grained MoE 3.0.
- Serving FLOPs follow *active* parameters, so per-user FLOPs stay about the same as the dense
  model of the same training compute. `SERVE_memory` is ×3 (coarse) or ×6 (fine-grained), which
  caps users per server.
- Network gate: `CEM_moe_eff = 1 + (CEM_moe − 1) × netFactor`, with netFactor 0.25 on Ethernet,
  0.6 on basic InfiniBand and 1.0 on a full fat-tree or NVLink domain (Design, from the ~1:1
  comm/compute ratio).
- Load balancing: until the "router balancing" research is done, each MoE run has a 25% chance
  of a *routing collapse* event that drops `CEM_moe` to 1.2 (Design). Research removes the risk.

Sources: Shazeer 2017 [1701.06538](https://arxiv.org/abs/1701.06538); Lepikhin 2020
[2006.16668](https://arxiv.org/abs/2006.16668); Fedus 2021 [2101.03961](https://arxiv.org/abs/2101.03961);
Zoph 2022 [2202.08906](https://arxiv.org/abs/2202.08906); Clark 2022 [2202.01169](https://arxiv.org/abs/2202.01169);
Jiang 2024 [2401.04088](https://arxiv.org/abs/2401.04088); Dai 2024 [2401.06066](https://arxiv.org/abs/2401.06066);
Krajewski 2024 [2402.07871](https://arxiv.org/abs/2402.07871); DeepSeek-AI 2024 [2412.19437](https://arxiv.org/abs/2412.19437).

---

## 3. Attention variant

**Options:** Full MHA → MQA → GQA → (MLA) → sliding window → hybrid SSM/linear. FlashAttention is
a separate *kernel* upgrade, not an architecture choice.

**KV cache per token** = `2 × layers × kv_heads × head_dim × bytes`. A Llama 2 70B-shaped model
(80 layers, 64 query heads, head_dim 128, BF16) gives (derived):
MHA 2.5 MiB/token (320 GiB at 128k), GQA-8 320 KiB/token (40 GiB at 128k), MQA 40 KiB/token.

**Literature**
- MQA (Shazeer 2019): one shared K/V head makes decoding "much faster" with "only minor quality
  degradation".
- GQA (Ainslie 2023), T5-XXL: MHA averages 47.2 at 1.51 s inference; MQA 46.6 at 0.24 s; GQA-8 47.1
  at 0.28 s. That is MQA −0.6 points and GQA −0.1 for a ~5–6× faster decode. Converting an MHA
  checkpoint ("uptraining") costs 5% of the original pre-training compute.
- MLA (DeepSeek-V2) compresses K/V into a latent vector. Against DeepSeek 67B the KV cache shrinks
  93.3% and max throughput rises 5.76×. This is confounded with the MoE switch.
- Sliding window (Longformer; Mistral 7B, W = 4096): the cache stops growing at W. For 32k
  sequences that's "8× less cache memory, without impacting the model quality" (Mistral's claim).
  Distant tokens are reached only indirectly, through stacked layers.
- Mamba (SSM) has 5× higher inference throughput and linear scaling. Mamba-3B matches Transformers
  twice its size. But at 8B on 3.5T tokens, pure SSMs **lag on copying, in-context learning and
  long-context reasoning** (5-shot MMLU, phonebook) (Waleffe 2024; Jelassi 2024 proves the copying
  gap). A hybrid (43% Mamba-2, 7% attention, 50% MLP) beats the 8B Transformer by +2.65 points on
  average and is predicted to generate up to 8× faster.
- FlashAttention is **exact** (identical outputs) and IO-aware: 3× on GPT-2 training and +15% on
  BERT-large. FlashAttention-2 is another 2–4× over baselines. It changes speed and memory only.

**Bad choices:** pure MQA at scale gives small quality losses (and training instability, per
Ainslie). A pure SSM or linear model collapses on retrieval-heavy tasks; tie that to "long-context
demand". Sliding window alone weakens long-range recall.

**Game rule**

| Option | CEM | SERVE (cost per user) | Notes |
|---|---|---|---|
| MHA | 1.00 | 1.00 | baseline |
| MQA | 0.95 | 0.45 | quality small hit |
| GQA | 0.99 | 0.50 | the sensible default once researched |
| MLA | 0.99 | 0.35 | late research |
| + sliding window | 0.97 | ×0.8, and KV no longer grows with context | |
| SSM hybrid | 1.02 | 0.35, KV ~constant | −10% "long-context recall" sub-score unless ≥7% attention layers |
| Pure SSM/linear | 0.95 | 0.25 | long-context demand bonus halved |

SERVE values are Design, scaled from the 5–8× decode speedups. Decoding is memory-bandwidth bound,
so cost tracks KV size only partially. FlashAttention: `MFU × 1.3` (v1), `× 1.6` (v2+) on training
and prefill. No rating effect.

Sources: Shazeer 2019 [1911.02150](https://arxiv.org/abs/1911.02150); Ainslie 2023
[2305.13245](https://arxiv.org/abs/2305.13245); DeepSeek-AI 2024 [2405.04434](https://arxiv.org/abs/2405.04434);
Beltagy 2020 [2004.05150](https://arxiv.org/abs/2004.05150); Jiang 2023 [2310.06825](https://arxiv.org/abs/2310.06825);
Gu 2023 [2312.00752](https://arxiv.org/abs/2312.00752); Waleffe 2024 [2406.07887](https://arxiv.org/abs/2406.07887);
Jelassi 2024 [2402.01032](https://arxiv.org/abs/2402.01032); Dao 2022 [2205.14135](https://arxiv.org/abs/2205.14135);
Dao 2023 [2307.08691](https://arxiv.org/abs/2307.08691).

---

## 4. Context length

**Options:** 2k → 4k → 8k → 32k (RoPE scaling) → 128k (long-context continued pre-training) → 1M.

**Literature**
- *Training cost:* Kaplan's per-token forward FLOPs are `2N + 2·n_layer·n_ctx·d_attn`, so attention
  adds about `n_ctx / (12·d_model)` on top of the 6N cost (derived; causal masking roughly halves
  it). At d_model = 8192 that is +4% at 4k and ~+130% at 128k. That's why labs train short and
  extend late: Llama 3 went 8K→128K in six stages on ~800B of its 15.6T tokens.
- *Extension methods:* Position Interpolation extends RoPE models to 32k "within 1000 steps".
  Naive extrapolation can "completely ruin" attention. YaRN needs 10× fewer tokens and 2.5× fewer
  steps than earlier methods. Fu et al.: 0.5–5B tokens of continued pre-training reach 128k
  retrieval, *if* the data is domain-balanced and length-upsampled. Only upsampling books is
  suboptimal.
- *Using the context:* "Lost in the middle": accuracy is U-shaped by position. GPT-3.5-Turbo
  dropped by more than 20%, and with the answer mid-context it scored below closed-book (56.1%).
  RULER: of 17 models all claiming ≥32k, only half performed satisfactorily at 32k.
- *Serving:* the KV cache grows linearly with context (§3), so long-context users take far more
  memory.

**Bad choices:** advertising a long context without long-document data (effective context ≪
claimed). Extrapolating RoPE with no interpolation. Long context on MHA (the KV cache explodes).

**Game rule**
- `TRAIN = 1 + ctx / (12·d_model) × longShare`, where longShare is about 0.05 if extended late (the
  Llama 3 recipe) and 1.0 if trained long from scratch. A simpler version is a flat +5–10% compute
  per context tier with the right research.
- `DEMAND_ctx = 1 + 0.08 × log2(ctx / 4k) × effectiveness` (Design; no paper ties context to
  demand).
- `effectiveness`: 1.0 with the long-data and YaRN research, 0.5 with "RoPE scaling only", and 0
  for naive extrapolation, which also gives CEM 0.9.
- `SERVE_ctx = 1 + kvBytesPerToken × avgCtxUsed / memPerUser` (or ×1.15 per tier with GQA,
  ×1.4 per tier with MHA, as a Design shortcut).

Sources: Kaplan 2020 [2001.08361](https://arxiv.org/abs/2001.08361); Su (RoPE) 2021
[2104.09864](https://arxiv.org/abs/2104.09864); Chen 2023 [2306.15595](https://arxiv.org/abs/2306.15595);
Peng 2023 [2309.00071](https://arxiv.org/abs/2309.00071); Fu 2024 [2402.10171](https://arxiv.org/abs/2402.10171);
Liu 2023 [2307.03172](https://arxiv.org/abs/2307.03172); Hsieh 2024 [2404.06654](https://arxiv.org/abs/2404.06654);
Llama 3 [2407.21783](https://arxiv.org/abs/2407.21783).

---

## 5. Data

### 5a. Deduplication
C4 contained a single 61-word sentence repeated 60,000+ times. Dedup makes models "emit memorized
text ten times less frequently" and need "fewer training steps to achieve the same or better
accuracy". It also removes train/test overlap, which touched over 4% of validation sets. No single
compute multiplier is reported. **Rule:** dedup research gives CEM 1.15 (Design), and skipping it
adds a "regurgitation" PR-event risk. Lee 2021 [2107.06499](https://arxiv.org/abs/2107.06499).

### 5b. Quality filtering
- FineWeb (15T tokens, 96 CC snapshots) beats other open sets, and FineWeb-Edu (1.3T) is
  "dramatically better" on MMLU and ARC.
- DCLM: model-based filtering is "key". A 7B model on 2.6T tokens reaches 64% MMLU, +6.6 points
  over MAP-Neo with 40% less compute, and is comparable to Llama 3 8B with 6.6× less compute
  (confounded with other recipe differences).
- phi-1 (1.3B, 6B filtered web + 1B synthetic "textbook" tokens, 4 days on 8 A100s) scores 50.6%
  on HumanEval. That's a narrow benchmark; broad transfer is less established.
- Filtering also *shrinks* the pool, which pushes you into repetition (Muennighoff found filtering
  pays off mainly on noisy data).

**Rule:** filter tiers heuristic / classifier / LLM-graded give CEM 1.3 / 2.0 / 3.0 (Design,
bracketed by DCLM's 1.7–6.6×), with usable unique tokens ×0.7 / ×0.3 / ×0.1. Penedo 2024
[2406.17557](https://arxiv.org/abs/2406.17557); Li 2024 [2406.11794](https://arxiv.org/abs/2406.11794);
Gunasekar 2023 [2306.11644](https://arxiv.org/abs/2306.11644).

### 5c. Code share
Adding code to pre-training gave up to +8.2% (relative) on NL reasoning, +4.2% on world knowledge,
+6.6% on generative win-rates and a 12× boost on code, for models from 470M to 2.8B (Aryabumi 2024).
Muennighoff found code mixing worth ~2× effective tokens even on NL-only tasks. **Rule:**
`coding sub-score ∝ codeShare`, and `CEM_code = 1 + 0.4 × codeShare` for codeShare ≤ 0.3, flat
above that and with a knowledge penalty past 0.5 (Design). Aryabumi 2024
[2408.10914](https://arxiv.org/abs/2408.10914).

### 5d. Repetition and epochs
Up to 4 epochs gives "negligible changes to loss" compared with unique data. Repeated tokens lose
value with a half-life of R*_D ≈ 15.4 repetitions (~16 epochs), after which "returns diminish
extremely fast". Their fitted law converts directly into a game rule:
`D_eff = U + U × 15.4 × (1 − e^(−R/15.4))`, where U is unique tokens and R = epochs − 1. Use
D_eff in place of D everywhere. This replaces or refines the current `dataLimitedExponent`.
Muennighoff 2023 [2305.16264](https://arxiv.org/abs/2305.16264).

### 5e. Synthetic data and model collapse
- If each generation's synthetic data *replaces* real data, the tails of the distribution vanish
  irreversibly (Shumailov, published in *Nature* 2024).
- If synthetic data *accumulates* alongside real data, collapse is avoided and test error stays
  bounded (Gerstgrasser 2024). Curated synthetic data (phi-1) helps.

**Rule:** synthetic tokens count at 0.5× in D_eff (Design). If the synthetic share exceeds 50%
*and* the real data isn't kept, CEM ×0.7 per generation, and a "bland/collapsed" tag lowers
creative demand. Shumailov 2023 [2305.17493](https://arxiv.org/abs/2305.17493); Gerstgrasser 2024
[2404.01413](https://arxiv.org/abs/2404.01413).

### 5f. The data wall
Epoch estimates the public stock at about 130T tokens (Common Crawl, median), 510T (indexed web)
and ~4e14 "effective" tokens. That is fully used between 2026 and 2032 (median 2028), and sooner
with over-training. **Rule:** cap the purchasable *unique web* tokens at ~4e14 over the whole game.
Beyond it, growth must come from repetition (5d), synthetic data (5e), licensed or private data, or
other modalities. Villalobos 2022 [2211.04325](https://arxiv.org/abs/2211.04325).

---

## 6. Tokenizer, optimizer and precision basics

- **Vocabulary size:** the optimal vocab grows with compute, and most LLMs are too small. Llama2-70B
  "should have been at least 216K" against its 32K. At 3B, going from 32K to 43K raised ARC-C from
  29.1 to 32.0 at equal FLOPs (Tao 2024).
  Tokenizers also tax languages unequally: the same text varies up to 15× in token count (Petrov
  2023), so non-English users cost more and get less context.
  **Rule:** vocab tiers 32k / 128k / 256k give CEM 1.0 / 1.05 / 1.07 and non-English
  `SERVE` ×1.6 / ×1.2 / ×1.1, with matching non-English demand (Design).
- **LR, warmup and loss spikes:** PaLM 540B saw "spikes in the loss roughly 20 times", even with
  gradient clipping. The fix was to restart ~100 steps earlier and skip 200–500 batches. Spikes
  appear in small models too at high LR, and qk-layernorm, z-loss and warmup reduce LR sensitivity
  (Wortsman 2023). Llama 3 had 466 job interruptions in 54 days, 419 unexpected (mostly hardware).
  **Rule:** a per-run "loss spike" event chance of ~0.3 × log10(params/1e9) %/day, each costing
  ~0.5–2% of run time to roll back. Stability research halves it, and an "aggressive LR" setting
  (TRAIN ×0.9) doubles it (Design).
- **Mixed precision and FP8:** FP16/BF16 training (Micikevicius 2017) is the baseline. FP8
  (E4M3/E5M2) matches 16-bit quality up to 175B. DeepSeek-V3's FP8 loss stayed within 0.25% of the
  BF16 loss. Fishman 2024 reached ~34% throughput gains but found *late-run* instabilities, from
  SwiGLU outlier amplification, that short tests miss. Kumar 2024: low-precision training reduces
  the "effective parameter count".
  **Rule:** FP8 gives `MFU ×1.3`. Without "FP8 stability" research, runs over 1T tokens risk a
  divergence event (lose 10% of the run).

Sources: Tao 2024 [2407.13623](https://arxiv.org/abs/2407.13623); Petrov 2023
[2305.15425](https://arxiv.org/abs/2305.15425); Chowdhery 2022 [2204.02311](https://arxiv.org/abs/2204.02311);
Wortsman 2023 [2309.14322](https://arxiv.org/abs/2309.14322); Micikevicius 2017
[1710.03740](https://arxiv.org/abs/1710.03740); Micikevicius 2022 [2209.05433](https://arxiv.org/abs/2209.05433);
Fishman 2024 [2409.12517](https://arxiv.org/abs/2409.12517); Kumar 2024 [2411.04330](https://arxiv.org/abs/2411.04330).

---

## 7. Post-training

**Options (progression):** none (base model) → SFT → RLHF (PPO and a reward model) → DPO → RL with
verifiable rewards (reasoning) → distilling reasoning into small models.

- **SFT:** LIMA fine-tuned a 65B model on only 1,000 curated examples. It was equivalent to or
  preferred over GPT-4 in 43% of cases, which suggests that "almost all knowledge" comes from
  pre-training. SFT unlocks the chat format; it doesn't add raw capability.
- **RLHF (InstructGPT):** the 1.3B InstructGPT was preferred over the 175B GPT-3, despite having
  100× fewer parameters. The 175B InstructGPT won 85 ± 3% of comparisons against GPT-3 and 71 ± 4%
  against few-shot GPT-3.
- **Alignment tax:** PPO regressed SQuAD, DROP, HellaSwag and WMT. Mixing in pre-training gradients
  (PPO-ptx) mostly fixes this. Anthropic's work found the tax hits *small* models, while large models
  see no harm or a bonus (Askell 2021; Bai 2022). Model averaging gives the best trade-off (Lin 2023).
- **Reward over-optimization:** with d = sqrt(KL from the initial policy), the true (gold) reward
  under RL follows `R(d) = d(α − β·ln d)`: it rises, peaks, then falls, even as the proxy reward
  keeps climbing. Larger reward models raise the peak (Gao 2022). Human-feedback reward models
  also favour **sycophancy** (Sharma 2023).
- **DPO:** solves the RLHF objective with a classification loss. It needs no reward model and no
  sampling, and matches or beats PPO on sentiment control, summarization and dialogue. DPO-style
  methods **still over-optimize** (Rafailov 2024).
- **RL with verifiable rewards:** DeepSeek-R1-Zero's pure RL raised AIME 2024 pass@1 from 15.6% to
  77.9%, and to 86.7% with self-consistency voting. The v1 preprint reported 71.0%; the figures
  changed between versions. R1 scores 79.8%. DeepSeek avoided neural reward models for reasoning
  because they are "susceptible to reward hacking". Responses grow naturally to "hundreds to
  thousands of tokens". The o1-style result is that accuracy grows roughly log-linearly with both
  RL compute and test-time compute (OpenAI blog, Sep 2024; not a paper). Snell 2024: adaptive
  test-time compute is 4× more efficient than best-of-N, and beats a 14× larger model, but only on
  easy-to-medium problems.
- **Inference cost of reasoning and overthinking:** o1-like models used 1,953% more tokens than
  conventional models on "2 + 3" (Chen 2024).
- **Distillation beats small-model RL:** on AIME, Qwen2.5-32B with RL from scratch scored 47.0%,
  against 72.6% for the same base distilled from R1, and R1-Distill-Qwen-7B reached 55.5%.

**Game rule**
- SFT gives a flat +60 rating (Design; it gates release as a "chat" product, and with no SFT,
  demand is ×0.3).
- RLHF and DPO give a rating bonus of `+B × g(KL)`, where `g = (d/d*)(1 − ln(d/d*))`, normalised so
  g = 1 at the optimum d* and g < 1 on both sides. The player picks an "RL strength" slider from 0
  to 2× d*. The bonus B is about +70 for RLHF (≈ InstructGPT's >100× parameter equivalence, i.e.
  ~7 doublings × 23 / 2 for conservatism; Design). DPO gets the same B at 0.3× post-training
  compute, but B is ×0.9 and d* is ×0.8 (it over-optimizes sooner; Design). A bigger RM
  (research) raises d*.
- Alignment tax: `−15 × (1 − min(1, N / 50B))` rating on knowledge benchmarks, removed by the
  "pretrain mix (PPO-ptx)" research.
- RL reasoning: math/code sub-score ×2–4 (from R1's 15.6→77.9 AIME; Design), with a general
  rating bonus of +40. Serving is `SERVE × thinkTokens/normalTokens`, which defaults to 10×. The
  "adaptive thinking" research cuts it to 4× (Design, between the ~20× overthinking extreme and
  short answers). It only pays off for a base model with rating ≥ 1000 (R1-Zero needed a strong
  base, and small models gain more from distillation). Below that, the bonus is halved.
- Reward hacking: a neural reward model on reasoning RL gives a 30% chance that the math bonus is
  void and a "gamed benchmarks" news event fires (Design; DeepSeek-R1 avoided it via rule-based
  rewards).

Sources: Zhou 2023 [2305.11206](https://arxiv.org/abs/2305.11206); Ouyang 2022
[2203.02155](https://arxiv.org/abs/2203.02155); Askell 2021 [2112.00861](https://arxiv.org/abs/2112.00861);
Bai 2022 [2204.05862](https://arxiv.org/abs/2204.05862); Lin 2023 [2309.06256](https://arxiv.org/abs/2309.06256);
Gao 2022 [2210.10760](https://arxiv.org/abs/2210.10760); Sharma 2023 [2310.13548](https://arxiv.org/abs/2310.13548);
Rafailov 2023 [2305.18290](https://arxiv.org/abs/2305.18290); Rafailov 2024 [2406.02900](https://arxiv.org/abs/2406.02900);
DeepSeek-AI 2025 [2501.12948](https://arxiv.org/abs/2501.12948); Shao 2024 (GRPO) [2402.03300](https://arxiv.org/abs/2402.03300);
Snell 2024 [2408.03314](https://arxiv.org/abs/2408.03314); Chen 2024 [2412.21187](https://arxiv.org/abs/2412.21187);
OpenAI, "Learning to reason with LLMs" (blog, 2024-09-12).

---

## 8. Inference and serving

- **INT8:** LLM.int8() halves memory with "no performance degradation" up to 175B, by keeping
  outlier features in 16-bit. SmoothQuant enables W8A8 (8-bit weights and activations).
- **INT4/INT3 (weight-only):** GPTQ quantizes to 3–4 bits with "negligible accuracy degradation" in
  ~4 GPU-hours for 175B, with 3.25× (A100) and 4.5× (A6000) speedups. AWQ protects ~1% salient
  channels and gets >3× over HF FP16. Dettmers 2022: 4-bit is "almost universally optimal" for
  accuracy per total model bits, so a bigger 4-bit model beats a smaller 8-bit one.
- **Failure modes:** 2–3-bit degrades noticeably, and Llama 3 (15T tokens) shows "non-negligible
  degradation", especially at ultra-low bits (Huang 2024). Kumar 2024: degradation grows with
  pre-training tokens, and enough over-training makes extra data "actively harmful" after
  quantization. This interacts with §1.
- **Speculative decoding:** **exact** (output distribution unchanged), 2–3× on T5-XXL (Leviathan)
  and 2–2.5× on Chinchilla 70B (Chen). Medusa uses extra heads instead of a draft model. Speed
  only, with no quality change.
- **Distillation:** DistilBERT is 40% smaller and 60% faster, keeping 97% of BERT's language
  understanding. Minitron prunes and distills 15B to 8B/4B with up to 40× fewer tokens and up to
  +16% MMLU over training from scratch. R1-Distill (§7) does the same for reasoning.

**Game rule**
- Quantization tiers: INT8 gives SERVE ×0.55 with CEM 1.0. INT4 gives SERVE ×0.35 with CEM
  `0.97 − 0.03 × log10(r/20)⁺`, which penalizes over-trained models (Kumar). INT2 gives SERVE ×0.25
  with CEM 0.8 (Design, from the reported speedups).
- Speculative decoding gives SERVE ×0.5, research only, with no rating effect.
- Distillation, a new "release a small sibling" action: a student 2–4× smaller than the teacher
  costs 5% of the teacher run's compute and is rated at the teacher's rating minus 40 (Design,
  loosely from Minitron and R1-Distill). Serving scales with the student's size.

Sources: Dettmers 2022 [2208.07339](https://arxiv.org/abs/2208.07339); Xiao 2022
[2211.10438](https://arxiv.org/abs/2211.10438); Frantar 2022 [2210.17323](https://arxiv.org/abs/2210.17323);
Lin 2023 [2306.00978](https://arxiv.org/abs/2306.00978); Dettmers 2022 [2212.09720](https://arxiv.org/abs/2212.09720);
Huang 2024 [2404.14047](https://arxiv.org/abs/2404.14047); Kumar 2024 [2411.04330](https://arxiv.org/abs/2411.04330);
Leviathan 2022 [2211.17192](https://arxiv.org/abs/2211.17192); Chen 2023 [2302.01318](https://arxiv.org/abs/2302.01318);
Cai 2024 [2401.10774](https://arxiv.org/abs/2401.10774); Hinton 2015 [1503.02531](https://arxiv.org/abs/1503.02531);
Sanh 2019 [1910.01108](https://arxiv.org/abs/1910.01108); Muralidharan 2024 [2407.14679](https://arxiv.org/abs/2407.14679).

---

## Summary table

Ratings use Δrating = 23·log2(CEM).

| Choice | Game effect (proposed) | Key source |
|---|---|---|
| Tokens/param r | CEM = exp(−0.45·log10(r/20)²); SERVE = sqrt(20/r) | Hoffmann 2022; Besiroglu 2024; Sardana 2023 |
| Under-trained (r ≈ 2) | CEM 0.64 (≈ −15 rating) | Chinchilla vs Gopher |
| Coarse / fine MoE | CEM 2 / 3 × network factor; serving memory ×3 / ×6 | Fedus 2021; Dai 2024; DeepSeek-V3 |
| MoE without balancing | 25% routing-collapse risk → CEM 1.2 | Shazeer 2017; Fedus 2021 |
| MQA / GQA / MLA | CEM 0.95 / 0.99 / 0.99; SERVE 0.45 / 0.5 / 0.35 | Ainslie 2023; DeepSeek-V2 |
| Sliding window | CEM 0.97; KV capped | Mistral 2023; Beltagy 2020 |
| SSM hybrid / pure SSM | CEM 1.02 / 0.95; SERVE 0.35 / 0.25; pure SSM loses recall | Waleffe 2024; Jelassi 2024 |
| FlashAttention | MFU ×1.3 → ×1.6; no quality change | Dao 2022, 2023 |
| Context tier up | DEMAND +8%·eff; TRAIN +5–10%; SERVE ↑ via KV | Chen 2023; Peng 2023; Fu 2024; Liu 2023; RULER |
| Long ctx without long data | effectiveness 0.5 (or 0 and CEM 0.9) | Fu 2024; Hsieh 2024 |
| Dedup | CEM 1.15; avoids regurgitation event | Lee 2021 |
| Quality filter tiers | CEM 1.3 / 2 / 3; unique tokens ×0.7 / 0.3 / 0.1 | DCLM; FineWeb; phi-1 |
| Code share | coding ∝ share; CEM +0.4·share (≤30%) | Aryabumi 2024; Muennighoff 2023 |
| Repeating data | D_eff = U + 15.4U(1−e^(−R/15.4)) | Muennighoff 2023 |
| Synthetic replacing real | CEM ×0.7 per generation; "bland" tag | Shumailov 2024; Gerstgrasser 2024 |
| Data wall | unique web capped ~4e14 tokens | Villalobos 2022 |
| Vocab size | CEM 1.0 → 1.07; non-English SERVE and demand | Tao 2024; Petrov 2023 |
| Loss spikes | random rollback events; stability research halves them | PaLM 2022; Wortsman 2023 |
| FP8 | MFU ×1.3; divergence risk on long runs without research | DeepSeek-V3; Fishman 2024 |
| SFT | +60 rating; gates chat demand | LIMA 2023; InstructGPT |
| RLHF / DPO | +B·g(KL), peaked; DPO 0.3× cost, earlier peak | Ouyang 2022; Gao 2022; Rafailov 2023, 2024 |
| Alignment tax | −15 on small models; fixed by PPO-ptx research | Ouyang 2022; Bai 2022 |
| RL reasoning | math/code ×2–4, +40 rating; SERVE ×10 (×4 adaptive) | DeepSeek-R1 2025; Snell 2024; Chen 2024 |
| Neural RM for reasoning | reward-hacking risk | DeepSeek-R1 2025; Gao 2022 |
| INT8 / INT4 / INT2 | SERVE 0.55 / 0.35 / 0.25; CEM 1 / ~0.97 / 0.8 | LLM.int8(); GPTQ; AWQ; Kumar 2024 |
| Speculative decoding | SERVE ×0.5; exact | Leviathan 2022; Chen 2023 |
| Distillation | cheap small sibling ≈ teacher −40 rating | Minitron 2024; DeepSeek-R1 2025 |
