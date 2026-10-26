extends Node
class_name PlayerAnimator
## Translates PlayerController state into the Wick's animations. The controller never learns a clip name:
## this node reads its velocity, listens to its signals, Melee's and Game's, and drives a PlayerAnimRig.
## Every decision (locomotion blend, foot planting, which state wins) is a static function tests can pin down.

enum State { LOCOMOTION, HIT, ATTACK_LIGHT, ATTACK_HEAVY, ROLL, DEATH }

const WALK_BLEND := PlayerAnimRig.WALK_BLEND
const RUN_BLEND := PlayerAnimRig.RUN_BLEND

@export var controller_path: NodePath = ^".."
@export var model_path: NodePath = ^"../Body/Model"
@export_group("Clips")
@export var idle_clip: StringName = &"CharacterArmature|Idle"
@export var walk_clip: StringName = &"CharacterArmature|Walk"
@export var run_clip: StringName = &"CharacterArmature|Run"
@export var roll_clip: StringName = &"CharacterArmature|Roll"
@export var light_clip: StringName = &"CharacterArmature|Sword_Slash"
@export var heavy_clip: StringName = &"CharacterArmature|Sword_Slash"
@export var unarmed_light_clip: StringName = &"CharacterArmature|Punch_Right"
@export var unarmed_heavy_clip: StringName = &"CharacterArmature|Kick_Right"
@export var hit_clip: StringName = &"CharacterArmature|HitRecieve"
@export var death_clip: StringName = &"CharacterArmature|Death"
@export_group("Foot planting")
## Ground speed (m/s) at which each clip's feet stay planted: the foot bone's average stance speed in the
## clip, measured headlessly, times the Body's 0.932 scale. Playback runs at speed / clip speed.
@export var walk_clip_speed: float = 0.99
@export var run_clip_speed: float = 1.67
@export var min_time_scale: float = 0.5
# Measured: the walk clip plants ~0.99 m/s and the run clip ~1.67 m/s at this model's scale, against a game
# walk of 4.2 and sprint of 7.0 — so planting the feet exactly would need ~4.2x, which reads as frantic legs.
# 3.5 halves the residual slide (30% -> ~17%) without that. The other lever is lowering walk_speed and
# sprint_speed by ~15% on PlayerController, which would remove the slide entirely; that is a feel call.
@export var max_time_scale: float = 3.5

var _controller: PlayerController
var _melee: Melee
var _game: Node
var _rig: PlayerAnimRig
var _anim: AnimationPlayer
var _missing: Array[StringName] = []
var _dead: bool = false
var _heavy: bool = false
var _speed: float = 0.0
var _blend: float = 0.0
var _time_scale: float = 1.0


func _ready() -> void:
	_controller = get_node_or_null(controller_path) as PlayerController
	var model: Node = get_node_or_null(model_path)
	_anim = _find_player(model)
	var available: PackedStringArray = _anim.get_animation_list() if _anim != null else PackedStringArray()
	_missing = PlayerAnimRig.missing_clips(available, required_clips())
	if _anim != null and _missing.is_empty():
		# The glb imports every clip as play-once; the .import file that could fix that is git-ignored (D-005),
		# so looping the gait clips here is the only setting that survives rebuilding assets/.
		for clip: StringName in [idle_clip, walk_clip, run_clip]:
			_anim.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
		_anim.stop()
		_rig = PlayerAnimRig.build(_anim, idle_clip, walk_clip, run_clip, hit_clip, roll_clip, death_clip, _attack_clips())
		_rig.attach(model)
	if _controller != null:
		_controller.dodged.connect(_on_dodged)
		_controller.damaged.connect(_on_damaged)
		# Children ready before parents: the controller's own @onready Melee ref is still null here.
		_melee = _controller.get_node_or_null(^"Melee") as Melee
	if _melee != null:
		_melee.swing_started.connect(_on_swing_started)
	_inject(get_node_or_null(^"/root/Game"))


func _inject(game: Node) -> void:
	_game = game
	if _game == null:
		return
	if not _game.is_connected(&"player_died", _on_player_died):
		_game.connect(&"player_died", _on_player_died)
	if not _game.is_connected(&"respawned", _on_respawned):
		_game.connect(&"respawned", _on_respawned)


func _physics_process(_delta: float) -> void:
	if _controller == null or _rig == null:
		return
	_speed = Vector2(_controller.velocity.x, _controller.velocity.z).length()
	_blend = locomotion_blend(_speed, _controller.walk_speed, _controller.sprint_speed)
	_time_scale = PlayerAnimRig.playback_scale(_speed, _blend, walk_clip_speed, run_clip_speed, min_time_scale, max_time_scale)
	_rig.set_locomotion(_blend, _time_scale)


func current_state() -> State:
	if _rig == null:
		return State.DEATH if _dead else State.LOCOMOTION
	return resolve(_dead, _rolling(), _rig.is_active(PlayerAnimRig.SHOT_ATTACK), _heavy, _rig.is_active(PlayerAnimRig.SHOT_HIT), false)


