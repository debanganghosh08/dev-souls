extends "res://tests/test_case.gd"
## Player scene tests. The runner executes inside SceneTree._init(), before the root Window is in the tree
## and before autoloads exist, so physics cannot be stepped in-process. Scene structure and the fall logic
## are tested here directly; real physics (landing, pit death) runs in a child headless Godot that plays
## greybox.tscn with the `--probe` user arg and prints two machine-readable lines.

const GREYBOX := "res://scenes/levels/greybox.tscn"
const GAME_SCRIPT := "res://scripts/autoloads/game.gd"
const PROBE_FRAME_CAP := "900"

var _scene: Node
var _player: PlayerController
var _game: Node
var _falls: Array[float] = []


func _fresh() -> void:
	_cleanup()
	_falls.clear()
	_scene = (load(GREYBOX) as PackedScene).instantiate()
	_player = _scene.get_node("Player") as PlayerController
	_game = (load(GAME_SCRIPT) as GDScript).new()
	_game.state = _game.State.PLAYING
	_player._inject(_game)
	_player.took_fall_damage.connect(func(drop: float) -> void: _falls.append(drop))


func _cleanup() -> void:
	if _scene != null:
		_scene.free()
		_scene = null
	if _game != null:
		_game.free()
		_game = null


func teardown() -> void:
	_cleanup()


func test_greybox_instantiates_with_player_rig_and_layers() -> void:
	_fresh()
	assert_not_null(_player, "greybox has a Player with the PlayerController script")
	assert_true(_player.has_node("%CameraRig"), "player has a unique CameraRig")
	assert_true(_player.has_node("%SpringArm"), "player has a unique SpringArm")
	assert_true(_player.has_node("%Camera"), "player has a unique Camera")
	assert_eq(_player.collision_layer, 2, "player body is on the player layer")
	assert_eq(_player.collision_mask, 1, "player body collides with world only")
	var arm: SpringArm3D = _player.get_node("%SpringArm") as SpringArm3D
	assert_eq(arm.collision_mask, 1, "spring arm only reacts to world geometry")
	assert_not_null(_scene.get_node_or_null("HUD/DebugLabel"), "greybox has the debug readout label")
	assert_true(_scene.get_node("Player").position.is_zero_approx(), "player is instanced at the origin")
	assert_true(is_equal_approx(_player.stamina_fraction(), 1.0), "stamina starts full")
	assert_false(_player.is_dodging, "not dodging at start")
	assert_false(_player.is_invulnerable, "not invulnerable at start")


func test_short_drops_do_nothing() -> void:
	_fresh()
	_player._update_fall_tracking(false, 0.0)
	_player._update_fall_tracking(false, -1.0)
	_player._update_fall_tracking(true, -1.5)
	assert_eq(_falls.size(), 0, "a 1.5 m ledge drop emits no fall damage")
	assert_eq(_game.state, _game.State.PLAYING, "a short drop does not kill")


func test_drop_over_damage_height_emits_but_does_not_kill() -> void:
	_fresh()
	_player._update_fall_tracking(false, 10.0)
	_player._update_fall_tracking(false, 4.0)
	_player._update_fall_tracking(true, 0.0)
	assert_eq(_falls.size(), 1, "a 10 m drop emits took_fall_damage once")
	assert_true(is_equal_approx(_falls[0], 10.0), "drop reported is peak minus landing height")
	assert_eq(_game.state, _game.State.PLAYING, "10 m is below the killing height")


func test_peak_is_tracked_from_the_highest_airborne_point() -> void:
	_fresh()
	_player._update_fall_tracking(false, 0.0)
	_player._update_fall_tracking(false, 5.0)
	_player._update_fall_tracking(false, 2.0)
	_player._update_fall_tracking(true, -5.0)
	assert_eq(_falls.size(), 1, "the drop counts from the arc's apex")
	assert_true(is_equal_approx(_falls[0], 10.0), "apex 5 to landing -5 is a 10 m drop")


