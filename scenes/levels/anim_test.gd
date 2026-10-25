extends Node3D
## Character animation test rig: flat ground, the player, number keys that force each animation state and a
## readout of what the animator is doing. With the user arg `--probe` (tests/test_animation.gd) it prints
## machine-readable PROBE lines and quits -- only when it is the root scene.

const PROBE_WALK_FRAMES := 60
const PROBE_SHOT_FRAMES := 90
const PROBE_DEATH_FRAMES := 5
const PROBE_SPEEDS: Array[float] = [0.0, 2.1, 4.2, 5.6, 7.0, 9.5]
const READOUT := "anim  %s   busy %s\nblend  %.2f   speed  %.2f m/s   rate  x%.2f\nclips %d   missing %s   rigged %s\n\n1 idle   2 walk   3 run   4 roll   5 light   6 heavy   7 hit   8 die   9 respawn\nWASD / mouse also work   F3 hide this readout"

@onready var _player: PlayerController = %Player
@onready var _label: Label = %Readout

var _animator: PlayerAnimator
var _game: Node
var _probe: bool = false
var _frames: int = 0
var _phase: int = 0
var _shot_frames: int = 0
var _shot_seen: bool = false
var _release_dodge: bool = false


func _ready() -> void:
	_animator = _player.get_node_or_null(^"%Animator") as PlayerAnimator
	_game = get_node_or_null(^"/root/Game")
	if _game != null:
		_game.state = _game.State.PLAYING
	_probe = OS.get_cmdline_user_args().has("--probe") and get_tree().current_scene == self
	if _probe:
		# Dying may autosave; point it at a throwaway slot so a probe never touches the real save.
		var save: Node = get_node_or_null(^"/root/SaveGame")
		if save != null:
			save.use_slot_path("user://probe_anim_slot.json")


func _process(_delta: float) -> void:
	if not _label.visible or _animator == null:
		return
	_label.text = READOUT % [
		_animator.state_name(), _yes_no(_animator.is_busy()),
		_animator.blend_value(), _animator.speed(), _animator.time_scale(),
		_animator.clip_count(), _missing_text(), _yes_no(_animator.is_rigged()),
	]


# Raw keycodes, not input actions: test-level conveniences that stay out of project.godot's input map.
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"debug_toggle"):
		_label.visible = not _label.visible
		return
	var key: InputEventKey = event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	match key.physical_keycode:
		KEY_1: _force_locomotion(false, false)
		KEY_2: _force_locomotion(true, false)
		KEY_3: _force_locomotion(true, true)
		KEY_4: _press_dodge()
		KEY_5: _swing(false)
		KEY_6: _swing(true)
		KEY_7:
			_player.take_damage(5.0, null)
		KEY_8:
			if _game != null:
				_game.kill_player()
		KEY_9:
			if _game != null:
				_game.respawn()


func _force_locomotion(forward: bool, sprint: bool) -> void:
	if forward:
		Input.action_press(&"move_forward")
	else:
		Input.action_release(&"move_forward")
	if sprint:
		Input.action_press(&"sprint")
	else:
		Input.action_release(&"sprint")


# A dodge is read with is_action_just_pressed, so the synthetic press is released on the next physics frame.
func _press_dodge() -> void:
	Input.action_press(&"dodge")
	_release_dodge = true


func _swing(heavy: bool) -> void:
	var melee: Melee = _player.get_melee()
	if melee != null:
		melee.try_attack(heavy)


func _physics_process(_delta: float) -> void:
	if _release_dodge and not _probe:
		Input.action_release(&"dodge")
		_release_dodge = false
	if not _probe or _animator == null:
		return
	_frames += 1
	match _phase:
		0: _probe_clips_and_walk()
		1: _probe_shot("roll", &"ROLL", _probe_arm_and_swing)
		2: _probe_shot("attack", &"ATTACK_LIGHT", _probe_die)
		3: _probe_death()


func _probe_clips_and_walk() -> void:
	if _frames == 1:
		print("PROBE animator clips=%d missing=%s idle=%s walk=%s run=%s roll=%s attack=%s hit=%s death=%s rigged=%s" % [
			_animator.clip_count(), _missing_text(),
			_animator.has_clip(_animator.idle_clip), _animator.has_clip(_animator.walk_clip),
			_animator.has_clip(_animator.run_clip), _animator.has_clip(_animator.roll_clip),
			_animator.has_clip(_animator.light_clip) and _animator.has_clip(_animator.heavy_clip),
			_animator.has_clip(_animator.hit_clip), _animator.has_clip(_animator.death_clip), _animator.is_rigged(),
		])
		for speed: float in PROBE_SPEEDS:
			print("PROBE blend speed=%.2f value=%.3f" % [speed, PlayerAnimator.locomotion_blend(speed, _player.walk_speed, _player.sprint_speed)])
		Input.action_press(&"move_forward")
		return
	if _frames < PROBE_WALK_FRAMES:
		return
	print("PROBE live speed=%.2f blend=%.3f rate=%.2f state=%s busy=%s" % [
		_animator.speed(), _animator.blend_value(), _animator.time_scale(), _animator.state_name(), _animator.is_busy(),
	])
	Input.action_release(&"move_forward")
	Input.action_press(&"dodge")
	_next_phase()


# Counts the frames the named state is showing after a one-shot was requested, then hands over.
func _probe_shot(label: String, state: StringName, then: Callable) -> void:
	if _frames == 2:
		Input.action_release(&"dodge")
	var showing: bool = _animator.state_name() == state
	if showing:
		_shot_frames += 1
		_shot_seen = true
	var settled: bool = _shot_seen and not showing and not _animator.is_busy()
	if _frames < PROBE_SHOT_FRAMES and not settled:
		return
	print("PROBE %s fired=%s active_frames=%d busy_after=%s state_after=%s" % [
		label, _shot_seen, _shot_frames, _animator.is_busy(), _animator.state_name(),
	])
	then.call()
	_next_phase()


func _probe_arm_and_swing() -> void:
	var inventory: Node = get_node_or_null(^"/root/Inventory")
	if inventory != null:
		inventory.add(&"sword")
	var melee: Melee = _player.get_melee()
	print("PROBE swing started=%s weapon=%s" % [melee != null and melee.try_attack(false), melee.equipped() if melee != null else &"none"])


func _probe_die() -> void:
	if _game != null:
		_game.kill_player()


func _probe_death() -> void:
	if _frames < PROBE_DEATH_FRAMES:
		return
	print("PROBE death state=%s busy=%s game=%s" % [_animator.state_name(), _animator.is_busy(), _state_name()])
	var save: Node = get_node_or_null(^"/root/SaveGame")
	if save != null:
		save.delete()
	get_tree().quit()


func _next_phase() -> void:
	_phase += 1
	_frames = 0
	_shot_frames = 0
	_shot_seen = false


func _missing_text() -> String:
	var missing: Array[StringName] = _animator.missing()
	return "none" if missing.is_empty() else ",".join(PackedStringArray(missing))


func _state_name() -> String:
	return "NO GAME" if _game == null else str(_game.State.keys()[_game.state])


func _yes_no(value: bool) -> String:
	return "yes" if value else "no"
