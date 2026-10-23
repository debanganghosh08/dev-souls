extends Interactable
class_name Lever
## Toggles sets_flag on and off (toggles_flag is forced on). Never spent unless given a once_flag.

const HANDLE_ON_DEG := 60.0
const HANDLE_SEC := 0.3

var _on: bool = false
var _handle: Node3D


func _init() -> void:
	toggles_flag = true


func _ready() -> void:
	super()
	_handle = get_node_or_null(^"%Handle") as Node3D
	_on = sets_flag != &"" and _has_flag(sets_flag)
	_pose(_handle, &"rotation_degrees", Vector3(HANDLE_ON_DEG if _on else 0.0, 0.0, 0.0), 0.0)


func is_on() -> bool:
	return _on


func _on_interact(_who: Node) -> void:
	_on = not _on
	_pose(_handle, &"rotation_degrees", Vector3(HANDLE_ON_DEG if _on else 0.0, 0.0, 0.0), HANDLE_SEC)
