extends Interactable
class_name Chest
## Gives its contents once and stays open. Needs a once_flag to persist; without one, it is derived from id.

const LID_OPEN_DEG := -80.0
const LID_OPEN_SEC := 0.4

## item id -> count, e.g. {"kindling_grey": 1}.
@export var contents: Dictionary = {}

var _lid: Node3D


func _ready() -> void:
	if once_flag == &"" and id != &"":
		once_flag = StringName("opened_" + String(id))
	super()
	_lid = get_node_or_null(^"%Lid") as Node3D
	if is_spent():
		_pose(_lid, &"rotation_degrees", Vector3(LID_OPEN_DEG, 0.0, 0.0), 0.0)


func _on_interact(_who: Node) -> void:
	if _inventory != null:
		for item: Variant in contents:
			_inventory.add(StringName(item), int(contents[item]))
	_pose(_lid, &"rotation_degrees", Vector3(LID_OPEN_DEG, 0.0, 0.0), LID_OPEN_SEC)
