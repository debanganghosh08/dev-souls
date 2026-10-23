extends Node3D
## Grey-box movement test level. Puts Game into PLAYING, feeds the on-screen readout, and offers two
## debug keys: `pause` (Esc) toggles PLAYING/PAUSED (frees the mouse), `interact` (E) respawns when DEAD.
## With the user arg `--probe` (used by tests/test_player.gd and tests/test_interaction.gd) it prints
## machine-readable lines and quits.

const PROBE_LAND_FRAMES := 120
const PROBE_STAIR_FRAMES := 90
const PROBE_INTERACT_FRAMES := 12
const PROBE_MAX_FRAMES := 600
const PIT_DROP_POINT := Vector3(23.0, 0.5, 0.0)
const STAIR_START_POINT := Vector3(0.0, 0.6, 7.0)
const CHEST_APPROACH_POINT := Vector3(2.0, 0.6, -2.0)
const STAIR_TOP_Y := 1.0
const READOUT := "speed  %5.2f m/s %s\nstamina  %3d %%\ngrounded %s   dodging %s   i-frames %s\nstate  %s\nlast fall  %.1f m\npos  (%.1f, %.1f, %.1f)\n\nfocus  %s\n%s\n%s\n\nWASD move   Shift sprint   Space dodge   mouse look\nE interact   Esc pause/unpause   E respawn when dead"

@onready var _player: PlayerController = %Player
@onready var _label: Label = %DebugLabel

var _game: Node
var _detector: InteractionDetector
var _prompt: String = ""
var _refusal: String = ""
var _reading: String = ""
var _last_fall: float = 0.0
var _probe: bool = false
var _probe_frames: int = 0
var _probe_phase: int = 0
var _probe_peak_y: float = -1000.0


func _ready() -> void:
	_game = get_node_or_null(^"/root/Game")
	_player.took_fall_damage.connect(_on_fall_damage)
	_detector = _player.get_node_or_null(^"%InteractionDetector") as InteractionDetector
	if _detector != null:
		_detector.focus_changed.connect(_on_focus_changed)
		_detector.interaction_refused.connect(_on_interaction_refused)
	var stone: LoreStone = %GraveMarker
	stone.reading_requested.connect(_on_reading_requested)
	if _game != null:
		_game.state = _game.State.PLAYING
	_probe = OS.get_cmdline_user_args().has("--probe")
	if _probe:
		# Interacting autosaves. Redirect to a throwaway slot BEFORE anything writes, so a probe run can
		# neither overwrite nor delete the player's real save.
		var save: Node = get_node_or_null(^"/root/SaveGame")
		if save != null:
			save.use_slot_path("user://probe_slot.json")


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
		_prompt if _prompt != "" else "-",
		_refusal,
		_reading,
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
		# Stand two strides south of the chest; the camera's rest yaw looks along -Z, straight at it.
		_player.global_position = CHEST_APPROACH_POINT
		_player.velocity = Vector3.ZERO
		(_player.get_camera_rig() as CameraRig).snap_to_target()
		_probe_frames = 0
		_probe_phase = 2
	elif _probe_phase == 2:
		if _probe_frames < PROBE_INTERACT_FRAMES:
			return
		_probe_interactions()
		_player.global_position = PIT_DROP_POINT
		_player.velocity = Vector3.ZERO
		_probe_frames = 0
		_probe_phase = 3
	elif _probe_phase == 3 and (_game.state == _game.State.DEAD or _probe_frames >= PROBE_MAX_FRAMES):
		print("PROBE pit state=%s y=%.3f drop=%.2f" % [_state_name(), _player.global_position.y, _last_fall])
		# Remove the throwaway probe slot redirected to in _ready (never the real one).
		var save: Node = get_node_or_null(^"/root/SaveGame")
		if save != null:
			save.delete()
		get_tree().quit()


# Focus through the real detector and camera, then the lever -> key -> door chain by direct calls.
func _probe_interactions() -> void:
	var inventory: Node = get_node_or_null(^"/root/Inventory")
	var target: Interactable = _detector.current_target() if _detector != null else null
	print("PROBE focus id=%s prompt=%s" % [
		target.id if target != null else "none",
		target.prompt_text() if target != null else "none",
	])
	var chest: Chest = %KindlingChest
	var opened: bool = _detector != null and _detector.try_interact()
	print("PROBE chest opened=%s kindling=%d spent=%s prompt_after=%s" % [
		opened,
		inventory.count(&"kindling_grey") if inventory != null else -1,
		chest.is_spent(),
		"empty" if chest.prompt_text() == "" else chest.prompt_text(),
	])
	var door: Door = %GateDoor
	var lever: Lever = %GateLever
	var barred: bool = not door.interact(_player)
	var lever_on: bool = lever.interact(_player) and lever.is_on()
	var keyless: bool = not door.interact(_player)
	if inventory != null:
		inventory.add(&"castle_key")
	var opened_door: bool = door.interact(_player)
	print("PROBE door barred=%s lever_on=%s keyless=%s opened=%s is_open=%s" % [
		barred, lever_on, keyless, opened_door, door.is_open(),
	])


func _on_focus_changed(target: Interactable) -> void:
	_prompt = "" if target == null else "E  %s" % target.prompt_text()


func _on_interaction_refused(reason: String) -> void:
	_refusal = reason


func _on_reading_requested(title: String, body: String) -> void:
	_reading = "%s - %s" % [title, body]


func _on_fall_damage(drop: float) -> void:
	_last_fall = drop


func _state_name() -> String:
	if _game == null:
		return "NO GAME"
	return str(_game.State.keys()[_game.state])


func _yes_no(value: bool) -> String:
	return "yes" if value else "no"
