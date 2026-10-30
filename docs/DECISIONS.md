# Decisions log (newest last). The owner can overturn any of these — say so and the lead updates it.

**D-001 (2026-10-10) Art direction: realistic-leaning dark fantasy.** PBR photoscanned textures and props
(Poly Haven, ambientCG), real-proportion humans (Quaternius Universal Base Characters + Universal Animation
Library), heavy fog and per-area grading. No low-poly or cartoon packs for anything the player sees up close.
Why: the owner rejected the toy-like look of the web game and wants an Elden-Ring mood.

**D-002 (2026-10-10) Trees: procedural generator in Godot** (trunk mesh + bark PBR + alpha twig cards cut from
Poly Haven twig atlases, 3–4 archetypes per area, LOD + MultiMesh). It is the approach proven in
`../souls-portfolio` (`src/game/engine/treegen.ts`). Built by the lead in the area milestones. Blender Sapling stays
the fallback for one or two hero trees (Hollow Mother).

**D-003 (2026-10-10) Animals limited to CC0 rigs that exist.** Deer, boar (pig re-skinned), horse, dog/wolf, frog;
crow/owl/vulture = re-skinned pigeon rig. Rat, lizard, scorpion, goat dropped (only CC-BY models exist). Hostile
roles go to wolves, wild dogs and **the Hollowed** — human enemies on the player's rig with Universal Animation
Library attack clips (no extra assets, more souls-like).

**D-004 (2026-10-10) Research reports are leads, not proof.** Every downloaded file is re-checked by the download
script (page licence string must say CC0, size and magic bytes checked) before import, and listed in `CREDITS.md`.

**D-005 (2026-10-10) GitHub = private backup of the project's essence only.** Repo
`github.com/debanganghosh08/dev-souls` (private) holds code, scenes, data, docs, scripts — **no assets or binaries**
(models, textures, audio, builds). Assets are rebuilt from the verified ID lists by the download script. Only the
lead pushes, only reviewed work on `main`, after each merge. Not used for hosting.

**D-006 (2026-10-23) Candle shrines are respawn points.** One per area, lit by the player, becomes the respawn
point via `Game.set_respawn()`. The spawn grave is the default until the first is lit. Why: the owner never
answered the open question and it blocked the respawn code; walking ~1 km back after every trap death is the
classic reason players quit. The owner can revert to grave-only at any time.

