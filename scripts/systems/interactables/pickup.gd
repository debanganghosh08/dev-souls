extends Interactable
class_name Pickup
## A thing lying on the ground. Taken once, then gone; needs a once_flag to stay gone across reloads
## (derived from id when not given).

@export var item: StringName
@export var amount: int = 1


func _ready() -> void:
	if once_flag == &"" and id != &"":
		once_flag = StringName("picked_" + String(id))
	super()
	if is_spent():
		_vanish()


func _on_interact(_who: Node) -> void:
	if _inventory != null and item != &"":
		_inventory.add(item, amount)
	_vanish()


func _vanish() -> void:
	visible = false
	set_deferred(&"monitorable", false)
