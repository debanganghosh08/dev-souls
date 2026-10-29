# Hand-off brief: W10 — a living village in the Ashen Vale

**This file is a prompt.** Paste the whole thing into an agent that has the repo checked out (Google
Antigravity, or any coding agent with file and shell access). It is written so the agent needs nothing else.
The repo owner is "the owner"; where this brief and the repo disagree, the repo wins.

---

## 1. What this project is

A third-person souls-like in **Godot 4.7.2** (Forward+, Jolt), at `C:\Projects\porty\dev-souls`, pushed to
`github.com/debanganghosh08/dev-souls`. One open area exists, the **Ashen Vale**: a valley inside a ridge
wall, a drained pond at its centre, a ruined castle on a plateau at (200, −160), a broken village at
(−200, 140), a road running between them, 20 houses, 46 small points of interest, 4 tall towers, and 107
fires. The player walks, sprints, jumps (F), swings a weapon, picks things up with E, and reads item lore.

**Read these first, in this order.** They are short and they are the project's memory:
- `docs/TASKS.md` — what is done, what is ready, what is blocked, and who it is waiting on.
- `docs/DECISIONS.md` — D-001 to D-026. **Every rule below comes from one of these.** Read D-005, D-013,
  D-019, D-021, D-022 and D-026 carefully.
- `docs/WORLD_PLAN.md` — the Vale's regions and the fill rules.
- `AGENTS.md` — how agents work in this repo.
- `docs/TOOLS.md` — the exact Godot commands, including the console executable used for headless runs.

## 2. Rules you must not break

1. **No binaries in git (D-005).** `assets/` and `builds/` are git-ignored and stay that way. If you need a
   model, a texture or a sound, either build it from code (every structure, fire, flame, garment and prop
   in this game is built from primitives in GDScript) or add it to the download script's ID list. Never
   commit a `.glb`, `.png`, `.jpg`, `.ogg`, `.mp4` or an exported build.
2. **Tests are the contract (D-021).** Every behavioural change ships with a test, and **every test you add
   must be seen to fail before it is trusted to pass.** Write the test, break the thing it checks, watch it
   fail, put it back. Say in your report what the failure said. A test that has never failed is decoration.
3. **Run the whole suite before you commit:** `"$GODOTC" --headless --script tests/run_tests.gd`, with
   stdout and stderr to **separate files** (this machine has been seen to clobber `2>&1`). Check three
   things: `PASS n / FAIL 0`, **zero** `SCRIPT ERROR` in both streams, and that the per-file sums add up to
   the total. The suite is currently **429 passing, 0 failing, 52 files**.
4. **Headless only.** Never launch a windowed game or the editor. The owner plays it; you do not.
5. **Content is data, code is a kit.** A new building is a JSON layout in `data/structures/`, not new code.
   A new site is a row in `data/sites/vale_*.json`. Add a new *kind* to a kit only when no existing kind can
   be arranged into the thing you want. This is why 20 houses cost 13 layouts and 4 towers cost 3.
6. **Placement rules are enforced by tests, not by judgement** (`tests/test_site_placement.gd`): every site
   must stand on dry ground inside the ridge, on ground a 2 m foundation can cover (≤1.6 m fall across its
   footprint), at least 3 m off the road's centre line, 1.5 m clear of every other site, and 10 m from the
   spawn. **Pick spots by querying the real heightfield in a throwaway `--script` run, not by eye**, then
   delete the throwaway. See `docs/reports/W9-F.md` for how this was done for 21 sites.
7. **Say what you did not verify.** Nothing in this project has a renderer in CI. Every colour, size and
   placement you choose is a guess until the owner records it. Each report ends with a "Not verified,
   plainly" section. Write yours.

## 3. What already exists that you should reuse, not rebuild

| You need | It already exists | Where |
|---|---|---|
| Walls, roofs, arches, stairs, pillars, rubble | `StructureKit` + `StructureKitParts`, `-House`, `-Trim` | `scripts/systems/structures/` |
| Wells, carts, fences, haystacks, scarecrows, tents, racks, troughs, graves, **garden beds** | `StructureKitProps`, `StructureKitPropsCamp` | same |
| Braziers, torches, hearths with remains, lamps, pyres, beacons + a flickering light that culls itself | `StructureKitFire`, `FireLight` | same |
| A building placed on terrain, with props and loot | `Settlements` reading `data/sites/*.json` | `scripts/systems/sites/` |
| Grass, flowers, ferns, pebbles, leaf drifts, zoned by place | `Grass` + `GrassZones` | `scripts/systems/` |
| **Wandering, fleeing and hostile animals with a full state machine** | `Creature` (`scripts/systems/creature.gd`) | — |
| **Time of day, and changing it** | `Game.time_of_day`, `Game.advance_time()`, `DayNightCycle` | — |
| A thing you press E on that shows text | `LoreStone` (`scripts/systems/interactables/lore_stone.gd`) | — |
| Wearing clothes picked up off the ground | `Wardrobe` + `GarmentKit` | `scripts/systems/` |

## 4. The work, cheapest and safest first

Do these in order. **Stop and report after each phase.** Each is a commit.