**D-007 (2026-10-23) Weekly milestones, Opus leads, Fable implements.** The owner now has a long-term Claude
subscription, so the 2026-10-19 hand-over to Gemini is void. Planning/review is cheap in tokens and high-leverage
while bulk code is expensive, so the lead specs and reviews, Fable subagents write code against those specs, and
Gemini (free on the owner's Google plan) does bulk content and research. Full table in `docs/PLAN.md` v2.

**D-009 (2026-10-24) Photoscan trees stay quarantined; procedural trees confirmed.** Poly Haven's
`fir_tree_01` is 465 MB and `pine_tree_01` is 914 MB — 1.35 GB for two tree species, against a 10 GB project
cap. `tools/assets.json` marks both `optional`: their licence is checked every run but they are only fetched
with `--include-optional`. This re-confirms D-002 (generate trees in Godot from bark + twig-card textures).
**Follow-up worth doing:** we may still want *only the texture files* out of those two assets as twig atlases,
without their geometry — the fetch script currently takes an asset whole or not at all.

**D-010 (2026-10-24) Audio is blocked on a Freesound API key.** Freesound's API returns 401 without a token
and the site download link 404s when not logged in, so all 24 verified CC0 sound IDs from `T-006` are out of
the manifest for now. **Owner action:** create a free Freesound account and API key, then audio can be added.
No substitute source and no scraping around the restriction (AGENTS.md licence rules).

**D-011 (2026-10-24) Licences are asserted from the asset page, not the API.** Poly Haven's API exposes no
licence field anywhere (`/info`, `/assets`, OpenAPI all checked), so `tools/fetch-assets.mjs` reads each asset
page's schema.org JSON-LD and requires both the `license` URL and `copyrightNotice` to say CC0 before writing
anything. Verified live: the CC-BY goat `d7dImmjtF8E` is refused with `SKIPPED licence ... CC-BY 3.0` and
nothing is written. This is how D-004 is actually enforced.

**D-008 (2026-10-23) Godot 4.7.2 stable, Jolt physics, Forward+.** Installed via winget; not on PATH, so every
command uses the full path in `docs/TOOLS.md` (the `_console.exe` build for anything headless). Verified: Jolt
active, Forward+ active, 12 input actions, named 3D physics layers.

**D-012 (2026-10-24) `type: "maps"` — take a texture out of an asset too big to ship.** The scanned conifers
(D-009) hold the one thing procedural trees actually need: an alpha-cut twig atlas. `tools/fetch-assets.mjs`
gained a `maps` asset type that pulls named texture keys out of any Poly Haven asset and leaves the geometry
behind, forcing PNG for anything matching `alpha|mask` because JPEG has no alpha channel. Result: **2.6 MB
instead of 1.35 GB** for both species' twig atlases, now at `assets/textures/shared/twig_{fir,pine}/`.
Measured, not estimated. Procedural trees (W3-03) are unblocked.

**D-013 (2026-10-24) Photoscan meshes are far denser than a game needs.** Measured after import: a treasure
chest is 68k vertices, a boulder 53k, a dead trunk 52k. Godot's importer can generate LODs, but LOD0 stays
heavy and these will be instanced in the hundreds. **Open:** decide between Godot's automatic LODs plus
aggressive distance culling, or adding a decimation step to the pipeline (which would mean a pinned
`@gltf-transform`/`meshoptimizer` dev dependency). Not urgent while the world is empty; decide in W3-02 before
placing anything in bulk.

**D-014 (2026-10-26) A terrain hole is bigger than you authored it, and the structure must floor the whole
thing.** The owner fell through the castle graveyard. The hole in `data/areas/vale.json` was correct; what
was wrong was assuming it was the size it says. `TerrainMesh` drops a cell when the cell's **centre** lies
in the rect, so a 6 x 9 m rect becomes a 6 x 8 m gap snapped outwards onto the 2 m collision grid, extending
roughly a metre past the crypt house on three sides. Nothing was built over that margin, so a 4.6 m shaft sat
under walkable ground. **Rule: whatever is built over a hole must floor the hole's snapped footprint, not its
authored footprint, and the only part left open must be a surface the player can stand on** (here, the stair
flight, widened 1.6 → 2.5 m to fill the shaft wall to wall rather than leaving a 0.45 m slot down each side).
`tests/test_crypt_mouth.gd` re-derives the snapped footprint from the data and walks a 0.2 m grid over it, so
moving the hole, the house or the stairs fails the build. Proven by negative control, not assumed: reverting
the width and deleting one slab reports 515 open samples.

**D-015 (2026-10-26) Ambient occlusion is not optional for cut stone.** The owner's words for Castle Morrow
were "some cardboard kind of thing". The shared `WorldEnvironment` had **no** SSAO, so a flat 0.45-energy sky
ambient filled every corner, recess and crevice evenly and the masonry lost all contact shading. Enabled with
radius 1.2 m, intensity 2.5, power 1.8, light_affect 0.15. Property names checked against `Environment`'s real
property list first, because Godot silently ignores an unknown property in a `.tscn` and the change would have
looked applied while doing nothing. No settings toggle yet: the owner's RTX 3070 Ti absorbs it, but a graphics
quality option belongs in `GameSettings` before release.

**D-016 (2026-10-26) `String.hash()` is stable across processes, so per-piece UV offsets are safe.** W6-02
derives each castle piece's texture offset from `name.hash()` so two identical walls standing side by side do
not line up pixel-for-pixel. The agent flagged cross-process stability as UNVERIFIED. Checked: two separate
headless runs returned byte-identical values for every piece name, and `"".hash()` is 5381 — the DJB2 seed,
i.e. a plain unseeded hash of the characters. So a wall looks the same on the owner's machine and a player's.
Were it ever otherwise the cost would be cosmetic only, but it is not something to leave assumed.

**D-017 (2026-10-26) The Mirror Pond's water has no collision, so the pond is already walkable.** `vale.gd`
builds the water as a bare `MeshInstance3D` with a `PlaneMesh` — no body, no `Area3D`. The player can
therefore walk down the basin's very gentle slope (measured: floor at y = **−11.375**, 0.1° at the centre,
under 1° out to the 42 m rim) and stand on the bottom under 6.4 m of water, whether or not the pond has been
drained. There is no swimming and no drowning. Two consequences: draining is a visual and narrative change,
not an access one; and **a terrain hole under the pond would be a pit the player falls into before the pond
is ever drained** — the castle graveyard bug (D-014) in a new place. So the Hearth's stairwell is capped by a
removable stone slab with collision, gated on `pond_drained`, which is the real seal on the endgame. The
heightfield's water level is deliberately NOT changed by draining: it decides where grass and trees may grow,
and a basin that has just stopped being a pond must stay bare mud.

