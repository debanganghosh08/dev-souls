extends Damageable
class_name Creature
## One script for every animal, driven by exports instead of subclasses. PASSIVE wanders, SKITTISH flees,
## HOSTILE chases and bites. IDLE <-> WANDER -> (FLEE | CHASE -> ATTACK) -> DEAD, with RETURN_HOME past
## home_leash. The decision is the pure static decide(); death is a quiet dissolve into golden motes.

enum Disposition { PASSIVE, SKITTISH, HOSTILE }
enum State { IDLE, WANDER, FLEE, CHASE, ATTACK, RETURN_HOME, DEAD }

const PLAYER_GROUP := &"player"
const DISSOLVE_SEC := 1.2
const SINK_DEPTH := 0.35
const RETURN_DONE_FRACTION := 0.3
const ARRIVE_DISTANCE := 0.6
const FIRST_BITE_FRACTION := 0.5
const IDLE_MIN_SEC := 1.0
const IDLE_MAX_SEC := 3.0
const WANDER_MIN_SEC := 2.0
const WANDER_MAX_SEC := 5.0

@export var disposition: Disposition = Disposition.PASSIVE
@export_group("Movement")
@export var move_speed: float = 2.0
@export var flee_speed: float = 7.5
@export var chase_speed: float = 5.5
@export var turn_speed: float = 8.0
@export var gravity: float = 22.0
@export_group("Senses")
@export var sight_range: float = 14.0
@export var wander_radius: float = 8.0
@export var home_leash: float = 25.0
@export_group("Attack")
@export var attack_range: float = 1.8
@export var attack_damage: float = 12.0
@export var attack_cooldown: float = 1.6
@export_group("Death")
@export var loot: Dictionary = {}
@export var death_flag: StringName = &""

var _state: State = State.IDLE
var _home: Vector3 = Vector3.ZERO
var _target: Vector3 = Vector3.ZERO
var _timer: float = 0.0
var _cooldown_left: float = 0.0
var _dissolving: bool = false
var _player: Node3D
var _inventory: Node
var _flags: Node
var _collider: CollisionShape3D
var _motes: GPUParticles3D
var _fade_targets: Array[GeometryInstance3D] = []
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


func _ready() -> void:
	super()
	_rng.randomize()
	_home = global_position
	_inventory = get_node_or_null(^"/root/Inventory")
	_flags = get_node_or_null(^"/root/Flags")
	_collider = get_node_or_null(^"CollisionShape3D") as CollisionShape3D
	_motes = get_node_or_null(^"Motes") as GPUParticles3D
	var body: GeometryInstance3D = get_node_or_null(^"Body") as GeometryInstance3D
	if body != null:
		_fade_targets.append(body)
		for child: Node in body.get_children():
			if child is GeometryInstance3D:
				_fade_targets.append(child)
	_begin_idle()


# No navigation mesh yet: the creature steers straight at its goal and lets move_and_slide handle walls.
# Good enough for the greybox; real terrain with trees and cliffs will need NavigationAgent3D.
func _physics_process(delta: float) -> void:
	if _state == State.DEAD:
		return
	if _player == null:
		_player = get_tree().get_first_node_in_group(PLAYER_GROUP) as Node3D
	var here: Vector3 = global_position
	var to_player: float = here.distance_to(_player.global_position) if _player != null else INF
	var to_home: float = here.distance_to(_home)
	_apply_decision(decide(disposition, to_player, to_home, sight_range, attack_range, home_leash, false))
	var dir: Vector3 = Vector3.ZERO
	var speed: float = 0.0
	match _state:
		State.IDLE:
			_timer -= delta
			if _timer <= 0.0:
				_begin_wander()
		State.WANDER:
			_timer -= delta
			dir = _flat_dir(here, _target)
			speed = move_speed
			if _timer <= 0.0 or here.distance_to(_target) <= ARRIVE_DISTANCE:
				_begin_idle()
		State.FLEE:
			dir = -_flat_dir(here, _player.global_position)
			speed = flee_speed
		State.CHASE:
			dir = _flat_dir(here, _player.global_position)
			speed = chase_speed
		State.ATTACK:
			dir = _flat_dir(here, _player.global_position)
			_cooldown_left -= delta
			if _cooldown_left <= 0.0:
				_bite()
		State.RETURN_HOME:
			dir = _flat_dir(here, _home)
			speed = move_speed
			if to_home <= home_leash * RETURN_DONE_FRACTION:
				_begin_idle()
	velocity.x = dir.x * speed
	velocity.z = dir.z * speed
	if is_on_floor():
		velocity.y = 0.0
	else:
		velocity.y -= gravity * delta
	move_and_slide()
	_face(dir, delta)


