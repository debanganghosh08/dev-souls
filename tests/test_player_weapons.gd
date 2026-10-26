extends "res://tests/test_case.gd"
## In-hand weapon props without a scene or autoloads: which prop each weapon id shows, that only one shows at a
## time, that the torch light is on only while the torch is held, the flicker's bounds, the vertex budget, the
## grip frame, the Melee and inventory wiring, and that a missing Sword node (assets/ absent) empties the hand
## instead of crashing. Nothing here proves how any of it looks.

const PLAYER_SCENE := "res://scenes/player/player.tscn"
const VERTEX_BUDGET := 400
const IDS: Array[StringName] = [&"unarmed", &"torch", &"sword", &"hammer"]


class FakeInventory extends Node:
	signal item_added(id: StringName, amount: int)
	signal item_removed(id: StringName, amount: int)
	var held: Array[StringName] = []

	func has(id: StringName) -> bool:
		return held.has(id)

	func add(id: StringName) -> void:
		held.append(id)
		item_added.emit(id, 1)

	func remove(id: StringName) -> void:
		held.erase(id)
		item_removed.emit(id, 1)


var _nodes: Array[Node] = []
var _weapons: PlayerWeapons
var _inventory: FakeInventory
var _hand: Node3D
var _sword: Node3D


func _fresh(with_sword: bool = true, melee: Node = null) -> void:
	_cleanup()
	_inventory = FakeInventory.new()
	_hand = Node3D.new()
	_sword = null
	if with_sword:
		_sword = Node3D.new()
		_sword.name = "Sword"
		_sword.transform = PlayerWeapons.DEFAULT_GRIP
		_sword.visible = false
		_hand.add_child(_sword)
	_weapons = PlayerWeapons.new()
	_weapons._inject(melee, _inventory, _hand, _sword)
	_nodes.append_array([_weapons, _hand, _inventory])


func _cleanup() -> void:
	for node: Node in _nodes:
		node.free()
	_nodes.clear()


func teardown() -> void:
	_cleanup()


func _visible(prop: Node3D) -> bool:
	return prop != null and prop.visible


func test_each_weapon_id_shows_its_own_prop() -> void:
	_fresh()
	_weapons.show_weapon(&"sword")
	assert_true(_visible(_sword), "sword shows the glb's Sword node")
	assert_false(_visible(_weapons.hammer()) or _visible(_weapons.torch()), "sword hides the built props")
	_weapons.show_weapon(&"hammer")
	assert_true(_visible(_weapons.hammer()), "hammer shows the hammer")
	assert_false(_visible(_sword) or _visible(_weapons.torch()), "hammer hides sword and torch")
	_weapons.show_weapon(&"torch")
	assert_true(_visible(_weapons.torch()), "torch shows the torch")
	assert_false(_visible(_sword) or _visible(_weapons.hammer()), "torch hides sword and hammer")
	_weapons.show_weapon(&"unarmed")
	assert_eq(_weapons.visible_prop_count(), 0, "unarmed shows nothing")
	assert_eq(_weapons.shown(), &"unarmed", "unarmed reports empty hands")


func test_exactly_one_prop_is_visible_at_a_time() -> void:
	_fresh()
	for id: StringName in IDS:
		_weapons.show_weapon(id)
		var expected: int = 0 if id == &"unarmed" else 1
		assert_eq(_weapons.visible_prop_count(), expected, "%s leaves %d prop visible" % [id, expected])
		assert_eq(_weapons.shown(), id, "shown() reports %s" % id)
	_weapons.show_weapon(&"bow")
	assert_eq(_weapons.visible_prop_count(), 0, "an id with no prop empties the hand")
	assert_eq(_weapons.shown(), &"unarmed", "an id with no prop reports unarmed")


func test_torch_light_is_on_only_while_the_torch_is_held() -> void:
	_fresh()
	assert_false(_weapons.torch_light_on(), "light starts off")
	for id: StringName in IDS:
		_weapons.show_weapon(id)
		assert_eq(_weapons.torch_light_on(), id == &"torch", "light on only for the torch (%s)" % id)
	_weapons.show_weapon(&"torch")
	var light: OmniLight3D = _weapons.light()
	assert_not_null(light, "the torch carries an OmniLight3D")
	assert_eq(light.get_parent(), _weapons, "the light hangs under the unscaled Weapons node, not the x93 hand")
	assert_true(light.light_color.r > light.light_color.g and light.light_color.g > light.light_color.b, "the light is warm")
	assert_true(light.omni_range >= 8.0, "range reaches across the 10 x 9 m crypt (%f)" % light.omni_range)
	assert_true(light.light_energy > 0.0, "the light has energy")
	_weapons.show_weapon(&"hammer")
	assert_false(_weapons.torch_light_on(), "switching away from the torch turns the light off")
	assert_false(light.visible, "no stray light stays on")


