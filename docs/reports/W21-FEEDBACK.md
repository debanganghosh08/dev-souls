# W21 feedback: the owner's recording of 3 November

Source: `game_recordings/Screen Recording 2026-11-03 202043.mp4` — 5 min 26 s, 1918×1078, with commentary.
The video is git-ignored (D-005); this file is the record of it. The audio was transcribed locally with
faster-whisper (small, int8, CPU) and the frames were read directly. Quotes below are the owner's own words,
with the timestamp they were said at.

## What he said

| At | Quote |
|---|---|
| 0:27 | "what I really want you to make is that you can make a bridge at this location, this exact location" |
| 0:34 | "I don't know why **the water is not rendering** over here, but you can make the water stream properly" |
| 1:23 | "this is the river part and **the bridge you have made is literally inside the river**" |
| 1:42 | "you have to fix this whole river part **just like the ocean you made** on that side of the map" |
| 1:59 | "the part of the bridges and all is **below the river** literally, so you have to fix that" |
| 2:07 | "you can add a complete, you know, **hanging bridge** from this side to that side" |
| 2:42 | "the bridge you have made but **it is not of any use because we cannot get into the bridge**, so you have to make the connecting thing in the bridge right here" |
| 2:55 | "there are much changes we can make in this whole map and areas" |
| 3:05 | "you can add a whole **river going from middle**, then different bridges, different cities and villages around it, just like Elden Ring" |
| 3:35 | "this is the map of Elden Ring — like this we have different **islands, different areas**, this is the sand area" |
| 4:46 | "**not only pixelated things**" |
| 4:51 | "our game is **completely pixelated**, you can see there is no proper things" |
| 5:04 | "I don't know the capabilities about Godot, but we can make things better I guess" |
| 5:09 | "and **proper roads** like this, proper **fences** like this fence we have in front — we can have the whole road like this around the fence" |

For the last two minutes he was not in the game: he opened the Elden Ring wiki map in a browser, then played
*ELDEN RING Gameplay Walkthrough [4K 60FPS PS5]* on YouTube and pointed at it. **That footage is the reference
he is asking to be measured against**, for the map screen and for the look.

## What the frames show

- **The bridge (2:43).** A thin flat deck on a single pier, a railing fragment at one end only, ending in fog
  without meeting the far bank. The bed beneath it is a wide grey gravel flat; the water is a narrow teal strip
  far to one side. His "the water is not rendering" and "we cannot get into the bridge" are the same picture.
- **The castle (4:57).** The wall reads as a near-black mass with no legible material; the tower cap is a flat
  disc of gravel texture. The field around it is flat green with visible horizontal tiling bands and sparse
  blades — mown, not wild.
- **Everywhere.** The sky is a flat grey gradient with no cloud and no sun. Distance dissolves into a grey fog
  wall. Close grass reads neon white-green. Conifer foliage and the castle crenellations crawl with speckle.
- **The player** renders as a near-black silhouette in daylight. Its materials genuinely are near-black
  (`Mat_Ash` albedo 0.11, 0.105, 0.1; `travellers_cloak` #4a4336), so under flat light it has no form. That is
  a lighting problem, not a reason to repaint an ashen pilgrim.

## Why the bridges are underwater — the mechanism

Found before any fix was attempted, so the work is not guesswork.

`data/sites/vale_crossings.json` places each crossing with the default `ground:"max"` — the **highest terrain
under the footprint**. `river_bridge.json`'s `keep_out` is `[-4.5, -16, 9, 32]`, a 13.5 × 48 m box that lies
**entirely inside the river cut** (`cuts.river` is half_width 9 with bank 28, about 56 m wide; `cuts.river_wide`
is half_width 15 with bank 30, about 60 m). So "the highest terrain under the footprint" is still riverbed, at
roughly −6 to −9 m, and the deck piece sits at that floor while the river's water surface at those points runs
−4.2 m to −7.5 m. **The deck is therefore built metres below the water by construction, at every crossing.**

Two consequences follow from the same fact, and both are things he complained about:

- Nothing joins the deck ends to the banks, so there is no way on.
- The piers sit at z = ±6 under a 30 m deck (±15), leaving 9 m overhanging unsupported at each end.

A bridge must be placed against **the river's water surface at its own position**, not against terrain maximum.
A hand-tuned `lift` per site would paper over this and break again the next time the terrain moves.

## "Pixelated" is aliasing, not resolution

`project.godot` runs Forward Plus with `msaa_3d=2` and **no TAA, no FXAA and no anisotropic filtering**. Alpha-
tested conifer foliage shimmers hard without temporal AA, and ground texture at grazing angles degrades into
exactly the stripes in his frames. The Environment compounds it: ACES tonemapping with `tonemap_white=4.0` and
**no CameraAttributes anywhere**, so there is no exposure control — bright surfaces wash to near-white and dark
ones crush to black, which is also why the castle is a silhouette and the grass is neon. Saturation is 1.14 and
contrast 1.12 on top of that.

The sky is a plain `ProceduralSkyMaterial`: **no clouds and no stars exist anywhere in the project.** Classic
fog is animated per hour from `data/daynight.json` while volumetric fog is **static at 0.0045** and does not
follow the curve — the same two-multiplying-fogs trap that produced the wall in W20.

## The work this became

| ID | Scope |
|---|---|
| W21-A | The river and the bridges: deck above water, approaches at both ends, piers to the bed, the ribbon continuous, the channel legible |
| W21-B | Render quality and the sky: AA, anisotropy, shadows, exposure and tonemapping, clouds, both fogs on one curve |
| W21-C | The map screen: real relief from the heightfield, water that reads as water, regions and labels |

Not yet started, and the smallest of his asks by emphasis: more content along the river — further crossings,
villages and distinct regions ("islands"), and the roads-and-fences dressing he pointed at. His own framing was
"we can add", not "this is broken".

## Open question for the owner

At 0:27 and 2:20 he points at a location on screen and says "this exact location" and "the north watch
location". The map screen names a place in that region, but the exact spot he meant cannot be recovered from the
video with confidence. **Before a new crossing is placed there, he should name it** — or drop a screenshot of
the map with a mark on it.
