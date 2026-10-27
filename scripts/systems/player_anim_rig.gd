extends RefCounted
class_name PlayerAnimRig
## Builds and drives the Wick's AnimationTree. It owns the graph and its parameter paths and knows nothing
## about game state. Stages, lowest to highest priority, each one overriding the stage before it:
##   Locomotion (BlendSpace1D: idle 0, walk 1, run 2) -> LocoScale (foot planting)
##   -> Hit (OneShot) -> Air (Blend2 faded in while airborne, holding one frame of a clip: AirSeek picks the
##   frame, AirScale at 0 keeps it) -> Attack (OneShot whose shot is chosen by the AttackPick transition, timed
##   by AttackScale) -> Roll (OneShot through RollScale) -> Death (Blend2 held at 1 while dead; DeathSeek
##   restarts the clip).
## Built in code rather than saved in player.tscn so a renamed clip is one export away, not a graph rewire.

const SHOT_HIT := &"Hit"
const SHOT_ATTACK := &"Attack"
const SHOT_ROLL := &"Roll"
const SHOTS: Array[StringName] = [SHOT_HIT, SHOT_ATTACK, SHOT_ROLL]
const P_BLEND := &"parameters/Locomotion/blend_position"
const P_LOCO_SCALE := &"parameters/LocoScale/scale"
const P_ATTACK_PICK := &"parameters/AttackPick/transition_request"
const P_ATTACK_SCALE := &"parameters/AttackScale/scale"
const P_ROLL_SCALE := &"parameters/RollScale/scale"
const P_DEATH_BLEND := &"parameters/Death/blend_amount"
const P_DEATH_SEEK := &"parameters/DeathSeek/seek_request"
const P_AIR_BLEND := &"parameters/Air/blend_amount"
const P_AIR_SEEK := &"parameters/AirSeek/seek_request"
const P_AIR_SCALE := &"parameters/AirScale/scale"
const FADE_IN := 0.08
const FADE_OUT := 0.12
const FIRE := AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE
const ABORT := AnimationNodeOneShot.ONE_SHOT_REQUEST_ABORT
# Blend-space positions of the gait clips: idle sits at 0.
const WALK_BLEND := 1.0
const RUN_BLEND := 2.0

var tree: AnimationTree
var _player: AnimationPlayer
var _request: Dictionary = {}
var _active: Dictionary = {}


static func build(
	player: AnimationPlayer,
	idle: StringName,
	walk: StringName,
	run: StringName,
	hit: StringName,
	roll: StringName,
	death: StringName,
	air: StringName,
	attacks: Array[StringName],
) -> PlayerAnimRig:
	var rig: PlayerAnimRig = PlayerAnimRig.new()
	rig._player = player
	var root: AnimationNodeBlendTree = AnimationNodeBlendTree.new()
	var space: AnimationNodeBlendSpace1D = AnimationNodeBlendSpace1D.new()
	space.min_space = 0.0
	space.max_space = 2.0
	space.sync = true
	space.add_blend_point(_anim(idle), 0.0, -1, &"idle")
	space.add_blend_point(_anim(walk), WALK_BLEND, -1, &"walk")
	space.add_blend_point(_anim(run), RUN_BLEND, -1, &"run")
	root.add_node(&"Locomotion", space)
	root.add_node(&"LocoScale", AnimationNodeTimeScale.new())
	root.connect_node(&"LocoScale", 0, &"Locomotion")
	root.add_node(&"HitAnim", _anim(hit))
	_add_shot(root, SHOT_HIT, &"LocoScale", &"HitAnim")
	root.add_node(&"AirAnim", _anim(air))
	root.add_node(&"AirScale", AnimationNodeTimeScale.new())
	root.connect_node(&"AirScale", 0, &"AirAnim")
	root.add_node(&"AirSeek", AnimationNodeTimeSeek.new())
	root.connect_node(&"AirSeek", 0, &"AirScale")
	root.add_node(&"Air", AnimationNodeBlend2.new())
	root.connect_node(&"Air", 0, SHOT_HIT)
	root.connect_node(&"Air", 1, &"AirSeek")
	var pick: AnimationNodeTransition = AnimationNodeTransition.new()
	pick.xfade_time = 0.0
	pick.input_count = attacks.size()
	root.add_node(&"AttackPick", pick)
	for i: int in attacks.size():
		var node_name: StringName = StringName("Attack%d" % i)
		pick.set_input_name(i, attacks[i])
		root.add_node(node_name, _anim(attacks[i]))
		root.connect_node(&"AttackPick", i, node_name)
	root.add_node(&"AttackScale", AnimationNodeTimeScale.new())
	root.connect_node(&"AttackScale", 0, &"AttackPick")
	_add_shot(root, SHOT_ATTACK, &"Air", &"AttackScale")
	root.add_node(&"RollAnim", _anim(roll))
	root.add_node(&"RollScale", AnimationNodeTimeScale.new())
	root.connect_node(&"RollScale", 0, &"RollAnim")
	_add_shot(root, SHOT_ROLL, SHOT_ATTACK, &"RollScale")
	root.add_node(&"DeathAnim", _anim(death))
	root.add_node(&"DeathSeek", AnimationNodeTimeSeek.new())
	root.connect_node(&"DeathSeek", 0, &"DeathAnim")
	root.add_node(&"Death", AnimationNodeBlend2.new())
	root.connect_node(&"Death", 0, SHOT_ROLL)
	root.connect_node(&"Death", 1, &"DeathSeek")
	root.connect_node(&"output", 0, &"Death")
	rig.tree = AnimationTree.new()
	rig.tree.name = &"AnimationTree"
	rig.tree.tree_root = root
	for shot: StringName in SHOTS:
		rig._request[shot] = StringName("parameters/%s/request" % shot)
		rig._active[shot] = StringName("parameters/%s/active" % shot)
	return rig