**D-018 (2026-10-26) The terrain's load time is frame-bound, not CPU-bound — so the obvious fix is the wrong
one.** Measured, three runs, headless: the wall clock for a full vale build is 2082–2182 ms unthrottled and
**4058 ms at 60 fps**, but the CPU actually spent inside `_build_chunk` is only **1.86–1.93 s** — height
sampling ~1.05 s (55 %), LOD mesh building ~0.8 s (43 %), collision faces ~43 ms (**2 %**), the rest node
creation. One chunk costs **~7.4 ms** against `build_budget_ms = 6.0`, and the loop builds one chunk
unconditionally and then only continues while under the deadline, so **it builds exactly one chunk per frame
for ~234 frames.** The owner's 5150 ms fits ~234 frames on a slower frame rate; it was not reproduced here.
So the build is waiting for frames, not for work, and raising the budget does not make it cheaper — a budget
of 8 ms would build two chunks and cost 14.8 ms, buying load time by paying for it in hitches while the
player walks. And the budget cannot help in the other direction either: `_process` builds one chunk
**unconditionally** and only then checks the deadline, so **~7.4 ms a frame is the floor whatever the budget
is set to**. The consequence worth knowing is not the load screen — `begin_build` primes the chunks around
the spawn synchronously, so the window appears before this starts — it is that the **first ~234 frames of
play carry a 7.4 ms tax**, about 44 % of a 60 fps frame for roughly four seconds, with the grass's 2 ms on
top. That is where the owner should look for a stutter just after spawning, and it is the real argument for
threading rather than tuning. **Open, deliberately not done:** move `TerrainMesh.sample_grid` (55 %, pure and read-only over
the Heightfield) onto a `WorkerThreadPool` task so the main thread only builds meshes (~3.2 ms a chunk). That
turns on whether `FastNoiseLite` tolerates concurrent reads, which is UNVERIFIED and must be proven before
anyone relies on it. Collision generation at 2 % needs nothing.

**D-019 (2026-10-26) Grass fills on a time budget, not a cell count.** Measured: at a fixed three cells a
frame a working frame averaged 3.5–4.0 ms and the worst was 5.4 ms (one 10.3 ms outlier), about 1.2 ms a
cell. Sprinting does not make a frame dearer — the cap is per frame either way — it makes working frames more
frequent, so the worst sprint frame is simply the worst three-cell frame, and that was over the 4 ms line a
single system should not cross. Now `fill_budget_ms = 2.0` with the old count kept as a hard cap: worst frame
3.6–4.4 ms, mean 2.6–2.8. The world it builds is provably identical — same cells, instances, blade verts and
audit counts in the probe — only reached on a different schedule. **Caveat: these are CPU numbers from a null
renderer.** The GPU cost of 8240 MultiMesh instances and 219k blade vertices is unmeasured, so "does it
hitch?" is only half answered; the other half needs the owner's eyes on a real frame.

