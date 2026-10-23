extends Interactable
class_name Door
## Swings its %Leaf open and lets the player through %Blocker. locked_flag is the flag that must be set
## before it opens; it is forwarded into the base's required_flag so all gating stays in one place.
## Give it a once_flag (or let one derive from id) so it is found open again after a reload.

@export var locked_flag: StringName
@export var open_angle_deg: float = 95.0
@export var open_time: float = 0.8

var _open: bool = false
var _leaf: Node3D
var _blocker: StaticBody3D


func _ready() -> void:
	if required_flag == &"" and locked_flag != &"":
		required_flag = locked_flag
	if once_flag == &"" and id != &"":
		once_flag = StringName("opened_" + String(id))
	super()
	_leaf = get_node_or_null(^"%Leaf") as Node3D
	_blocker = get_node_or_null(^"%Blocker") as StaticBody3D
	if is_spent():
		_swing(0.0)


func is_open() -> bool:
	return _open


func _on_interact(_who: Node) -> void:
	_swing(open_time)


func _swing(seconds: float) -> void:
	_open = true
	_pose(_leaf, &"rotation_degrees", Vector3(0.0, open_angle_deg, 0.0), seconds)
	if _blocker != null:
		_blocker.set_deferred(&"collision_layer", 0)
