# Model design (planned, next pass after the move/network pass)

The player's idea: research unlocks *choices* you make when you build a model, not only
flat percentage boosts. Game Dev Tycoon's development stages are the reference.

## Research tracks
Reorganise research into tracks that match how models are really made:
- **Pre-training:** architecture (dense → MoE), attention variants, context length,
  tokenizer, optimizers, FP8 and similar efficiency work.
- **Post-training:** SFT → RLHF → DPO → RL with verifiable rewards (reasoning), tool use.
- **Data:** web crawl, code, books and papers, synthetic data, dedup and filtering.
- **Infrastructure / serving:** kernels, batching, KV cache, speculative decoding,
  disaggregated serving, quantization.

## A run happens in two phases
1. **Pre-training run:** the big, long, compute-heavy run (what exists today). You choose:
   - **Architecture:** Dense, or MoE once researched. MoE gives more quality per FLOP but
     needs a bigger, better-networked cluster.
   - **Attention:** Full → GQA → sliding window → linear. Cheaper serving and longer context
     trade off against a little quality.
   - **Context length:** it starts LOW (2k–4k) and research unlocks 32k → 128k → 1M. Longer
     context raises user demand and costs training and serving compute.
   - **Data mix:** shares of web, code, books and synthetic, which shift benchmark strengths.
2. **Post-training:** a shorter, cheaper phase after pre-training, before release. You choose
   the method (SFT, RLHF, DPO, RL reasoning). It raises rating and changes serving cost:
   reasoning models think longer and are pricier to serve.

## Rules
- There is no dominant pick. Every option has a cost that depends on the player's hardware
  (cluster size, network tier, serving capacity), which ties the grid to model design.
- Each option has a one-line, technically accurate explanation.
- The game remembers the last setup, so starting a run stays one tap.
- The release card shows the effects, e.g. "code-heavy mix won coding" or "RL reasoning
  won math", which makes good share-card material.
