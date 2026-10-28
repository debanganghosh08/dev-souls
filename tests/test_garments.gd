extends "res://tests/test_case.gd"
## Clothes you find and wear (W9-C), and the spear. The owner asked for the simplest possible rule: press E,
## and it is on. So the test that matters is the last one here: an item arriving in the inventory puts the
## garment on the player with nothing else pressed. Seen to fail: docs/reports/W9-C.md quotes the control.

const ITEMS := "res://data/items.json"
const GARMENTS := "res://data/garments.json"
const WEAR := "wear"

var _nodes: Array[Node] = []


func teardown() -> void:
	for node: Node in _nodes:
		node.free()
	_nodes.clear()


func test_every_wearable_item_has_a_cut_and_every_cut_an_item() -> void:
	var items: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ITEMS))
	var garments: Dictionary = Wardrobe.load_from(GARMENTS)
	assert_true(garments.size() >= 3, "there are clothes to find (%d)" % garments.size())
	var wearable: Array[String] = Wardrobe.wearable_ids(items)
	assert_true(wearable.size() >= 3, "at least three items are wearable (%d)" % wearable.size())
	for id: String in wearable:
		assert_true(garments.has(id), "%s is an item with the wear slot, so it needs a cut in garments.json" % id)
		var entry: Dictionary = items[id]
		assert_eq(str(entry.get("kind", "")), "garment", "%s is filed under Clothes in the inventory" % id)
		assert_true(str(entry.get("lore", "")) != "", "%s has a line of lore like every other item" % id)
	for id: Variant in garments:
		assert_true(wearable.has(str(id)), "%s is a cut with no item to pick up" % str(id))


func test_a_garment_builds_cloth_that_hangs_down_and_wraps_the_body() -> void:
	var garments: Dictionary = Wardrobe.load_from(GARMENTS)
	for id: Variant in garments:
		var entry: Dictionary = garments[id]
		var node: Node3D = GarmentKit.make(entry, "test_" + str(id))
		_nodes.append(node)
		var cloth: MeshInstance3D = node.get_node_or_null(^"Cloth") as MeshInstance3D
		assert_not_null(cloth, "%s has cloth" % str(id))
		if cloth == null:
			continue
		var verts: PackedVector3Array = (cloth.mesh as ArrayMesh).surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		assert_true(verts.size() > 40, "%s is a sheet, not a plane (%d vertices)" % [str(id), verts.size()])
		var low: float = INF
		var high: float = -INF
		var widest: float = 0.0
		var behind: int = 0
		for v: Vector3 in verts:
			low = minf(low, v.y)
			high = maxf(high, v.y)
			widest = maxf(widest, absf(v.x))
			if v.z < 0.0:
				behind += 1
		var length: float = float(entry.get("length", 0.0))
		assert_true(absf((high - low) - length) < 0.12, "%s falls about its stated length (%.2f vs %.2f)"
				% [str(id), high - low, length])
		assert_true(high <= 0.001, "%s hangs DOWN from the shoulders, not up over the head" % str(id))
		assert_true(widest > 0.1, "%s wraps round the body (%.2f m across)" % [str(id), widest])
		assert_true(behind > verts.size() / 3, "%s sits behind the player, where a cloak goes" % str(id))
		var material: StandardMaterial3D = cloth.material_override as StandardMaterial3D
		assert_not_null(material, "%s has a material" % str(id))
		if material != null:
			assert_eq(material.cull_mode, BaseMaterial3D.CULL_DISABLED,
					"%s is cloth: the inside of it is visible too" % str(id))


func test_picking_one_up_puts_it_on_with_nothing_else_pressed() -> void:
	var wardrobe := Wardrobe.new()
	_nodes.append(wardrobe)
	var inventory := _FakeInventory.new()
	_nodes.append(inventory)
	wardrobe._inject(inventory)
	wardrobe._ready()
	assert_eq(wardrobe.worn(), &"", "the player starts in what they stand up in")
	inventory.add(&"leather_coat")
	assert_eq(wardrobe.worn(), &"leather_coat", "taking the coat wore the coat, with no second step")
	assert_not_null(wardrobe.worn_node(), "the cloth is on the player")
	# A better one found later replaces it, which is what a player expects.
	inventory.add(&"travellers_cloak")
	assert_eq(wardrobe.worn(), &"travellers_cloak", "the last one found is the one worn")
	assert_eq(wardrobe.get_child_count(), 1, "exactly one garment hangs on the player at a time")
	# The negative control for the whole mechanism: a thing that is not clothing changes nothing.
	inventory.add(&"hammer")
	assert_eq(wardrobe.worn(), &"travellers_cloak", "picking up a hammer does not dress the player in it")
	wardrobe.take_off()
	assert_eq(wardrobe.worn(), &"", "and it can come off again")
	assert_eq(wardrobe.get_child_count(), 0, "nothing is left hanging")


func test_the_spear_is_a_real_weapon_with_the_longest_reach_and_a_prop_to_hold() -> void:
	var table: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/weapons.json"))
	assert_true(table.has("spear"), "the spear is in the weapon table")
	var spear: Dictionary = table.get("spear", {})
	for key: String in ["name", "damage_multiplier", "stamina_multiplier", "reach_bonus"]:
		assert_true(spear.has(key), "the spear has '%s' like every other weapon" % key)
	assert_true(float(spear.get("reach_bonus", -1.0)) > float((table.get("sword", {}) as Dictionary).get("reach_bonus", 0.0)),
			"a spear outreaches a sword, which is the only reason to carry one")
	assert_true(float(spear.get("damage_multiplier", 0.0)) < float((table.get("hammer", {}) as Dictionary).get("damage_multiplier", 9.0)),
			"and hits for less than a hammer")
	var prop: Node3D = PlayerWeapons.build_spear(null, null, null)
	_nodes.append(prop)
	assert_true(prop.get_child_count() >= 5, "the spear is built from a shaft, a blade and its fittings")
	assert_true(PlayerWeapons.vertex_count(prop) < 400, "it stays inside the prop budget (%d vertices)"
			% PlayerWeapons.vertex_count(prop))
	var lowest: float = INF
	var highest: float = -INF
	for child: Node in prop.get_children():
		var mi: MeshInstance3D = child as MeshInstance3D
		if mi == null:
			continue
		lowest = minf(lowest, mi.position.y)
		highest = maxf(highest, mi.position.y)
	assert_true(highest - lowest > 1.0, "it is a long weapon, held near the middle (%.2f m between fittings)"
			% (highest - lowest))
	# PlayerLoadout has to know it, or picking one up would leave the player bare-handed.
	assert_true(PlayerLoadout.PRIORITY.has(&"spear"), "auto-equip knows the spear exists")


## The inventory's add/has/items and item_added, which is all Wardrobe touches.
class _FakeInventory:
	extends Node
	signal item_added(id: StringName, amount: int)
	signal item_removed(id: StringName, amount: int)

	var counts: Dictionary = {}

	func add(id: StringName, amount: int = 1) -> void:
		counts[id] = int(counts.get(id, 0)) + amount
		item_added.emit(id, amount)

	func has(id: StringName) -> bool:
		return counts.has(id)

	func items() -> Dictionary:
		return counts.duplicate()