# Pure state decision, unit-tested. "Within" is inclusive (<=); "beyond the leash" is strict (>), so a
# creature exactly on its leash still reacts to the player.
static func decide(
	kind: Disposition,
	distance_to_player: float,
	distance_to_home: float,
	sight: float,
	bite_range: float,
	leash: float,
	dead: bool = false,
) -> State:
	if dead:
		return State.DEAD
	if distance_to_home > leash:
		return State.RETURN_HOME
	match kind:
		Disposition.SKITTISH:
			return State.FLEE if distance_to_player <= sight else State.WANDER
		Disposition.HOSTILE:
			if distance_to_player <= bite_range:
				return State.ATTACK
			if distance_to_player <= sight:
				return State.CHASE
			return State.WANDER
	return State.WANDER


func state_name() -> String:
	return str(State.keys()[_state])


func is_dissolving() -> bool:
	return _dissolving


func motes_active() -> bool:
	return _motes != null and _motes.emitting


func home_position() -> Vector3:
	return _home


func _on_died(_from: Node) -> void:
	_state = State.DEAD
	velocity = Vector3.ZERO
	collision_layer = 0
	collision_mask = 0
	if _collider != null:
		_collider.set_deferred(&"disabled", true)
	_grant_loot()
	if death_flag != &"" and _flags != null:
		_flags.set_flag(death_flag)
	_start_dissolve()


func _grant_loot() -> void:
	if _inventory == null:
		return
	for id: Variant in loot.keys():
		_inventory.add(StringName(str(id)), int(loot[id]))


# The design's emotional beat: no blood, no ragdoll. The body sinks a little and fades while a handful of
# golden motes rise from it, then the node is gone.
func _start_dissolve() -> void:
	_dissolving = true
	if not is_inside_tree():
		queue_free()
		return
	if _motes != null:
		_motes.emitting = true
	var tween: Tween = create_tween().set_parallel(true)
	tween.tween_property(self, ^"position:y", position.y - SINK_DEPTH, DISSOLVE_SEC).set_ease(Tween.EASE_IN)
	for target: GeometryInstance3D in _fade_targets:
		tween.tween_property(target, ^"transparency", 1.0, DISSOLVE_SEC)
	tween.chain().tween_callback(queue_free)


# RETURN_HOME is sticky until the creature is well inside its leash, so a player standing at the boundary
# cannot make it flip between giving up and re-engaging every frame.
func _apply_decision(decided: State) -> void:
	if _state == State.RETURN_HOME and decided != State.RETURN_HOME and decided != State.DEAD:
		return
	if decided == State.WANDER:
		if _state != State.IDLE and _state != State.WANDER:
			_begin_idle()
		return
	if decided == _state:
		return
	if decided == State.ATTACK:
		_cooldown_left = attack_cooldown * FIRST_BITE_FRACTION
	_state = decided


func _bite() -> void:
	_cooldown_left = attack_cooldown
	if _player != null and _player.has_method(&"take_damage"):
		_player.call(&"take_damage", attack_damage, self)


func _begin_idle() -> void:
	_state = State.IDLE
	_timer = _rng.randf_range(IDLE_MIN_SEC, IDLE_MAX_SEC)


func _begin_wander() -> void:
	_state = State.WANDER
	_timer = _rng.randf_range(WANDER_MIN_SEC, WANDER_MAX_SEC)
	var angle: float = _rng.randf_range(0.0, TAU)
	var radius: float = _rng.randf_range(0.3, 1.0) * wander_radius
	_target = _home + Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)


func _face(dir: Vector3, delta: float) -> void:
	if dir.length_squared() < 0.0001:
		return
	rotation.y = lerp_angle(rotation.y, atan2(-dir.x, -dir.z), minf(turn_speed * delta, 1.0))


static func _flat_dir(from: Vector3, to: Vector3) -> Vector3:
	var out: Vector3 = Vector3(to.x - from.x, 0.0, to.z - from.z)
	return out.normalized() if out.length_squared() > 0.0001 else Vector3.ZERO
