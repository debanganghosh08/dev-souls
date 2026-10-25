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
| Owner (Debangan) | Final say on story, look, scope. Judges how the game *feels* and *looks* — no agent can. In-editor painting/placement when that beats scripting. |
| **Claude Opus — lead** (long-term) | Architecture, specs, reviews, hard bugs, merges, the only one who pushes. |
| **Claude Fable 5.1 subagents** | Implement one specced system at a time, run the headless checks, write the report. |
| Gemini 3.1 Pro / Flash (Antigravity) | Bulk content (dialogue, item text, data rows), research, asset verification. |
| Claude Sonnet / GPT-OSS (Antigravity) | Second-opinion review when a change is risky. |

Weekly milestones and the full schedule live in `docs/PLAN.md`. Tool paths and commands: `docs/TOOLS.md`.

## Task protocol (how agents talk to each other — through files, not chat)
1. Pick the top `READY` task assigned to you in `docs/TASKS.md`. Do only that task.
2. Create the branch `task/<ID>` **from `main`** (`git checkout main; git checkout -b task/<ID>`); touch only the
   files the task allows. When finished, switch back to `main` so the next task starts clean.
3. Run the task's checks. Commit with message `<ID>: <summary>`.
4. Write `docs/reports/<ID>.md`: what changed, checks run + results, screenshots path if visual, open questions,
   anything you were unsure about. Keep it under 40 lines. Mark the task `REVIEW` in `TASKS.md`.
5. The lead reviews the diff + report, then merges to `main` or sends it back with notes. Only the lead pushes,
   only `main`, to the private backup `origin` (github.com/debanganghosh08/dev-souls). Never push task branches.
   **Never commit assets or binaries** (models, textures, audio, builds) — `.gitignore` blocks them; don't force it.
If a spec is unclear or contradicts the design: **stop and ask in the report** — never invent lore or scope.
**Never present a guess as a fact.** Versions, URLs, sizes, licences: write only what you read on the source
page, and mark anything else `UNVERIFIED`.

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
- **Never create a symlink or directory junction from a worktree into the main checkout.** `assets/` is
  git-ignored, so a fresh worktree has none — the correct fix is to run `node tools/fetch-assets.mjs` *inside*
  the worktree (it re-verifies every licence and costs a few minutes), never to link back to the real folder.
  **Why:** an agent linked `assets` to the main checkout's folder; `git worktree remove --force` later followed
  that link and deleted 264 MB of real art. It was fully recoverable only because `tools/assets-manifest.json`
  is tracked. Lead rule to match: before removing any worktree, check it for links
  (`cmd //c dir /AL /S <worktree>`) and delete them first.

## Code conventions
- GDScript with **static typing everywhere** (`var hp: int = 3`, typed function signatures). Godot 4 style guide.
- One scene per thing (`scenes/npc/maren.tscn`), its script next to it. Small scripts (< 300 lines).
- Content lives in **`data/`** (JSON + `.dialogue` files), never hard-coded in scripts.
- Global state only through the autoloads: `Game` (flow, death/respawn), `Flags` (story/quest flags), `SaveGame`,
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
