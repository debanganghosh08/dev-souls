extends Node3D
## Grey-box movement test level. Puts Game into PLAYING and feeds the debug readout, hidden until
## `debug_toggle` (F3). Pause, death and prompts are the UI layer's job (scenes/ui, composed by main.gd).
## With the user arg `--probe` (used by tests/test_player.gd and tests/test_interaction.gd) it prints
## machine-readable lines and quits -- only when it is the root scene, so main.tscn's own probe can load it.

const PROBE_LAND_FRAMES := 120
const PROBE_STAIR_FRAMES := 90
const PROBE_INTERACT_FRAMES := 12
const PROBE_COMBAT_FRAMES := 60
const PROBE_MAX_FRAMES := 600
const PROBE_BITE_FRAMES := 400
const PIT_DROP_POINT := Vector3(23.0, 0.5, 0.0)
const STAIR_START_POINT := Vector3(0.0, 0.6, 7.0)
const CHEST_APPROACH_POINT := Vector3(2.0, 0.6, -2.0)
const COMBAT_STAND_OFFSET := Vector3(0.0, 0.0, 1.6)
const COMBAT_DEER_OFFSET := Vector3(3.0, 0.0, 0.0)
const STAIR_TOP_Y := 1.0
const READOUT := "speed  %5.2f m/s %s\nstamina  %3d %%   health  %3d %%\ngrounded %s   dodging %s   i-frames %s\nstate  %s\nweapon  %s   attack  %s\nlast fall  %.1f m\npos  (%.1f, %.1f, %.1f)\ntime  %02d:%02d  %s\n\nfocus  %s\n%s\n%s\n\nWASD move   Shift sprint   Space dodge   mouse look\nLMB light   RMB heavy   E interact   Esc pause   F3 hide this readout\nT +2 hours   Y hold to race the clock"

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
var _probe_hit: bool = false
var _probe_hit_damage: float = 0.0
var _probe_bite: bool = false


func _ready() -> void:
	_game = get_node_or_null(^"/root/Game")
	_player.took_fall_damage.connect(_on_fall_damage)
	var melee: Melee = _player.get_melee()
	if melee != null:
		melee.hit_landed.connect(_on_hit_landed)
	_detector = _player.get_node_or_null(^"%InteractionDetector") as InteractionDetector
	if _detector != null:
		_detector.focus_changed.connect(_on_focus_changed)
		_detector.interaction_refused.connect(_on_interaction_refused)
	var stone: LoreStone = %GraveMarker
	stone.reading_requested.connect(_on_reading_requested)
	_label.visible = false
	if _game != null:
		_game.state = _game.State.PLAYING
	_probe_bite = OS.get_cmdline_user_args().has("--probe-bite") and get_tree().current_scene == self
	_probe = OS.get_cmdline_user_args().has("--probe") and get_tree().current_scene == self
	if _probe or _probe_bite:
		# Interacting autosaves. Redirect to a throwaway slot BEFORE anything writes, so a probe run can
		# neither overwrite nor delete the player's real save.
		var save: Node = get_node_or_null(^"/root/SaveGame")
		if save != null:
			save.use_slot_path("user://probe_slot.json")


func _process(delta: float) -> void:
	if _game != null and Input.is_physical_key_pressed(KEY_Y):
		_game.advance_time(delta * 2.0)
	if not _label.visible:
		return
	var v: Vector3 = _player.velocity
	var p: Vector3 = _player.global_position
	var melee: Melee = _player.get_melee()
	_label.text = READOUT % [
		Vector2(v.x, v.z).length(),
		"(sprint)" if _player.is_sprinting() else "",
		roundi(_player.stamina_fraction() * 100.0),
		roundi(_player.health_fraction() * 100.0),
		_yes_no(_player.is_on_floor()),
		_yes_no(_player.is_dodging),
		_yes_no(_player.is_invulnerable),
		_state_name(),
		melee.weapon_name() if melee != null else "-",
		melee.state_name() if melee != null else "-",
		_last_fall,
		p.x, p.y, p.z,
		int(_hour()), int(fposmod(_hour(), 1.0) * 60.0),
		"night" if _game != null and _game.is_night() else "day",
		_prompt if _prompt != "" else "-",
		_refusal,
		_reading,
	]