func test_lethal_drop_kills_via_game() -> void:
	_fresh()
	_player._update_fall_tracking(false, 0.0)
	_player._update_fall_tracking(false, -12.0)
	_player._update_fall_tracking(true, -20.0)
	assert_eq(_falls.size(), 1, "a lethal drop still emits took_fall_damage")
	assert_eq(_game.state, _game.State.DEAD, "a 20 m drop calls Game.kill_player")


func test_landing_while_not_playing_does_not_kill() -> void:
	_fresh()
	_game.state = _game.State.PAUSED
	_player._update_fall_tracking(false, 0.0)
	_player._update_fall_tracking(true, -20.0)
	assert_eq(_game.state, _game.State.PAUSED, "Game.kill_player ignores non-PLAYING states")


func test_headless_run_lands_and_pit_kills() -> void:
	var output: Array = []
	var args: PackedStringArray = [
		"--headless", "--path", ProjectSettings.globalize_path("res://"),
		GREYBOX, "--quit-after", PROBE_FRAME_CAP, "--", "--probe",
	]
	var code: int = OS.execute(OS.get_executable_path(), args, output, true)
	var text: String = "\n".join(PackedStringArray(output))
	assert_eq(code, 0, "child headless run of greybox exits cleanly")
	assert_false("SCRIPT ERROR" in text, "child run printed no script errors")
	var landed: Dictionary = _probe_line(text, "PROBE landed")
	assert_true(not landed.is_empty(), "probe printed the landing line")
	if not landed.is_empty():
		assert_eq(landed["floor"], "true", "player is on the floor after 120 physics frames")
		assert_true(absf(float(landed["y"])) < 0.05, "player settled at the floor height (y=%s)" % landed["y"])
		assert_eq(landed["pos_written"], "true", "Game.player_position was written")
	# Guards the step-up fix: CharacterBody3D cannot climb steps on its own, so without
	# PlayerController._try_step_up the player sticks at the first 0.25 m tread (verified by a control run
	# with step_up_enabled = false: peak_y stayed at the 0.6 spawn height and z never passed 7.67).
	var stairs: Dictionary = _probe_line(text, "PROBE stairs")
	assert_true(not stairs.is_empty(), "probe printed the stairs line")
	if not stairs.is_empty():
		assert_eq(stairs["climbed"], "true", "player climbed the staircase (peak_y=%s)" % stairs["peak_y"])
		assert_true(float(stairs["peak_y"]) > 0.9, "reached the 1 m stair top (peak_y=%s)" % stairs["peak_y"])
	var pit: Dictionary = _probe_line(text, "PROBE pit")
	assert_true(not pit.is_empty(), "probe printed the pit line")
	if not pit.is_empty():
		assert_eq(pit["state"], "DEAD", "falling into the 20 m pit killed the player")
		assert_true(float(pit["drop"]) > 16.0, "reported drop exceeds the killing height (drop=%s)" % pit["drop"])


