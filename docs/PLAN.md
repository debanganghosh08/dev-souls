# Dev Souls — Technical plan, budgets, schedule (v1, 2026-10-09)

## Machine (measured 2026-10-09)
i9-12900H 14c/20t · 32 GB RAM · RTX 3070 Ti Laptop 8 GB VRAM (+ Iris Xe) · C: 79 GB free.
Verdict: comfortably enough for Godot 4 development and for running this game at high settings.

## Stack (decided)
| Need | Choice | Why |
|---|---|---|
| Engine | **Godot 4.x stable, standard (GDScript) build**, Forward+ renderer | Free, light (~150 MB), exports .exe, text scene files AI can read/edit |
| Terrain + foliage | **Terrain3D** plugin (MIT) | 1–2 km terrains with clipmap LOD, texture painting, instanced foliage/rocks |
| Physics | **Jolt** (built into Godot 4.4+, enable in Project Settings) | Fast, stable character/rigid-body physics |
| Dialogue | **Dialogue Manager** plugin (MIT) | Plain-text `.dialogue` files with flag conditions — ideal for LLM-written content |
| Tests | **GUT** (MIT) | Headless tests for flags/inventory/save |
| Assets | CC0: Quaternius (characters, animals, nature, modular ruins), Kenney, Poly Haven, ambientCG, Poly Pizza CC0 | Free, legal to sell |
| Audio | CC0 (freesound CC0 filter, Sonniss GDC bundles are royalty-free) + Godot audio buses with reverb zones | — |
| Distribution | Windows export → zip/installer (Inno Setup) → **itch.io** (free, `butler` uploads) + link on the portfolio | Steam later ($100 fee) |
Pin exact versions on day 1 in `docs/DECISIONS.md`. Never upgrade mid-project without a reason.

## How "only render what's near the player" works
- **Areas = separate scenes**, loaded in the background with `ResourceLoader.load_threaded_request` while the
  player walks a connecting pass; the area behind is freed. At most 2 areas in memory.
- **Inside an area:** Terrain3D clipmap LOD (far terrain is cheap), foliage via MultiMesh instancing,
  **visibility ranges** (HLOD) on props/buildings, **occlusion culling** (baked occluders for castle/hills),
  LOD meshes auto-generated on import, fog hides the far distance (also the art style).
- Targets on the owner's RTX 3070 Ti: **60 fps at 1440p, FSR2 quality** · ≤ 2,000 draw calls · ≤ 3 M tris visible
  · VRAM ≤ 5 GB · Fps cap 60 + V-sync default (keeps the laptop cool). Low/Medium/High presets for other PCs.

## Size budget (hard cap 5 GB on disk)
Godot editor 0.15 GB · export templates ~1 GB (delete non-Windows templates after install) · source assets
≤ 2 GB · `.godot/` import cache ≤ 1 GB · builds ≤ 0.8 GB. **Shipped game ≤ 1.5 GB.**
Textures 2K max (1K for small props), VRAM-compressed; audio OGG.

## Schedule
Claude is available until **2026-10-19** with a shared, limited budget → Claude does the *heavy, hard-to-get-right*
parts; everything content-shaped goes to Gemini. ★ = needs Claude.

| Day | Date | Work | Who |
|---|---|---|---|
| D0 | 10-09 | Plan, design draft, Gemini onboarding | Claude ★ |
| D1 | 10-10 | Owner installs Godot + approves story. Gemini: version/licence check + asset sourcing list | Owner, Gemini |
| D2 | 10-11 | Project scaffold, autoloads (Game/Flags/Save/Inventory), player controller + camera, interaction, death/respawn, save/load, tests | Claude ★ |
| D3 | 10-12 | Dialogue integration + flag-reactive NPC base, item card + inventory UI, main menu/pause/settings | Claude ★ / Gemini (UI) |
| D4 | 10-13 | Asset pipeline (import presets, LOD, CC0 credits), player + animal rigs/animations, simple combat + animal AI | Claude ★ / Gemini (imports) |
| D5 | 10-14 | Area A Ashen Vale: terrain, castle kit, village, ponds, atmosphere + area streaming | Claude ★ + Owner (painting) |
| D6 | 10-15 | Area B Weeping Wood: dense forest, rain, water shader, bog | Claude ★ / Gemini |
| D7 | 10-16 | Area C Sunscar Barrens: desert, sheds, windmill, mirage effect, dusk logic | Gemini (Claude reviews) |
| D8 | 10-17 | Puzzles, traps, all 13 NPCs + dialogue, secrets placement | Gemini + Gemini Flash |
| D9 | 10-18 | Hearth + endings, audio pass, perf pass, Windows export + installer | Claude ★ |
| D10 | 10-19 | Full playthrough, bug list, **hand-over docs frozen** (DECISIONS, TASKS backlog for Gemini) | Claude ★ |
If tokens run short, cut in this order: Barrens size → secrets count → NPC count (13 → 9) → combat enemies. The
three-Kindling story stays.

## After 2026-10-19 (Gemini leads)
Gemini 3.1 Pro works through the remaining `TASKS.md` backlog (content, polish, bug fixes) with Gemini Flash for
bulk text. Rules don't change: one task, one branch, one report, owner merges. Risky changes get a second-opinion
review from Claude 4.6 or GPT-OSS inside Antigravity.

## Token-saving rules (for all agents)
- Data-driven: new NPC/item/quest step = data rows + a `.dialogue` file, not new code.
- Specs in `TASKS.md` name the exact files to touch → agents never scan the repo.
- Reports ≤ 40 lines; reviews look at the diff only.
- Godot scene placement and terrain painting are faster by hand in the editor — the owner does them; AI writes
  scripts that scatter/place by rule when the count is large.
- One full-autonomy day for Claude when the shared budget allows: use it for D5–D6 (areas + streaming), the
  hardest work.

## Risks
Scope (3 areas in 10 days is tight; areas may ship greyboxed and get art after 10-19) · asset style mismatch
(stick to one main source per category) · Windows SmartScreen warns on unsigned .exe (normal for itch.io games;
signing costs money later) · laptop heat during bakes/exports (one heavy job at a time).
