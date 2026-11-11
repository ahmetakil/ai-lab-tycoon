# Grid redesign (v2 core loop)

The main screen becomes a Reactor-style tile grid. You physically place GPUs, cooling and
network gear; *where* you place them matters. Everything else (research tree, releases,
rivals, eras, share card, offline progress) stays.

## Rooms (separate grids, bigger scale each era)
Each room is its own grid, and its tiles represent more hardware than the room before.
Earlier rooms keep working (they're good for serving).

| id | name | era | size | 1 GPU tile = | ambient cooling/tile |
|---|---|---|---|---|---|
| garage | Garage | garage | 4×4 | 1 GPU | 1 |
| closet | Server closet | startup | 6×6 | 8-GPU server | 4 |
| colo | Colocation cage | startup | 8×8 | 8-GPU server | 8 |
| hall | Datacenter hall | lab | 10×10 | rack (~32–72 GPUs) | 30 |
| campus | Datacenter campus | lab | 10×10 | pod (~1k GPUs) | (tune) |
| gigasite | Gigawatt site | lab | 12×12 | building (~20k GPUs) | (tune) |

Rooms are bought with money (and gated by era/power tier). The global **power cap** (existing
power tiers) still applies across all rooms. Numbers marked "tune" are for the sim agent.

## Tile kinds
All tiles are 1×1. Adjacency is **orthogonal (4 neighbours)**.

### GPU tiles
`tflops`, `powerKw`, `heat`, `gpusPerTile`. Examples (ids are fixed, numbers are tunable):
- garage: `gpu_old` Old gaming GPU (the bad home GPU: cheap, slow, hot), `gpu_gamer`
  Gaming GPU, `gpu_v_class` Used V-class datacenter GPU
- startup: `srv_a_class` A-class server (8 GPUs), `srv_h_class` H-class server (8 GPUs)
- lab: `rack_h_class` H-class rack, `rack_b_class` B-class NVL rack (needs liquid cooling),
  `rack_r_class` R-class rack, `pod_b_class` B-class pod (campus), `bldg_r_class` R-class
  building (gigasite)

### Cooling tiles
`cooling` = total heat removed per tick, **split evenly among adjacent GPU tiles**, and
`powerKw` (cooling costs power: a PUE lesson).
- garage: `cool_fan` Box fan (weak, nearly free power), `cool_window_ac` Window AC (strong
  but power-hungry)
- startup: `cool_crac` Precision AC (CRAC), `cool_rear_door` Rear-door heat exchanger (requires
  `liquid_cooling`)
- lab: `cool_liquid` Direct liquid-cooling loop, `cool_chiller` Chiller plant, `cool_tower`
  Cooling tower (campus/gigasite)

### Network tiles (the key mechanic)
A switch connects every GPU tile orthogonally adjacent to it. Switches adjacent to switches
link up. A **cluster** is a connected group of GPUs joined through switches; GPU-to-GPU
adjacency alone does NOT connect. Every switch has `linkGbps` (display) and `gpuCap`: the
number of GPUs it can keep fed during training.
- garage: `net_home` Home router (1 GbE), `net_5g` 5 Gbit switch, `net_10g` 10 GbE switch
- startup: `net_100g` 100G Ethernet, `net_ib` InfiniBand 400G (requires `interconnect`)
- lab: `net_ib_spine` InfiniBand spine, `net_nvlink` NVLink-ish rack fabric, `net_optical`
  Optical fabric (requires `parallelism`)

**Bottleneck rule:** a cluster's capacity is set by its *slowest* switch
(`clusterCap = min gpuCap over its switches`).
`scalingEfficiency = 1` if `gpus <= clusterCap`, else `(clusterCap / gpus)^0.5`.
UI text: "Your 5 Gbit switch can keep 8 GPUs fed. With 32 GPUs, training runs at 50%."

## Training vs serving
- **Training uses only your largest cluster** (by effective TFLOPS × scaling efficiency,
  across all rooms; the `multi_site` upgrade may later merge rooms with a penalty).
  Training compute = that cluster's effective TFLOPS × scalingEfficiency × run.fraction.
- **Serving uses every other GPU**, networked or not, plus the training cluster's unused
  fraction. Serving doesn't need networking.
- Effect: build one dense, well-networked, well-cooled block for training; spare and old
  GPUs serve users. That's how real infrastructure works.

## Heat
For each GPU tile: `netHeat = heat − ambientCooling − Σ(adjacent cooler share)`.
If netHeat > 0, the tile throttles: `speed = max(0.3, 1 − 0.7 × netHeat / heat)`.
**No destruction** (it's an idle game; offline must be safe). Throttle shows as a red tint.
(Overclocking with burnout risk is a v3 idea.)

## Interactions with existing systems
- Global `utilization` (MFU from software upgrades) still multiplies all GPU TFLOPS.
- `liquid_cooling` upgrade unlocks liquid tiles (and keeps its power reduction). `interconnect`
  unlocks InfiniBand. `parallelism` unlocks the optical fabric and maybe raises gpuCap.
- Power cap is global across rooms; GPU and cooling tiles draw power.
- Tiles can be moved for free (encourages rearranging) and sold for 50%.
- Save format bumps to v2; v1 saves start fresh (unreleased game, fine).

## Sim API (contract the UI codes against)
```dart
enum TileKind { gpu, cooling, network }
class TileDef { id, name, blurb, kind, era, Set<String> rooms, cost, powerKw,
  tflops, heat, gpusPerTile, cooling, gpuCap, linkGbps, requires, minPowerTier }
class RoomDef { id, name, blurb, era, width, height, cost, ambientCooling, tileScaleLabel,
  minPowerTier }
const tiles = <TileDef>[...]; const rooms = <RoomDef>[...];

class TileStatus { TileDef def; double netHeat; double speed; int? clusterId;
  bool inTrainingCluster; double effectiveTflops; }
class Cluster { int id; String roomId; List<(int x, int y)> gpuCells; double gpus;
  double rawTflops; double gpuCap; double scalingEfficiency; bool isTraining; }

// Game
bool isRoomOwned(String roomId); bool canBuyRoom(String roomId); bool buyRoom(String roomId);
String? tileAt(String roomId, int x, int y);
bool canPlace(String roomId, int x, int y, String tileId); // money, power, era, requires, empty cell, allowed room
bool placeTile(String roomId, int x, int y, String tileId);
bool moveTile(String roomId, int fx, int fy, int tx, int ty); // same room; swap if occupied
double sellValue(String tileId); bool sellTile(String roomId, int x, int y);
TileStatus? tileStatus(String roomId, int x, int y);
List<Cluster> clusters(String roomId); Cluster? get trainingCluster;
double get totalGpus;
String? placeBlockReason(String roomId, int x, int y, String tileId); // human-readable
```
Existing getters (`rawTflops`, `effectiveTflops`, `trainingTflops`, `servingTflops`,
`capacity`, `powerUsedKw`...) keep their meaning, now computed from the grid.

## Final numbers (sim, v2)

Source of truth: `lib/sim/content.dart` (data), `lib/sim/grid.dart` (rules),
`lib/sim/game.dart` (API). Pacing: `docs/BALANCE.md`.

### Rules as implemented
- **Ambient cooling** is a room-wide pool: `ambientCooling × width × height`,
  shared evenly by the room's GPU tiles. So `netHeat = heat − pool / gpuTiles
  − Σ(adjacent cooler shares)`. This is what makes "the 3rd–4th GPU gets hot":
  the garage pool is 16 and an RTX 4090's heat is 4.5, so 3 GPUs are cool and
  the 4th throttles (speed ≈ 0.92) until a fan goes next to it.
- **Coolers** split `cooling` evenly among their orthogonally adjacent GPU
  tiles; a cooler next to no GPU does nothing. Spare cooling isn't carried
  over (netHeat < 0 just means headroom).
- **Clusters**: union-find over switch tiles (switch–switch links) plus every
  GPU tile touching a switch, so a GPU touching two switch networks joins
  them. A GPU tile touching no switch is a **cluster of one** (gpuCap = its own
  GPUs, efficiency 1): a lone GPU or 8-GPU server can always train by itself.
  `clusters(room)` includes these lone clusters (`Cluster.networked == false`).
- **Training cluster** = the cluster with the highest
  `rawTflops × scalingEfficiency` over all rooms (ties: first in room order,
  then row-major). `trainingTflops = that × utilization × run.fraction`.
  `servingTflops = effectiveTflops − trainingCluster.effectiveTflops ×
  fraction` (+ cloud). The scaling-efficiency loss is wasted, not served.
- `rawTflops` (Game and Cluster) is after heat throttling, before MFU;
  `peakTflops` ignores heat. `effectiveTflops = rawTflops × utilization`.
- **Power**: GPU tiles × `powerMult` (liquid cooling −15%) + cooling and
  network tiles as listed, one global cap.
- **Selling** refunds 50%; the last GPU can't be sold. **Moving** is free
  (swap if occupied, same room only). **Replacing** (e.g. a switch upgrade)
  sells the old tile and charges the difference; only the extra kW must fit.
- `parallelism` doesn't raise gpuCap; it unlocks the optical fabric.
- Startup unlocks at 3k users (was 5k): a 4×4 garage holds ~8 GPUs.
- Start: garage with one RTX 4090 (`gpu_gamer`) at (1, 1), $500 (a fan is $120, a router
  $150).

### API additions beyond the contract
`TileDef.isGpu/isCooling/isNetwork/tflopsPerKw`, `RoomDef.cells/ambientTotal`,
`tileById(id)`, `roomById(id)` (nullable), `GameState.grids` /
`tileAt` / `setTile` / `tileCounts` / `startedFromOldSave`,
`Game.ownedRooms`, `roomBlockReason`, `isTileUnlocked`, `tileLockReason`,
`tilesForRoom`, `replaceTile` / `replaceBlockReason`, `sellBlockReason`,
`tilePowerKw`, `peakTflops`, `trainingClusterTflops`;
`placeBlockReason(..., {ignoreMoney})`; `TileStatus.ambientCooling /
adjacentCooling / adjacentGpus / throttling`; `Cluster.switchCells /
peakTflops / effectiveTflops / bottleneckTileId / networked / trainingTflops`.

### Extra tile
`pod_r_class` ("Rubin SuperPOD", campus, power-plant tier). Art: `tile_pod_r_class`.

Display names use real GPU products (RTX 4090, H100, GB200 NVL72, ...); ids keep the
old class names. Lab and company names stay parody.

### Rooms and tiles
| room | size | GPU tile = | ambient/cell (total) | cost | needs power tier |
|---|---|---|---|---|---|
| `garage` Garage | 4×4 | 1 GPU | 1 (16) | free | 0 (outlet) |
| `closet` Server closet | 6×6 | 8-GPU server | 4 (144) | $10k | 2 (office) |
| `colo` Colocation cage | 8×8 | 8-GPU server | 8 (512) | $200k | 3 (colo) |
| `hall` Datacenter hall | 10×10 | rack (32–72 GPUs) | 30 (3000) | $1.5M | 4 (hall) |
| `campus` Datacenter campus | 10×10 | pod (~1k GPUs) | 60 (6000) | $15M | 5 (campus) |
| `gigasite` Gigawatt site | 12×12 | building (~16k GPUs) | 100 (14.4k) | $50M | 7 (gw_campus) |

| GPU tile | rooms | GPUs | TFLOPS | kW | heat | cost | locks |
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
| `bldg_r_class` | gigasite | 16.4k | 57.3M | 54.1k | 900 | $800M | liquid_cooling, tier 7 (gw_campus) |

| cooling tile | rooms | cooling | kW | cost | locks |
|---|---|---|---|---|---|
| `cool_fan` | garage | 4 | 0.05 | $120 |  |
| `cool_window_ac` | garage | 10 | 0.9 | $500 |  |
| `cool_crac` | closet, colo | 40 | 3 | $12k |  |
| `cool_rear_door` | closet, colo | 90 | 1.5 | $40k | liquid_cooling |
| `cool_chiller` | hall, campus | 300 | 40 | $150k |  |
| `cool_liquid` | hall, campus | 450 | 10 | $250k | liquid_cooling |
| `cool_tower` | campus, gigasite | 1800 | 200 | $4M |  |

| network tile | rooms | gpuCap (GPUs) | Gbps | kW | cost | locks |
|---|---|---|---|---|---|---|
| `net_home` | garage | 4 | 1 | 0.01 | $150 |  |
| `net_5g` | garage | 8 | 5 | 0.02 | $600 |  |
| `net_10g` | garage, closet, colo | 32 | 10 | 0.05 | $2.5k |  |
| `net_100g` | closet, colo, hall | 256 | 100 | 0.5 | $20k |  |
| `net_ib` | closet, colo, hall, campus | 4096 | 400 | 1 | $60k | interconnect |
| `net_ib_spine` | hall, campus | 32.8k | 800 | 10 | $1M | interconnect |
| `net_nvlink` | hall, campus, gigasite | 131.1k | 14.4k | 30 | $5M |  |
| `net_optical` | campus, gigasite | 4.2M | 1600 | 100 | $30M | parallelism |
