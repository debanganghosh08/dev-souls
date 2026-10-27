# Task board

Status: `READY` → `IN PROGRESS` → `REVIEW` → `DONE` (or `BLOCKED` / `CHANGES`). Protocol: see `AGENTS.md`.
Reports in `docs/reports/<ID>.md`. Decisions in `docs/DECISIONS.md`. Design in `docs/GAME_DESIGN.md`.

## The goal, in one paragraph
A downloadable Windows game. The player wakes in a dead valley, explores two or three areas of about a
square kilometre each on foot, and hunts for a dying entity to rekindle. Nobody tells them where it is:
ten to fifteen half-ruined inhabitants give fragments of a hint, and the rest is hidden — under trees, in
chests, behind the map's edges. Traps kill, and death costs progress but never the save. Combat exists and
is simple. It ships as an `.exe` the owner can market; it is never a web page.

## Where it actually stands (verified 2026-10-26, not estimated)
- **259 tests pass**, `main` pushed to `github.com/debanganghosh08/dev-souls`.
- 13,248 lines of GDScript. 381 asset files, 268 MB, all CC0 and licence-audited. Project 812 MB of 10 GB.
- **Area 1 of 3 exists.** The Ashen Vale: 1 km² heightfield with chunked LOD and near-player collision, a
  pond, a boundary ridge, procedural trees and grass, Castle Morrow (gatehouse, curtain, keep, chapel,
  belfry, graveyard, crypt, sluice house), a broken village, and the three-bell puzzle.
- **The player works.** Walk/sprint/dodge/stamina/fall damage/step-up, third-person camera, melee with
  per-weapon damage and reach, deer that flee, wolves that bite (verified: 100 → 52 health over 6.6 s).
- **The frame works.** Title → play → death → respawn at a candle shrine, saving, flags, inventory with
  `???` silhouettes, lore cards, HUD, pause, settings, day/night with per-area palettes.
- **What does not exist yet:** the dying entity and the ending — the actual objective. Areas 2 and 3. Any
  NPC or line of dialogue. Any sound. Any trap. Any `.exe`.

So: there is a world and a character, and no game in them yet. The next milestone that matters most is
**W7**, because everything else is scenery until there is something to find.

## Done
| ID | What | Notes |
|---|---|---|
| T-001 | Tool/version/licence research | Gemini. Versions were vague; superseded by D-008 |
| T-002 | First CC0 asset list | Gemini. **Rejected** — low-poly, guessed facts. Superseded by T-005 |
| T-005 | Realistic CC0 asset sourcing | Gemini. Good. Outcomes → D-001…D-004 |
| T-006 | Exact asset IDs, machine-verified | Gemini. All 66 IDs re-verified by the lead |
| W1-01 | Godot project scaffold | Lead. Jolt + Forward+ + 12 input actions, verified headless |
| W1-02 | State layer: Flags, Inventory, SaveGame, Game | Fable |
| W1-03 | Player controller, camera, stamina, greybox | Fable. Lead fixed unclimbable stairs (`_try_step_up`) |
| W1-04 | Interaction system, props, lore | Fable. Lead fixed tests sharing the real save slot |
| W1-05 | Menu, HUD, lore cards, death, pause, settings | Fable. `main.tscn` is the entry point |
| W2-01 | Day/night cycle, sky profiles, atmosphere | Fable. Lead wired in `sky.tscn` (it was unused) |
| W2-03 | Terrain: heightfield, chunked LOD, collision | Fable. Lead fixed inverted face winding (fell through) |
| W3-01 | CC0 download pipeline + licence audit | Fable. Licence gate verified live against a CC-BY asset |
| W3-02 | Dress the world with real assets | Fable |
| W3-03 | Procedural trees | Fable. Twig atlases via D-012: 2.6 MB instead of 1.35 GB |
| W3-05 | Castle Morrow, village, bell puzzle | Fable |
| W4-02 | Grass | Fable. Lead has not measured its frame cost — see W6-04 |
| W5-01 | Combat, creatures, animal rigs | Fable. Lead added `--probe-bite` after finding bites untested |
| W5-02 | Animation rig, foot planting | Fable. Lead fixed scene BOMs that broke a cold import |
| W5-03 | Terrain holes so structures can go underground | Lead |
| W6-01 | Seal the crypt mouth; enable SSAO | Lead. The owner fell through this; negative control in the test |
| W6-02 | Castle surfaces: per-material tiling, UV offset, plinths | Fable. Everything had tiled once per metre regardless of the texture |
| W6-03 | Weapons visible in the hand; torch light | Fable. Corrected my spec: follows `Melee.equipped()`, not `best_weapon()` |
| W7-01a | The endgame rule: `Hearth.ending_for` | Lead. Two endings, four outcomes, derived from item kind |
| W7-01b.1 | The sluice socket and draining the pond | Lead. The socket had been an empty marker since W3-05 |

## IN FLIGHT
**W6-04 · Measure the grass and terrain frame cost.** Fable, in a worktree. The two numbers under "open
engineering questions" below are guesses; this instruments both and acts only on what the numbers show.

## READY — next, in the order that matters
**W7-01a · The endgame rule.** `DONE` (lead). `scripts/systems/hearth.gd` + `data/hearth.json`: who may
rekindle the Hearth and which of the two endings they get, derived from item *kind* in `data/items.json` so
the inventory panel and the Hearth can never disagree about what the quest needs. Pure logic, no nodes, every
branch pinned by `tests/test_hearth.gd`. Draft endgame wording added to `data/ui_text.json` pending O-3.
**W7-01b/c · Stage the endgame.** `DONE` (lead + Fable). The sluice socket, the pond draining, the stone seal
over the stairwell, the Hearth's chamber beneath the pond (`tests/test_hearth_mouth.gd` guards its hole, D-014),
the Hearth interactable and both ending cards.
*Blocked by content, not code:* the Sluice Wheel is in the Barrens and two of the three Kindlings are in the
Wood and the Barrens, so the chain cannot be walked end to end until those areas exist. The socket and the
Hearth refusing is correct behaviour, not an omission.

