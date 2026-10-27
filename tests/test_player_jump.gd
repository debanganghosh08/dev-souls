extends "res://tests/test_case.gd"
## The jump's pure rules: the F binding, the launch speed derived from the height, PlayerJump's coyote and
## buffer clocks (no double jump), and the fall tracker's view of a jump through a bare PlayerController
## (no scene, no tree: a jump on the flat lands for free, a jump off a ledge adds its apex to the drop).
## Real physics for the same rules runs in test_player.gd's --probe-jump child process.

const DT := 1.0 / 60.0
const COYOTE := 0.12
const BUFFER := 0.12
const GAME_SCRIPT := "res://scripts/autoloads/game.gd"

var _player: PlayerController
var _game: Node
var _falls: Array[float] = []
var _landings: Array[float] = []


func teardown() -> void:
	_cleanup()


func _fresh_jump() -> PlayerJump:
	var j: PlayerJump = PlayerJump.new()
	j.update(true, false, DT, COYOTE, BUFFER)
	return j


func _off_floor(j: PlayerJump, frames: int) -> void:
	for i: int in frames:
		j.update(false, false, DT, COYOTE, BUFFER)


# A bare controller: no scene, so no model needed; _inject replaces the Game autoload as test_player.gd does.
func _fresh_controller() -> void:
	_cleanup()
	_falls.clear()
	_landings.clear()
	_player = PlayerController.new()
	_game = (load(GAME_SCRIPT) as GDScript).new()
	_game.state = _game.State.PLAYING
	_player._inject(_game)
	_player.took_fall_damage.connect(func(drop: float) -> void: _falls.append(drop))
	_player.landed.connect(func(drop: float) -> void: _landings.append(drop))


func _cleanup() -> void:
	if _player != null:
		_player.free()
		_player = null
	if _game != null:
		_game.free()
		_game = null


func _health() -> float:
	return _player.get_health().current


func test_jump_is_bound_to_physical_f_and_dodge_keeps_space() -> void:
	assert_true(InputMap.has_action(&"jump"), "project.godot defines a jump action")
	var keys: Array[int] = []
	for event: InputEvent in InputMap.action_get_events(&"jump"):
		if event is InputEventKey:
			keys.append((event as InputEventKey).physical_keycode)
	assert_eq(keys, [KEY_F], "jump is bound to physical F and nothing else")
	var dodge_keys: Array[int] = []
	for event: InputEvent in InputMap.action_get_events(&"dodge"):
		if event is InputEventKey:
			dodge_keys.append((event as InputEventKey).physical_keycode)
	assert_eq(dodge_keys, [KEY_SPACE], "dodge is still Space")


func test_launch_speed_comes_from_gravity_and_height() -> void:
	var v: float = PlayerJump.launch_speed(22.0, 1.1)
	assert_true(is_equal_approx(v, sqrt(2.0 * 22.0 * 1.1)), "v = sqrt(2 g h)")
	assert_true(is_equal_approx(PlayerJump.apex_height(v, 22.0), 1.1), "the apex of that speed is the height again")
	assert_true(is_equal_approx(PlayerJump.launch_speed(22.0, 0.0), 0.0), "zero height launches nothing")
	assert_true(is_equal_approx(PlayerJump.launch_speed(22.0, -1.0), 0.0), "a negative height launches nothing")
	assert_true(is_equal_approx(PlayerJump.apex_height(5.0, 0.0), 0.0), "zero gravity cannot divide")
	_fresh_controller()
	assert_true(is_equal_approx(_player.jump_velocity(), PlayerJump.launch_speed(_player.gravity, _player.jump_height)), "the controller derives its launch speed from its own gravity and height")
	assert_true(absf(PlayerJump.apex_height(_player.jump_velocity(), _player.gravity) - 1.1) < 0.001, "default tuning peaks at 1.1 m")


