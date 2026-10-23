extends Node3D
class_name CameraRig
## Third-person orbit camera. The rig is top_level so it follows the target's position but never its rotation.
## Yaw lives on the rig, pitch on the spring arm; the arm pulls the camera in when world geometry is behind.

@export var mouse_sensitivity: float = 0.0025
@export var pitch_min_deg: float = -70.0
@export var pitch_max_deg: float = 25.0
@export var distance: float = 4.5
@export var height: float = 1.6
@export var follow_lag: float = 12.0
@export var invert_y: bool = false
@export var start_pitch_deg: float = -12.0
@export var target_path: NodePath = ^".."

@onready var _arm: SpringArm3D = %SpringArm
@onready var _camera: Camera3D = %Camera

var _target: Node3D
var _game: Node
var _pitch: float = 0.0
var _shake_strength: float = 0.0
var _shake_duration: float = 0.0
var _shake_time_left: float = 0.0


func _ready() -> void:
	top_level = true
	_target = get_node_or_null(target_path) as Node3D
	_pitch = deg_to_rad(start_pitch_deg)
	_arm.rotation.x = _pitch
	_apply_tuning()
	snap_to_target()
	_game = get_node_or_null(^"/root/Game")
	if _game != null:
		_game.connect(&"state_changed", _on_game_state_changed)
	_update_mouse_mode()


func _unhandled_input(event: InputEvent) -> void:
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	var motion: InputEventMouseMotion = event as InputEventMouseMotion
	if motion == null:
		return
	rotation.y = wrapf(rotation.y - motion.relative.x * mouse_sensitivity, -PI, PI)
	var vertical_sign: float = 1.0 if invert_y else -1.0
	_pitch = clampf(
		_pitch + motion.relative.y * mouse_sensitivity * vertical_sign,
		deg_to_rad(pitch_min_deg),
		deg_to_rad(pitch_max_deg)
	)
	_arm.rotation.x = _pitch


func _process(delta: float) -> void:
	_apply_tuning()
	if _target != null:
		global_position = global_position.lerp(_target.global_position, minf(follow_lag * delta, 1.0))
	_update_shake(delta)


func get_yaw() -> float:
	return rotation.y


func snap_to_target() -> void:
	if _target != null:
		global_position = _target.global_position


func add_shake(strength: float, duration: float) -> void:
	_shake_strength = maxf(_shake_strength, strength)
	_shake_duration = maxf(duration, 0.001)
	_shake_time_left = _shake_duration


# Re-applied every frame so the owner can tune distance/height live in the remote inspector.
func _apply_tuning() -> void:
	_arm.spring_length = distance
	_arm.position.y = height


func _update_shake(delta: float) -> void:
	if _shake_time_left <= 0.0:
		return
	_shake_time_left = maxf(_shake_time_left - delta, 0.0)
	# Camera offsets are untouched by SpringArm3D, so the shake survives the arm's per-tick repositioning.
	var amplitude: float = _shake_strength * (_shake_time_left / _shake_duration)
	_camera.h_offset = randf_range(-amplitude, amplitude)
	_camera.v_offset = randf_range(-amplitude, amplitude)
	if _shake_time_left == 0.0:
		_shake_strength = 0.0
		_camera.h_offset = 0.0
		_camera.v_offset = 0.0


func _on_game_state_changed(_old: int, _new: int) -> void:
	_update_mouse_mode()


func _update_mouse_mode() -> void:
	# Headless runs (tests, CI) have no window to capture the mouse in; touching the mouse mode there
	# is at best pointless, so bail out before any Input.mouse_mode write.
	if DisplayServer.get_name() == "headless" or not DisplayServer.window_can_draw():
		return
	var playing: bool = _game != null and _game.state == _game.State.PLAYING
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if playing else Input.MOUSE_MODE_VISIBLE
