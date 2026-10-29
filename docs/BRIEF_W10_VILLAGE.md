# Hand-off brief: W10 — Hollowmere, a village that is actually a village

**This file is a prompt.** Paste the whole thing into the agent. It is written to be self-contained.

---

## 0. THE HARD RULE: you write content, not code

The repo owner has decided this, and it is not negotiable. **Any change you make to a program file will be
thrown away unread.** You are being asked to build content out of a toolkit that already exists, the way a
level designer works — not to extend the engine.

**You may create and edit ONLY these:**
- `data/**/*.json` — layouts, placements, text, tuning. This is where the work is.
- `docs/reports/W10-*.md` — your report.
- `docs/REQUESTS.md` — see §6. This is how you ask for code, instead of writing it.

**You may NOT touch, for any reason:**
- `*.gd`, `*.gdshader`, `*.tscn`, `*.tres`, `*.uid`, `project.godot`, `export_presets.cfg`, `.gitignore`
- anything under `scripts/`, `scenes/`, `tests/`, `tools/`, `addons/`, `assets/`, `builds/`
- `docs/DECISIONS.md`, `docs/TASKS.md` (the lead owns those)

You may **run** scripts and tools (§4). Running is not changing.

**Work on a branch, never on `main`:** `git checkout -b antigravity/w10-village`. Commit, push the branch,
and stop. The lead reviews and merges. If you find yourself unable to do something without code, that is
expected and §6 is the answer — it is not a reason to break this rule.

---

## 1. The project in one page

A third-person souls-like in **Godot 4.7.2**, at `C:\Projects\porty\dev-souls`. One open area exists, the
**Ashen Vale**: a 1024 m map, ringed by an impassable ridge at radius ~410, with a drained pond at the
centre (radius 42, water at y = −5, the basin is under water out to roughly 85 m), a ruined castle on a
plateau at **(200, −160)**, a broken village at **(−200, 140)**, and an old road running between them
through the valley floor. Coordinates are **(x, z)** in metres; y is up.

Already built and placed: 20 houses, 46 small points of interest, 4 climbable towers, 107 fires, and
wayside lamps along the road. **94 sites in all.** The player walks, sprints, jumps (F), swings a weapon,
picks things up with E, wears clothes, and reads item lore.

