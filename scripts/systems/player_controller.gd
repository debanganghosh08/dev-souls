extends CharacterBody3D
class_name PlayerController
## Souls-like locomotion: camera-relative walk/sprint, dodge roll, gravity, fall tracking, plus the player's
## Health and the Melee child. Hard landings deal scaled damage; a lethal one or empty health asks Game to kill.
## The player does not extend Damageable (no multiple inheritance) but offers the same take_damage shape.

signal took_fall_damage(drop: float)
signal dodged()
signal health_changed(fraction: float)
signal damaged(amount: float, from: Node)

@export_group("Movement")
@export var walk_speed: float = 4.2
@export var sprint_speed: float = 7.0
@export var acceleration: float = 12.0
@export var friction: float = 16.0
@export var rotation_speed: float = 10.0
@export_group("Gravity")
@export var gravity: float = 22.0
@export var terminal_velocity: float = 55.0
@export_group("Dodge")
@export var dodge_speed: float = 9.5
@export var dodge_duration: float = 0.45
@export var dodge_cost: float = 25.0
@export var dodge_invulnerable_fraction: float = 0.6
@export_group("Stamina")
@export var stamina_max: float = 100.0
@export var stamina_regen_per_sec: float = 30.0
@export var stamina_regen_delay_sec: float = 0.6
@export var sprint_drain_per_sec: float = 18.0
@export_group("Health")
@export var max_health: float = 100.0
@export_group("Falling")
@export var fall_damage_height: float = 8.0
@export var killing_fall_height: float = 16.0
@export var fall_damage_per_metre: float = 12.0
@export_group("Steps")
@export var step_up_enabled: bool = true
@export var max_step_height: float = 0.4
@export var step_probe_distance: float = 0.3

var is_invulnerable: bool = false
var is_dodging: bool = false

@onready var _rig: CameraRig = %CameraRig
@onready var _melee: Melee = get_node_or_null(^"Melee") as Melee

var _stamina: Stamina = Stamina.new()
var _health: Health = Health.new()
var _game: Node
var _inventory: Node
var _state_playing: int = -1
var _sprinting: bool = false
var _dodge_time_left: float = 0.0
var _dodge_dir: Vector3 = Vector3.FORWARD
var _airborne: bool = false
var _peak_y: float = 0.0
var _wish_dir: Vector3 = Vector3.ZERO


func _ready() -> void:
	_sync_stamina_tuning()
	_stamina.reset()
	_health.set_max(max_health, false)
	_health.reset()
	if _game == null:
		_inject(get_node_or_null(^"/root/Game"), get_node_or_null(^"/root/Inventory"))
	_auto_equip()


# The Game autoload is looked up by path instead of the `Game` global so tests can hand in an instance
# before autoloads exist (same idiom as Game._inject for SaveGame).
func _inject(game: Node, inventory: Node = null) -> void:
	_game = game
	if inventory != null and inventory != _inventory:
		_inventory = inventory
		if not _inventory.is_connected(&"item_added", _on_item_added):
			_inventory.connect(&"item_added", _on_item_added)
	if _game == null:
		return
	_state_playing = _game.State.PLAYING
	if not _game.is_connected(&"respawned", _on_respawned):
		_game.connect(&"respawned", _on_respawned)


func _physics_process(delta: float) -> void:
	var playing: bool = _is_playing()
	if playing:
		_sync_stamina_tuning()
		_stamina.tick(delta)
		if is_dodging:
			_update_dodge(delta)
		else:
			_update_locomotion(delta)
	else:
		velocity.x = 0.0
		velocity.z = 0.0
		_sprinting = false
		_wish_dir = Vector3.ZERO
	if is_on_floor():
		velocity.y = 0.0
	else:
		velocity.y = maxf(velocity.y - gravity * delta, -terminal_velocity)
	move_and_slide()
	if playing and step_up_enabled:
		_try_step_up()
	_update_fall_tracking(is_on_floor(), global_position.y)
	if playing:
		_face_velocity(delta)
	if _game != null:
		_game.player_position = global_position


func stamina_fraction() -> float:
	return _stamina.fraction()


func health_fraction() -> float:
	return _health.fraction()


func get_stamina() -> Stamina:
	return _stamina


func get_health() -> Health:
	return _health


func get_melee() -> Melee:
	return _melee


# Dodge i-frames and any non-PLAYING state (dead, paused, menu) swallow damage outright.
func take_damage(amount: float, from: Node) -> float:
	if is_invulnerable or not _is_playing():
		return 0.0
	var applied: float = _health.damage(amount)
	if applied <= 0.0:
		return 0.0
	damaged.emit(applied, from)
	health_changed.emit(_health.fraction())
	if _health.is_dead():
		_game.kill_player()
	return applied


func is_sprinting() -> bool:
	return _sprinting


func get_camera_rig() -> Node3D:
	return _rig


func _is_playing() -> bool:
	return _game != null and _game.state == _state_playing


func _sync_stamina_tuning() -> void:
	_stamina.max_value = stamina_max
	_stamina.regen_per_sec = stamina_regen_per_sec
	_stamina.regen_delay_sec = stamina_regen_delay_sec


