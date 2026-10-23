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
	var pit: Dictionary = _probe_line(text, "PROBE pit")
	assert_true(not pit.is_empty(), "probe printed the pit line")
	if not pit.is_empty():
		assert_eq(pit["state"], "DEAD", "falling into the 20 m pit killed the player")
		assert_true(float(pit["drop"]) > 16.0, "reported drop exceeds the killing height (drop=%s)" % pit["drop"])


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