func test_missing_sword_node_degrades_to_empty_hands() -> void:
	_fresh(false)
	_weapons.show_weapon(&"sword")
	assert_eq(_weapons.visible_prop_count(), 0, "no sword node means nothing shows")
	assert_eq(_weapons.shown(), &"unarmed", "a sword that cannot be shown reports unarmed")
	assert_false(_weapons.torch_light_on(), "light stays off")
	_weapons.show_weapon(&"hammer")
	assert_eq(_weapons.visible_prop_count(), 1, "the built props still work without the sword")
	_weapons.show_weapon(&"torch")
	assert_eq(_weapons.visible_prop_count(), 1, "torch still works without the sword")
	assert_true(_weapons.torch_light_on(), "torch light still works without the sword")
	assert_true(_weapons.hammer().transform.origin.is_equal_approx(PlayerWeapons.DEFAULT_GRIP.origin), "props fall back to the recorded grip")


func test_props_hang_from_the_hand_in_the_sword_grip_frame() -> void:
	_fresh()
	for prop: Node3D in [_weapons.hammer(), _weapons.torch()]:
		assert_eq(prop.get_parent(), _hand, "%s is parented to the hand attachment" % prop.name)
		assert_true(prop.transform.origin.is_equal_approx(_sword.transform.origin), "%s sits at the sword's grip" % prop.name)
		var basis: Basis = prop.transform.basis
		assert_true(basis.orthonormalized().is_equal_approx(_sword.transform.basis.orthonormalized()), "%s faces the way the sword faces" % prop.name)
		assert_true(basis.get_scale().is_equal_approx(Vector3.ONE * PlayerWeapons.HAND_METRE), "%s is shrunk from metres into hand units" % prop.name)
		assert_false(prop.visible, "%s starts hidden" % prop.name)
	var ember: Node3D = _weapons.torch().get_node("Ember")
	assert_true(ember.position.y < 0.0, "the ember sits down the blade axis (-Y), the way the sword points")


func test_props_stay_under_the_vertex_budget() -> void:
	var hammer: Node3D = PlayerWeapons.build_hammer(null, null, null)
	var torch: Node3D = PlayerWeapons.build_torch(null, null, null, null)
	_nodes.append_array([hammer, torch])
	var hammer_verts: int = PlayerWeapons.vertex_count(hammer)
	var torch_verts: int = PlayerWeapons.vertex_count(torch)
	assert_true(hammer_verts > 0 and hammer_verts < VERTEX_BUDGET, "hammer is %d vertices" % hammer_verts)
	assert_true(torch_verts > 0 and torch_verts < VERTEX_BUDGET, "torch is %d vertices" % torch_verts)
	assert_eq(hammer.get_child_count(), 4, "hammer is shaft, head and two bands")
	assert_eq(torch.get_child_count(), 4, "torch is shaft, wrap, char and ember")
	var head: MeshInstance3D = hammer.get_node("Head")
	assert_true(head.mesh is BoxMesh, "the hammer head is a box")
	assert_true((head.mesh as BoxMesh).size.x > (head.mesh as BoxMesh).size.y, "the head is longest across X, the blade-width axis")


func test_resolve_follows_melee_unless_the_weapon_was_dropped() -> void:
	var inventory := FakeInventory.new()
	_nodes.append(inventory)
	inventory.held = [&"sword", &"torch"]
	assert_eq(PlayerWeapons.resolve(&"torch", inventory), &"torch", "a torch chosen over a held sword shows the torch")
	assert_eq(PlayerWeapons.resolve(&"unarmed", inventory), &"sword", "unarmed in Melee falls back to the best weapon held")
	assert_eq(PlayerWeapons.resolve(&"hammer", inventory), &"sword", "a hammer no longer held falls back to the best weapon")
	inventory.held = []
	assert_eq(PlayerWeapons.resolve(&"sword", inventory), &"unarmed", "nothing held is unarmed")
	assert_eq(PlayerWeapons.resolve(&"sword", null), &"sword", "without an inventory Melee's word stands")
	assert_eq(PlayerWeapons.resolve(&"unarmed", null), &"unarmed", "nothing anywhere is unarmed")


