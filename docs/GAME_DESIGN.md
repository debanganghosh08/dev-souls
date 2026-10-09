# Dev Souls — Game Design (draft v1, 2026-10-09 — owner must approve before content work starts)

## Pillars
1. **Exploration is the game.** No quest markers, no minimap. Everything is found by looking, reading, listening.
2. **Melancholy and dread.** Grey light, fog, silence, distant sounds. Beauty that is dying.
3. **Hints, never answers.** NPCs speak in fragments. Inscriptions must be read carefully.
4. **Death teaches.** Traps kill; you wake at the grave by the pond and keep everything you found.
5. **Small but dense.** Three ~1 km² areas packed with points of interest, built from a reusable kit.

## Story
The land of **Hollowmere** was warmed for an age by **the Hearth** — an old fire-being that lived beneath the
Mirror Pond. People forgot its name and stopped tending it. Now it gutters. Colour drains from the world,
animals go strange, and people wander without purpose.

The player is **the Wick**: a pilgrim of wax and ash who wakes in an open grave beside the pond. A wick exists
to carry flame. The Wick must gather **three Kindlings** (one per area), learn **the Hearth's true Name**, open
the way beneath the pond and rekindle it — or choose to become its fuel.

**Endings (cheap: one scene, two variants)**
- *Rekindle* — speak the Name, the Hearth wakes, dawn and colour return; the Wick burns down to a stub, at peace.
- *Become the Flame* — without the Name the Hearth can only feed on you; the Wick becomes the new Hearth, the land
  stays grey but warm. (Reached if the player enters without the full Name.)

## World — three areas (each ~1 × 1 km; ~600 m playable core, the rest hills/mist boundary)
Areas connect through narrow passes (a gorge, a collapsed bridge, a tunnel). The next area loads in the
background while the player walks the pass — no loading screens.

### A. Ashen Vale (spawn) — grief
Grey grass, dead orchards, the **Mirror Pond** with the spawn grave, a broken village, hills, small ponds,
and **Castle Morrow** (ruined: courtyard, chapel with bell, collapsed keep, sluice house, crypt).
Fauna: crows, stray dogs, a lame horse; Hollowed (lost humans, hostile) in the crypt. Mood: overcast, fog, ash flakes, slow wind.
- **Kindling 1 (Grey):** in the chapel bell. Ring the three castle bells in the order written on the
  graveyard headstones → the chapel bell falls → the Kindling is in the bell-bed.
- **The pond seal:** the Mirror Pond can only be entered when drained. The sluice house needs the
  **Sluice Wheel** (found in the Barrens) — the castle's flood channel then drains the pond.

### B. Weeping Wood — overgrowth
Dense evergreen + monsoon forest, constant rain, standing water, bogs, a waterfall, moss, mushrooms,
a hermit's stilt hut, a drowned shrine. Fauna: deer, boar, frogs, owls, wolves (hostile, simple).
- **Kindling 2 (Green):** inside the **Hollow Mother** tree, sealed by a ring of thorns. Fire cannot be carried
  through the rain — the player must get a **storm lantern** from the hermit (trade: bring her the drowned
  shrine's bell-rope) and walk the **dry path under the canopy** (only route without rain, readable from the
  map stone) → burn the thorn ring.

### C. Sunscar Barrens — thirst
Cracked plains, red hills, cactus, a few lone trees, salt flats, abandoned sheds, a dry well, a windmill,
cliff-side caves. Fauna: vultures, wild horses, wild dogs and Hollowed bandits (hostile).
- **Kindling 3 (Red):** in the **Mirage House** at the very edge of the map — only solid at dusk
  (daytime it is a shimmer you walk through). The blind cartographer's hint: *"Where the heat lies,
  the house does not. Go when the sun bleeds."*
- **Sluice Wheel:** at the bottom of the dry well (climb down with the rope from the windmill).

