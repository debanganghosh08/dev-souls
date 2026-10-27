# W8-G: grass everywhere, in zones of density and colour

All figures are **CPU-side, headless (null renderer), this laptop**, from the vale probe. Headless proves density, coverage,
counts and CPU cost; it says **nothing about how the grass looks** and **nothing about GPU cost** (instances, draw calls, blade
vertices are up by about half; what that costs a real frame only the owner's eyes and a real run can say). The game, editor
and any window were never launched. Every palette and density below is **UNVERIFIED by eye** and in data for the owner to tune.

## What changed
- `data/grass/zones_vale.json` + `scripts/systems/grass_zones.gd` (pure, static-free, no nodes): zones in paint order, each a
  soft shape (base / noise / rect / ring / plateau top / plateau skirt / height / road) and the channels it sets (density,
  blade height, tall-grass weight, wildflower weight, root/tip palette), lerped by weight so zones blend; plus a slow colour
  noise (green/gold and light/dark over ~220 m) so no two fields match. Zones (density x meadow, height, tall, flowers, palette):
  meadow 1.0/1.0/0/0.6 `#2f3a1e`-`#9a9a52`; tall patches (noise 0.011, 0.2-0.55) 1.4/1.15/1/- golden `#3a3a1c`-`#c9a94f`;
  pond shore (42-75 m) 0.9/1.05/0/0.4 `#23331f`-`#6f8f4a`; south meadows (x -50..200, z 200..420) 1.1/-/-/1.0 `#26381c`-`#7fa046`;
  southwest farms (x -260..-110, z -220..-40) and castle hill skirt (rim to foot of the 80 m blend) 1.4/1.2/1/0.2 golden;
  north hilltops (rect z < -190 and height 3.5-7.5 m) and ridge foot (r 335-420) 0.6/0.8-0.85/0/0 dry `#3a3526`-`#b9a77a`;
  castle courtyard and village (plateau discs) 0.45/0.6/0/0 trampled `#2d2f22`-`#8c8460`; road (+-2.5 m, 4 m feather) 0.04/0.65/0/0.
- `vale.gd._grass_density`: keep-out and ridge checks kept exactly; the plateau factor (zero within 118 m of the castle) is gone.
- **Colour per blade.** The shader read a baked root-to-tip vertex gradient and tinted it from `INSTANCE_CUSTOM`. Now the blade
  mesh is white with the per-blade shade jitter in vertex alpha, the MultiMesh **instance colour** (`use_colors`) carries the
  tip, `INSTANCE_CUSTOM.rgb` the root as a fraction of it (`.a` wind phase), and the shader ramps along `UV2.y` (UV.y stays
  the bend mask, so a flower head takes the petal colour without the whole lean). Brightness and dry drift moved to the CPU.
- Two layers in `data/grass/vale.json`: `tall_grass` (clump, 0.8-1.2 m, 0.45/m2 where the tall channel is 1) and `wildflowers`
  (new `flower` kind: stalk + two crossed quads, 14 verts, 0.05/m2 x channel, heads `#e3c54a` `#ece6d2` `#8d74c6`, stem `#3d4d26`).
  The meadow layer's candidate pool is sized for the densest zone (max_per_cell 170 -> 240) so 1.4x is reachable; patch_min 0.3 -> 0.5.
- `GrassCell` samples the zones on its 3 m grid (25 per cell) and the layers read them bilinearly; a tall/flower layer skips a
  cell whose channel is zero everywhere. `GrassLattice.site_factor` is left in place (still tested, no longer used by the vale).

## Coverage (tests/test_grass_zones.gd, pure, with the real keep-out mask, 5 m grid, r <= 380)
14 624 open points: **93.6 %** get >= 0.5x meadow (need 90 %; 63.9 % get >= 1.0x, mean 0.99x, the shortfall is the two 0.45x
settlement discs); 0 bare; negative control (meadow 0.3x) scores 69.4 % and fails. **Castle hill skirt (78-158 m, 2058 points)
averages 1.38x** (need 1.2x), lowest 0.74x, tall weight 0.97; `site_factor` averaged 0.78 there and left the rim bare (it ramps
0 -> 1 over 78-118 m, not zero to 118 m). Village skirt 0.99x. Road: 0.04 to 2 m, 0.34 at 4 m, 0.96 at 6 m, 1.0 at 8 m.
First suite run caught a real bug: the hill was 1.09x because the north-hilltops feather and the ridge-foot ring were painted over
it; the castle hill now paints after both and the hilltops rect stops at x = 100 as the plan says. Determinism and NaN safety tested.

## Instances and cost (3 probe runs each; `--probe` lattice is the 109 cells round the spawn)
| | before | after |
|---|---|---|
| instances / blade verts at the spawn | 8644 / 218 944 (5 layers) | **12 259 / 327 652** (7 layers; tall 1122, flowers 236) |
| sprint end, castle hill (new probe) | 14 165 / 371 232 (control: old data, same rig) | **23 653 / 664 328** (tall 4075) |
| fill, mean / worst ms per working frame, spawn | 4.32-4.47 / 6.39-6.91 | **3.21-3.32 / 9.4-13.0** |
| fill, mean / worst ms, sprint (5 runs) | 3.45-3.48 / 7.1-9.4 (control) | **3.41-3.54 / 12.3-24.2** |

A zoned cell holds ~1.7x the instances; whole-cell filling cost 5.1-5.4 ms mean and 8-19 ms worst at the spawn, 6.1-6.5 / 23-40 ms
in the sprint. Pure (no scene) a cell is 2.1-3.1 ms; the live scene runs the same code ~2x slower and, in a few cells, 3-8x slower in
*every* phase at once (instrumented), i.e. the thread was descheduled or clocked down (hybrid cores / power management: UNVERIFIED), the
same effect the control shows at half the size. **What I did:** the unit of fill work is now **one layer of one cell** (D-019's budget
check runs after each layer; `fill_cells_per_frame` caps cells *started* per frame) and `fill_budget_ms` 2.0 -> **1.0**. The lattice
built is identical for any schedule (test_grass_budget still proves it); the mean working frame is back at the pre-change level; the
worst frames are the stalls above landing inside one grass layer and did not move with the budget. Two budget tests changed because the
contract changed: a zero budget now fills one layer a frame, not one cell. The next lever is `cell_size` 12 -> 9 m on the Grass node in
`vale.tscn` (0.56x work per unit, ~1.8x cells and MultiMesh nodes, so more draw calls, unmeasurable headlessly) -- the lead's call.

## Sprint probe (`--probe-sprint`, tests/test_grass_sprint.gd)
Player at `sprint_speed` 7.0 m/s from (60, 80) toward (300, -120) for 1500 simulated 60 fps frames (175 m: meadow, east road, the castle
skirt), Grass stepped once per frame by hand (its `_process` off, so headless frame pacing cannot flatter it), unfilled cells within 30 m
counted every frame. **max_unfilled_30m = 0, frames_with_unfilled = 0** in every run (10 runs across all schedule variants, plus 2 control runs), 221 cells refilled.

## Checks
`--headless --import` exit 0, 0 ERROR lines before and after. Suite: **PASS 357 / FAIL 0 before, PASS 367 / FAIL 0 after** (+7
zone tests, +3 sprint tests), **0 `SCRIPT ERROR` lines both**, 9 pre-existing ERROR lines and the 31-object leak warning identical.
Worktree `assets/` is a plain robocopy (381 files, no links), not committed. Not verified: the look, GPU cost, the owner's machine.
Over the 300-line guideline: `grass.gd` 370, `grass_zones.gd` 320 -- flagged, not split, to keep the diff reviewable.
