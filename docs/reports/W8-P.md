# W8-P: the small things between the houses

## What changed
- **`scripts/systems/structures/kit_props.gd`** (was empty) + new **`kit_props_camp.gd`** (forwarded to, so each stays under 300 lines).
  Twelve kinds, vertices with default params: **well** 384 (stone ring + timber frame as two surfaces of one mesh; dry, floor at 0.15 m),
  **cart** 368 (tipped with the layout's `tilt`), **fence** 240 per 6 m (`length`, `spacing`, `rails`, `broken`: leaning posts, at least one
  top rail on the ground, only whole bays collide), **haystack** 260, **scarecrow** 120, **cairn** 168, **signpost** 72, **campfire** 404
  (stones, charred logs, burnt disc), **tent_frame** 120 (bare or planked: the kit has no cloth), **weapon_rack** 192, **grave_mound** 120,
  **trough** 168. Every standing piece reaches `sink` (0.8 m) below the ground because Settlements floors a site at its highest ground and
  these have no foundation. None is a `Footprint` ground kind, so every layout lists `keep_out` rects for the ground its pieces cover
  (grass, trees, the road/overlap rules and my anchor test all read those).
- **15 layouts in `data/structures/pois/`**: well_trough, haystacks, farm_corner, field_gate (kit `wall`/`broken_wall` at 0.9 m as dry-stone
  walls, gate hanging open), crossroads (signpost at the origin so it sits nearest the road), campsite, siege_camp (4 tents, 2 racks, cold
  fire, tipped cart, palisade stub), field_graves (6 mounds, cairn, one headstone), lone_grave, cairn_trio, cairn_lone, stone_ring (kit
  `block`s, one fallen, altar slab), shore_fire, picket, orchard_fence.
- **35 placements in `data/sites/vale_pois.json`** (brief said ~25; the extra ten are cairn groups and lone graves filling gaps), chosen from
  the real heightfield with a scratchpad scanner, never by eye: R1 shore fire + cairn on the east shore (the basin is below water out to
  r ~ 85 and the east is its only dry shore inside r ~ 105); R2 crossroads 6 m off the fork's north side, field wall with gate, road cairn;
  R3 village well + trough, haystacks, farm corner; R4 two farm corners, field gate, orchard fence; R5 stone ring, two cairn groups, a
  shepherd's grave, cairns at (60, -200); **R6** the siege camp on the flat plateau before the gate (224, -108) with field graves at
  (190, -98), a picket and a campsite where the road climbs onto the plateau (140, -148 / 138, -168), a cairn on the road's climb and
  cairns behind the castle (the approach skirt is 13-19 degrees, too steep for anything bigger than a cairn); R7 woods camp + cairns;
  R8 grave, cairns, hermit's cairn, cairns at (160, 110); R9 two graves and three cairns at the edge, lowest one 0.8 m above water.
  Scenery only: no `props`, nothing in items or lore.
- **`tests/test_pois.gd`** (10): every kind builds geometry and collision and is not also claimed by the house kit; standing pieces reach
  below ground; broken fence; tilt; every layout builds every piece and declares ground; every keep_out holds a piece; **every footprint
  >= 25 m from all 20 house anchors**; scenery only; cost budget; the vale probe spawns >= 35 and masks >= my footprints.

## Checks (console build, headless; worktree merged with `main` 1c3dc88 first; assets plain-robocopied, 0 reparse points)
- `--headless --import`: exit 0, 0 ERROR lines before and after.
- `run_tests.gd`: **before PASS 368 / FAIL 0, 0 SCRIPT ERROR; after PASS 378 / FAIL 0, 0 SCRIPT ERROR** (+10). `test_site_placement.gd` 6/6 with
  all 35 sites, unchanged. Direct probe: `PROBE sites fixed=3 spawned=35 props=0 pieces=123 keepout_cells=7921 keepout_obbs=232`.
- Cost of the 35 sites: **23,396 vertices and 197 colliders** in 137 piece instances; 15 layouts shared (`share_pieces`).
- **Negative control**, shore_cairn moved to (70, 130): `FAIL test_every_poi_keeps_clear_of_every_house_anchor: shore_cairn keeps 25 m from
  the house anchor [70, 130] (0.0 m)`; restored, 10/10 again.

## Not verified, plainly
- **Nothing visual.** Whether a scarecrow reads as a scarecrow, a haystack in `plaster` as hay or the `timber` flat colour as charred wood,
  whether 35 small things are enough or too many: unseen, null renderer. All sizes are layout JSON to retune. Pieces are `sink`-buried, not
  founded: on a drop the uphill side sits proud by up to 1.6 m (worst: the east-road cairn, 20-degree skirt). No jetty: the pond fails "dry".