**D-020 (2026-10-26) The game exports to a standalone Windows build, and it works.** Until today nobody had
ever tried, which made the project's entire purpose — "people can download it for PC" — the largest
unverified assumption in it. Done now: `export_presets.cfg` (committed; it is config, not a binary) produces
`DevSouls.exe` 104 MB + `DevSouls.pck` 422 MB, **526 MB**, into the git-ignored `builds/`. Verified by
running the exported build's own `--probe` headlessly: menu → vale → death → respawn → inventory → item card
→ equip → ending card, seven PROBE lines, **zero errors, exit 0**. That is the strong result, because a
missing resource would have failed loading `player.tscn` immediately: the 268 MB of CC0 art is git-ignored
but lives under `res://`, and an export does not consult `.gitignore`, so it is all in the pack.
The templates (1.19 GB archive, 212 MB kept, Windows x86_64 only) live in `%APPDATA%`, not the repo.
**Still unverified and not claimable:** how the build looks, how fast it runs, and whether it works on any
machine other than this one — a headless probe renders nothing. It needs one real run here and one on a PC
that has never had Godot installed.

**D-021 (2026-10-26) A green suite was not proof that every test ran.** Found by the W7-01c agent, honestly
reported against its own work: its first draft had a typed-array bug that aborted a coverage test part-way,
and the test still counted as **passed**. A GDScript runtime error ends the function it happens in and raises
nothing the runner can catch, so `run_tests.gd` saw a test that recorded no assertion failure — because it
had recorded nothing at all. That is exactly how a test that proves nothing hides inside `PASS 335 / FAIL 0`,
and the crypt-mouth and hearth-mouth coverage tests are the ones where it would matter most.
Two guards now, because neither is sufficient alone:
1. `TestCase` counts assertions reached and `run_tests.gd` **fails any test that reached none**, which catches
   an error before the first assertion (and also catches a test that genuinely asserts nothing). Proven by
   negative control: a deliberately empty test reports `1 passed, 1 failed`, and today no real test trips it.
2. The suite's output is checked for `SCRIPT ERROR` lines, which catches an error *after* the first
   assertion. Expected count in a checkout that has `assets/`: **0**, verified. An agent worktree has no
   `assets/`, so lines there are the missing-model failures and must be diffed before/after, never ignored.
The general lesson is the one this project keeps relearning: a test is only evidence once it has been seen to
fail. Negative controls are not optional (D-014).

**D-022 (2026-10-27) Built ground is a data layer, and scattering asks it instead of avoiding plateaus.** The
owner: the hill up to the castle is "only plain ground… there is literally no grass". The cause was a blunt
rule — grass was zero on every plateau and only ramped back to full across the first half of its slope skirt:
for the castle, bare to **78 m** from its centre and thinned out to **118 m** (W8-G measured the 78–158 m hill
ring at 0.78× on average, bare at the rim); trees and props avoided plateaus the same way. That was a stand-in for
"don't grow through floors". Replaced by the thing it stood in for: `data/sites/` lists every built place;
`Footprint` gives each layout's ground pieces as oriented rectangles; `KeepOutMask` rasterises them to 0.5 m
cells once, so the per-blade question is one lookup. **Terrain holes are masked whole**, because there is no
ground in a hole for anything to grow on — and buried slabs are deliberately *not* ground pieces: the crypt's
ceiling lies 0.3 m under the graveyard and counting it would have left an 11 m bare patch over it.
`Settlements` builds houses and props from the same data at the **highest** ground under each footprint, so no
corner ever floats. Repeated layouts share meshes and collision shapes (`StructureBuilder.share_pieces`).
`tests/test_site_placement.gd` holds the rules every site must obey whoever places it — dry, inside the ridge,
on ground a 2 m foundation can cover, off the old road, clear of the spawn, never crowding another site — so two
agents can fill the map at once and only ever have to satisfy the tests, not each other.

