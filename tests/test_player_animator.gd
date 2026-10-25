extends "res://tests/test_case.gd"
## Pure animator decisions: the speed -> idle/walk/run blend, foot-planting playback rate, the state-priority
## resolver and the clip fitting helpers. No scene, no tree: every function under test is static.

const WALK := 4.2
const SPRINT := 7.0


func _blend(speed: float) -> float:
	return PlayerAnimator.locomotion_blend(speed, WALK, SPRINT)


func test_blend_rests_at_idle_walk_and_run() -> void:
	assert_true(is_equal_approx(_blend(0.0), 0.0), "standing still is pure idle")
	assert_true(is_equal_approx(_blend(WALK), 1.0), "walk speed lands exactly on the walk clip")
	assert_true(is_equal_approx(_blend(SPRINT), 2.0), "sprint speed lands exactly on the run clip")
	assert_true(is_equal_approx(_blend(SPRINT + 5.0), 2.0), "beyond sprint (the dodge dash) clamps to run")


func test_blend_is_linear_between_the_anchors() -> void:
	assert_true(is_equal_approx(_blend(WALK * 0.5), 0.5), "half walk speed is half way to the walk clip")
	assert_true(is_equal_approx(_blend((WALK + SPRINT) * 0.5), 1.5), "midway between walk and sprint is 1.5")
	assert_true(_blend(1.0) < _blend(2.0) and _blend(2.0) < _blend(5.0), "blend grows with speed")


func test_blend_survives_degenerate_speeds() -> void:
	assert_true(is_equal_approx(_blend(-3.0), 0.0), "a negative speed reads as idle")
	assert_true(is_equal_approx(_blend(NAN), 0.0), "NaN speed reads as idle, never NaN")
	assert_true(is_equal_approx(_blend(INF), 2.0), "infinite speed clamps to run")
	assert_true(is_equal_approx(PlayerAnimator.locomotion_blend(3.0, 0.0, SPRINT), 0.0), "zero walk speed cannot divide")
	assert_true(is_equal_approx(PlayerAnimator.locomotion_blend(3.0, -1.0, SPRINT), 0.0), "negative walk speed reads idle")
	assert_true(is_equal_approx(PlayerAnimator.locomotion_blend(6.0, WALK, WALK), 1.0), "sprint == walk never reaches run")
	assert_true(is_equal_approx(PlayerAnimator.locomotion_blend(6.0, WALK, 2.0), 1.0), "sprint below walk caps at walk")
	assert_true(is_equal_approx(PlayerAnimator.locomotion_blend(3.0, NAN, SPRINT), 0.0), "NaN walk speed reads idle")
	assert_true(is_equal_approx(PlayerAnimator.locomotion_blend(5.0, WALK, NAN), 0.0), "NaN sprint speed reads idle")


func test_death_beats_everything() -> void:
	var dead: PlayerAnimator.State = PlayerAnimator.resolve(true, true, true, true, true, false)
	assert_eq(dead, PlayerAnimator.State.DEATH, "death wins over roll, attack and hit together")
	assert_eq(PlayerAnimator.resolve(true, false, false, false, false, false), PlayerAnimator.State.DEATH, "death alone is death")


func test_roll_beats_attack_and_attack_beats_locomotion() -> void:
	assert_eq(PlayerAnimator.resolve(false, true, true, true, false, true), PlayerAnimator.State.ROLL, "roll wins over a heavy swing")
	assert_eq(PlayerAnimator.resolve(false, true, false, false, false, true), PlayerAnimator.State.ROLL, "roll alone is roll")
	assert_eq(PlayerAnimator.resolve(false, false, true, false, false, false), PlayerAnimator.State.ATTACK_LIGHT, "a light swing beats locomotion")
	assert_eq(PlayerAnimator.resolve(false, false, true, true, false, false), PlayerAnimator.State.ATTACK_HEAVY, "heavy flag picks the heavy attack")
	assert_eq(PlayerAnimator.resolve(false, false, true, false, true, false), PlayerAnimator.State.ATTACK_LIGHT, "a hit does not interrupt a swing (Melee never cancels one)")
	assert_eq(PlayerAnimator.resolve(false, false, false, false, false, false), PlayerAnimator.State.LOCOMOTION, "nothing requested is locomotion")