## W8 — filling the Ashen Vale (2026-10-27) — see `docs/WORLD_PLAN.md`
**W8-F · The site layer.** `DONE` (lead). Built ground as data (`data/sites/`), a keep-out mask that grass, trees
and props consult instead of avoiding whole plateaus, and a spawner for houses and props (D-022).
**W8-J · Jump on F.** `DONE` (Fable). ~1.16 m apex, stamina, coyote time and buffer; no jump clip exists in the
model, so the airborne pose is a measured frame of the run cycle.
**W8-G · Grass everywhere.** `DONE` (Fable). Zones of density and colour, tall grass, wildflowers, a worn road;
93.6 % of open ground at least half-meadow, the castle hill at 1.38x, no unfilled cell near a sprinting player.
**W8-G2 · Grass frame spikes.** `DONE` (Fable). Resumable 32-candidate steps: worst frame 17–20 → 7.6–10.5 ms in
the lead's runs, p95 2.6–2.7 ms, none over 16 ms (D-024).
**W8-G3 · Incremental re-thinning.** `READY`. The whole-lattice re-thin every 2 m of movement costs up to 10.2 ms
and is now the largest single spike in the grass; split it across frames like the fill.
**W8-H · Twenty houses.** `DONE` (Fable). Five archetypes, thirteen layouts, twenty placements, twenty new items,
two key puzzles, and homes for the castle key, sword and hammer (none had a source in the shipped level).
**W8-P · Points of interest.** `DONE` (Fable + lead). 46 placements of 15 layouts; eleven of them added by the
lead to close the rim gaps. Something built within 80 m of 99.9 % of walkable ground (D-023).
**W7-02 · Traps.** `READY`. Something that kills: a crypt floor that gives, a sluice that floods, a rotten
bridge. Death already costs progress and keeps the save, so this is placement and triggers, not new systems.
**W8-01 · Area 2, the Wood.** `READY`. Dense forest, little sky, a drowned shrine. Reuses the heightfield,
the structure kit, the tree and grass systems — this should be mostly data, and if it is not, that is the
finding.
**W8-02 · Area 3, the Barrens.** `READY`. Deserted, few trees, cactus and bone, caves. Same reuse.
**W8-03 · Area streaming.** `READY`. At most two areas resident; load and free across a connecting pass.
`main.gd._begin_level()` is the single entry point.
**W9-01 · NPCs and hints.** `BLOCKED` on O-3. Ten to fifteen of them, each giving a fragment and no map
marker. Needs the story settled first or the lines get written twice.
**W10-01 · Windows export.** `DONE` (lead, 2026-10-26). A standalone build, exported and verified by running its
own probe; see D-020 and `docs/TOOLS.md`. Re-export after every merge that adds content.
**W10-02 · Audio.** `BLOCKED` on O-2 (D-010). Everything about sound is waiting on one free API key.

## OWNER — only you can do these
**O-1 · Play it and judge the feel.** Every movement and combat number in the game is still a first guess.
Walk, sprint, roll, fight a wolf, climb the wall stairs, go down into the crypt. Then say: too floaty or too
heavy? camera too close? does the roll feel good to spam? Known and unjudged: the dodge roll plays at about
3.7× speed and may look frantic; the heavy attack is the light clip slowed down; walking still slides about
17% because the clip plants at 0.99 m/s against a 4.2 m/s walk (lowering walk and sprint ~15% is the proper
fix, but that is a feel decision, not a bug).
**O-2 · A free Freesound API key.** All audio is blocked on it. See D-010.
**O-3 · Sign off `docs/GAME_DESIGN.md`** — the title, the names, the story, and the draft lore wording. It
is still the October draft, and W7-01 and W9-01 both need it. **Also settle one contradiction:** the lore on
`sluice_wheel`, `torch` and `bell_rope` in `data/items.json` all say the water has *already* left Hollowmere,
while the design doc says the pond must be drained before it can be entered. Both cannot be true.
**O-4 · The game has no icon.** `project.godot` sets no `config/icon` and the export preset no
`application/icon`, so the window and the `.exe` currently carry Godot's default robot. For something you
intend to market that is the first thing anyone sees, and it is a branding decision, not an engineering one.
A 256×256 `.ico` (and an `icon.svg` for the project) is all it takes; say what you want on it and I will
build it, or drop a file in and I will wire it up.

## Open engineering questions
- **Grass frame cost — being measured now (W6-04).** Previously unmeasured, and it may hitch when sprinting. The knobs are `fill_cells_per_frame`
  and `density`. Nobody has put a number on it (W6-04).
- **Terrain build time is 5150 ms** on the owner's machine — the valley is silent for five seconds on load.
- **D-013 undecided:** the photoscan props are 50–68k vertices each and will be instanced in the hundreds.
  Godot's automatic LODs, or a decimation step in the pipeline?
- **Nobody has walked the castle with eyes on it.** The gate in its arch, the rubble steps, the collapsed
  roofs over doorways, the sluice socket that is still empty, the village chest holding a placeholder
  `torch` — all of it is only known to be geometrically present, not to be good.
- **The hammer and torch have no in-hand mesh** — being fixed in W6-03 as this is written.
