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
- Power cap (kW/MW): limits how many GPUs you can run. Power tiers are named
  after the electrical supply (Garage outlet → 3-phase service → leased colo
  circuits → medium-voltage feed → on-site substation → PPA → gigawatt grid
  interconnect → restarted nuclear → multi-site), never after a place. Each
  place has a power limit (its electrical service): a bigger supply needs a
  bigger building, so you move first. Moving keeps your tier and buys nothing.
- Network tier: how many GPUs your one training cluster keeps fed (all GPUs in
  the room are cabled together; past the cap a run scales at √(cap/GPUs)).
- Heat: coolers next to hot GPUs (the early placement puzzle); from the Medium
  lab a central cooling plant cools every GPU tile.
- Model rating: an Arena-style score from effective training compute
  (log scale) + post-training bonuses (instruction tuning, RLHF...). The data budget caps
  useful compute Chinchilla-style (compute past ~0.3*D^2 has diminishing returns).
- Users: drift toward demand (from rating x hype); capped by serving capacity; over
  capacity → overload churn. Bigger models cost more to serve → serving-efficiency upgrades.

## Moments
- Training runs: commit X% of compute for N minutes; live progress; predicted rating.
- Release: open vs closed choice, plus a launch stunt (cryptic tweet / risky live demo).
- Launch reviews (lib/sim/reviews.dart, Game Dev Tycoon style): four parody
  outlets (LLM Arena-ish, The Benchmarker, Tech Twitter Vibes, HackerNooz)
  score each release /10 with a quip naming why: the gap to the best rival on
  the board, the rating jump, benchmark strengths, mishaps, open weights,
  serving cost, the stunt, and novelty (shipping the exact same design again
  scores lower, once there are real options to vary). The average sets a
  demand buzz ×0.8–×1.5 that fades over half the era's shortest run; it is
  centred on what the bot averages, so it nets out to ~×1. Scores flip in
  one at a time (~2.4 s, tap to skip) before the share card.
- Viral spike: demand x4 for 90s. Fix: pause training, rent cloud, quantize.
- Rival ladder: parody labs at historical snapshots; beat rating AND users to pass.
- Live rival feed (lib/sim/news.dart): rivals show up on the leaderboard as
  they "release" ("yAI released Grokk 3: 1,503 rating..."), as a news card
  at the bottom of the map (one at a time; tap opens the leaderboard on that
  row) and in the leaderboard's News tab, plus ~18 lines of parody industry
  gossip. Releases while you're away go in the "while you were away" digest.
  The next rival to beat is always released; up to two more drip out ahead
  of you over game time, only from eras you've reached. The feed never
  changes gates or who can be beaten.
- One place at a time: buying the next room *moves* you there with all your
  tiles (same layout, centred in the bigger floor); the old room is gone.
  Moving only costs money; an era's goal still unlocks its parts and tiers.
  Moving is a short moment (truck along the road, fade, tiles pop in;
  tap to skip). Rules: docs/GRID.md.
- Eras (six, one new room each; gates and unlocks in docs/BALANCE.md):

  | era | room (size) | gate | rivals |
  |---|---|---|---|
  | Parents' garage | Garage 4×4 | start | Tiny-Transformer, GPT-ish-1 |
  | Startup | Server closet 7×7 | 3k users | BURT, GPT-ish-2 |
  | Small lab | Colocation cage 10×10 | rating 1000 | Meenie, GPT-ish-3 |
  | Medium lab | Datacenter hall 14×14 | rating 1130 | Mixtrawl, ChatGPT-ish |
  | Big lab | Datacenter campus 18×18 | rating 1260 | GPT-ish-4 → GPT-ish-4.5 (the big labs) |
  | Frontier lab | Gigawatt site 22×22 | rating 1490 | GPT-ish-5 → GPT-ish-6 Astral |

- Pacing: a 2–3 day casual game (3–4 sessions of 30–60 min a day). Startup
  in the first session (~12 min), final rival at ~55 h wall-clock. Training
  runs grow from minutes to hours (1m/3m/10m in the garage, 2h/4h/8h at the
  frontier) so a run finishes while you're away; time compression per era
  keeps their FLOPs realistic.
- Always-visible goal: a strip under the project bar ("Next era: Small lab ·
  rating 998 / 1,000 · train & release a better model"); the rating plate
  ("RATING 1293 · beat GPT-ish-4: 1339") opens the leaderboard.
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
