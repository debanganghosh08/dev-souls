# World plan — filling the Ashen Vale (W8)

**Why.** The owner, after playing: *"Apart from the castle I don't think there is much to do in the game right
now… the game feels too empty."* The castle hill is bare ground, there are no houses outside the village, and a
1 km² valley has one destination in it. Elden Ring's lesson is that something worth walking to is always in
view, and the ground itself is never bare.

**Rule of thumb for the whole plan:** from anywhere walkable, something built should be visible within
~60–80 m, and the ground under your feet should almost always be grass, a road, or a floor.

## 0. The foundation (lead, done before any of the below)
Built first so three agents can fill the map in parallel without inventing three placement systems.
- `data/sites/vale.json` — the fixed sites (castle, village, Hearth chamber). `vale_houses.json` and
  `vale_pois.json` — the new ones, one file per agent so they never edit the same file.
- `SiteRegistry` — loads every site; `Footprint` — where each layout piece meets the ground (oriented
  rectangles, so a house turned 37° is masked as itself, not as a box); `KeepOutMask` — those footprints
  rasterised to 0.5 m cells, one lookup per question.
- **Grass, trees and scattered props now keep off built ground instead of off whole plateaus.** That one change
  is what lets grass grow up the castle hill, round the village and in the castle courtyard.
- `Settlements` — builds every non-fixed site from data, at the **highest** ground under its footprint (no
  corner ever floats), with its loot. Repeated layouts **share one set of meshes and collision shapes**.
- Two extension kits, `kit_house.gd` and `kit_props.gd`, so new piece types never collide in one file.

## 1. The map, region by region
Coordinates are world metres. +X east, −Z north. The pond is the origin; the playable valley is roughly a disc of
radius 395 inside the ridge. The old road (already in the terrain as the valley channel) runs
**village (−200, 140) → (−90, 70) → pond (0, 0) → (105, −80) → castle (200, −160).**

| # | Region | Where | Grass | What is built there |
|---|---|---|---|---|
| R1 | **Mirror Pond & the Grave** | r < 100 round the pond; spawn at (49, 76) | Shore ring greener and damp; meadow beyond | Old Maren's gravekeeper cottage near the spawn; a fisher's shack on the shore; a wayside shrine where the road meets the pond; a jetty, a campfire ring |
| R2 | **The West Road** | the road from the pond to the village | Worn dirt road, meadow either side | A roadside stone cottage; an overturned cart; a signpost at the fork; field walls |
| R3 | **Broken Village outskirts** | 60–120 m round (−200, 140) | Trampled inside the village, meadow outside | Two cottages, a shack, a barn; a well, haystacks |
| R4 | **Southwest farms & dead orchard** | around (−230, −60) to (−120, −200) | Tall golden meadow, the densest in the Vale | Two barns, a farmhouse cottage, an orchard shack; fences, scarecrows, haystacks |
| R5 | **North hills** | z < −200, x −150 … 100 | Short, dry, sparse on the tops | A watch hut on a summit (a view and a reward for the climb); a shepherd's shack; cairns, a stone ring |
| R6 | **East Road & Castle Hill** | the road from the pond to the castle, and the hill's 80 m skirt | **Dense golden grass all the way up the hill** — the owner's first complaint | A toll-and-watch hut at the foot of the hill; a roadside shrine; the remains of a siege camp |
| R7 | **East woods** | the forested east | Under-canopy: ferns and leaf drifts as now | A woodcutter's shack, a sawpit, a watch hut on the ridge edge |
| R8 | **South meadows** | z > 200, x −50 … 200 | Lush, greenest, with wildflowers | A hermit's shack, cairns, a grave mound |
| R9 | **The map's edge** | r ≈ 360–390, at the ridge foot | Sparse, pale straw | A hidden shrine holding something rare; a lone shack. *"At the map edge"* is a hiding place the design promises |

## 2. Houses — five archetypes, twenty placements (W8-H)
Built from the existing kit (walls, broken walls, roofs, timber frames, slabs, stairs) plus new house pieces in
`kit_house.gd`. Every archetype has **an intact and a ruined variant**, and placements vary by yaw and by
material; with five archetypes that is ten distinct buildings shared across twenty sites.

| Archetype | Size | Character | Placements |
|---|---|---|---|
| **Shack** | ~3 × 4 m | Plank walls, lean-to roof, one door | 6 — fisher (R1), village (R3), orchard (R4), shepherd (R5), woodcutter (R7), hermit (R8) |
| **Stone cottage** | ~5 × 6 m | Stone walls, slate roof, door and window, hearth, loft | 5 — Maren's (R1), roadside (R2), outskirts ×2 (R3), farmhouse (R4) |
| **Barn / warehouse** | ~8 × 12 m | Timber frame, plank walls, wide doors, hayloft with stairs | 3 — near the village (R3), farms ×2 (R4) |
| **Watch hut** | ~3 × 3 m | Stone base, timber lookout reached by stairs | 3 — north summit (R5), castle foot (R6), east ridge (R7) |
| **Wayside shrine** | ~3 × 4 m | Arched front, altar, candles | 3 — pond junction (R1), east road (R6), map-edge secret (R9) |

