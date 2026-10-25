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
var _fall: PlayerFallTracker = PlayerFallTracker.new()
var _dodge: PlayerDodge = PlayerDodge.new()
var _game: Node
var _inventory: Node
var _state_playing: int = -1
var _sprinting: bool = false
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
	var wish_dir: Vector3 = PlayerMotion.wish_direction(input, yaw)
	var has_input: bool = PlayerMotion.has_input(wish_dir)
	if Input.is_action_just_pressed(&"dodge") and is_on_floor() and _stamina.spend(dodge_cost):
		_start_dodge(wish_dir.normalized() if has_input else -global_basis.z)
		return
	_sprinting = has_input and Input.is_action_pressed(&"sprint") and _stamina.drain(sprint_drain_per_sec, delta)
	_wish_dir = wish_dir
	var target_speed: float = sprint_speed if _sprinting else walk_speed
	var horizontal: Vector3 = Vector3(velocity.x, 0.0, velocity.z)
	horizontal = PlayerMotion.steer(horizontal, wish_dir, target_speed, acceleration, friction, delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.z


func _start_dodge(direction: Vector3) -> void:
	_dodge.start(direction, dodge_duration)
	is_dodging = true
	is_invulnerable = true
	_sprinting = false
	dodged.emit()


func _update_dodge(delta: float) -> void:
	_wish_dir = _dodge.direction
	is_invulnerable = _dodge.tick(delta, dodge_duration, dodge_invulnerable_fraction)
	velocity.x = _dodge.direction.x * dodge_speed
	velocity.z = _dodge.direction.z * dodge_speed
	if not _dodge.active():
		is_dodging = false
		is_invulnerable = false


func _try_step_up() -> void:
	PlayerStepUp.try_step_up(self, _wish_dir, max_step_height, step_probe_distance)


func _face_velocity(delta: float) -> void:
	rotation.y = PlayerMotion.turn_toward(rotation.y, Vector3(velocity.x, 0.0, velocity.z), rotation_speed, delta)


func _update_fall_tracking(on_floor: bool, y: float) -> void:
	var drop: float = _fall.update(on_floor, y)
	if drop <= PlayerFallTracker.NO_LANDING or drop <= fall_damage_height:
		return
	took_fall_damage.emit(drop)
	if drop > killing_fall_height:
		if _game != null:
			_game.kill_player()
		return
	take_damage(fall_damage_for(drop), null)


func fall_damage_for(drop: float) -> float:
	return PlayerFallTracker.damage_for(drop, fall_damage_height, fall_damage_per_metre)


func _on_item_added(_id: StringName, _amount: int) -> void:
	_auto_equip()


func _auto_equip() -> void:
	if _melee == null or _inventory == null:
		return
	var best: StringName = PlayerLoadout.best_weapon(_inventory)
	if best == WeaponTable.UNARMED:
		_melee.unequip()
	else:
		_melee.equip(best)


func _on_respawned() -> void:
	if _game != null:
		global_position = _game.respawn_point
	velocity = Vector3.ZERO
	is_dodging = false
	is_invulnerable = false
	_sprinting = false
	_fall.reset()
	_stamina.reset()
	_health.reset()
	health_changed.emit(_health.fraction())
	if _rig != null:
		_rig.snap_to_target()
