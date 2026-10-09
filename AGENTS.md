# Dev Souls — rules for every AI agent (read this first, every session)

**What:** a PC-only (Windows) downloadable, exploration-first souls-like built in **Godot 4 (GDScript)**.
Codename "Dev Souls". Three areas, one hidden dying entity to rekindle, ~13 NPCs, secrets, traps, simple combat.
It is a separate project from `../souls-portfolio` (the web portfolio) — **never edit anything outside `dev-souls/`.**

## Read order
1. `AGENTS.md` (this) → 2. `docs/PLAN.md` (tech, budgets, schedule) → 3. `docs/GAME_DESIGN.md` (story, world, NPCs)
→ 4. `docs/TASKS.md` (your assignment). Do not read the whole repo; read only the files your task names.

## Team and roles
| Who | Role |
|---|---|
| Owner (Debangan) | Final say on story, look, scope. Does in-editor painting/placement when that is faster than AI. |
| Claude (lead, available until **2026-10-19**, limited tokens) | Architecture, core systems, hard bugs, writes task specs, reviews merges. |
| Gemini 3.1 Pro (High), Antigravity | Main implementer: features from `TASKS.md` specs. **Becomes lead after 2026-10-19.** |
| Gemini Flash (3.6–3.8) | Bulk content: dialogue, item text, data rows, asset lists, docs, small scripts. |
| Claude 4.6 / GPT-OSS 120B (Antigravity) | Second-opinion reviews only, when a change is risky. |

## Task protocol (how agents talk to each other — through files, not chat)
1. Pick the top `READY` task assigned to you in `docs/TASKS.md`. Do only that task.
2. Work on a git branch `task/<ID>`; touch only the files the task allows.
3. Run the task's checks. Commit with message `<ID>: <summary>`.
4. Write `docs/reports/<ID>.md`: what changed, checks run + results, screenshots path if visual, open questions,
   anything you were unsure about. Keep it under 40 lines. Mark the task `REVIEW` in `TASKS.md`.
5. The lead reviews the diff + report, then merges to `main` or sends it back with notes.
If a spec is unclear or contradicts the design: **stop and ask in the report** — never invent lore or scope.

## Hard rules
- **Licences: CC0 only** (Quaternius, Kenney, Poly Haven, ambientCG, Poly Pizza items marked CC0). Plugins MIT only.
  Every third-party file goes in `CREDITS.md` (name, URL, licence). No AI-generated imitations of real games' assets.
- **Downloads are untrusted:** fetch into `.cache/dl/<asset-id>/`, check size/type, never run anything from them,
  convert/import, then delete the raw download.
- **Disk cap 5 GB for everything** (editor, export templates, project, `.godot/` cache). Check with
  `du -sh` before big imports. Shipped game target ≤ 1.5 GB.
- **Laptop safety:** before heavy jobs (imports, bakes, exports) check CPU load < 50 %. One heavy process at a time.
  Never leave the game running in the background. Editor + game + browser together only for short tests.
- No secrets, keys, emails or personal data in the repo.
- Never rename/move files outside your task (Godot breaks references); if needed, do it in the editor and say so.

## Code conventions
- GDScript with **static typing everywhere** (`var hp: int = 3`, typed function signatures). Godot 4 style guide.
- One scene per thing (`scenes/npc/maren.tscn`), its script next to it. Small scripts (< 300 lines).
- Content lives in **`data/`** (JSON + `.dialogue` files), never hard-coded in scripts.
- Global state only through the autoloads: `Game` (flow, death/respawn), `Flags` (story/quest flags), `Save`,
  `Inventory`, `AudioBus`. Communicate with signals, not polling.
- No per-frame allocations in `_process`/`_physics_process`; cache node refs in `_ready`.
- Pure logic (flags, quests, inventory, save format) gets GUT tests in `tests/`.

## Definition of done (every task)
Project opens with no errors · game runs from the main menu through the touched feature · `tests/` pass
(`godot --headless -s addons/gut/gut_cmdln.gd`) · no new warnings in the Output panel · report written.

## Folder layout
```
dev-souls/
  AGENTS.md  CREDITS.md  project.godot
  .agent/rules/     Antigravity workspace rule (points here)
  docs/             PLAN, GAME_DESIGN, TASKS, reports/, DECISIONS.md
  addons/           terrain_3d, dialogue_manager, gut (MIT)
  assets/           models/ textures/ audio/ (imported CC0 only)
  data/             items.json, npcs.json, flags.json, dialogue/*.dialogue
  scenes/           main/, player/, npc/, animals/, areas/{vale,wood,barrens}/, props/, ui/
  scripts/          autoloads/, systems/
  tests/
  .cache/           (git-ignored) raw downloads
```
