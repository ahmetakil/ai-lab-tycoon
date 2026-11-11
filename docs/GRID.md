# The grid (v4: one place at a time)

The main screen is a Reactor-style tile grid in the room you're in. You place
GPUs and coolers; *where* coolers sit matters early (the heat puzzle), and
networking and central cooling are global tiers you buy like power.
Everything else (research, releases, rivals, eras, share card, offline
progress) is unchanged.

Source of truth: `lib/sim/content.dart` (data), `lib/sim/grid.dart` (rules),
`lib/sim/game.dart` (API). Pacing: `docs/BALANCE.md`.

## One room at a time: moving

You live in exactly one room. The next room along the road is shown as a faint
silhouette with a "Move here" sign; buying it **moves** you there:

- **Money is the only gate.** You can move as soon as you have the cash, even
  before the room's era. The era still has its normal goal and still unlocks
  that room's parts, power and network tiers and research; moving early just
  gives more floor and the room's free cooling. Rooms are strictly
  sequential (`Game.nextRoom`).
- **Every tile comes along** with the same relative layout, centred in the
  bigger floor: `Game.moveOffset(from, to) = ((w₂ − w₁) ~/ 2, (h₂ − h₁) ~/ 2)`
  (odd extra columns/rows go right/bottom; deterministic). Every room is at
  least as big as the one before, so everything fits. The old room is gone.
- The training run, users, upgrades and the power / network / cooling tiers
  carry on unchanged. `Game.moveTo(roomId)` emits `RoomMoved(from, to, offset)`.
- `Game.moveRequirements(roomId)` is the modal's checklist: **Cash** (the
  only required row), then the room's era goal and its usual power tier as
  "not needed to move, unlocks the new parts" rows, each with progress, a
  how-to hint and an action (`RequirementAction.power` / `.train`).
  `roomBlockReason` is one sentence: "Costs $15.0k. You have $3.2k.",
  "Move to the Server closet first.", "You're already in the Garage."

Save v4 (one room, tiers). Older saves (v3 had several rooms at once) start
fresh; the game is unreleased.

## Rooms

| room | era | size | GPU tile = | room cooling/cell (total) | cost | usual power tier |
|---|---|---|---|---|---|---|
| `garage` Garage | garage | 4×4 | 1 GPU | 1.0 (16) | free | 0 (Garage outlet) |
| `closet` Server closet | startup | 7×7 | 8-GPU server | 2.5 (123) | $15k | 2 (Office with 3-phase power) |
| `colo` Colocation cage | smallLab | 10×10 | 8-GPU server | 5.0 (500) | $2M | 3 (Colocation cage) |
| `hall` Datacenter hall | mediumLab | 14×14 | rack (32–72 GPUs) | 18.0 (3528) | $3M | 4 (Datacenter hall) |
| `campus` Datacenter campus | bigLab | 18×18 | pod (~1k GPUs) | 40.0 (12960) | $30M | 5 (Datacenter campus) |
| `gigasite` Gigawatt site | globalLab | 22×22 | building (~8k GPUs) | 70.0 (33880) | $400M | 7 (Gigawatt campus) |

"Usual power tier" is what the room's own GPUs need; it doesn't gate the move.
The garage stays a cramped 4×4; each later room has roughly 1.5× the floor of
the one before.

## Tiles

All tiles are 1×1. Adjacency is orthogonal (4 neighbours). Two kinds: **GPU**
and **cooling** (network switch tiles are gone since v4).

- **Any unlocked tile can be placed in any room** (an old gaming card in a
  gigawatt site is allowed, just a poor deal: the tray shows TFLOPS/kW and
  TFLOPS/$). Placement only blocks on the cell (empty, inside), unlocks (era,
  research, power tier) and power headroom and cash. `TileDef.rooms` is the
  set of rooms a tile is *sold for*: the tray shows the current era's parts
  (and newer) first and the older ones in a collapsed "Older parts" group
  (`Game.tilesForRoom`, `Game.isOlderPart`).
- In build mode, a drag with a part selected paints it along the path (every
  crossed cell that allows it); a tap places one.

### GPU tiles

