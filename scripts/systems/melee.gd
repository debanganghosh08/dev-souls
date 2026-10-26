extends Node3D
class_name Melee
## The player's attack system, a child of the player body. IDLE -> WINDUP -> ACTIVE -> RECOVERY -> IDLE.
## Weapon multipliers come from WeaponTable (data/weapons.json). The hit test is the pure static in_arc().

signal swing_started(heavy: bool)
signal hit_landed(target: Node, amount: float)
signal swing_finished()
## The held weapon changed (PlayerWeapons shows it); UNARMED when the hands empty.
signal weapon_changed(item_id: StringName)

enum State { IDLE, WINDUP, ACTIVE, RECOVERY }

const UNARMED := WeaponTable.UNARMED
const TARGET_MASK := 24  # physics layers 4 (enemy) | 5 (animal)
const MAX_TARGETS := 16
const HIT_HEIGHT := 0.9
const MIN_REACH := 0.5
# float32 Vector3 maths vs 64-bit GDScript floats: a target placed exactly at the reach or arc boundary
# lands a hair outside without this slack, so boundaries are inclusive within EPSILON.
const EPSILON := 0.0001

@export_group("Damage")
@export var light_damage: float = 18.0
@export var heavy_damage: float = 34.0
@export_group("Stamina")
@export var light_stamina: float = 14.0
@export var heavy_stamina: float = 26.0
@export_group("Timing")
@export var light_windup: float = 0.14
@export var heavy_windup: float = 0.34
@export var active_time: float = 0.12
@export var light_recovery: float = 0.26
@export var heavy_recovery: float = 0.52
@export_group("Hit volume")
@export var reach: float = 2.2
@export var arc_degrees: float = 110.0

var _state: State = State.IDLE
var _heavy: bool = false
var _time_left: float = 0.0
var _equipped: StringName = UNARMED
var _weapons: Dictionary = {}
# One swing hits each body at most once, however many frames or query results overlap it.
var _hit_this_swing: Array[Node] = []
var _game: Node
var _state_playing: int = -1
var _inventory: Node
var _stamina: Stamina
var _body: Node3D
var _query: PhysicsShapeQueryParameters3D
var _query_shape: SphereShape3D


func _ready() -> void:
	if _weapons.is_empty():
		_weapons = WeaponTable.load_from()
	if _body == null:
		var player: PlayerController = get_parent() as PlayerController
		_inject(
			get_node_or_null(^"/root/Game"),
			get_node_or_null(^"/root/Inventory"),
			player.get_stamina() if player != null else null,
			player,
		)
	_query_shape = SphereShape3D.new()
	_query = PhysicsShapeQueryParameters3D.new()
	_query.shape = _query_shape
	_query.collision_mask = TARGET_MASK
	_query.collide_with_areas = false
	_query.collide_with_bodies = true


# Same idiom as PlayerController._inject: tests hand in fakes before any autoload exists.
func _inject(game: Node, inventory: Node, stamina: Stamina, body: Node3D) -> void:
	_game = game
	_inventory = inventory
	_stamina = stamina
	_body = body
	if _game != null:
		_state_playing = _game.State.PLAYING
	if _weapons.is_empty():
		_weapons = WeaponTable.DEFAULTS.duplicate(true)


func _physics_process(delta: float) -> void:
	if _state == State.IDLE and _is_playing():
		if Input.is_action_just_pressed(&"attack_heavy"):
			try_attack(true)
		elif Input.is_action_just_pressed(&"attack_light"):
			try_attack(false)
	step(delta)


# No combo buffering and no input queue: a press outside IDLE is dropped on purpose, so every swing is a
# commitment the player chose while able to choose (the Souls feel). Stamina is paid up front for the same reason.
func try_attack(heavy: bool) -> bool:
	if not can_attack():
		return false
	if _stamina == null or not _stamina.spend(stamina_cost(heavy)):
		return false
	_heavy = heavy
	_hit_this_swing.clear()
	_enter(State.WINDUP)
	swing_started.emit(heavy)
	return true


func can_attack() -> bool:
	return _state == State.IDLE and _is_playing() and not _body_is_dodging()


func step(delta: float) -> void:
	if _state == State.IDLE:
		return
	_time_left -= delta
	if _time_left > 0.0:
		return
	match _state:
		State.WINDUP:
			_enter(State.ACTIVE)
		State.ACTIVE:
			_enter(State.RECOVERY)
		State.RECOVERY:
			_state = State.IDLE
			swing_finished.emit()


