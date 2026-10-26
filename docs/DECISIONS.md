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