**Foundations.** A site's floor sits at the highest ground under it; every archetype carries a stone foundation
reaching ~2 m down so the low side is never open, and a front step wherever the floor stands more than the
0.4 m step-up above the ground at the door.

**Loot — every house holds something.** About 20 new items, all in the souls voice of the existing ones, all
**DRAFT pending the owner's sign-off (O-3)**:
- *Lore items* that tell Hollowmere's story through the people who lived in it — Maren's spade, Pell's carved
  fish, Ser Aldous's oath ribbon, a toll ledger, a letter never sent, a siege tally stick.
- *Lore that points at the main quest* — the toll ledger records the Sluice Wheel being carried off toward the
  Barrens; a shrine's tablet carries a verse whose capitals hide a syllable. Hints in fragments, never a map or a
  marker — the design's own rule for NPCs, applied to objects.
- *Two keys* that make small puzzles of their own: a locked cottage whose key is in a barn across the valley; a
  watch-hut chest whose key is at a shrine.
- *The three weapons* get proper homes. The sword, the hammer and the torch currently come from wherever the
  first chests put them; each gets a deliberate place.
- **Nothing that belongs to another area moves into the Vale.** The Sluice Wheel and two Kindlings stay where
  the design puts them.

## 3. Points of interest — the small things between (W8-P)
New pieces in `kit_props.gd`, composed into ~25 small layouts and spread so the gaps between houses are never
empty: **well, cart (upright and overturned), fence runs, haystacks, scarecrows, cairns, signposts, campfire
rings, tent frames, weapon racks, grave mounds, a jetty, dry-stone field walls.** Scenery only — all loot lives
in the houses file, so every item in the game has exactly one place it comes from.

## 4. Grass everywhere (W8-G)
- **Every walkable surface grows grass unless something is built on it, it is under water, or it is a road.**
- **Zones**, each a density and a palette, in data so the owner can retune them:

| Zone | Density | Look |
|---|---|---|
| Meadow (default open ground) | 1.0× | Olive to gold, with green running through it |
| Tall meadow (noise patches, the castle hill skirt, the southwest farms) | 1.4× + a tall-grass layer | Golden, waist-high |
| Pond shore (42–75 m from the pond) | 0.9× | Greener and damper |
| South meadows | 1.1× + wildflowers | The greenest in the Vale |
| Roads (the old road, ±2.5 m) | near zero in the middle | Worn dirt — readable from a distance |
| Inside settlements (castle courtyard, village) | ~0.45× | Short, trampled |
| Ridge foot and hilltops | ~0.6× | Pale, dry straw |
| Under trees | as now | Ferns and leaf drifts |

- **Colour**, per blade, from the zone palette plus a slow colour noise across the valley, so no two fields are
  quite the same green. Moved away from the old "no saturated green" ashen brief: the owner asked for
  *beautiful*. Still dark-fantasy, not cartoon (D-001).
- **Wildflowers** — a sparse new layer: yellow, white and violet specks in the meadows.
- **Budget:** the grass fills on a 2 ms CPU budget (D-019). Denser grass costs more cells per frame, so the test
  is that **at sprint speed there are no unfilled cells within 30 m of the player.**

## 5. Jump (W8-J — in progress)
F key. ~1.1 m apex, costs stamina, coyote time and a jump buffer, no double jump, no fall damage from its own
landing. Reaches a 0.6 m and a 0.9 m block, not a 2 m ledge — enough for rubble, kerbs and broken masonry,
which is where the owner wants it.

## 6. Who does what, and how it lands
| Task | Owner | Touches |
|---|---|---|
| Foundation | lead | `scripts/systems/sites/`, `data/sites/vale.json`, `vale.gd` filters, `StructureBuilder` hooks |
| W8-J jump | Fable | player controller, input map, animation rig |
| W8-G grass | Fable | grass scripts, `data/grass/`, `vale.gd._grass_density` only |
| W8-H houses | Fable | `kit_house.gd`, `data/structures/houses/`, `data/sites/vale_houses.json`, items and lore |
| W8-P points of interest | Fable | `kit_props.gd`, `data/structures/pois/`, `data/sites/vale_pois.json` |

Each lands on its own branch; the lead merges, runs the full suite, checks for `SCRIPT ERROR` lines, re-exports
the Windows build and re-runs its probe.

**What no agent can judge:** how any of this looks. Headless has no renderer. After it lands, screenshots of the
castle hill, a meadow and a house interior are the fastest way to tune colours and density.
