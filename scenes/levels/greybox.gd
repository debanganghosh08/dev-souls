extends Node3D
## Grey-box movement test level. Puts Game into PLAYING, feeds the on-screen readout, and offers two
## debug keys: `pause` (Esc) toggles PLAYING/PAUSED (frees the mouse), `interact` (E) respawns when DEAD.
## With the user arg `--probe` (used by tests/test_player.gd) it prints two machine-readable lines and quits.

const PROBE_LAND_FRAMES := 120
const PROBE_STAIR_FRAMES := 90
const PROBE_MAX_FRAMES := 600
const PIT_DROP_POINT := Vector3(23.0, 0.5, 0.0)
const STAIR_START_POINT := Vector3(0.0, 0.6, 7.0)
const STAIR_TOP_Y := 1.0
const READOUT := "speed  %5.2f m/s %s\nstamina  %3d %%\ngrounded %s   dodging %s   i-frames %s\nstate  %s\nlast fall  %.1f m\npos  (%.1f, %.1f, %.1f)\n\nWASD move   Shift sprint   Space dodge   mouse look\nEsc pause/unpause   E respawn when dead"

@onready var _player: PlayerController = %Player
@onready var _label: Label = %DebugLabel

var _game: Node
var _last_fall: float = 0.0
var _probe: bool = false
var _probe_frames: int = 0
var _probe_phase: int = 0
var _probe_peak_y: float = -1000.0


func _ready() -> void:
	_game = get_node_or_null(^"/root/Game")
	_player.took_fall_damage.connect(_on_fall_damage)
	if _game != null:
		_game.state = _game.State.PLAYING
	_probe = OS.get_cmdline_user_args().has("--probe")


func _process(_delta: float) -> void:
	var v: Vector3 = _player.velocity
	var p: Vector3 = _player.global_position
	_label.text = READOUT % [
		Vector2(v.x, v.z).length(),
		"(sprint)" if _player.is_sprinting() else "",
		roundi(_player.stamina_fraction() * 100.0),
		_yes_no(_player.is_on_floor()),
		_yes_no(_player.is_dodging),
		_yes_no(_player.is_invulnerable),
		_state_name(),
		_last_fall,
		p.x, p.y, p.z,
	]


func _unhandled_input(event: InputEvent) -> void:
	if _game == null:
		return
	if event.is_action_pressed(&"pause"):
		if _game.state == _game.State.PLAYING:
			_game.state = _game.State.PAUSED
		elif _game.state == _game.State.PAUSED:
			_game.state = _game.State.PLAYING
	elif event.is_action_pressed(&"interact") and _game.state == _game.State.DEAD:
		_game.respawn()


# Headless probe: lets the test suite assert on real physics without driving the loop itself.
func _physics_process(_delta: float) -> void:
	if not _probe or _game == null:
		return
	_probe_frames += 1
	if _probe_phase == 0 and _probe_frames >= PROBE_LAND_FRAMES:
		print("PROBE landed y=%.3f floor=%s pos_written=%s" % [
			_player.global_position.y,
			_player.is_on_floor(),
			_game.player_position.is_equal_approx(_player.global_position),
		])
		_player.global_position = STAIR_START_POINT
		_player.velocity = Vector3.ZERO
		# move_back drives +Z, which is up the staircase.
		Input.action_press(&"move_back")
		_probe_frames = 0
		_probe_phase = 1
	elif _probe_phase == 1:
		_probe_peak_y = maxf(_probe_peak_y, _player.global_position.y)
		if _probe_frames < PROBE_STAIR_FRAMES:
			return
		Input.action_release(&"move_back")
		print("PROBE stairs peak_y=%.3f climbed=%s z=%.2f" % [
			_probe_peak_y,
			_probe_peak_y >= STAIR_TOP_Y - 0.2,
			_player.global_position.z,
		])
		_player.global_position = PIT_DROP_POINT
		_player.velocity = Vector3.ZERO
		_probe_frames = 0
		_probe_phase = 2
	elif _probe_phase == 2 and (_game.state == _game.State.DEAD or _probe_frames >= PROBE_MAX_FRAMES):
		print("PROBE pit state=%s y=%.3f drop=%.2f" % [_state_name(), _player.global_position.y, _last_fall])
		get_tree().quit()


func _on_fall_damage(drop: float) -> void:
	_last_fall = drop


func _state_name() -> String:
	if _game == null:
		return "NO GAME"
	return str(_game.State.keys()[_game.state])


func _yes_no(value: bool) -> String:
	return "yes" if value else "no"