**D-023 (2026-10-27) "Too empty" is measured as distance to the nearest built thing.** The owner: "the game
feels too empty… do not make the player feel bored that there is nothing." WORLD_PLAN's rule was that something
built should be within ~60–80 m of anywhere walkable. Measured over every walkable 10 m cell (inside the ridge,
out of the water, under 35°; 3,852 points), as the distance to the nearest point of any built footprint:
after the twenty houses (W8-H) and 35 points of interest (W8-P), **90.3 % within 80 m, median 37 m, emptiest
spot 137 m** — the gaps all at the valley's outer rim, where nobody had a reason to build. Eleven more sites,
**every one reusing an existing layout** (no new geometry; exactly the reuse the owner asked for), placed at the
flattest legal spot near each gap: **99.9 % within 80 m, 94.1 % within 60 m, median 31 m, emptiest 83 m.**
`tests/test_world_reach.gd` holds it at ≥ 99 % within 80 m and no spot further than 95 m, and was seen to fail
against the map without the fillers before it was trusted to pass (D-021).

**D-024 (2026-10-27) Grass fills in resumable steps; the remaining spike is the thinning pass.** After W8-G zoned
the grass, the lead measured worst fill frames of 16.7–20.2 ms. Cause, confirmed by a per-unit counter: the
budget (D-019) was checked only *between* units of work and one unit — one layer of one cell — cost 4.0–4.7 ms
against a 1 ms budget, a floor that any background load multiplied. (W8-G2 could reproduce the large spikes only
under contention; the lead's three runs had no other session running. The laptop was seen drifting in speed
through the day, so which figure is "idle" is unresolved; the fix removes the floor either way.) W8-G2 made a
layer's fill resumable in 32-candidate steps with the RNG drawn in a fixed order, so any split builds identical
blades (proven for steps 1–72 and whole), and stopped re-thinning the whole lattice on every working frame.
**Lead's own measurement after the merge, idle, three sprint runs:** mean 1.47–1.53 ms, p95 2.6–2.7 ms, worst
7.6 / 7.9 / 10.5 ms, **zero frames over 16 ms**, one frame over 8 ms in three runs, no unfilled cell within 50 m
of a sprinting player. The agent's ≤ 6 ms worst-frame target is met in its runs, **not in the lead's**.
**Open:** the whole-lattice re-thin, now run every 2 m of movement, itself costs up to **10.2 ms** (`grass_thin_worst_ms`)
and sits outside the fill timer; make it incremental the way the fill now is. All CPU-side; GPU unmeasured.

**D-025 (2026-10-27) Fire is the map's only signpost, and it is data on a piece, not a light in a scene.** The
owner, after playing at night: "there are no guided things: no fire, nothing… it becomes very hard for me and
any player who would play to see through the castle or see anywhere on the map." Elden Ring's rule is the one
the design already follows — no quest markers — so the direction has to come from the world itself, and the
thing a player walks towards in the dark is a fire. Three choices worth recording:
1. **A fire is a kit piece that declares its own light.** `StructureKitFire` returns the usual
   `{kind, mesh, shapes, verts}` plus a `lights` list, and `StructureKit.make_node/make_multi` turns each
   entry into a `FireLight` once per placement. So a layout lights itself by naming a piece: no level code,
   no scene, no per-site wiring, and twenty instanced wall torches stay one MultiMesh draw.
2. **How far a flame is SEEN is not how far its light REACHES.** The flame is a billboarded quad (additive,
   unshaded, on a teardrop texture painted in code — D-005 keeps binaries out of git) drawn out to a
   per-kind sight distance (lamp 70 m, hearth 95 m, pyre 170 m, beacon 240 m), while the light itself is
   faded out just past its own range. A watchfire is therefore visible from across the valley for the price
   of two triangles. No fire casts a shadow, ever: that is what makes a hundred of them affordable.
3. **Fires dim by day, they do not switch off.** `day_share` keeps 50 % of the energy at noon (85–100 %
   indoors and in the crypt), on the same sunrise-at-06:00 arc DayNightCycle paints the sky by. A fire that
   vanished at dawn would be a lamp, not a world.

