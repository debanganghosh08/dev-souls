extends Area3D
class_name InteractionDetector
## Lives on the player. Keeps the set of Interactables inside a sphere of max_range (via area signals, so no
## per-frame allocation), picks the single best one each frame, and fires the `interact` action at it.
## focus_changed drives the on-screen prompt; interaction_refused relays the target's refusal text.

signal focus_changed(target: Interactable)
signal interaction_refused(reason: String)

const INTERACTABLE_LAYER := 4 # 3d_physics/layer_3 "interactable"
const CENTRE_WEIGHT := 0.8

@export var max_range: float = 3.2
@export var max_angle_deg: float = 75.0
@export var camera_path: NodePath

var _camera: Camera3D
var _game: Node
var _state_playing: int = -1
var _candidates: Array[Interactable] = []
var _target: Interactable


func _ready() -> void:
	collision_layer = 0
	collision_mask = INTERACTABLE_LAYER
	monitoring = true
	monitorable = false
	var shape := SphereShape3D.new()
	shape.radius = max_range
	var collider := CollisionShape3D.new()
	collider.shape = shape
	add_child(collider)
	_camera = get_node_or_null(camera_path) as Camera3D
	_game = get_node_or_null(^"/root/Game")
	if _game != null:
		_state_playing = _game.State.PLAYING
	area_entered.connect(_on_area_entered)
	area_exited.connect(_on_area_exited)


func _process(_delta: float) -> void:
	var best: Interactable = _pick() if _is_playing() else null
	if best == _target:
		return
	if is_instance_valid(_target):
		_target.set_focused(false)
	_target = best
	if _target != null:
		_target.set_focused(true)
	focus_changed.emit(_target)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"interact") and _target != null and _is_playing():
		get_viewport().set_input_as_handled()
		try_interact()


func current_target() -> Interactable:
	return _target


func try_interact() -> bool:
	if _target == null or not is_instance_valid(_target):
		return false
	var who: Node = get_parent()
	if not _target.interact(who):
		interaction_refused.emit(_target.refusal_reason())
		return false
	return true


## Pure ranking so tests can check it. Returns -1 for anything out of reach or out of view. Otherwise a value
## in [0, 1]: centring (1 at dead centre, 0 at the edge of view) weighted CENTRE_WEIGHT, nearness (1 touching,
## 0 at max_range) weighted the rest. Centring dominates; distance only separates similar angles, so a thing
## a hair less centred but a stride closer still wins, which is what feels right at a cluttered altar.
static func score(angle_deg: float, distance: float, max_angle: float, reach: float) -> float:
	if reach <= 0.0 or max_angle <= 0.0 or distance > reach or angle_deg > max_angle or angle_deg < 0.0:
		return -1.0
	var centring: float = 1.0 - angle_deg / max_angle
	var nearness: float = 1.0 - distance / reach
	return centring * CENTRE_WEIGHT + nearness * (1.0 - CENTRE_WEIGHT)


func _pick() -> Interactable:
	var best: Interactable = null
	var best_score: float = -1.0
	var origin: Vector3 = global_position
	var eye: Vector3 = _camera.global_position if _camera != null else origin
	var forward: Vector3 = -_camera.global_basis.z if _camera != null else -global_basis.z
	for candidate: Interactable in _candidates:
		if not is_instance_valid(candidate) or candidate.prompt_text() == "":
			continue
		var to_eye: Vector3 = candidate.global_position - eye
		var angle_deg: float = rad_to_deg(forward.angle_to(to_eye)) if to_eye.length_squared() > 0.0001 else 0.0
		var s: float = score(angle_deg, origin.distance_to(candidate.global_position), max_angle_deg, max_range)
		if s > best_score:
			best_score = s
			best = candidate
	return best


func _is_playing() -> bool:
	return _game != null and _game.state == _state_playing


func _on_area_entered(area: Area3D) -> void:
	var it: Interactable = area as Interactable
	if it != null and not _candidates.has(it):
		_candidates.append(it)


func _on_area_exited(area: Area3D) -> void:
	_candidates.erase(area)