func equip(item_id: StringName) -> bool:
	if item_id == UNARMED:
		unequip()
		return true
	if not _weapons.has(item_id):
		return false
	if _inventory == null or not _inventory.has(item_id):
		return false
	_set_equipped(item_id)
	return true


func unequip() -> void:
	_set_equipped(UNARMED)


func equipped() -> StringName:
	return _equipped


func state_name() -> String:
	return str(State.keys()[_state])


func is_heavy_swing() -> bool:
	return _heavy


func damage_for(heavy: bool) -> float:
	return (heavy_damage if heavy else light_damage) * weapon_stat(&"damage_multiplier", 1.0)


func stamina_cost(heavy: bool) -> float:
	return (heavy_stamina if heavy else light_stamina) * weapon_stat(&"stamina_multiplier", 1.0)


func current_damage() -> float:
	return damage_for(_heavy)


func effective_reach() -> float:
	return maxf(reach + weapon_stat(&"reach_bonus", 0.0), MIN_REACH)


func weapon_name() -> String:
	return str(_weapon_entry().get("name", String(_equipped)))


func weapon_stat(key: StringName, fallback: float) -> float:
	return float(_weapon_entry().get(key, fallback))


func facing() -> Vector3:
	if _body == null:
		return -global_basis.z
	return -(_body.global_basis.z if _body.is_inside_tree() else _body.basis.z)


# Runs the arc test against candidate bodies and damages each new Damageable once. Public so tests can
# feed fakes; the live path collects candidates with a physics query in _sweep.
func apply_hits(candidates: Array, attacker_pos: Vector3, facing_dir: Vector3) -> int:
	var hits: int = 0
	var swing_reach: float = effective_reach()
	for candidate: Variant in candidates:
		var target: Damageable = candidate as Damageable
		if target == null or target.is_dead() or _hit_this_swing.has(target):
			continue
		if not in_arc(attacker_pos, facing_dir, _position_of(target), swing_reach, arc_degrees):
			continue
		_hit_this_swing.append(target)
		var amount: float = target.take_damage(current_damage(), _body)
		hits += 1
		hit_landed.emit(target, amount)
	return hits


# Pure hit test: within reach (inclusive) and within arc_degrees total (half each side of facing, inclusive).
# Standing inside the target counts as a hit; a zero facing cannot aim and misses everything else.
static func in_arc(attacker_pos: Vector3, facing_dir: Vector3, target_pos: Vector3, reach_m: float, arc: float) -> bool:
	if reach_m < 0.0:
		return false
	var to_target: Vector3 = target_pos - attacker_pos
	var distance: float = to_target.length()
	if distance > reach_m + EPSILON:
		return false
	if distance <= EPSILON:
		return true
	if facing_dir.length_squared() <= EPSILON:
		return false
	var cos_half: float = cos(deg_to_rad(clampf(arc, 0.0, 360.0) * 0.5))
	var alignment: float = facing_dir.normalized().dot(to_target / distance)
	return alignment >= cos_half - EPSILON


func _set_equipped(item_id: StringName) -> void:
	if item_id == _equipped:
		return
	_equipped = item_id
	weapon_changed.emit(item_id)


func _enter(state: State) -> void:
	_state = state
	match state:
		State.WINDUP:
			_time_left = heavy_windup if _heavy else light_windup
		State.ACTIVE:
			_time_left = active_time
			_sweep()
		State.RECOVERY:
			_time_left = heavy_recovery if _heavy else light_recovery


# Targets are gathered once per swing, on entering ACTIVE, never per frame: ACTIVE is a window for feel and
# animation, not a repeated hit scan.
func _sweep() -> void:
	if _body == null or not is_inside_tree() or not _is_playing():
		return
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	if space == null:
		return
	var origin: Vector3 = _body.global_position
	_query_shape.radius = effective_reach()
	_query.transform = Transform3D(Basis.IDENTITY, origin + Vector3.UP * HIT_HEIGHT)
	var results: Array[Dictionary] = space.intersect_shape(_query, MAX_TARGETS)
	var candidates: Array = []
	for result: Dictionary in results:
		candidates.append(result["collider"])
	apply_hits(candidates, origin, facing())


func _is_playing() -> bool:
	return _game != null and _game.state == _state_playing


func _body_is_dodging() -> bool:
	return _body != null and _body.get(&"is_dodging") == true


func _weapon_entry() -> Dictionary:
	return _weapons.get(_equipped, _weapons.get(UNARMED, {}))


# Fakes in unit tests never enter a tree, where global_position is an error.
static func _position_of(node: Node3D) -> Vector3:
	return node.global_position if node.is_inside_tree() else node.position