# The main probe kills the wolf before it ever bites, so the hostile-damage path — the thing that gives the
# world stakes — would otherwise go unverified. This stands the player next to the wolf and never attacks.
func _run_bite_probe() -> void:
	var wolf: Creature = get_node_or_null(^"Creatures/Wolf") as Creature
	if wolf == null or _game == null:
		print("PROBE bite error=no_wolf")
		get_tree().quit()
		return
	_probe_frames += 1
	if _probe_frames == 1:
		_player.global_position = wolf.global_position + Vector3(1.2, 0.0, 0.0)
		_player.velocity = Vector3.ZERO
		return
	if _probe_frames < PROBE_BITE_FRAMES:
		return
	print("PROBE bite player_hp=%.1f wolf_state=%s dist=%.2f bitten=%s" % [
		_player.health_fraction() * _player.max_health,
		wolf.state_name(),
		_player.global_position.distance_to(wolf.global_position),
		_player.health_fraction() < 1.0,
	])
	var save: Node = get_node_or_null(^"/root/SaveGame")
	if save != null:
		save.delete()
	get_tree().quit()


func _hour() -> float:
	return _game.time_of_day if _game != null else 0.0


# Raw keycodes, not input actions: these are test-level conveniences for judging the day/night look without
# waiting out a 20-minute cycle, so they deliberately stay out of project.godot's input map.
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"debug_toggle"):
		_label.visible = not _label.visible
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_T and _game != null:
			_game.advance_time(2.0)




# Headless probe: lets the test suite assert on real physics without driving the loop itself.
func _physics_process(_delta: float) -> void:
	if _probe_bite:
		_run_bite_probe()
		return
	if not _probe or _game == null:
		return
	_probe_frames += 1
	if _probe_phase == 0 and _probe_frames >= PROBE_LAND_FRAMES:
		print("PROBE landed y=%.3f floor=%s pos_written=%s" % [
			_player.global_position.y,
			_player.is_on_floor(),
			_game.player_position.is_equal_approx(_player.global_position),
		])
		_print_perf_probe()
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
		_probe_combat_setup()
		_probe_frames = 0
		_probe_phase = 3
	elif _probe_phase == 3:
		var melee: Melee = _player.get_melee()
		if _probe_frames < PROBE_COMBAT_FRAMES and melee != null and melee.state_name() != "IDLE":
			return
		_probe_combat_report()
		_player.global_position = PIT_DROP_POINT
		_player.velocity = Vector3.ZERO
		_probe_frames = 0
		_probe_phase = 4
	elif _probe_phase == 4 and (_game.state == _game.State.DEAD or _probe_frames >= PROBE_MAX_FRAMES):
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


# Combat by direct calls: the Inventory hands over a sword (auto-equipped through item_added), the player is
# stood a stride south of the wolf facing -Z (straight at it), a deer is dropped beside them, one light swing starts.
func _probe_combat_setup() -> void:
	var inventory: Node = get_node_or_null(^"/root/Inventory")
	if inventory != null:
		inventory.add(&"sword")
	var wolf: Creature = %Wolf
	var deer: Creature = %DeerA
	_player.global_position = wolf.global_position + COMBAT_STAND_OFFSET
	_player.velocity = Vector3.ZERO
	_player.rotation.y = 0.0
	deer.global_position = _player.global_position + COMBAT_DEER_OFFSET
	var melee: Melee = _player.get_melee()
	if melee != null:
		melee.try_attack(false)


func _probe_combat_report() -> void:
	var melee: Melee = _player.get_melee()
	var wolf: Creature = %Wolf
	var deer: Creature = %DeerA
	print("PROBE combat equipped=%s state=%s hit=%s dmg=%.2f wolf_hp=%.1f player_hp=%.1f" % [
		melee.equipped() if melee != null else "none",
		melee.state_name() if melee != null else "none",
		_probe_hit,
		_probe_hit_damage,
		wolf.health.current,
		_player.health_fraction() * _player.max_health,
	])
	print("PROBE creature kind=deer state=%s dead=%s motes=%s" % [
		deer.state_name(), deer.is_dead(), deer.motes_active(),
	])
	wolf.take_damage(1000.0, _player)
	print("PROBE creature kind=wolf state=%s dead=%s motes=%s dissolving=%s" % [
		wolf.state_name(), wolf.is_dead(), wolf.motes_active(), wolf.is_dissolving(),
	])


# Frame cost at the spawn vantage. The RenderingServer counters are the previous frame's; under --headless the
# renderer is a null device, so they read 0 there and only mean something on a real GPU. The dressing line is
# a CPU-side count (instances placed, MultiMesh draws before culling, LOD0 triangles if every one drew).
func _print_perf_probe() -> void:
	print("PROBE perf draw_calls=%d primitives=%d" % [
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME),
	])
	var dressing: LevelDressing = get_node_or_null(^"Dressing") as LevelDressing
	var stats: Dictionary = dressing.stats() if dressing != null else {}
	print("PROBE dressing instances=%d multimeshes=%d colliders=%d est_triangles=%d" % [
		stats.get("instances", 0), stats.get("multimeshes", 0), stats.get("colliders", 0), stats.get("triangles", 0),
	])


func _on_hit_landed(_target: Node, amount: float) -> void:
	_probe_hit = true
	_probe_hit_damage = amount


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