| GPU tile | sold for | GPUs | TFLOPS | kW | heat | cost | locks |
|---|---|---|---|---|---|---|---|
| `gpu_old` | garage | 1 | 30 | 0.35 | 6 | $900 |  |
| `gpu_gamer` | garage | 1 | 80 | 0.45 | 4.5 | $2k |  |
| `gpu_v_class` | garage | 1 | 125 | 0.5 | 5 | $3k |  |
| `srv_a_class` | closet, colo | 8 | 2496 | 5.6 | 28 | $50k |  |
| `srv_h_class` | closet, colo | 8 | 7920 | 10.4 | 42 | $150k | tier 3 (colo) |
| `rack_h_class` | hall | 32 | 31.7k | 40 | 160 | $580k | tier 4 (hall) |
| `rack_b_class` | hall | 72 | 162k | 172.8 | 260 | $2.85M | liquid_cooling, tier 5 (campus) |
| `pod_b_class` | campus | 1024 | 2.3M | 2406.4 | 600 | $39M | liquid_cooling, tier 5 (campus) |
| `rack_r_class` | hall | 72 | 252k | 244.8 | 340 | $3.9M | liquid_cooling, tier 6 (plant) |
| `pod_r_class` | campus | 1024 | 3.6M | 3430 | 750 | $54.6M | liquid_cooling, tier 6 (plant) |
| `bldg_r_class` | gigasite | 8.2k | 28.7M | 27.0k | 700 | $300M | liquid_cooling, tier 7 (gw_campus) |

**GPU supply crunch**: a GPU tile costs `cost × min(4, (1 + priceGrowth)^owned)`
(`Game.tilePrice`). Garage GPUs and coolers have no crunch. Selling refunds
half the list price.

### Cooling tiles

| cooling tile | sold for | cooling | kW | cost | locks |
|---|---|---|---|---|---|
| `cool_fan` | garage | 4 | 0.05 | $120 |  |
| `cool_window_ac` | garage | 10 | 0.9 | $500 |  |
| `cool_crac` | closet, colo | 40 | 3 | $12k |  |
| `cool_rear_door` | closet, colo | 90 | 1.5 | $40k | liquid_cooling |
| `cool_chiller` | hall, campus | 300 | 40 | $150k |  |
| `cool_liquid` | hall, campus | 450 | 10 | $250k | liquid_cooling |
| `cool_tower` | campus, gigasite | 1800 | 200 | $4M |  |
| `cool_dry` | gigasite | 3000 | 450 | $9M |  |

## Training cluster and network tier

**All GPU tiles in the room form one training cluster**, cabled overhead:
where they sit doesn't matter for training. The cluster cap comes from the
**network tier**, a global upgrade bought in the Network panel (like power):

| network tier | era | feeds (GPUs) | Gbps | cost | requires |
|---|---|---|---|---|---|
| `copper1g` Copper Ethernet 1G | garage | 4 | 1 | $0 |  |
| `copper10g` 10G copper | garage | 32 | 10 | $1.5k |  |
| `fiber100g` 100G fiber | startup | 256 | 100 | $40k |  |
| `ib400g` InfiniBand 400G | smallLab | 4096 | 400 | $1.5M | interconnect |
| `ibspine` InfiniBand spine | mediumLab | 32768 | 800 | $15M | interconnect |
| `nvlink` NVLink fabric | bigLab | 131072 | 14400 | $200M |  |
| `optical` Optical fabric | globalLab | 4194304 | 1600 | $1.5B | parallelism |

- `scalingEfficiency = 1` if `gpus ≤ cap`, else `sqrt(cap / gpus)` (GPU counts,
  not tiles: a tile stands for `gpusPerTile` GPUs). A lone GPU tile always
  trains at full speed (its GPUs share one box).
- Training compute = cluster effective TFLOPS × scaling efficiency × run
  fraction. Serving = effective TFLOPS × (1 − fraction) (+ rented cloud). The
  scaling loss is wasted, not served.
- The HUD's network plate reads "96 / 256 GPUs fed" (green under 80% of the
  cap, amber from 80%, red over it with "→ NN% scaling"); tapping it opens
  the Network panel (current tier, next tier, price, buy). Build mode labels
  the cluster ("96 GPUs · trains · 256 fed") and draws decorative cable trays
  over the GPU rows, styled by tier (orange copper → blue fiber → InfiniBand
  bundles → bright NVLink / optical).

## Heat (the spatial part)

For each GPU tile: `netHeat = heat − roomCooling / gpuTiles − plant − Σ(adjacent
cooler shares)`.