### The Name (optional path to the true ending)
Three inscription fragments — the chapel crypt (Vale), the drowned shrine (Wood), the windmill (Barrens).
Each shows one syllable hidden in a longer verse (the capitalised letters). The Name is spoken at the Hearth
via a choice that only appears once all three are read.

## Main quest graph
```
Wake at grave ──► explore Vale ──► Kindling 1 (bells)
      │                 └──► Castle sluice house (needs Sluice Wheel)
      ├──► Wood ──► hermit trade ──► lantern ──► dry path ──► Kindling 2
      └──► Barrens ──► windmill rope ──► dry well ──► Sluice Wheel
                   └──► dusk + edge of map ──► Mirage House ──► Kindling 3
3 Kindlings + Sluice Wheel ──► drain pond ──► descend ──► the Hearth ──► ending (Name read? Rekindle : Become)
```
Any order. Every step sets a flag in `data/flags.json`; NPC lines react to flags.

## NPCs (13) — each gives at most one hint per visit, in fragments
| # | Name | Area | Role / hint |
|---|---|---|---|
| 1 | Old Maren, gravekeeper | Vale spawn | Tutorial voice. Points at the headstones "the dead keep good order". |
| 2 | Ser Aldous, helmless knight | Castle gate | Lost his oath; gives castle key. Dies later (flag-driven). |
| 3 | The Bell-Ringer's ghost | Chapel | Only visible at night; hums the bell order wrong (red herring) unless you read the stones. |
| 4 | Pell, child at the pond | Mirror Pond | "Something warm lives under the water." Moves away as you collect Kindlings. |
| 5 | Oduya, hermit | Wood stilt hut | Trades the storm lantern for the bell-rope. |
| 6 | Bram, lost brother | Wood | Searching for Tam (#12). Reunion side quest → gives a key item. |
| 7 | The Bog Fisher | Wood bog | Warns about the deep water (drowning trap). |
| 8 | The Deer-Speaker | Wood glade | Hints at the dry path: "the deer never get wet". |
| 9 | Salt merchant | Barrens shed | Sells nothing; talks about the windmill rope. |
| 10 | Vesna, blind cartographer | Barrens cave | Mirage House hint. Owns the only map stone. |
| 11 | The Sun-Mad Prophet | Barrens hill | Raves; one true line hidden in the nonsense. |
| 12 | Tam, the lying twin | Barrens | Every statement is false — the player must invert it. |
| 13 | The Pilgrim | Moves between areas | Story arc; appears once per area, then is found dead at the pond before the ending. |

## Secrets, hiding places, puzzles (target: 25–30 discoverables)
Under a tree root, in chests, behind breakable walls, in a well, on a roof, in a burnt tree, at the map edge,
inside a bird's nest, under a pond, at night only, at dusk only, behind a waterfall. Collectibles = lore items
(each a short item card in souls voice), keys, the 3 Kindlings, the 3 Name fragments, a few weapons/charms.

## Traps and death
Collapsing castle floor, falling portcullis, hidden spike pits (Wood, under leaves), deep bog (drowning),
poison spore clouds, quicksand (Barrens), rockfall, cliffs. **Death → "YOU FADED" screen → wake at the grave.**
Inventory, flags and opened things persist. Respawning at the grave every time on 1 km maps can feel punishing:
**recommendation — one unlockable candle shrine per area as a respawn point** (owner decides).

## Combat (deliberately simple)
Light attack, heavy attack, dodge-roll, stamina bar. 2–3 weapons (staff, sword, hammer) + torch.
Passive animals flee; wolves, wild dogs and the Hollowed (human enemies, same rig as the player) attack with a
simple chase/lunge AI. No bosses in v1.

## Art, audio, feel
Realistic-leaning stylised (CC0 PBR textures, Quaternius-style models), heavy fog, volumetric light,
per-area colour grade (Vale grey-blue, Wood green-black, Barrens rust). Day/night cycle (~20 min).
Sparse ambient score, silence, wind, rain, distant bells. Souls-style UI (dark panels, gold serif text,
item cards — same visual language as the portfolio).
