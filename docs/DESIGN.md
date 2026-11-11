# AI Lab Tycoon — design (v1 / MVP)

Idle tycoon: grow an AI lab from one gaming GPU in your parents' garage to a gigawatt frontier lab,
racing parody versions of real labs through history. Lightly educational: every upgrade
is a real technique with a one-line, accurate explanation. Audience: tech people on X /
LinkedIn. It must feel like a game, not a spreadsheet.

## Core loop (one sentence)
Split compute between serving users (money now) and committed training runs (a better
model later); spend money on GPUs (raw compute, uses power) or software (efficiency, no
power) to get more useful compute under the power cap; release models to grow users and
beat rival labs.

## Resources (keep it to these)
- Money: the only currency.
- Compute: GPUs x TFLOPS x utilization (the MFU bar; software raises it).
- Power cap (kW/MW): limits how many GPUs you can run. Cooling is flavour only.
- Model rating: an Arena-style score from effective training compute
  (log scale) + post-training bonuses (instruction tuning, RLHF...). The data budget caps
  useful compute Chinchilla-style (compute past ~0.3*D^2 has diminishing returns).
- Users: drift toward demand (from rating x hype); capped by serving capacity; over
  capacity → overload churn. Bigger models cost more to serve → serving-efficiency upgrades.

## Moments
- Training runs: commit X% of compute for N minutes; live progress; predicted rating.
- Release: open vs closed choice, plus a launch stunt (cryptic tweet / risky live demo).
- Viral spike: demand x4 for 90s. Fix: pause training, rent cloud, quantize.
- Rival ladder: parody labs at historical snapshots; beat rating AND users to pass.
- Eras (six, one new room each; gates and unlocks in docs/BALANCE.md):

  | era | room | gate | rivals |
  |---|---|---|---|
  | Parents' garage | Garage | start | Tiny-Transformer, GPT-ish-1 |
  | Startup | Server closet | 3k users | BURT, GPT-ish-2 |
  | Small lab | Colocation cage | rating 1000 | Meenie, GPT-ish-3 |
  | Medium lab | Datacenter hall | rating 1120 | Mixtrawl, ChatGPT-ish |
  | Big lab | Datacenter campus | rating 1260 | GPT-ish-4 → GPT-ish-4.5 (the big labs) |
  | Frontier lab | Gigawatt site | rating 1500 | GPT-ish-5 → GPT-ish-6 Astral |

- Pacing: a 2–3 day casual game (3–4 sessions of 30–60 min a day). Startup
  in the first session (~12 min), final rival at ~51 h wall-clock. Training
  runs grow from minutes to hours (1m/3m/10m in the garage, 2h/4h/8h at the
  frontier) so a run finishes while you're away; time compression per era
  keeps their FLOPs realistic.
- GPU supply crunch: each GPU of a type you own makes the next pricier (×4 cap).
- Offline progress capped at 8h, with a "while you were away" summary.
- Settings has a "Playtest speed" control (1×, 10×, 60×, 600×), in all builds
  for now.
- Shareable release card (the marketing engine).

## Rules
- Parody names only. Never real company or product names, logos or people.
- Upgrade blurbs must be technically accurate. Made-up tech is v2 and gets labelled.
- No real-money monetization in v1.

## Out of scope for v1
Prestige, hiring, dashboards, made-up tech, cloud save, monetization.