func state_name() -> String:
	return str(State.keys()[current_state()])


func is_busy() -> bool:
	return current_state() != State.LOCOMOTION


func is_rigged() -> bool:
	return _rig != null


func missing() -> Array[StringName]:
	return _missing


func has_clip(clip: StringName) -> bool:
	return _anim != null and _anim.has_animation(clip)


func clip_count() -> int:
	return _anim.get_animation_list().size() if _anim != null else 0


func required_clips() -> Array[StringName]:
	return [idle_clip, walk_clip, run_clip, roll_clip, light_clip, heavy_clip, hit_clip, death_clip]


func blend_value() -> float:
	return _blend


func time_scale() -> float:
	return _time_scale


func speed() -> float:
	return _speed


# 0 = idle, 1 = walk clip, 2 = run clip; linear between, clamped beyond. Rest, reverse and NaN read as idle.
static func locomotion_blend(speed_mps: float, walk_speed: float, sprint_speed: float) -> float:
	if is_nan(speed_mps) or is_nan(walk_speed) or is_nan(sprint_speed) or speed_mps <= 0.0 or walk_speed <= 0.0:
		return 0.0
	if speed_mps <= walk_speed:
		return speed_mps / walk_speed * WALK_BLEND
	if sprint_speed <= walk_speed:
		return WALK_BLEND
	var run_mix: float = clampf((speed_mps - walk_speed) / (sprint_speed - walk_speed), 0.0, 1.0)
	return WALK_BLEND + run_mix * (RUN_BLEND - WALK_BLEND)


# Which animation wins when several are wanted at once. Death is absolute. A roll overrides a swing because
# the controller lets the player dodge mid-swing. Melee never cancels a swing, so the swing keeps showing over
# a hit (the blow it lands is real). A hit reaction never shows during i-frames or a roll.
static func resolve(dead: bool, rolling: bool, attacking: bool, heavy: bool, hit: bool, invulnerable: bool) -> State:
	if dead:
		return State.DEATH
	if rolling:
		return State.ROLL
	if attacking:
		return State.ATTACK_HEAVY if heavy else State.ATTACK_LIGHT
	if hit and not invulnerable:
		return State.HIT
	return State.LOCOMOTION


func _attack_clips() -> Array[StringName]:
	var out: Array[StringName] = [light_clip]
	for clip: StringName in [heavy_clip, unarmed_light_clip, unarmed_heavy_clip]:
		if has_clip(clip) and not out.has(clip):
			out.append(clip)
	return out


# Unarmed swings fall back to the weapon clips when the model has no punch or kick.
func _attack_clip(heavy: bool, armed: bool) -> StringName:
	if armed:
		return heavy_clip if heavy else light_clip
	var unarmed: StringName = unarmed_heavy_clip if heavy else unarmed_light_clip
	return unarmed if has_clip(unarmed) else (heavy_clip if heavy else light_clip)


func _rolling() -> bool:
	return (_controller != null and _controller.is_dodging) or _rig.is_active(PlayerAnimRig.SHOT_ROLL)


func _on_dodged() -> void:
	if _rig == null or resolve(_dead, true, false, false, false, true) != State.ROLL:
		return
	_rig.fire_roll(PlayerAnimRig.fit_scale(_rig.clip_length(roll_clip), _controller.dodge_duration))


func _on_swing_started(heavy: bool) -> void:
	if _rig == null:
		return
	var wanted: State = resolve(_dead, _rolling(), true, heavy, false, _controller.is_invulnerable)
	if wanted != State.ATTACK_LIGHT and wanted != State.ATTACK_HEAVY:
		return
	_heavy = heavy
	var clip: StringName = _attack_clip(heavy, _melee.equipped() != WeaponTable.UNARMED)
	var duration: float = PlayerAnimRig.swing_duration(
		_melee.heavy_windup if heavy else _melee.light_windup,
		_melee.active_time,
		_melee.heavy_recovery if heavy else _melee.light_recovery,
	)
	_rig.fire_attack(clip, PlayerAnimRig.fit_scale(_rig.clip_length(clip), duration))


func _on_damaged(_amount: float, _from: Node) -> void:
	if _rig == null:
		return
	var attacking: bool = _rig.is_active(PlayerAnimRig.SHOT_ATTACK)
	if resolve(_dead, _rolling(), attacking, _heavy, true, _controller.is_invulnerable) != State.HIT:
		return
	_rig.fire_hit()


func _on_player_died() -> void:
	_dead = true
	if _rig != null:
		_rig.abort_shots()
		_rig.set_dead(true)


func _on_respawned() -> void:
	_dead = false
	if _rig != null:
		_rig.set_dead(false)


static func _find_player(node: Node) -> AnimationPlayer:
	if node == null:
		return null
	if node is AnimationPlayer:
		return node as AnimationPlayer
	for child: Node in node.get_children():
		var found: AnimationPlayer = _find_player(child)
		if found != null:
			return found
	return null
