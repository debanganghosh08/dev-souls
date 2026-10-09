# Decisions log (newest last). The owner can overturn any of these — say so and the lead updates it.

**D-001 (2026-10-10) Art direction: realistic-leaning dark fantasy.** PBR photoscanned textures and props
(Poly Haven, ambientCG), real-proportion humans (Quaternius Universal Base Characters + Universal Animation
Library), heavy fog and per-area grading. No low-poly or cartoon packs for anything the player sees up close.
Why: the owner rejected the toy-like look of the web game and wants an Elden-Ring mood.

**D-002 (2026-10-10) Trees: procedural generator in Godot** (trunk mesh + bark PBR + alpha twig cards cut from
Poly Haven twig atlases, 3–4 archetypes per area, LOD + MultiMesh). It is the approach proven in
`../souls-portfolio` (`src/game/engine/treegen.ts`). Built by the lead in the area milestones. Blender Sapling stays
the fallback for one or two hero trees (Hollow Mother).

**D-003 (2026-10-10) Animals limited to CC0 rigs that exist.** Deer, boar (pig re-skinned), horse, dog/wolf, frog,
goat; crow/owl/vulture = re-skinned pigeon rig. Rat, lizard, scorpion dropped (only CC-BY models exist). Hostile
roles go to wolves, wild dogs and **the Hollowed** — human enemies on the player's rig with Universal Animation
Library attack clips (no extra assets, more souls-like).

**D-004 (2026-10-10) Research reports are leads, not proof.** Every downloaded file is re-checked by the download
script (page licence string must say CC0, size and magic bytes checked) before import, and listed in `CREDITS.md`.
