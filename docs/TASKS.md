# Task board

Status: `READY` → `IN PROGRESS` → `REVIEW` → `DONE` (or `BLOCKED` / `CHANGES`). Protocol: see `AGENTS.md`.
Reports go in `docs/reports/<ID>.md`.

## T-001 · Gemini · DONE (merged 2026-10-09)
Tool/version/licence check. **Lead note:** the versions are approximate ("4.4.x or 4.3") and the Jolt link is the
old, now-archived extension. Exact versions are pinned on D2 from the binaries actually installed and written to
`docs/DECISIONS.md`. Use the newest Godot 4 stable from godotengine.org, whatever its number.

## T-002 · Gemini · CHANGES — superseded by T-005 (branch `task/T-002` not merged)
Lead review: (1) it chose a stylised low-poly baseline (Quaternius nature/ruins), but the owner wants a
**realistic-leaning, Elden-Ring-mood** look; (2) several pack URLs, animal lists and sizes look inferred rather
than read from the page; (3) it missed the sources already proven in `../souls-portfolio` (Quaternius *Universal*
Base Characters + Universal Animation Library, Poly Haven models, Poly Pizza CC0 animals); (4) the T-002 branch was
cut from `task/T-001` instead of `main`.

## T-003 · Owner · READY — Before D2
1. Install the newest Godot 4 stable (standard build, Windows): godotengine.org/download/windows.
2. Read `docs/GAME_DESIGN.md`; edit names/story freely; decide: candle-shrine respawn points yes/no; final title.
3. Art direction: see T-005 options once the report is in.

## T-004 · Gemini Flash · BLOCKED (needs T-003 story approval) — NPC dialogue drafts
13 `.dialogue` files per the NPC table, ≤ 12 lines each, flag-reactive, souls voice, hints never answers.

## T-005 · Gemini 3.1 Pro · READY — Realistic-leaning CC0 asset sourcing, verified (research only, no downloads)
Same categories as T-002, but the target look is **realistic-leaning dark fantasy** (PBR textures, real-world
proportions, no cartoon/low-poly). Rules:
- **Open every URL** and record what the page actually says. Write `VERIFIED` only for facts you read on the page
  (licence text, contents list, file size); otherwise write `UNVERIFIED`. Do not estimate sizes.
- Start from the proven sources: Poly Haven (models + textures + HDRIs), ambientCG, Quaternius **Universal Base
  Characters** + **Universal Animation Library**, Poly Pizza (only models whose page states CC0), Kenney (props only).
- **Trees/plants are the known gap** (realistic CC0 trees are rare). List what exists on Poly Haven/ambientCG, and
  describe two fallbacks with effort estimates: (a) trees made in Blender with its built-in Sapling Tree Gen add-on
  + Poly Haven bark/leaf textures, (b) procedural trees built in Godot from twig-card textures.
- Animals: list for each of the 13 animals the exact model + page + whether it is rigged/animated, or `GAP`.
- End with a short recommendation: one primary source per category and the total size of the chosen set.
**Files allowed:** `docs/reports/T-005.md`, the T-005 line in `docs/TASKS.md`. Branch `task/T-005` **from `main`**.
**Done when:** every category has a verified candidate or an explicit GAP with a fallback.
