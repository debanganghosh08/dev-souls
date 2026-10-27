# W8-J: a jump on F, to shortcut rubble, kerbs and broken masonry

## What changed
- **`project.godot`**: `jump` action, physical F (keycode 70), same event format as `interact`. Dodge stays Space.
- **New `scripts/systems/player_jump.gd`** (`PlayerJump`, pure like `PlayerDodge`): coyote and buffer clocks; `take()` fires once when
  a press meets a floor or its grace and spends both clocks (so no double jump); `launch_speed(g, h) = sqrt(2 g h)`, `apex_height`.
- **`player_controller.gd`**: `@export_group("Jump")`: `jump_height 1.1` (clears a 0.9 m block, never a 2 m ledge), `jump_cost 12`,
  `coyote_time 0.12`, `jump_buffer_time 0.12`, `air_control 0.3` (was fully steerable in the air; now acceleration and friction are
  scaled off the floor). Signals `jumped()`, `landed(drop)`. `_update_locomotion` returns true on the launch frame and
  `_physics_process` sets `velocity.y = jump_velocity()` instead of the floor's zeroing (move_and_slide skips its snap for a body
  moving up; the probe confirms it). Refusals follow dodge: only while PLAYING and not dodging, a press mid-swing is dropped like
  Melee drops presses outside IDLE, stamina paid up front and refused outright when short. Step-up still runs only on the floor.
  **Fall tracker** (read, unchanged) measures from the arc's highest point, so a flat jump lands as a drop of its own apex (1.16 m,
  far under the 8 m threshold) and a ledge jump as ledge + apex. `landed(drop)` now fires on every landing.
- **Animation.** `wick.glb` listed headlessly: 24 clips, **no jump, fall or land clip**. Pose chosen by measuring the bone tracks
  (own FK, heights along the rest pose's feet-to-head axis): **`Run` held at 0.833 s**, the stride's flight phase, lifts both feet
  most of any upright clip (lowest foot 0.0079 below the hips vs 0.0095 standing; Roll's best is the tumble, kicks plant a foot).
  `PlayerAnimRig` gains an Air stage (Blend2 between Hit and Attack; AirSeek picks the frame, AirScale 0 holds it); `PlayerAnimator`
  gains `State.AIR`, `air_clip`, `air_pose_time`, `air_delay 0.15` (walk-offs count after 0.15 s off the floor, a jump at once),
  `air_fade 0.1`, `resolve(..., airborne := false)`. Attack and roll show over the pose; a mid-air hit does not flinch.
- **Greybox**: `JumpBlockLow` 0.6 m (x -13), `JumpBlockHigh` 0.9 m (x -16), `JumpLedgeTall` 2 m (x -10), all at z -6..-4; a
  `keep_out` for the yard in `greybox.json` (no scatter zone reached it); "F jump" in the readout. Nothing other probes use moved.
  New `scenes/levels/greybox_jump_probe.gd` runs on `--probe-jump`: 12 scenarios, one PROBE line each. **Tests**: new
  `tests/test_player_jump.gd` (8), `test_player.gd` +1 (the child-process probe), `test_player_animator.gd` +2 (AIR, `airborne_now`).

## Checks (console build, headless only; worktree from `main` e3c4425, main not ahead; assets plain-robocopied, no links)
- `--headless --import` before and after: exit 0, 0 ERROR lines. `run_tests.gd` with the full `assets/` copy (with only `characters/` the baseline was 309 / 26 from missing props and rocks):
  **PASS 335 / FAIL 0, 0 SCRIPT ERROR before; PASS 346 / FAIL 0, 0 SCRIPT ERROR after** (+11).
- Probe at 60 Hz: apex **1.159 m** for 1.1 (+0.059 is the semi-implicit Euler step, inside the +-0.1 band); stamina 100 -> 88;
  health 100, 0 fall-damage emissions on the flat; 6 stamina refuses (0.000 rise); a press while rising -> 1 jump; a press at
  y 0.33 falling -> 2, at the apex -> 1; 3 frames off the 2 m ledge jumps (peak 3.06, drop 3.06, no damage), 10 frames does not;
  0.6 and 0.9 m blocks landed on (y 0.601, 0.901) pressing 1.3 m before the edge at walk speed, the 2 m ledge not (y 0.001),
  walking alone never mounts the 0.6 m block (step-up max 0.4). Observed: `Input.action_press` lands one physics frame later.

## Not verified, plainly
- **Nothing visual, nothing about feel**: null renderer. Whether 1.1 m reads as a hop or matches the real castle kerbs, whether a
  held Run frame looks like a jump or a glitch (a zero time scale holding a seeked frame is read from the engine source, not
  watched), whether 0.1 s fades are right — unseen; all are exports on `Player` / `%Animator`.
- Open: should a swing cancel into a jump (dropped now, matching Melee)? W8-J is not in `docs/TASKS.md`; no status changed there.
