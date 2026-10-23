# Task board

Status: `READY` → `IN PROGRESS` → `REVIEW` → `DONE` (or `BLOCKED` / `CHANGES`). Protocol: see `AGENTS.md`.
Reports in `docs/reports/<ID>.md`. Weekly milestones in `docs/PLAN.md`. Decisions in `docs/DECISIONS.md`.

## Done
| ID | What | Notes |
|---|---|---|
| T-001 | Tool/version/licence research | Gemini. Versions were vague; superseded by D-008 |
| T-002 | First CC0 asset list | Gemini. **Rejected** — picked low-poly, guessed facts. Superseded by T-005 |
| T-005 | Realistic CC0 asset sourcing | Gemini. Good. Outcomes → D-001…D-004 |
| T-006 | Exact asset IDs, machine-verified | Gemini. All 66 IDs re-verified by the lead. Source list for the fetch script |
| W1-01 | Godot project scaffold | Lead. Jolt + Forward+ + 12 input actions + named layers, verified headless |
| W1-02 | State layer: Flags, Inventory, SaveGame, Game | Fable. 31 tests |
| W1-03 | Player controller, third-person camera, stamina, greybox | Fable. Lead fixed unclimbable stairs (`_try_step_up`) |
| W1-04 | Interaction system: interactables, detector, props, lore | Fable. Lead fixed tests sharing the real save slot |
| W1-05 | Main menu, HUD, lore cards, death screen, pause, settings | Fable. `main.tscn` is now the entry point |
| W2-01 | Day/night cycle, sky profiles, atmosphere | Fable. Lead wired `sky.tscn` into greybox (it was unused) |
| W3-01 | CC0 asset download pipeline + licence audit trail | Fable. 42 assets, 246 MB; licence gate verified live |

**State at 2026-10-24: 99 tests passing, `main` pushed, the game boots title → play → death → respawn.**

## OWNER — do these next (nothing else is blocked on anything but this)
**O-1 · Play it and judge the feel.** This is the one thing no agent and no test can do.
`"$GODOT" --editor` then press Play (paths in `docs/TOOLS.md`), or run `scenes/main/main.tscn`.
Walk, sprint, roll, climb the stairs, drop off the ledge, fall in the pit, open the chest, read the stone,
throw the lever, try the door before and after finding the key. Then tell the lead:
- movement — too floaty / too heavy / about right? camera distance and sensitivity?
- the dodge roll — distance, duration, how it feels to spam
- all tuning numbers are first guesses and live on `PlayerController` / `CameraRig` in the inspector
- the interface — text sizes, panel darkness, how long prompts and toasts linger
- the writing — "YOU FADED", "Awakening…", "This will unmake your journey.", the six lore texts in
  `data/lore.json` and everything in `data/ui_text.json` are an agent's draft and need your voice
**O-2 · Freesound API key** (see D-010) — audio is blocked without it.
**O-3 · Read `docs/GAME_DESIGN.md`** and settle the title, names and story beats; it is still the Oct-9 draft.

## READY
**W2-02 · Area streaming.** Load/free area scenes in the background while the player walks a connecting pass,
at most two areas resident. `main.gd._begin_level()` is the single entry point to build on.
**W2-03 · Terrain3D.** Install the addon, a 1 km² vale heightmap, texture painting by slope/height, LOD check.
**W3-02 · Dress the greybox with real assets.** Replace grey primitives with the fetched CC0 models/textures;
import presets, LODs, a materials pass. Needs the full fetch run first (`node tools/fetch-assets.mjs`).
**W3-03 · Procedural trees** (D-002/D-009): trunk mesh + bark PBR + alpha twig cards, 3–4 archetypes, MultiMesh
+ LOD. Consider pulling only the *texture* files from `fir_tree_01`/`pine_tree_01` without their geometry.

## BLOCKED
**W4-01 · NPCs + Dialogue Manager + quest flags** — blocked on O-3 (story sign-off).
**W6-01 · Audio system** — blocked on O-2 (Freesound key).
