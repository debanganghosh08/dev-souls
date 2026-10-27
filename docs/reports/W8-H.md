# W8-H: five house archetypes, twenty placements, and a home for every item

## What changed
- **`kit_house.gd`**: `lean_roof` (one slab sloping to +Z, overhanging), `lean_wall` (top climbs to +X; `wall`'s pier arithmetic for its
  opening, one wedge on top), `gable` (two wedges back to back: flat-topped walls left an intact pitched roof open at its ends). All via
  `StructureKit.builder`.
- **`data/structures/houses/`**, 13 layouts (one scratch generator keeps them consistent; the JSON is the data): shack ×3 (planks,
  plaster, ruined), cottage ×4 (stone/blocks × intact/ruined), barn, watch, shrine (intact/ruined). Each: floor slab (top 0.12), a 2 m
  stone foundation buried at y −2 (not ground, D-022), a six-tread stone **doorstep** from y −1.6 to the slab top (buried on flat
  ground, its upper treads show on a slope) under a `keep_out`, and `door`/`lofts` blocks the tests read. Lofts: cottage 2.1 m (roof
  rise 2.4 keeps 1.75 m headroom at the edge), barn 2.7 m, watch lookout 3.12 m by an outside stair landing at a parapet gap.
- **`vale_houses.json`**: 20 sites exactly at the lead's anchors (every ground drop ≤ 0.92 m of the 1.6 allowed), yaw toward the road or
  the approach, 29 props. Shacks: fisher, village (ruined), orchard (ruined), shepherd (plaster), woodcutter, hermit (plaster). Cottages:
  Maren, road (blocks, **locked**), outskirts N (ruined blocks) and S, farmhouse (ruined). Barns: village, farm W (ruined), farm S.
  Watches: north, castle foot, east ridge (ruined). Shrines: pond, east road (ruined), map edge.
- **`items.json`** +20, DRAFT O-3 in `_comment`: keys `cottage_key`, `watch_key`; writings `unsent_letter`, `bell_ringers_hymnal`,
  `toll_ledger` (the Sluice Wheel carted east, no toll taken), `siege_tally`; keepsakes `maren_spade`, `hearth_ash`, `pell_fish`,
  `candle_stub`, `cracked_mirror`, `dog_collar`, `rust_sickle`, `orchard_apple`, `pruning_hook`, `shepherd_crook`, `watchmans_horn`,
  `oath_ribbon`, `woodcutter_wedge`, `pilgrim_token`. New kind `keepsake` ("Keepsakes" in `ui_text.json` + `UiText.DEFAULTS`).
  **`lore.json`** +6 tablets; `pond_shrine_verse` hides A·S·H in its capitals as a **placeholder** the owner should set to the crypt's syllable.
- Where the big three live: **`castle_key`** + `oath_ribbon` in the castle-foot watch chest, locked by `watch_key` from the ruined
  east-road shrine's altar (Ser Aldous's story until he exists); **`hammer`** in the village barn's hayloft; **`sword`** on the
  map-edge shrine's altar. `cottage_key` (farm_barn_s hayloft) opens the west-road cottage's door: the letter to Tam and Bram.
  `torch` stays in the village chest. Nothing from the Wood or the Barrens was placed; the endgame is not completable.

## Checks (console build, headless only; merged `main` 1c3dc88 first; `assets/` plain-robocopied, 0 reparse points)
- `--import` before/after: exit 0, 0 ERROR. Suite **before PASS 368 / FAIL 0, 0 SCRIPT ERROR; after PASS 381 / FAIL 0, 0 SCRIPT ERROR** (same 9 deliberate ERROR lines both runs; +12 `test_houses.gd`,
  +1 `test_terrain.gd`: `PROBE sites` spawned = every non-fixed site, 20 of them houses, props = 29; item counts 13→33 in
  `test_overlays`, `test_inventory`, `test_inventory_panel`). `test_site_placement.gd` untouched and green.
- Doorsteps over the real heightfield: every stair foot **buried** 0.85–1.60 m; thresholds 0.00–0.66 m over the ground at the door
  (east_road_shrine shows three treads). Negative controls, seen to fail, then restored: `north_watch` lifted 3 m →
  `doorstep's foot ... (hangs 1.40 m)`, `threshold ... (3.01)`; hermit pickup set to `sword` → `sword has exactly one source (found
  ["hermit_shack/hermit_token", "edge_shrine/edge_shrine_sword"])`, `pilgrim_token ... (found [])`.
- Audit: 33 items; 26 with exactly one source (castle, village, Hearth scenes + every site's props; greybox excluded), 7 other-area items
  with none. Walkability from built collision: the capsule fits inside and outside every door, over ≥ 50 % of every floor and beside
  every prop; stairs 1.0 m wide, risers ≤ 0.3; loft stairs land within a riser of their slab, at its edge.
- Cost (verts / colliders / draw instances): shack 492/20/8 (ruined 738/30/9), cottage 960/41/16 (ruined 1140/48/13), barn 1056/45/16
  (**ruined 1764/74/16, the heaviest: rubble ×8 + collapsed roof**), watch 1104/46/16 (ruined 1152/48/14), shrine 864/37/14 (ruined
  1092/46/12). Twenty sites add **258 draw instances, 783 colliders, 18,660 drawn verts**; meshes are shared per layout.
## Not verified: anything visual (no renderer): whether a house reads as a house, whether the door model fits a 1.4 m opening, materials by eye; the walk is collision arithmetic, not a played run. W8-H is not in `docs/TASKS.md`; nothing marked there.