**Measured, 103 fires placed** (26 hearths, 20 lamp stones, 17 braziers, 17 wall torches, 13 torch posts,
8 beacons, 2 pyres) across 51 sites: all 13 house layouts, 21 new wayside sites along the old road, the eight
camps whose rings were cold, 21 in Castle Morrow and 8 in the broken village. **The darkest point of the
walkable road is 24.8 m from a fire** (sampled every 8 m outside the pond basin, which is water;
`tests/test_firelight.gd` holds it under 40 m). **The negative control taught something:** with
`vale_lights.json` held back the worst stretch is **57.7 m**, on the climb to the castle — so the first limit
written, 60 m, was no guard at all and the test passed without the lights it exists to check. The limit is
40 m, which only the wayside lights reach (D-021)). Live, from the spawn: `PROBE fires total=103
drawing=9 worst_crowd_60m=26 cull=90 nearest_to_spawn=21.7` — nine flames drawing at once of a hundred and
three, and at most twenty-six can ever fall inside one cull sphere, which is the number to watch if more are
added. **Unverified:** every colour, size and energy here is a first guess against a null renderer. Nobody
has seen a single flame.

**D-026 (2026-10-28) The recording settled four arguments that headless runs could not.** The owner sent 83
seconds of gameplay. It is the first time anybody has seen this world, and it moved four things from opinion
to fact:
1. **The grass was desert scrub.** Blades were metre-wide splayed fans standing a metre apart over brown
   ground: 1.15 clumps/m², 0.28-0.62 m tall, `align` 0.6 (tilted outward, which is what made them read as
   agave), coloured pale straw and drifted 45 % further toward straw by `dry_amount`. The owner: "the
   starting area is not the desert area". Now 2.8/m² (2.4x), 0.15-0.33 m, a third as wide, `align` 0.22, and
   green. Density alone was not enough: the ground BETWEEN blades was the problem, so the terrain shader
   gained `grass_tint`, applied to the grass layer only, and the bald zones (hilltops, ridge foot,
   settlements, 0.45-0.6x) came up to 0.7-0.85x. Consistency was the owner's word and it is now the rule.
2. **Fog was hiding the whole game.** 0.034-0.050 is a wall at roughly 60 m. Every house, the castle and all
   103 fires of W9-F were behind it, which is most of what "the game feels too empty" was measuring. Cut to
   a third (0.012-0.017). It is still hazy, still thickest at dawn and dusk.
3. **There was no road, because thin grass is not a road.** The grass zones have thinned the valley line
   since W8-G, but with the same ground texture under it the result is invisible. The old road is now worn
   into the terrain shader itself (up to eight segments of the same valley polyline every other system
   already uses, gravel blended over grass, fading out as the slope turns to rock).
4. **Stamina was costing the owner play time, not adding tension.** "Remove that stamina cap... the bar
   should be there but it should not get depleted." One switch rather than ripped-out code: `Stamina.unlimited`
   makes every spend and drain succeed and take nothing. The pool, the costs and the refusals are all still
   there, still tested, and the jump probe turns them back on to prove it.

**Also decided:** a tower is generated, not hand-written. Three towers of 33-42 pieces each are a script's
output (stairs turning 180° a storey, floor slabs that leave the stairwell open, a landing at every head), so
the shape is argued about in one place instead of in 110 JSON entries. **The headroom test is why that
mattered:** the first cut roofed every flight at 1.2 m and the second left the top flight of every watchtower
climbing to no floor at all. Both were found by walking the real treads in a test, not by eye.

**Measured after the pass:** grass instances **12,142 -> 31,357** (blade verts 324k -> 718k), worst fill frame **5.8 ms** (p95 3.8, none over 8), which needed the fill slice raised from 1.0 to 2.2 ms -- at 1.0 a sprinting player outran the fill and left cells bare inside 50 m, so a bigger slice is simply the price of the field the owner asked for. `PROBE sites fixed=3 spawned=91 props=34 pieces=709` and `PROBE fires total=107`. Suite **419 -> 428, 0 failures, 0 script errors, 51/51 files.**

