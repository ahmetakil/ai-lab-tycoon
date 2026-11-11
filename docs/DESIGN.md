# AI Lab Tycoon — design (v1 / MVP)

Idle tycoon: grow an AI lab from one gaming GPU in a garage to a frontier datacenter,
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
- Eras: Garage → Startup (3k users) → Lab (rating 1100).
- Offline progress capped at 8h, with a "while you were away" summary.
- Shareable release card (the marketing engine).

## Rules
- Parody names only. Never real company or product names, logos or people.
- Upgrade blurbs must be technically accurate. Made-up tech is v2 and gets labelled.
- No real-money monetization in v1.

## Out of scope for v1
Frontier era/prestige, hiring, dashboards, made-up tech, cloud save, monetization.