# The tree sits beside the AnimationPlayer so both resolve track paths from the same model root.
func attach(model_root: Node) -> void:
	model_root.add_child(tree)
	tree.anim_player = tree.get_path_to(_player)
	tree.active = true
	# The airborne pose is a held frame: a seek passes through a zero time scale, nothing else moves it.
	tree.set(P_AIR_SCALE, 0.0)


func set_locomotion(blend: float, time_scale: float) -> void:
	tree.set(P_BLEND, blend)
	tree.set(P_LOCO_SCALE, time_scale)


func fire_hit() -> void:
	tree.set(_request[SHOT_HIT], FIRE)


func fire_attack(clip: StringName, time_scale: float) -> void:
	tree.set(P_ATTACK_PICK, clip)
	tree.set(P_ATTACK_SCALE, time_scale)
	tree.set(_request[SHOT_ATTACK], FIRE)


func fire_roll(time_scale: float) -> void:
	tree.set(P_ROLL_SCALE, time_scale)
	tree.set(_request[SHOT_ROLL], FIRE)


# Seeks the airborne clip to the frame to hold; call when a spell in the air begins.
func hold_air_pose(time: float) -> void:
	tree.set(P_AIR_SEEK, maxf(time, 0.0))


# 0 = locomotion shows through, 1 = the held airborne pose; the animator fades between them.
func set_airborne(amount: float) -> void:
	tree.set(P_AIR_BLEND, clampf(amount, 0.0, 1.0))


# Death is a held blend, not a one-shot: a one-shot would fall back to idle and the corpse would stand up.
func set_dead(dead: bool) -> void:
	if dead:
		tree.set(P_DEATH_SEEK, 0.0)
	tree.set(P_DEATH_BLEND, 1.0 if dead else 0.0)


func abort_shots() -> void:
	for shot: StringName in SHOTS:
		tree.set(_request[shot], ABORT)


func is_active(shot: StringName) -> bool:
	return bool(tree.get(_active[shot]))


func clip_length(clip: StringName) -> float:
	if _player == null or not _player.has_animation(clip):
		return 0.0
	return _player.get_animation(clip).length


# Foot planting: play the gait at (ground speed / speed the clip was authored for) so the stance foot slides
# back at exactly the ground speed. Idle keeps real time, so the scale eases in with the walk blend.
static func playback_scale(
	speed_mps: float, blend: float, walk_clip_speed_mps: float, run_clip_speed_mps: float, min_scale: float, max_scale: float
) -> float:
	if is_nan(speed_mps) or is_nan(blend) or speed_mps <= 0.0 or blend <= 0.0:
		return 1.0
	var clip_speed: float = lerpf(walk_clip_speed_mps, run_clip_speed_mps, clampf(blend - WALK_BLEND, 0.0, 1.0))
	if is_nan(clip_speed) or clip_speed <= 0.0 or max_scale < min_scale:
		return 1.0
	var planted: float = clampf(speed_mps / clip_speed, min_scale, max_scale)
	return lerpf(1.0, planted, clampf(blend, 0.0, 1.0))


static func swing_duration(windup: float, active: float, recovery: float) -> float:
	return maxf(windup + active + recovery, 0.0)


# Playback rate that makes a clip last exactly target_duration; degenerate inputs leave it at real time.
static func fit_scale(clip_length: float, target_duration: float) -> float:
	if is_nan(clip_length) or is_nan(target_duration) or clip_length <= 0.0 or target_duration <= 0.0:
		return 1.0
	return clip_length / target_duration


static func missing_clips(available: PackedStringArray, required: Array[StringName]) -> Array[StringName]:
	var out: Array[StringName] = []
	for clip: StringName in required:
		if not available.has(String(clip)) and not out.has(clip):
			out.append(clip)
	return out


static func _anim(clip: StringName) -> AnimationNodeAnimation:
	var node: AnimationNodeAnimation = AnimationNodeAnimation.new()
	node.animation = clip
	return node


static func _add_shot(root: AnimationNodeBlendTree, shot_name: StringName, from: StringName, shot_from: StringName) -> void:
	var shot: AnimationNodeOneShot = AnimationNodeOneShot.new()
	shot.fadein_time = FADE_IN
	shot.fadeout_time = FADE_OUT
	root.add_node(shot_name, shot)
	root.connect_node(shot_name, 0, from)
	root.connect_node(shot_name, 1, shot_from)
