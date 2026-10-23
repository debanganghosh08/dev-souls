extends "res://tests/test_case.gd"

const GameScript := preload("res://scripts/autoloads/game.gd")

var game: Node
var transitions: Array = []
var died_count: int = 0
var respawned_count: int = 0
var last_time: float = -1.0


func setup() -> void:
	game = GameScript.new()
	game.state_changed.connect(func(old: int, new: int) -> void: transitions.append([old, new]))
	game.player_died.connect(func() -> void: died_count += 1)
	game.respawned.connect(func() -> void: respawned_count += 1)
	game.time_changed.connect(func(h: float) -> void: last_time = h)


func teardown() -> void:
	game.free()


func test_defaults() -> void:
	assert_eq(game.state, GameScript.State.BOOT, "starts in BOOT")
	assert_eq(game.respawn_area, &"vale", "default respawn area")
	assert_eq(game.respawn_point, Vector3.ZERO, "default respawn point")
	assert_eq(game.playtime_seconds, 0.0, "no playtime yet")


func test_state_setter_ignores_noop() -> void:
	transitions.clear()
	game.state = GameScript.State.PLAYING
	game.state = GameScript.State.PLAYING
	game.state = GameScript.State.PAUSED
	assert_eq(transitions, [[GameScript.State.BOOT, GameScript.State.PLAYING],
			[GameScript.State.PLAYING, GameScript.State.PAUSED]], "only real transitions emit")


func test_kill_player_only_from_playing() -> void:
	died_count = 0
	for s: int in [GameScript.State.BOOT, GameScript.State.PAUSED, GameScript.State.MENU]:
		game.state = s
		game.kill_player()
		assert_eq(game.state, s, "kill ignored from state %d" % s)
	assert_eq(died_count, 0, "no death signal outside PLAYING")
	game.state = GameScript.State.PLAYING
	game.kill_player()
	assert_eq(game.state, GameScript.State.DEAD, "dead after kill")
	assert_eq(died_count, 1, "player_died emitted once")
	game.kill_player()
	assert_eq(died_count, 1, "second kill while DEAD ignored")


func test_respawn_only_from_dead() -> void:
	respawned_count = 0
	game.respawn_point = Vector3(5.0, 1.0, 5.0)
	game.player_position = Vector3(99.0, 0.0, 99.0)
	game.state = GameScript.State.PLAYING
	game.respawn()
	assert_eq(game.player_position, Vector3(99.0, 0.0, 99.0), "respawn ignored while PLAYING")
	assert_eq(respawned_count, 0, "no signal when ignored")
	game.kill_player()
	game.respawn()
	assert_eq(game.state, GameScript.State.PLAYING, "back to PLAYING")
	assert_eq(game.player_position, Vector3(5.0, 1.0, 5.0), "moved to respawn point")
	assert_eq(respawned_count, 1, "respawned emitted")


func test_set_respawn_without_save_is_safe() -> void:
	game.set_respawn(&"wood", Vector3(1.0, 2.0, 3.0))
	assert_eq(game.respawn_area, &"wood", "area set")
	assert_eq(game.respawn_point, Vector3(1.0, 2.0, 3.0), "point set")


func test_playtime_only_while_playing() -> void:
	game.playtime_seconds = 0.0
	game.state = GameScript.State.PAUSED
	game._process(1.0)
	assert_eq(game.playtime_seconds, 0.0, "paused does not count")
	game.state = GameScript.State.PLAYING
	game._process(0.5)
	game._process(0.25)
	assert_eq(game.playtime_seconds, 0.75, "playing accumulates")
	game.state = GameScript.State.DEAD
	game._process(1.0)
	assert_eq(game.playtime_seconds, 0.75, "dead does not count")


func test_advance_time_wraps() -> void:
	game.time_of_day = 23.0
	game.advance_time(2.5)
	assert_true(is_equal_approx(game.time_of_day, 1.5), "wraps past 24")
	assert_true(is_equal_approx(last_time, 1.5), "time_changed carries wrapped value")
	game.advance_time(-3.0)
	assert_true(is_equal_approx(game.time_of_day, 22.5), "negative delta wraps backwards")
	game.time_of_day = 24.0
	assert_eq(game.time_of_day, 0.0, "24.0 normalises to 0.0")


func test_is_night_boundaries() -> void:
	game.time_of_day = 5.99
	assert_true(game.is_night(), "just before 6 is night")
	game.time_of_day = 6.0
	assert_false(game.is_night(), "6.0 is day")
	game.time_of_day = 19.99
	assert_false(game.is_night(), "just before 20 is day")
	game.time_of_day = 20.0
	assert_true(game.is_night(), "20.0 is night")
	game.time_of_day = 0.0
	assert_true(game.is_night(), "midnight is night")