func test_hit_reaction_is_suppressed_while_invulnerable_or_rolling() -> void:
	assert_eq(PlayerAnimator.resolve(false, false, false, false, true, false), PlayerAnimator.State.HIT, "a plain hit shows the reaction")
	assert_eq(PlayerAnimator.resolve(false, false, false, false, true, true), PlayerAnimator.State.LOCOMOTION, "i-frames swallow the reaction")
	assert_eq(PlayerAnimator.resolve(false, true, false, false, true, false), PlayerAnimator.State.ROLL, "a hit while rolling (after i-frames) keeps the roll")


func test_state_order_matches_priority() -> void:
	assert_true(PlayerAnimator.State.LOCOMOTION < PlayerAnimator.State.HIT, "hit outranks locomotion")
	assert_true(PlayerAnimator.State.HIT < PlayerAnimator.State.ATTACK_LIGHT, "attack outranks hit")
	assert_true(PlayerAnimator.State.ATTACK_HEAVY < PlayerAnimator.State.ROLL, "roll outranks attack")
	assert_true(PlayerAnimator.State.ROLL < PlayerAnimator.State.DEATH, "death outranks roll")


func test_playback_scale_plants_feet() -> void:
	var at_walk: float = PlayerAnimRig.playback_scale(2.0, 1.0, 2.0, 4.0, 0.5, 3.0)
	assert_true(is_equal_approx(at_walk, 1.0), "walking at the walk clip's authored speed plays at real time")
	var fast_walk: float = PlayerAnimRig.playback_scale(4.0, 1.0, 2.0, 4.0, 0.5, 3.0)
	assert_true(is_equal_approx(fast_walk, 2.0), "twice the authored speed doubles the rate")
	var at_run: float = PlayerAnimRig.playback_scale(4.0, 2.0, 2.0, 4.0, 0.5, 3.0)
	assert_true(is_equal_approx(at_run, 1.0), "running at the run clip's authored speed plays at real time")
	var idle: float = PlayerAnimRig.playback_scale(0.0, 0.0, 2.0, 4.0, 0.5, 3.0)
	assert_true(is_equal_approx(idle, 1.0), "idle never slows to a frozen breath")
	var creeping: float = PlayerAnimRig.playback_scale(0.2, 0.1, 2.0, 4.0, 0.5, 3.0)
	assert_true(creeping > 0.9 and creeping < 1.0, "a creep eases in from real time (%f)" % creeping)
	assert_true(is_equal_approx(PlayerAnimRig.playback_scale(50.0, 2.0, 2.0, 4.0, 0.5, 3.0), 3.0), "rate is clamped above")
	assert_true(is_equal_approx(PlayerAnimRig.playback_scale(NAN, 1.0, 2.0, 4.0, 0.5, 3.0), 1.0), "NaN speed plays real time")
	assert_true(is_equal_approx(PlayerAnimRig.playback_scale(3.0, 1.0, 0.0, 0.0, 0.5, 3.0), 1.0), "zero clip speed cannot divide")


func test_fit_scale_and_swing_duration() -> void:
	assert_true(is_equal_approx(PlayerAnimRig.fit_scale(1.667, 0.45), 1.667 / 0.45), "roll clip fits the dodge duration")
	assert_true(is_equal_approx(PlayerAnimRig.fit_scale(0.0, 0.45), 1.0), "a missing clip length plays real time")
	assert_true(is_equal_approx(PlayerAnimRig.fit_scale(1.0, 0.0), 1.0), "a zero target plays real time")
	assert_true(is_equal_approx(PlayerAnimRig.fit_scale(NAN, 1.0), 1.0), "NaN length plays real time")
	assert_true(is_equal_approx(PlayerAnimRig.swing_duration(0.14, 0.12, 0.26), 0.52), "light swing is windup+active+recovery")
	assert_true(is_equal_approx(PlayerAnimRig.swing_duration(0.34, 0.12, 0.52), 0.98), "heavy swing is windup+active+recovery")
	assert_true(is_equal_approx(PlayerAnimRig.swing_duration(-1.0, 0.0, 0.0), 0.0), "a negative total clamps to zero")


func test_missing_clips_reports_each_absent_name_once() -> void:
	var available: PackedStringArray = PackedStringArray(["Idle", "Walk"])
	var required: Array[StringName] = [&"Idle", &"Walk", &"Run", &"Run", &"Roll"]
	var missing: Array[StringName] = PlayerAnimRig.missing_clips(available, required)
	assert_eq(missing.size(), 2, "two distinct clips are missing")
	assert_true(missing.has(&"Run") and missing.has(&"Roll"), "the missing names are Run and Roll")
	assert_true(PlayerAnimRig.missing_clips(available, [&"Idle"]).is_empty(), "nothing missing when all present")