**D-027 (2026-10-29) Bone space is centimetres, and the test has to measure the world, not the mesh.** The
owner's second recording showed an enormous black sheet standing behind the player, always behind them and
growing with every climb. It was the W9-C cloak: the character glTF is authored in centimetres, every bone
under `CharacterArmature/Skeleton3D` carries a scale of about 100, and anything parented to one inherits it.
`PlayerWeapons` has divided its props by `HAND_METRE` (0.01) since W6-03 for exactly this reason; `Wardrobe`
did not. **Measured by the negative control: 86.0 m tall, 69.5 m wide, hanging 6.0 m over the shoulder.**
Two things follow, and the second is the general one:
1. The factor is now **measured, not assumed** (`Wardrobe.fit_factor` walks the parent chain of scales), so
   a rig in metres gets 1.0 and nothing has to know which rig it is standing on.
2. **`test_a_garment_builds_cloth_that_hangs_down_and_wraps_the_body` passed throughout.** It checked the
   mesh, and the mesh was always right: a 0.86 m sheet of cloth. Only the world transform was wrong. Any
   test of something attached to a bone, a scaled node or an imported rig has to measure it **where the
   player sees it** -- local extent times every scale between it and the world -- or it is testing the one
   number that was never in doubt.

**D-028 (2026-10-30) A village is props on ground somebody already cleared.** W10 put people, animals, fires
to rest at and things to find into Hollowmere without choosing a single new piece of ground. Every one of
them is a **prop on a site that already existed**, which is why it cost an afternoon rather than a week:
placement rules, legality, the keep-out mask and the reach tests were all settled when the buildings went
in, and `tests/test_site_placement.gd` only asks that a prop sit within 4 m of its own site. Three things
made that possible, and each is small:
1. **`Settlements.set_coerced` understands a child path.** `"Talk/lore_key"` sets a property on a child
   node, so one villager scene serves ten villagers who each say something different -- no script per
   villager, no scene per villager.
2. **An NPC is a `Creature`.** The wander/flee/leash state machine written for deer is what a villager
   needs; a villager is that script, the player's body, and a `LoreStone` on an Area3D child.
3. **A rest fire is an `Interactable` that calls `Game.advance_time`.** The sky, the fog, the sun, the moon
   and all 164 fires already follow the clock, so moving the clock moves the world. The whole feature is
   `next_stop()`, a pure function over a list of hours, and the wrap past midnight is the only hard part.

**Measured:** 151 sites (was 94), 1,354 structure pieces, **164 fires**, 10 villagers, 13 animals, 6 rest
fires, 42 items. Grass worst fill frame 5.55 ms. **Open, and honest:** `worst_crowd_60m` is now **44** --
forty-four fires can fall inside one cull sphere in Hollowmere, against a budget of 45. The village is at
the limit, and the next settlement will need the cull distance tuned or the lamps thinned rather than more
of both.

**D-029 (2026-10-30) Things floated because nothing measured whether they touched the ground.** The owner,
watching his own recording: "many things are floating in the air". Every placement test asked whether a
thing stood in a legal PLACE; none asked whether there was ground under all of it. A site is floored at the
HIGHEST point under its footprint (D-022), so on any slope the low side hangs unless the building reaches
down past the fall. `tests/test_no_floating.gd` now measures exactly that for all 126 sloping sites, and it
was not a village problem: cairns, shore fires and road braziers across the whole valley were standing over
gaps. Two fixes, both data: village foundations 2 m -> 4.5 m, and the kit's default `SINK` for a loose prop
0.8 m -> 1.8 m, which is free because every centimetre of it is under the ground line unless the ground has
already fallen away. **Worst shortfall 3.51 m -> 0.21 m.**

**Also W11:** the forest band moved to the road the player walks first, spawn to Hollowmere, at more than
twice the trees (**213 -> 533 in the valley**); ferns and sprigs went from one every five paces to roughly
one per two square metres, which is what "bushes, big bushes" had to mean with no new models; grass
**31,357 -> 43,551** instances, worst fill frame 3.63 ms. The **Overlook** was finally built -- 22 m up over
a 57 m skirt at (-240, 8), with a watchtower on top and the painted road running to its foot. It is smaller
and further out than intended for a reason worth recording: **a plateau cannot overlap a site**, because its
skirt tilts the ground out from under one and the 1.6 m drop rule then fails. Nothing in this valley had
more than 87 m of clear space left, so the hill was sized to the room that existed.
