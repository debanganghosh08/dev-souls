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