**Read before you start** (short, and they are the project's memory):
`docs/DECISIONS.md` (D-001…D-027 — the rules and why), `docs/WORLD_PLAN.md` (the Vale's regions),
`docs/TOOLS.md` (the exact Godot commands), and `docs/reports/W9-F.md` (a worked example of exactly the
kind of job you are being given: 103 fires placed as data, with the measurements).

---

## 2. What to build

The owner, after playing: *"the map feels empty… I want a village with lights and fire in all places, big
bullock carts, a full village. You can make a 200 metre, 300 metre big village. Small villages won't make
any sense."*

### W10-A · Hollowmere village — the main job
A settlement **200–300 m across**, built in three rings so it reads as a real place rather than a grid:

1. **A dense core, ~100 m across:** 25–35 structures packed shoulder to shoulder along a **main street**
   with one crossing lane. Buildings face the street. Gaps between them are filled with fences, garden
   beds, carts, crates, barrels, troughs and wells — not grass. This is the bit that must feel crowded:
   standing anywhere in the core you should see **at least four buildings**.
2. **A middle ring, out to ~180 m:** workshops, barns, drying racks, animal pens, log piles, a smithy, a
   mill — spaced wider, with yards and kitchen gardens between them.
3. **An outer ring, out to ~300 m:** crofts, field walls, haystacks, scarecrows, orchard fences, a
   graveyard, and the ruins of the parts of the village that did not survive — use the *ruined* variants.

**Lights everywhere**, because the owner plays at night and the valley is dark away from a fire. Every
street gets `lamp_stone` every ~15 m; junctions, the well and the market get a `brazier`; the square gets a
`pyre`; a `beacon` goes on the tallest thing. Follow `docs/reports/W9-F.md` — the fire kit is done, you are
placing it.

**Also wanted and all possible from the kit:** bullock carts (the `cart` kind, big ones — set `w` 3.4–4.0,
`wheel` 0.7; use `tilt` for a tipped one), market stall rows, sitting areas (benches are `block`, 0.45 m
high, round a `campfire` or a `brazier`), washing lines, a village gate, a stone bridge or culvert.

**Where:** pick the emptiest quarter. Run `tests/test_world_reach.gd` first and read its numbers; it
measures how far walkable ground is from anything built. Keep clear of the castle plateau (200, −160) and
the existing broken village (−200, 140) — this is a *different*, bigger settlement.

### W10-B · New layouts the village needs
The 28 existing layouts are cottages, shacks, barns, shrines and watch huts. A village of that size needs
kinds that do not exist yet. Write **6–10 new layouts** in `data/structures/village/` (new folder), all
from the vocabulary in §3:
- a **two-storey townhouse** (upper floor on a `floor_slab`, outside stair, shutters as `wall` openings)
- a **workshop with a lean-to** (`lean_roof`, `lean_wall` already exist)
- a **market stall row** (`timber_frame` + `pitched_roof`, open sides, `block` counters)
- a **walled yard with a gate** (`wall` with an opening, `fence`, `garden_bed`)
- a **smithy** (a `brazier` or `hearth_remains` as the forge, an anvil `block`, a water `trough`)
- a **mill**, a **well house**, a **drying rack**, a **pig pen**, a **stone bridge** — as many as serve.

### W10-C · The forest road — the part you can only half do
The owner wants *"a forest area where there is a road and on both sides dense trees, one big tree, and
sitting areas"*. **Trees are not in your vocabulary** — they are a separate system driven from a scene
file, which you may not touch. So:
- **You do:** everything built along that road — a woodcutter's camp, log piles (`block` repeats), a
  charcoal burner's mound, sitting areas round fires, a shrine at the big tree's foot, lamps down the
  corridor, a `signpost` at the fork.
- **Put the forest itself in `docs/REQUESTS.md`** (§6): say which road stretch, how wide a band of trees
  on each side, and where the one big landmark tree should stand. The lead will do it in code.

---

## 3. Your vocabulary

A structure is a JSON layout: a list of **pieces**, each a `kind` placed at a local position. These are
**all 37 kinds that exist.** A layout naming anything else silently fails to build, and the suite will
catch it.

```
Walls and masses   wall  broken_wall  block  pillar  arch  buttress  timber_frame
Floors and stairs  floor_slab  stairs
Roofs              pitched_roof  collapsed_roof  lean_roof  lean_wall  gable
Ruin and detail    rubble  headstone  bell
Yards and farms    fence  garden_bed  haystack  scarecrow  well  trough  cart  cairn
Camps              tent_frame  weapon_rack  signpost  campfire  grave_mound
Fire and light     brazier  torch_post  wall_torch  hearth_remains  lamp_stone  pyre  beacon
```

**Materials** (the `mat` parameter): `castle_wall blocks stone roof planks plaster timber bronze iron char
cloth bone ember soil sprout`.

**Read the kit source for each kind's parameters before using it.** You may not edit those files, but you
must read them — they are the documentation:
`scripts/systems/structures/kit.gd`, `kit_parts.gd`, `kit_house.gd`, `kit_props.gd`, `kit_props_camp.gd`,
`kit_fire.gd`.

**The schema**, by example — a layout (`data/structures/village/townhouse.json`):

```json
{
  "_comment": "Why this building exists and how it is put together.",
  "name": "townhouse",
  "keep_out": [[-1.4, 4.2, 2.8, 2.2]],
  "pieces": [
    {"name": "foundation", "kind": "block", "at": [0, -2, 0], "yaw": 0,
     "params": {"w": 6.2, "h": 2, "d": 8.2, "mat": "stone"}},
    {"name": "front", "kind": "wall", "at": [0, 0, 4], "yaw": 0,
     "params": {"w": 6, "h": 3, "t": 0.5, "mat": "plaster",
                "opening": {"width": 1.4, "height": 2.4}}},
    {"name": "lamps", "kind": "lamp_stone", "repeat": [[3.4, 0, 4.2, 0], [-3.4, 0, 4.2, 0]],
     "params": {"radius": 0.5, "sink": 1.0}}
  ]
}
```

- `at` is `[x, y, z]` **local to the building**; `yaw` is degrees. `repeat` places the same piece many
  times as **one instanced draw** — use it wherever you can, it is nearly free (D-013).
- `keep_out` is `[x, z, w, d]` rectangles marking ground the pieces cover but the geometry does not declare
  (a doorstep, an earth floor). Grass and trees stop there. Every rect must have a piece standing in it.
- A building on a slope needs a **foundation** `block` about 2 m down and a **doorstep** `stairs` at its
  door, like every existing house. Read `data/structures/houses/cottage_intact.json` and copy the pattern.

**A site** (a placement) is a row in a new file `data/sites/vale_village.json`:

```json
{
  "_comment": "Hollowmere (W10): …",
  "sites": [
    {"id": "hollowmere_townhouse_01", "layout": "res://data/structures/village/townhouse.json",
     "at": [-120.0, 250.0], "yaw": 35.0}
  ]
}
```

Props (things to pick up or read) go on a site as `"props": [...]` — copy the shape from
`data/sites/vale_houses.json`. **Every `id` in the area must be unique.**

---

## 4. How to choose where things stand — run this, do not guess

Every site must obey `tests/test_site_placement.gd`: dry ground, inside the ridge, a fall of no more than
1.6 m across its footprint, at least 3 m off the road's centre line, 1.5 m clear of every other site, 10 m
from the player's spawn. **A tool exists to answer all of that before you write the row.** Set
`GODOTC` from `docs/TOOLS.md`, then:

```
GODOTC --headless --script tools/ground_report.gd -- --grid -200,180,-40,320 --step 20 --legal-only
      every legal spot in a rectangle — this is how you lay out a village
GODOTC --headless --script tools/ground_report.gd -- --find -120,250 --footprint 12
      "about here" → the nearest spot a 12 m building can actually stand on
GODOTC --headless --script tools/ground_report.gd -- --at -120,250
      check one spot, and be told which rule it breaks if it fails
```

Sweep a grid, choose from the legal spots, place the street along them. It is a search tool, not a
substitute for the suite.

---

## 5. Finishing each piece of work

1. **Run the whole suite**, stdout and stderr to **separate files** (this machine has been seen to clobber
   `2>&1`): `GODOTC --headless --script tests/run_tests.gd > out.txt 2> err.txt`
2. Check **three** things: `PASS n / FAIL 0`; **zero** `SCRIPT ERROR` in *both* files; and that the
   per-file sums add up to the total. Baseline before you start: **434 passing, 0 failing, 52 files.**
3. If a test fails, **the test is right and your data is wrong.** You may not edit a test to make it pass.
   If you believe a test is genuinely wrong, put it in `docs/REQUESTS.md` and leave it failing.
4. Write `docs/reports/W10-A.md` in the house style (see `docs/reports/W9-F.md`): what you added, the
   **numbers you measured**, and a closing section headed "Not verified, plainly" listing everything that
   has never been seen by a human eye. Include: how many structures, how many piece instances, total
   drawn vertices, the village's extent in metres, and `test_world_reach.gd`'s numbers before and after.
5. Commit to the branch with a message saying what the change is *for*. Push the branch. **Do not merge.**

**Cost budget.** Every placement costs draw calls. Keep the whole village under **1,200 new piece
instances** and **400,000 drawn vertices**, and say in your report what it actually came to. Reuse layouts
heavily — 20 houses cost 13 layouts, and 4 towers cost 3; that is the standard. If a thing appears more
than twice, it is a layout, not a one-off.

---

## 6. `docs/REQUESTS.md` — how to ask for code

You will hit things the kit cannot do: trees, animals that walk, people who move, water you can swim in,
a new piece kind. **Do not write them.** Append to `docs/REQUESTS.md`, one entry each:

```markdown
## R-1 · A band of dense trees along the forest road
**What content needs it:** the forest corridor, W10-C. I placed the woodcutter's camp, log piles and the
sitting areas, but the road runs through open grass.
**What I would need:** trees planted in a band ~25 m either side of the road between (x1,z1) and (x2,z2),
dense enough to close the view, plus one landmark tree ~3x normal height at (x,z).
**What I did instead:** left the corridor dressed but open.
```

Be specific about the coordinates and the look, because someone else is going to build it from your words
alone. **A good request file is a deliverable of this job, not an admission of failure.**

---

## 7. The two traps that have already cost this project

- **The map lies at a distance.** Everything here is placed and measured headless; nobody sees it until the
  owner records it. Two recordings have now overturned six things the tests called fine — grass that
  measured dense but read as desert scrub, fog that hid the entire world, and a cloak that was 86 m tall.
  **Write down what you have not seen.**
- **Measure the thing the player experiences, not the thing that is easy to measure.** The cloak's mesh was
  always a correct 0.86 m; only its size *in the world* was wrong, and the test checked the mesh. When you
  report "the village is dense", measure what someone standing in it would see — buildings visible from a
  point — not the file count.

---

## 8. How this will be reviewed, so there are no surprises

The lead runs exactly this on your branch, and the first command is the one that matters:

```
git diff --stat main..antigravity/w10-village -- ':!data' ':!docs/reports' ':!docs/REQUESTS.md'
```

**If that prints anything at all, the branch is rejected without being read.** It means a program file was
touched. There is no appeal and no partial credit — the owner's words were "if Antigravity makes code
changes, I won't let any of them happen."

Then, in order: the suite is re-run from a clean checkout and must match the numbers in your report; every
new site is checked against `tools/ground_report.gd`; the piece and vertex counts are checked against the
budget in §5; `docs/REQUESTS.md` is read and turned into real work; and the result is exported and sent to
the owner to record. Anything you flagged as unseen is looked at in that recording first.

Write your report so that someone who did not do the work can tell, from the numbers alone, whether the
village is dense enough. That is the whole test.