# Real physics for the jump (W8-J): greybox.tscn with --probe-jump hands the level to GreyboxJumpProbe, which
# drives the controller through its input actions and prints one line per scenario. The numbers asserted here
# are the controller's exports (1.1 m apex, 12 stamina, 0.12 s coyote and buffer) and the greybox's blocks.
func test_headless_jump_probe_hops_blocks_and_never_hurts() -> void:
	var output: Array = []
	var args: PackedStringArray = [
		"--headless", "--path", ProjectSettings.globalize_path("res://"),
		GREYBOX, "--quit-after", "2400", "--", "--probe-jump",
	]
	var code: int = OS.execute(OS.get_executable_path(), args, output, true)
	var text: String = "\n".join(PackedStringArray(output))
	assert_eq(code, 0, "child headless jump probe exits cleanly")
	assert_false("SCRIPT ERROR" in text, "jump probe printed no script errors")
	var flat: Dictionary = _probe_line(text, "PROBE jump_flat")
	assert_true(not flat.is_empty(), "probe printed the flat jump line")
	if not flat.is_empty():
		assert_eq(flat["jumped"], "true", "F on the flat jumps")
		assert_true(absf(float(flat["peak"]) - float(flat["target"])) <= 0.1, "apex within 0.1 m of jump_height (peak=%s target=%s)" % [flat["peak"], flat["target"]])
		assert_true(absf(float(flat["land_y"])) < 0.05, "landed back on the floor (y=%s)" % flat["land_y"])
		assert_eq(flat["falls"], "0", "a flat jump registers no fall damage")
		assert_true(is_equal_approx(float(flat["health"]), 100.0), "a flat jump costs no health (health=%s)" % flat["health"])
		assert_true(is_equal_approx(float(flat["stamina_before"]) - float(flat["stamina_after"]), float(flat["cost"])), "stamina drops by jump_cost (%s -> %s)" % [flat["stamina_before"], flat["stamina_after"]])
	var refused: Dictionary = _probe_line(text, "PROBE jump_refused")
	assert_true(not refused.is_empty(), "probe printed the refused line")
	if not refused.is_empty():
		assert_eq(refused["jumped"], "false", "short stamina refuses the jump")
		assert_true(absf(float(refused["peak"])) < 0.05, "and the body never left the floor (peak=%s)" % refused["peak"])
	var double: Dictionary = _probe_line(text, "PROBE jump_double")
	assert_true(not double.is_empty(), "probe printed the double-jump line")
	if not double.is_empty():
		assert_eq(double["rising"], "true", "the second press came while still rising")
		assert_eq(double["jumps"], "1", "no second jump in the air")
		assert_true(float(double["peak"]) < 1.3, "the apex stayed a single jump's (peak=%s)" % double["peak"])
	var buffer: Dictionary = _probe_line(text, "PROBE jump_buffer")
	assert_true(not buffer.is_empty(), "probe printed the buffer line")
	if not buffer.is_empty():
		assert_eq(buffer["jumps"], "2", "a press just before landing jumps again on landing (press_y=%s)" % buffer["press_y"])
	var apex: Dictionary = _probe_line(text, "PROBE jump_apex_press")
	assert_true(not apex.is_empty(), "probe printed the apex-press line")
	if not apex.is_empty():
		assert_eq(apex["jumps"], "1", "a press at the apex has expired by the landing (press_y=%s)" % apex["press_y"])
	var coyote: Dictionary = _probe_line(text, "PROBE jump_coyote")
	assert_true(not coyote.is_empty(), "probe printed the coyote line")
	if not coyote.is_empty():
		assert_eq(coyote["jumped"], "true", "3 frames after walking off the 2 m ledge still jumps")
		assert_true(float(coyote["peak"]) > 2.5, "the coyote jump rose above the ledge top (peak=%s)" % coyote["peak"])
		assert_true(absf(float(coyote["drop"]) - float(coyote["peak"])) < 0.1, "the drop reported is apex to floor: ledge plus apex (drop=%s)" % coyote["drop"])
		assert_eq(coyote["falls"], "0", "ledge plus apex is still under the damage height")
	var late: Dictionary = _probe_line(text, "PROBE jump_late_press")
	assert_true(not late.is_empty(), "probe printed the late-press line")
	if not late.is_empty():
		assert_eq(late["jumped"], "false", "10 frames after walking off is past the coyote grace")
		assert_true(float(late["peak"]) < 2.1, "and the body only fell (peak=%s)" % late["peak"])
	for lane: Array in [["jump_block_low", "true"], ["jump_block_high", "true"], ["jump_ledge_tall", "false"], ["jump_walk_low", "false"]]:
		var line: Dictionary = _probe_line(text, "PROBE %s " % lane[0])
		assert_true(not line.is_empty(), "probe printed the %s line" % lane[0])
		if not line.is_empty():
			assert_eq(line["reached"], lane[1], "%s (%s m): reached=%s expected %s (land_y=%s peak=%s z=%s)" % [lane[0], line["height"], line["reached"], lane[1], line["land_y"], line["peak"], line["z"]])


func _probe_line(text: String, prefix: String) -> Dictionary:
	var out: Dictionary = {}
	for line: String in text.split("\n"):
		line = line.strip_edges()
		if not line.begins_with(prefix):
			continue
		for token: String in line.substr(prefix.length()).split(" ", false):
			var kv: PackedStringArray = token.split("=", true, 1)
			if kv.size() == 2:
				out[kv[0]] = kv[1]
		return out
	return out