func _update_locomotion(delta: float) -> void:
	var input: Vector2 = Input.get_vector(&"move_left", &"move_right", &"move_forward", &"move_back")
	var yaw: float = _rig.get_yaw() if _rig != null else 0.0
	var wish_dir: Vector3 = Vector3(input.x, 0.0, input.y).rotated(Vector3.UP, yaw)
	var has_input: bool = wish_dir.length_squared() > 0.0001
	if Input.is_action_just_pressed(&"dodge") and is_on_floor() and _stamina.spend(dodge_cost):
		_start_dodge(wish_dir.normalized() if has_input else -global_basis.z)
		return
	_sprinting = has_input and Input.is_action_pressed(&"sprint") and _stamina.drain(sprint_drain_per_sec, delta)
	_wish_dir = wish_dir
	var target_speed: float = sprint_speed if _sprinting else walk_speed
	var horizontal: Vector3 = Vector3(velocity.x, 0.0, velocity.z)
	var target: Vector3 = wish_dir * target_speed if has_input else Vector3.ZERO
	var speeding_up: bool = has_input and target.length_squared() >= horizontal.length_squared()
	var rate: float = acceleration if speeding_up else friction
	horizontal = horizontal.move_toward(target, rate * delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.z


func _start_dodge(direction: Vector3) -> void:
	_dodge_dir = Vector3(direction.x, 0.0, direction.z).normalized()
	_dodge_time_left = dodge_duration
	is_dodging = true
	is_invulnerable = true
	_sprinting = false
	dodged.emit()


func _update_dodge(delta: float) -> void:
	_wish_dir = _dodge_dir
	_dodge_time_left -= delta
	var elapsed_fraction: float = 1.0 - _dodge_time_left / maxf(dodge_duration, 0.001)
	is_invulnerable = elapsed_fraction < dodge_invulnerable_fraction
	velocity.x = _dodge_dir.x * dodge_speed
	velocity.z = _dodge_dir.z * dodge_speed
	if _dodge_time_left <= 0.0:
		is_dodging = false
		is_invulnerable = false


# CharacterBody3D cannot climb steps: a 0.25 m stair tread reads as a wall, so the player sticks. When the
# way ahead is blocked at foot level but clear one step higher, lift the body onto the step and settle it.
# Teleporting is safe here only because test_move proved the raised volume is free.
func _try_step_up() -> void:
	if not is_on_floor() or not is_on_wall():
		return
	var flat: Vector3 = Vector3(_wish_dir.x, 0.0, _wish_dir.z)
	if flat.length_squared() < 0.0001:
		return
	var ahead: Vector3 = flat.normalized() * step_probe_distance
	if not test_move(global_transform, ahead):
		return
	var lifted: Transform3D = global_transform.translated(Vector3.UP * max_step_height)
	if test_move(lifted, ahead):
		return
	global_transform = lifted.translated(ahead)
	move_and_collide(Vector3.DOWN * (max_step_height + 0.05))


func _face_velocity(delta: float) -> void:
	var horizontal: Vector3 = Vector3(velocity.x, 0.0, velocity.z)
	if horizontal.length_squared() < 0.01:
		return
	var target_yaw: float = atan2(-horizontal.x, -horizontal.z)
	rotation.y = lerp_angle(rotation.y, target_yaw, minf(rotation_speed * delta, 1.0))


# Tracks the highest point of an airborne arc; on landing the drop decides fall damage / death.
func _update_fall_tracking(on_floor: bool, y: float) -> void:
	if not on_floor:
		if not _airborne:
			_airborne = true
			_peak_y = y
		elif y > _peak_y:
			_peak_y = y
		return
	if not _airborne:
		return
	_airborne = false
	var drop: float = _peak_y - y
	if drop <= fall_damage_height:
		return
	took_fall_damage.emit(drop)
	if drop > killing_fall_height:
		if _game != null:
			_game.kill_player()
		return
	take_damage(fall_damage_for(drop), null)


# Damage grows linearly with every metre past fall_damage_height; the hard kill above killing_fall_height
# stays in _update_fall_tracking so a lethal drop never depends on these numbers.
func fall_damage_for(drop: float) -> float:
	return maxf(drop - fall_damage_height, 0.0) * fall_damage_per_metre


func _on_item_added(_id: StringName, _amount: int) -> void:
	_auto_equip()


# Best weapon held wins: sword > hammer > torch. Nothing held leaves the hands empty (Melee's unarmed entry).
func _auto_equip() -> void:
	if _melee == null or _inventory == null:
		return
	for id: StringName in [&"sword", &"hammer", &"torch"]:
		if _inventory.has(id):
			_melee.equip(id)
			return
	_melee.unequip()


func _on_respawned() -> void:
	if _game != null:
		global_position = _game.respawn_point
	velocity = Vector3.ZERO
	is_dodging = false
	is_invulnerable = false
	_sprinting = false
	_airborne = false
	_stamina.reset()
	_health.reset()
	health_changed.emit(_health.fraction())
	if _rig != null:
		_rig.snap_to_target()
