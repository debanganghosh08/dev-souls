extends RefCounted
class_name PlayerLoadout
## Which held weapon the player fights with. Best weapon held wins: sword > hammer > torch. Nothing held
## leaves the hands empty (Melee's unarmed entry), so there is never a stale weapon after a drop.

const PRIORITY: Array[StringName] = [&"sword", &"hammer", &"torch"]


static func best_weapon(inventory: Node) -> StringName:
	if inventory == null:
		return WeaponTable.UNARMED
	for id: StringName in PRIORITY:
		if inventory.has(id):
			return id
	return WeaponTable.UNARMED
