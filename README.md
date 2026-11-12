<div align="center">

# Dev Souls

**A souls-like you explore rather than grind — built in Godot 4, where almost nothing is hand-placed.**

The castle, the village, the forest, the river and the ground under all of it are generated from
data at load. There is no level file full of furniture. There is a 2 KB JSON description of a
building, and code that turns it into stone.

[![Godot](https://img.shields.io/badge/Godot-4.7.2-478cbf?logo=godotengine&logoColor=white)](https://godotengine.org)
[![GDScript](https://img.shields.io/badge/GDScript-statically%20typed-355570)](https://docs.godotengine.org/en/stable/tutorials/scripting/gdscript/index.html)
[![Tests](https://img.shields.io/badge/tests-523%20passing-3fb950)](#how-it-is-tested)
[![Platform](https://img.shields.io/badge/platform-Windows%20x64-0078d4)](#play-it)
[![Art](https://img.shields.io/badge/art-CC0%20only-ff8800)](CREDITS.md)

</div>

---

> *The Hearth beneath the Mirror Pond is going out. The Vale is emptying. Somebody has to go down
> there and decide what the last fire is for.*

---

## Screenshots

<!--
  TODO (owner): drop 3-4 PNGs into docs/screens/ and uncomment.
  Good shots: the Vale at dawn from the ridge, the castle silhouette, the river gorge from a
  bridge, the full map screen. 1600px wide, PNG, under ~600 KB each.
-->

| | |
|---|---|
| _screenshot: the Ashen Vale at dawn_ | _screenshot: Castle Morrow_ |
| _screenshot: the river gorge_ | _screenshot: the map_ |

---

## What it is

A PC exploration game in the Soulsborne tradition — quiet, hostile, light on instruction. You walk
into a valley, work out what happened to it, and find your way down to the fire underneath.

It is **not** a reimplementation of any existing game. The systems, world and story are original;
the art is CC0 and credited in [`CREDITS.md`](CREDITS.md).

**The Ashen Vale**, the area that exists today, holds:

| | |
|---|---|
| **242** placed sites — buildings, ruins, shrines, camps, crossings | **~5,500** trees across six woods |
| **28,000+** grass instances, filled around you as you move | **289** fires, each casting real light |
| **4** river crossings over a cut gorge up to 18.7 m deep | **1 km²** of continuous, walkable ground |

---

## How the world is made

This is the part worth reading if you came here from a video.

**The ground is a function, not a file.** There is no heightmap image. `height_at(x, z)` composes
noise, a valley, a pond basin, a ridge, crests, plateaus and river cuts, and returns a height. The
terrain mesh, the collision, the grass, the tree placement and the map screen's relief all ask that
same function, so none of them can ever disagree about where the ground is.

**Buildings are described, not modelled.** A structure is a JSON list of pieces — `block`,
`floor_slab`, `wall`, `stairs`, `lamp_stone` — and a builder turns it into meshes and collision at
load. 65 layouts cover every cottage, tower, bridge and ruin in the game. Change a number, get a
different building.

**Rivers are cut to an absolute elevation.** A river is a line of `(x, z, water-surface)` points.
The bed is dug to `surface − depth` wherever the ground happens to be, the ground is only ever
lowered, and the water surface is drawn from *the same list of numbers* — so the water and its bed
cannot drift apart. The surface falls from −4.2 m to −7.5 m across the map: a 0.4 % gradient, which
is roughly what a real river has.

**Everything that can be data, is data.** Items, weapons, garments, day/night palettes, grass zones,
forest groves, site placements, structure layouts, scatter — all in [`data/`](data/). The scripts
are the machine; the JSON is the world.

---

## Play it

**You need:** Windows x64. Nothing else — no engine install, no dependencies.

The repository does **not** contain the game's art or a prebuilt binary (see
[Why the art isn't here](#why-the-art-isnt-here)). To build and run it yourself:

```bash
# 1. Install Godot 4.7.2
winget install GodotEngine.GodotEngine

# 2. Restore the CC0 art from the tracked manifest (~267 MB, licence-checked as it downloads)
node tools/fetch-assets.mjs

# 3. Import once, then play
godot --headless --import
play.bat
```

**Controls**

| | | | |
|---|---|---|---|
| **WASD** move | **Shift** sprint | **Space** dodge | **F** jump |
| **E** interact | **Tab** inventory | **M** map | **Esc** pause |
| **LMB / RMB** light / heavy attack | **F3** debug readout | | |

A packaged Windows build is **526 MB** (`DevSouls.exe` + `DevSouls.pck`). There is no public
release yet — see [Status](#status).

---

## Status

Honest version, because the repository is public and the commit history tells the truth anyway.

**Works**

- One full area, the Ashen Vale, walkable end to end with no loading screen
- Third-person movement, camera, stamina, dodge, jump, step-up, fall damage
- Melee combat, health, creature AI, an inventory, equipment and a wardrobe
- A day/night cycle with a procedural sky, clouds, volumetric fog and moving shadows
- A full-screen map drawn from the real heightfield — relief, water, roads, named places
- Saving, a title screen, pause, settings, death and an ending

**Not done yet**

- **No audio.** Not one sound. Blocked on an asset-source API key, not on code.
- **Two of the three designed areas** — the Weeping Wood and the Sunscar Barrens — do not exist
- **No named NPCs.** The design calls for 13; the villages are currently empty of people
- No traps, and no public release

**In progress** — a 2 km world with three reachable islands, swimming, and a boat.

---

## How it is tested

`523 tests across 65 files`, run headless, no editor, no GPU:

```bash
godot --headless --script tests/run_tests.gd
```

Two rules this project learned the hard way and now lives by:

1. **A passing suite is not proof.** A GDScript runtime error aborts the test function it happens
   in and raises nothing the runner can catch — so a test that dies halfway still reports as
   passed. The runner fails any test that reached no assertion, and the output is grepped for
   `SCRIPT ERROR` separately.
2. **Every claim gets a negative control.** Before a fix is believed, the code is deliberately
   broken again to confirm the new test actually catches it. In one week that practice caught two
   tests that passed for the wrong reason — including one that had been certifying bridges as
   square when they stood up to 58° off.

**Headless proves logic, never looks.** No screenshot, frame rate or visual claim in this
repository was made from a headless run.

---

## Why the art isn't here

`assets/` is in `.gitignore` and always will be. The art is ~267 MB of CC0 models and textures from
Poly Haven, Quaternius, Kenney, ambientCG and Poly Pizza. Rather than commit it, the repository
tracks a **manifest** — and `tools/fetch-assets.mjs` re-downloads every file, verifies its licence
against the source page, writes an audit trail and regenerates [`CREDITS.md`](CREDITS.md).

That decision has already paid for itself once: an agent-created symlink was followed by a
`git worktree remove --force` and deleted 264 MB of art. It was fully recoverable, because the
manifest was tracked.

---

## Layout

```
dev-souls/
├── AGENTS.md           the rules every contributor (human or AI) reads first
├── CREDITS.md          every third-party file, its source and its licence
├── data/               96 JSON files — the world, in data
├── scripts/            100 GDScript files: autoloads, systems, UI
├── scenes/             one scene per thing
├── tests/              65 headless test files
├── tools/              asset fetcher, river/site/terrain diagnostics
└── docs/               the plan, the design, and ~37 build reports
```

Two documents are worth opening if you want the real story:
[`docs/DECISIONS.md`](docs/DECISIONS.md) — 47 numbered decisions, each with the measurement that
forced it — and [`docs/reports/`](docs/reports), a report per week of work saying what was built,
what was checked, and what was still wrong.

---

## How it was built

Dev Souls is written by a human director working with AI coding agents under a strict file-based
protocol: a task board, one task per agent, a branch per task, and a written report with its checks
before anything merges. The rules are in [`AGENTS.md`](AGENTS.md) and the commit trailers name
which model wrote what.

The owner judges how the game *looks* and *feels* — no agent can — and records gameplay for review.
Several of the sharpest bugs in `docs/DECISIONS.md` were found by him walking the world and saying
something was wrong.

---

## Licence

**The code has no licence chosen yet**, which by default means all rights reserved — if you want to
reuse any of it, open an issue and ask.

Everything third-party is already settled: the art is **CC0 only**, each file credited with its
source and licence in [`CREDITS.md`](CREDITS.md); Godot is MIT; the agent skills under
`.claude/skills/` are Apache-2.0 with their `LICENSE` and `NOTICE` kept beside them.

Dev Souls is an original work. It is made in admiration of the Soulsborne genre and contains no
assets, code or text from any FromSoftware title.

<div align="center">

**[Decisions](docs/DECISIONS.md)** · **[Build reports](docs/reports)** · **[Credits](CREDITS.md)** · **[Contributor rules](AGENTS.md)**

</div>
