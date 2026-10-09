# Task board

Status: `READY` → `IN PROGRESS` → `REVIEW` → `DONE` (or `BLOCKED`). Protocol: see `AGENTS.md`.
Reports go in `docs/reports/<ID>.md`.

## T-001 · Gemini 3.1 Pro · REVIEW — Verify tools, versions, licences (research only, no installs)
Find the current stable version, download URL, licence and Godot-version compatibility of:
Godot 4 (standard build, Windows), Terrain3D, Dialogue Manager, GUT, Jolt (built-in status in current Godot),
Inno Setup, itch.io `butler`. Note anything that changed recently (breaking changes, deprecations).
**Files allowed:** `docs/reports/T-001.md` only. **Done when:** a table with name, version, URL, licence, notes.

## T-002 · Gemini 3.1 Pro · READY — CC0 asset sourcing list (research only, no downloads)
Using `docs/GAME_DESIGN.md`, list candidate **CC0** packs for: humanoid rigged character + animation library;
animals (crow, dog, horse, rat, deer, boar, frog, owl, wolf, vulture, lizard, goat, scorpion); trees (conifer,
broadleaf/monsoon, dead, cactus), bushes, grass, rocks/cliffs; modular castle/ruins/village kit; sheds, windmill,
well; props (chests, barrels, bells, lanterns, graves); PBR terrain textures; ambient audio (rain, wind, bells).
Prefer one main source per category for a consistent style. For each: pack name, URL, licence (quote the exact
licence text location), format, size, style note. Flag anything not clearly CC0 as REJECTED.
**Files allowed:** `docs/reports/T-002.md`. **Done when:** every category has ≥ 1 candidate or an explicit gap.

## T-003 · Owner · READY — Before D2
1. Install Godot 4 stable (standard build) once T-001 confirms the version; tell Claude the version.
2. Read `docs/GAME_DESIGN.md`; edit names/story freely; decide: candle-shrine respawn points yes/no; final title.

## T-004 · Gemini Flash · BLOCKED (needs T-003 story approval) — NPC dialogue drafts
13 `.dialogue` files per the NPC table, ≤ 12 lines each, flag-reactive, souls voice, hints never answers.