- **Room cooling** is a pool, `ambientCooling × width × height`, shared evenly
  by the room's GPU tiles.
- **Coolers** split `cooling` evenly among their orthogonally adjacent GPU
  tiles; a cooler next to no GPU does nothing. Coolers don't carry anything
  else (no network role).
- **Central cooling** (`plant`) is a global tier bought in the Cooling panel
  from the Medium lab on. It removes `perGpuTile` heat from every GPU tile, so
  big rooms are about capacity; cooler tiles become optional tuning:

| central cooling | era | heat removed per GPU tile | cost | requires |
|---|---|---|---|---|
| `room_air` Room air | garage | 0 | $0 |  |
| `chiller` Central chilled water | mediumLab | 80 | $3M |  |
| `tower` Evaporative cooling towers | bigLab | 250 | $40M |  |
| `liquid` Facility liquid loop | bigLab | 450 | $150M | liquid_cooling |
| `dry` Dry-cooler farm | globalLab | 550 | $800M |  |

- If netHeat > 0 the tile throttles: `speed = max(0.2, 1 − netHeat / heat)`
  (red tint and a % badge). No destruction.

## Power

| power tier | era | cap | cost |
|---|---|---|---|
| `outlet` Garage outlet | garage | 1.8 kW | $0 |
| `panel` Upgraded electrical panel | garage | 8 kW | $3k |
| `office` Office with 3-phase power | startup | 50 kW | $60k |
| `colo` Colocation cage | smallLab | 500 kW | $1M |
| `hall` Datacenter hall | mediumLab | 2 MW | $4M |
| `campus` Datacenter campus | mediumLab | 20 MW | $7M |
| `plant` Dedicated power plant deal | bigLab | 300 MW | $120M |
| `gw_campus` Gigawatt campus | globalLab | 1.0 GW | $350M |
| `nuclear_restart` Restarted nuclear plant | globalLab | 2.0 GW | $1B |
| `multi_site` Multi-site cluster | globalLab | 4.0 GW | $2B |


GPU tiles draw `powerKw × powerMult` (liquid cooling −15%), coolers their
listed kW; one cap for the room.

## Sim API (what the UI codes against)

```dart
enum TileKind { gpu, cooling }
class TileDef { id, name, blurb, kind, era, Set<String> rooms /* sold for */, cost, powerKw,
  tflops, heat, gpusPerTile, cooling, requires, minPowerTier, priceGrowth; nativeTo(roomId) }
class RoomDef { id, name, blurb, era, width, height, cost, ambientCooling, tileScaleLabel,
  minPowerTier }
class NetworkDef { id, name, blurb, era, gpuCap, linkGbps, cost, requires }
class CoolingDef { id, name, blurb, era, perGpuTile, cost, requires }
const tiles, rooms, powerTiers, networkTiers, coolingTiers;
RoomDef? roomAfter(id); int roomIndex(id);

// GameState: grids holds exactly one room; roomId, room; powerTier, networkTier, coolingTier.
// Game
RoomDef currentRoom; RoomDef? nextRoom; bool isRoomOwned(id);
List<Requirement> moveRequirements(id); String? roomBlockReason(id); bool moveTo(id);
static (int, int) moveOffset(from, to);
String eraLockReason(era); // "Unlocks in Small lab: reach rating 1,000 (you're at 998)."
NetworkDef network; double networkCap; NetworkDef? nextNetworkTier;
String? networkBlockReason(); bool buyNextNetworkTier();
CoolingDef cooling; CoolingDef? nextCoolingTier; String? coolingBlockReason();
bool buyNextCoolingTier(); bool coolingTiersVisible;
List<TileDef> tilesForRoom(id); bool isOlderPart(t, id);
String? placeBlockReason(id, x, y, tileId, {ignoreMoney}); bool placeTile(...);
bool moveTile(...); bool replaceTile(...); bool sellTile(...);
TileStatus? tileStatus(id, x, y); // .plantCooling, .ambientCooling, .adjacentCooling...
Cluster? trainingCluster; // .gpus, .gpuCap, .scalingEfficiency, .overCap
```

Lock reasons are actionable: "Needs power: Colocation cage.", "Research
Liquid cooling first.", "Not enough power: needs 5.6 kW, 2.5 kW free. Tap ⚡
Power to upgrade."
