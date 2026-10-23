# Dev Souls — Technical plan, budgets, schedule (v2, 2026-10-23)

## What changed in v2
The owner now has their own long-term Claude Max subscription, so the "Claude disappears on 2026-10-19"
deadline is **gone**. Cadence is now **one focused milestone per week**, each ending in a playable build.
Disk allowance raised to **7–10 GB**. Everything still documented so any agent can pick up the work.

## Machine (measured 2026-10-09, re-checked 10-23)
i9-12900H 14c/20t · 32 GB RAM · RTX 3070 Ti Laptop 8 GB VRAM · C: ~129 GB free. Plenty for this project.

## Stack (installed / decided)
| Need | Choice | Status |
|---|---|---|
| Engine | **Godot 4.7.2 stable** (standard, GDScript), Forward+ renderer | INSTALLED 10-23 via winget. See `docs/TOOLS.md` for paths |
| Physics | **Jolt** (built into Godot 4.4+) | Enable in project settings |
| Terrain + foliage | **Terrain3D** (MIT) | Install in W2 |
| Dialogue | **Dialogue Manager** (MIT) | Install in W4 |
| Tests | GDScript headless runner (`tests/run_tests.gd`), no addon needed | W1 |
| Assets | CC0 only — exact verified IDs in `docs/reports/T-006.md` | Download script in W3 |
| Distribution | Windows export → Inno Setup installer → itch.io + portfolio link | W6 |

## Model / agent architecture (token economics)
Planning is cheap and high-leverage; bulk code is expensive. So:
| Work | Who | Why |
|---|---|---|
| Architecture, specs, reviews, hard bugs, merges, pushes | **Claude Opus (lead)** | Small output, needs judgment |
| Implementing a specced system, one at a time | **Claude Fable 5.1 subagents** | Large output, tight spec, cheap |
| Content in bulk (dialogue, item text, data rows), research, asset verification | **Gemini in Antigravity** | Free on the owner's Google plan |
| Second opinion on a risky change | Claude Sonnet / GPT-OSS in Antigravity | Cheap sanity check |
Rules: one system per agent · spec names the exact files · agent runs the headless checks · lead reviews the diff
· lead commits and pushes. No agent pushes. No agent invents lore or scope.

## Weekly milestones (each ends in a playable build + a tag)
| Week | Milestone | Verified by |
|---|---|---|
| **W1** (tonight, 10-23) | **Foundation:** project scaffold; autoloads Game/Flags/Save/Inventory; third-person player + camera (walk/sprint/dodge/stamina); interaction system; death + respawn; save/load; greybox test level; headless tests | Headless tests + owner walks the greybox |
| W2 | World streaming + Terrain3D; area scenes load/free at passes; day/night cycle; fog + per-area grade; perf HUD | Walk 1 km, no hitches, fps logged |
| W3 | **Ashen Vale**: asset download script (verified CC0 IDs), procedural trees, castle/ruins kit, village, ponds, props | Area walkable and dressed |
| W4 | NPCs + Dialogue Manager + quest flags; 13 NPC scenes; item cards + inventory UI; main menu/pause/settings | Full Vale quest chain completable |
| W5 | **Weeping Wood** + **Sunscar Barrens**; animals + simple combat + the Hollowed; traps | All three areas completable |
| W6 | The Hearth, both endings, audio pass, perf pass, Windows export + installer, itch.io page | Full playthrough start → ending |
Cut order if a week overruns: Barrens size → secrets count → NPC count (13→9) → combat variety. The
three-Kindling story always stays.

## Size budget (cap 10 GB on disk; shipped game ≤ 2 GB)
Godot editor ~0.2 GB · export templates ~1 GB (Windows only, delete the rest) · source assets ≤ 3 GB ·
`.godot/` import cache ≤ 2 GB · builds ≤ 1 GB. Textures 2K max (1K for small props); audio OGG.

## Performance targets (owner's RTX 3070 Ti)
60 fps at 1440p with FSR2 quality · ≤ 2,000 draw calls · ≤ 3 M tris visible · VRAM ≤ 5 GB · fps cap 60 + V-sync
on by default so the laptop stays cool. Low/Medium/High presets for other machines.

## Laptop safety (unchanged, applies to every agent)
Check CPU load < 50 % before heavy jobs (imports, bakes, exports) · one heavy process at a time · never leave the
game or editor running in the background · short runs.

## Risks
Scope is the main one: 3 areas is a lot of content, so areas may stay greybox for a week before art lands ·
realistic CC0 trees do not exist (solved: procedural, D-002) · unsigned .exe triggers a SmartScreen warning
(normal for itch.io; code signing costs money later) · heat during export/bake (one job at a time).