func test_inventory_changes_re_evaluate_the_hand() -> void:
	_fresh()
	_weapons.refresh()
	assert_eq(_weapons.shown(), &"unarmed", "empty inventory, empty hand")
	_inventory.add(&"torch")
	assert_eq(_weapons.shown(), &"torch", "picking up a torch shows it")
	assert_true(_weapons.torch_light_on(), "and lights it")
	_inventory.add(&"hammer")
	assert_eq(_weapons.shown(), &"hammer", "a hammer outranks the torch")
	assert_false(_weapons.torch_light_on(), "the torch light went out")
	_inventory.remove(&"hammer")
	assert_eq(_weapons.shown(), &"torch", "dropping the hammer goes back to the torch")
	_inventory.remove(&"torch")
	assert_eq(_weapons.shown(), &"unarmed", "dropping everything empties the hand")
	assert_eq(_weapons.visible_prop_count(), 0, "nothing visible after dropping everything")


func test_melee_equip_drives_the_hand() -> void:
	var melee: Melee = Melee.new()
	_fresh(true, melee)
	_nodes.append(melee)
	_inventory.held = [&"sword", &"torch"]
	melee._inject(null, _inventory, null, null)
	_weapons.refresh()
	assert_eq(_weapons.shown(), &"sword", "with Melee unarmed the best held weapon shows")
	assert_true(melee.equip(&"torch"), "Melee accepts the held torch")
	assert_eq(_weapons.shown(), &"torch", "weapon_changed switched the hand to the torch")
	assert_true(_weapons.torch_light_on(), "the torch is lit")
	assert_true(melee.equip(&"sword"), "Melee accepts the sword")
	assert_eq(_weapons.shown(), &"sword", "weapon_changed switched back to the sword")
	assert_false(_weapons.torch_light_on(), "the light went out with the sword")
	melee.unequip()
	assert_eq(_weapons.shown(), &"sword", "unequip with a sword still held falls back to the best weapon")
	_inventory.held = []
	melee.unequip()
	_weapons.refresh()
	assert_eq(_weapons.shown(), &"unarmed", "nothing held, nothing shown")


func test_flicker_is_bounded_and_restless() -> void:
	var lo: float = INF
	var hi: float = -INF
	var t: float = 0.0
	while t < 10.0:
		var f: float = PlayerWeapons.flicker(t)
		lo = minf(lo, f)
		hi = maxf(hi, f)
		t += 0.01
	assert_true(lo >= -1.0 and hi <= 1.0, "flicker stays in [-1, 1] (%f..%f)" % [lo, hi])
	assert_true(lo < -0.3 and hi > 0.3, "flicker actually moves (%f..%f)" % [lo, hi])
	assert_ne(PlayerWeapons.flicker(0.5), PlayerWeapons.flicker(0.51), "flicker changes frame to frame")


func test_player_scene_wires_the_weapons_node() -> void:
	var player: Node = (load(PLAYER_SCENE) as PackedScene).instantiate()
	_nodes.append(player)
	var weapons: PlayerWeapons = player.get_node_or_null("Weapons") as PlayerWeapons
	assert_not_null(weapons, "player.tscn carries a Weapons node with the PlayerWeapons script")
	if weapons == null:
		return
	for mat: Material in [weapons.wood_material, weapons.iron_material, weapons.iron_dark_material, weapons.wrap_material, weapons.char_material, weapons.ember_material]:
		assert_not_null(mat, "every prop material is assigned in the scene")
	assert_true((weapons.ember_material as StandardMaterial3D).emission_enabled, "the ember glows")
	assert_not_null(player.get_node_or_null(weapons.hand_path.get_concatenated_names().trim_prefix("../")), "the hand path resolves in the player scene")
	assert_not_null(player.get_node_or_null(weapons.sword_path.get_concatenated_names().trim_prefix("../")), "the sword path resolves in the player scene")
	assert_not_null(player.get_node_or_null("Melee"), "the melee path has a Melee to follow")
