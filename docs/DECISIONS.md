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

**D-008 (2026-10-23) Godot 4.7.2 stable, Jolt physics, Forward+.** Installed via winget; not on PATH, so every
command uses the full path in `docs/TOOLS.md` (the `_console.exe` build for anything headless). Verified: Jolt
active, Forward+ active, 12 input actions, named 3D physics layers.