func test_press_on_the_floor_jumps_and_spends_both_clocks() -> void:
	var j: PlayerJump = _fresh_jump()
	assert_false(j.take(), "no press, no jump")
	j.update(true, true, DT, COYOTE, BUFFER)
	assert_true(j.wants_jump() and j.can_jump(), "a press on the floor wants and can")
	assert_true(j.take(), "a press on the floor jumps")
	assert_false(j.take(), "the same press is spent")
	assert_false(j.can_jump(), "launching spends the coyote grace")
	j.update(false, true, DT, COYOTE, BUFFER)
	assert_false(j.take(), "a second press in the air is not a second jump")
	assert_true(j.wants_jump(), "but it stays buffered for the landing")


func test_coyote_grace_honours_an_early_press_and_refuses_a_late_one() -> void:
	var j: PlayerJump = _fresh_jump()
	_off_floor(j, 3)
	j.update(false, true, DT, COYOTE, BUFFER)
	assert_true(j.take(), "3 frames (0.05 s) off a ledge still jumps")
	j = _fresh_jump()
	_off_floor(j, 8)
	j.update(false, true, DT, COYOTE, BUFFER)
	assert_false(j.can_jump(), "9 frames (0.15 s) off a ledge is past the grace")
	assert_false(j.take(), "so the press does not jump")
	assert_true(j.wants_jump(), "it is buffered instead")


func test_buffered_press_fires_on_landing_within_its_time_and_expires_after() -> void:
	var j: PlayerJump = PlayerJump.new()
	j.update(false, true, DT, COYOTE, BUFFER)
	assert_false(j.take(), "a press in the air with no grace does not jump")
	_off_floor(j, 5)
	j.update(true, false, DT, COYOTE, BUFFER)
	assert_true(j.take(), "landing 6 frames (0.1 s) after the press jumps")
	j = PlayerJump.new()
	j.update(false, true, DT, COYOTE, BUFFER)
	_off_floor(j, 8)
	assert_false(j.wants_jump(), "the press is gone after 9 frames (0.15 s)")
	j.update(true, false, DT, COYOTE, BUFFER)
	assert_false(j.take(), "so landing then does not jump")


func test_reset_clears_both_clocks() -> void:
	var j: PlayerJump = _fresh_jump()
	j.update(true, true, DT, COYOTE, BUFFER)
	j.reset()
	assert_false(j.can_jump(), "reset clears the coyote grace")
	assert_false(j.wants_jump(), "reset clears the buffered press")
	assert_false(j.take(), "nothing to take after a reset")


func test_jump_on_the_flat_lands_for_free() -> void:
	_fresh_controller()
	_player._update_fall_tracking(false, 0.12)
	_player._update_fall_tracking(false, 1.16)
	_player._update_fall_tracking(false, 0.5)
	_player._update_fall_tracking(true, 0.0)
	assert_eq(_landings.size(), 1, "landing is reported once")
	assert_true(is_equal_approx(_landings[0], 1.16), "the drop is the jump's own apex")
	assert_eq(_falls.size(), 0, "an apex far below fall_damage_height hurts nothing")
	assert_true(is_equal_approx(_health(), _player.max_health), "health untouched")
	assert_eq(_game.state, _game.State.PLAYING, "and nobody died")


func test_jump_off_a_ledge_costs_the_ledge_plus_the_apex() -> void:
	_fresh_controller()
	_player._update_fall_tracking(false, 2.1)
	_player._update_fall_tracking(false, 3.1)
	_player._update_fall_tracking(true, 0.0)
	assert_true(is_equal_approx(_landings[0], 3.1), "a 1.1 m jump off a 2 m ledge is a 3.1 m drop")
	assert_eq(_falls.size(), 0, "3.1 m is still under the 8 m damage height")
	# Same jump off a 10 m ledge: the apex is added to what the plain fall would cost.
	_player._update_fall_tracking(false, 10.1)
	_player._update_fall_tracking(false, 11.1)
	_player._update_fall_tracking(true, 0.0)
	assert_eq(_falls.size(), 1, "an 11.1 m drop hurts")
	assert_true(is_equal_approx(_falls[0], 11.1), "the drop reported is the ledge plus the apex")
	var expected: float = _player.fall_damage_for(11.1)
	assert_true(expected > _player.fall_damage_for(10.0), "it costs more than the plain 10 m fall")
	assert_true(is_equal_approx(_player.max_health - _health(), expected), "health lost matches fall_damage_for(ledge + apex)")
