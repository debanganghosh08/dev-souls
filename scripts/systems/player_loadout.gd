extends RefCounted
class_name PlayerLoadout
## Which held weapon the player fights with. Best weapon held wins: sword > hammer > torch. Nothing held
## leaves the hands empty (Melee's unarmed entry), so there is never a stale weapon after a drop.

## Best first. The spear outranges the sword but swings slowest, so it sits under it: auto-equip should
## hand the player the quickest thing that hits hard, and the spear is a choice, not a default.
const PRIORITY: Array[StringName] = [&"sword", &"spear", &"hammer", &"torch"]


static func best_weapon(inventory: Node) -> StringName:
	if inventory == null:
		return WeaponTable.UNARMED
	for id: StringName in PRIORITY:
		if inventory.has(id):
			return id
	return WeaponTable.UNARMED
