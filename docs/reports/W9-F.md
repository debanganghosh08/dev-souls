# W9-F: firelight

The owner, after playing at night: *"as the game continuously shifts from day to night… at night there are no
guided things: no fire, nothing. It becomes very hard for me and any player who would play to see through the
castle or see anywhere on the map."* Asked for: a fireplace at every house design, with remains around it
(half-burnt cloth, food cans, bones) for the eerie read; a fire-holder stick outside the shacks with a flame
that appears as the player comes near; fire in random places across the map; lamps on rocks beside the road;
the castle decorated inside and a little outside with lit things; and on the watch hut, a fire on top with
smaller ones lit below.

## What changed

- **`scripts/systems/structures/fire_light.gd`** (new, 238 lines). `FireLight extends OmniLight3D`: the light
  and the flame of one fire. Two beating sines gutter the energy and the flame together (the same trick
  `HearthSite` uses, so no fire finds a rhythm), the phase fixed per fire from where it stands. Never casts a
  shadow. Culls itself past `cull_distance` and the engine fades the light out a little past its own reach, so
  a flame visible at 240 m costs two triangles and no light. The camera, the hour and the darkness are read
  **once per frame for the whole world** (statics keyed on `Engine.get_process_frames()`, not
  `get_frames_drawn()` — a headless run draws nothing and the count would never restart), not once per fire.
  The flame is one billboarded (`BILLBOARD_FIXED_Y`) additive unshaded quad on a 64x64 teardrop texture
  **painted in code**: no fire texture exists in `assets/` and D-005 keeps binaries out of git.
- **`scripts/systems/structures/kit_fire.gd`** (new, 251 lines). Seven kinds, each returning the usual piece
  plus a `lights` list: **brazier** (iron bowl on three splayed legs, coals), **torch_post** (post, iron band,
  rag head — the fire-holder stick), **wall_torch** (bracket and sconce, mounted at whatever height its layout
  gives it; the only kind that does not sink), **hearth_remains** (ring of stones, charred logs burning, a back
  slab, and what whoever sat there left: two bundles of half-burnt cloth, four bones, a pot on its side, a
  can), **lamp_stone** (a lantern cage on a boulder — the wayside light), **pyre** (crossed timbers in a square
  well, on a buried footing), **beacon** (iron fire basket on a mast; the longest reach in the kit). Every
  light field is overridable from the layout params: `energy`, `range`, `flame`, `flicker`, `day`, `cull`,
  `color`.
- **`kit.gd`**: `make_node`/`make_multi` hang one `FireLight` per light spec **per placement**, so instanced
  wall torches stay one MultiMesh draw and one body with N small lights. A piece with no `lights` gets none.
- **`materials.gd`**: five flat-coloured kinds for the lit kit (`iron` metallic, `char`, `cloth`, `bone`) plus
  **`ember`**, the only material in the kit that emits: emission 2.6 over the glow threshold in
  `scenes/environment/sky.tscn` (1.2), so a coal bed blooms a little at night and costs nothing but its pixels.
- **`settlements.gd`**: `_limit_draw` skips a `FireLight` — a house draws to 320 m, a fire must keep its own
  far shorter cull.
- **`vale.gd`**: a new `PROBE fires` line (total, drawing this frame, worst crowd in one 60 m sphere, cull,
  distance to the nearest fire from the spawn).
- **Data, 103 fires over 51 sites.** All 13 house layouts: a hearth with remains or a brazier in the yard, a
  torch post or a lamp by the door, a wall torch inside the barn, the cottage with blockwork and over the
  shrine altar, and a **beacon on the lookout floor of both watch huts** with a hearth and a brazier below it.
  21 new wayside sites in **`data/sites/vale_lights.json`** (way lamps every ~19 m on alternating verges of the
  old road, a brighter brazier at every fourth, four watchfires, four lost hearths out in the empty ground, two
  more on the way in from the spawn) built from **4 new layouts** in `data/structures/pois/` (`way_lamp`,
  `road_brazier`, `lost_hearth`, `watchfire`). The **eight camps** whose fire rings were cold
  (`campsite`, `crossroads`, `picket`, `shore_fire`, `siege_camp`) now burn: their `campfire` piece became
  `hearth_remains`, so no new placements were needed. **21 in Castle Morrow** — gate braziers, wall torches on
  both faces of the gatehouse, a courtyard pyre, a wall-walk brazier, three chapel torches and one over the
  altar, a chapel brazier, two graveyard lamps, torches down the crypt mouth and in the crypt, a brazier on the
  crypt floor, a brazier in the keep — and **8 in the broken village**, including a beacon at its edge.
  Every wayside spot was picked against the real heightfield: 4.9 m off the valley polyline, at least 0.8 m
  above the water, falling no more than 1.2 m across its footing, and clear of the pond basin, both plateaus,
  every other site and every house anchor.
- **`tests/test_firelight.gd`** (new, 345 lines, 12 tests).

## Checks (console build, headless, main checkout)

- `--headless --import`: exit 0, no errors.
- `run_tests.gd`: **PASS 419 / FAIL 0** (was 406), **0 SCRIPT ERROR** in stdout and stderr, per-file sums
  419/0 over 49/49 files.
- Live scene: `PROBE sites fixed=3 spawned=87 props=29 pieces=504 keepout_cells=13236 keepout_obbs=478` and
  **`PROBE fires total=103 drawing=9 worst_crowd_60m=26 cull=90 nearest_to_spawn=21.7`** — of 103 fires, nine
  are drawing from the spawn, and at most 26 can ever fall inside one 60 m cull sphere (the castle holds 21 of
  those by itself). Grass unaffected: `grass_fill_worst_ms=2.551`, none over 4 ms in that run.
- **The road is never dark for long: the darkest walkable point is 24.8 m from a fire**, at (181, -144),
  sampled every 8 m along the valley polyline outside the pond basin (42 points; the basin is water).
- **Negative control** (D-021), `data/sites/vale_lights.json` held back: 82 fires over 30 sites, and the
  darkest stretch of road goes to **57.7 m** at (118, -91), the climb to the castle. That run also found a
  flaw in this test: at the 60 m limit first written, the road test **passed without the lights it exists to
  check** (the houses and camps alone keep it at 57.7 m). The limit is now 40 m, which only the wayside
  lights reach, and the control fails it by 17.7 m. Restored, and the suite is green again.

## Not verified, plainly

- **Nobody has seen a single flame.** The teardrop texture, the additive blend, the billboard, the gutter
  depth, every colour and every energy: all written against a null renderer. They are all data or one
  constant, so they are cheap to retune once there is a screenshot.
- **The flame has no smoke, no light-shaft, no heat shimmer, and does not move its shadow** — it has no
  shadow. A one-quad flame may read as flat from very close.
- **Night away from a fire is still pitch dark.** The fires only help where something was built; the open
  meadows and the rim are untouched, and `moon_energy` is 0.12. Logged as W9-F2.
- **A fire can stand in grass.** House-yard fires were deliberately left out of the keep-out mask, because a
  `keep_out` rect also grows the footprint the house is floored on and would move twenty houses up or down.
  Blades may poke through a ring of stones; the burnt disc under each fire is what hides it.