### W10-A · A village worth walking into (data only, no new code)
The owner: *"the game is looking too empty even now. I want you to add a small village kind of thing."*
Build a dense settlement, not another scatter of houses. Target: **25–35 structures inside a 120 m square**,
close enough that you can always see three from where you stand.
- Reuse the 13 house layouts in `data/structures/houses/` and the 15 in `data/structures/pois/`. Write
  **4–6 new layouts** for the kinds a village needs and does not have: a **two-storey townhouse**, a
  **workshop with a lean-to**, a **covered market stall row**, a **walled yard with a gate**, a **bridge or
  culvert**. All from existing kit kinds.
- Lay **streets**: the terrain shader already wears a road into the ground from a polyline
  (`material.road.waypoints` in `data/areas/vale.json`, up to 8 segments). Give the village a spine street
  and one crossing. Buildings face the street; fences and garden beds fill the gaps between them.
- Dress it: bullock carts (`cart`, with `tilt` for a tipped one), haystacks, troughs, wells, market crates
  (`block`), washing lines, garden beds. Fires along the street (`lamp_stone`, `brazier`) so it reads at
  night — see `docs/reports/W9-F.md` for the pattern.
- Put it where the map is emptiest. `tests/test_world_reach.gd` measures that; run it and read its numbers
  before choosing.
- **Test:** extend `test_world_reach.gd`'s standard, and add a density test for the village (N structures
  within the square, every door reachable, nothing overlapping).

### W10-B · A plateau you climb for the view
The owner wants *"some plateau area where we can climb and see the whole map"*. Plateaus are three numbers
in `data/areas/vale.json` (`centre`, `radius`, `height`, `blend`) and are applied **after** the pond basin
is carved — this is how the pond islet exists. Add a high one with a **walkable ramp or switchback stair**
cut up its side (the kit's `stairs` and `floor_slab`), a ruin and a beacon on top.
**Watch the skirt:** `tests/test_heightfield.gd` requires no step over 1.26 m per 1.5 m, which is what makes
a plateau climbable at all. The islet failed this twice before its blend was long enough.

### W10-C · People who live there
The owner wants *"some people roaming some streets… people doing their own work"*.
- **Do not write a new AI.** `Creature` already wanders, flees, chases, returns home on a leash and dies
  properly. An NPC is a `Creature` with `PASSIVE` disposition, a human model and a home point.
- An NPC that talks is `LoreStone`'s pattern: press E, read a line. Put the lines in
  `data/npc_lines.json`, keyed by NPC id, several per NPC, chosen by time of day. **Do not record voices**
  — audio is blocked on an API key the owner has not supplied (see O-2 in `docs/TASKS.md`), and a voice
  line is a binary (D-005).
- **Faces are the expensive part and the trap.** There is one character model in the repo
  (`assets/models/characters/wick.glb`, git-ignored, authored in **centimetres** — see the next paragraph).
  Different-looking villagers come from **different clothes and colours on the same body**: `GarmentKit`
  already builds cloaks, coats and mantles from data, and the player's own body uses five material
  overrides that can be re-tinted per NPC. Do that before you go looking for new models.
- **The centimetre trap, which has already cost this project once:** every bone under
  `CharacterArmature/Skeleton3D` carries a scale of about **100**. Anything parented to a bone inherits it.
  `PlayerWeapons` divides its props by `HAND_METRE` (0.01); `Wardrobe.fit_factor()` measures the chain and
  divides by it. The first cut of the cloak did neither and rendered an **86-metre sheet of cloth** behind
  the player. If you parent anything to a bone, measure the chain, and **test the WORLD size, not the mesh
  size** — see `test_a_garment_is_worn_at_human_size_even_on_a_rig_authored_in_centimetres`.

### W10-D · Rest at a fire, and move the sun
The owner wants *"a fire campsite where I can actually rest and change day to night"*. This is small and
mostly exists: an interactable at a lit campsite that calls `Game.advance_time()` to the next of dawn /
noon / dusk / midnight, with a fade. Use `HearthSite` as the model for a "use once per visit" interactable
and `data/daynight.json` for what each hour looks like. **Test the pure time arithmetic separately from the
node** (wrapping past midnight is where this goes wrong).

### W10-E · Water and boats — read this before agreeing to it
The owner asked for *"real water mechanics, boats and all"*. Be straight with them about the cost before
starting: the pond is currently a flat plane with no buoyancy, no swimming, no water volume and no shader
interaction, and the player controller is a `CharacterBody3D` with no swim state. Boats mean buoyancy,
water-relative movement, a mounting/dismounting state, and collision against a moving platform — that is a
system, not a layout, and it is the single most expensive item on the owner's list. **Propose a cut-down
version first** (a punt on a fixed path between two jetties, or water that slows and drowns you) and let
the owner choose.

## 5. How to work

- Plan briefly, then build. The owner has said twice that planning should be cheap and the building should
  be real.
- Commit per phase with a message that says **what the change is for**, not just what it touches. Look at
  `git log` for the house style. End commit messages with the attribution line the harness gives you.
- Push to `main` when the suite is green.
- Re-export the Windows build after a content change that the owner will play:
  `"$GODOTC" --headless --export-release "Windows Desktop"`, then verify it by running the exported exe
  headless with `--probe` and checking it prints its PROBE lines with no script errors.
- Write one report per phase in `docs/reports/`, in the house style: what changed, the numbers you measured,
  the negative control, and what you did not verify.
- **Ask the owner for a new screen recording after each phase that changes how the world looks.** Two
  recordings have now overturned six things that headless measurement called fine. It is the cheapest
  quality tool this project has.
