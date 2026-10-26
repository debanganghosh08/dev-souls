extends Node3D
class_name PlayerWeapons
## What the player's hand shows: the Wick's own Sword mesh, a procedural hammer or a procedural torch (with its
## light), one at a time, or nothing when unarmed. Visual only: damage, stamina and reach stay in WeaponTable
## and Melee. Follows Melee.equipped() (what actually hits) and re-checks on every inventory change.

const UNARMED := WeaponTable.UNARMED
const SWORD := &"sword"
const HAMMER := &"hammer"
const TORCH := &"torch"

# The Wick's armature carries the x100 scale of its centimetre export, so one unit in the hand attachment's
# local space is 100 model-metres. Props are authored in metres and shrunk by this on the way in.
const HAND_METRE := 0.01
# The Sword node's transform inside Middle1_R, read headlessly from the glb: grip centre at the origin, blade
# down local -Y, pommel +Y, blade width across X. Every prop is built in that frame so it sits where the sword
# sits, and this copy covers the case where the Sword node is gone.
const DEFAULT_GRIP := Transform3D(
	Vector3(-0.013944, -0.999902, -0.000923), Vector3(0.999902, -0.013945, 0.00091), Vector3(-0.000923, -0.00091, 0.999999),
	Vector3(-0.000004, 0.000911, -0.000251),
)
const EMBER_NAME := &"Ember"

@export var hand_path: NodePath = ^"../Body/Model/RootNode/CharacterArmature/Skeleton3D/Middle1_R"
@export var sword_path: NodePath = ^"../Body/Model/RootNode/CharacterArmature/Skeleton3D/Middle1_R/Sword"
@export var melee_path: NodePath = ^"../Melee"
@export_group("Materials")
@export var wood_material: Material
@export var iron_material: Material
@export var iron_dark_material: Material
@export var wrap_material: Material
@export var char_material: Material
@export var ember_material: Material
@export_group("Torch light")
## The castle crypt is an enclosed, unlit 10 x 9 m stone room; this range has to make it readable, not glow.
@export var torch_light_range: float = 9.0
@export var torch_light_energy: float = 2.2
@export var torch_light_colour: Color = Color(1.0, 0.72, 0.42)
@export_range(0.0, 0.5) var flicker_amount: float = 0.12

var _melee: Node
var _inventory: Node
var _hand: Node3D
var _sword: Node3D
var _hammer: Node3D
var _torch: Node3D
var _ember: Node3D
var _light: OmniLight3D
var _shown: StringName = UNARMED
var _time: float = 0.0


func _ready() -> void:
	if _hand == null:
		var hand: Node3D = get_node_or_null(hand_path) as Node3D
		var sword: Node3D = get_node_or_null(sword_path) as Node3D
		# assets/ is git-ignored (D-005): without the glb neither node exists and the game must still run.
		if hand == null:
			push_warning("PlayerWeapons: hand node %s not found; props are parented to %s" % [hand_path, name])
		if sword == null:
			push_warning("PlayerWeapons: sword node %s not found; the sword will not show" % sword_path)
		_inject(get_node_or_null(melee_path), get_node_or_null(^"/root/Inventory"), hand, sword)
	refresh()


# Same idiom as Melee._inject: tests hand in fakes (or null) before any autoload exists.
func _inject(melee: Node, inventory: Node, hand: Node3D, sword: Node3D) -> void:
	_melee = melee
	_inventory = inventory
	_hand = hand if hand != null else self
	_sword = sword
	if _hammer == null:
		_build_props()
	if _melee != null and _melee.has_signal(&"weapon_changed") and not _melee.is_connected(&"weapon_changed", _on_weapon_changed):
		_melee.connect(&"weapon_changed", _on_weapon_changed)
	if _inventory != null:
		for sig: StringName in [&"item_added", &"item_removed"]:
			if _inventory.has_signal(sig) and not _inventory.is_connected(sig, _on_inventory_changed):
				_inventory.connect(sig, _on_inventory_changed)
	set_process(false)


# The light lives here, under the unscaled player, not under the x93 hand: Light3D range and shadows are not
# meant to inherit a scale like that. It is moved onto the ember every frame the torch is out.
func _process(delta: float) -> void:
	_time += delta
	var f: float = flicker(_time)
	_light.light_energy = torch_light_energy * (1.0 + flicker_amount * f)
	_light.omni_range = torch_light_range * (1.0 + 0.5 * flicker_amount * f)
	if _ember.is_inside_tree() and _light.is_inside_tree():
		_light.global_position = _ember.global_position


func refresh() -> void:
	var equipped: StringName = _melee.equipped() if _melee != null and _melee.has_method(&"equipped") else UNARMED
	show_weapon(resolve(equipped, _inventory))


# Exactly one prop, or none. An id with no prop (unarmed, unknown, or sword with the node missing) empties the hand.
func show_weapon(id: StringName) -> void:
	var prop: Node3D = _prop_for(id)
	for candidate: Node3D in [_sword, _hammer, _torch]:
		if candidate != null:
			candidate.visible = candidate == prop
	_shown = id if prop != null else UNARMED
	var torch_out: bool = _shown == TORCH
	_light.visible = torch_out
	set_process(torch_out)
	if torch_out:
		_light.light_energy = torch_light_energy
		_light.omni_range = torch_light_range


func shown() -> StringName:
	return _shown


func visible_prop_count() -> int:
	var count: int = 0
	for candidate: Node3D in [_sword, _hammer, _torch]:
		if candidate != null and candidate.visible:
			count += 1
	return count


func torch_light_on() -> bool:
	return _light.visible


func hammer() -> Node3D:
	return _hammer


func torch() -> Node3D:
	return _torch


func light() -> OmniLight3D:
	return _light


# What the hand should show: the weapon Melee actually hits with, as long as it is still held (the controller
# only re-equips on pickups, so a dropped weapon is stale in Melee), else the best weapon held.
static func resolve(equipped: StringName, inventory: Node) -> StringName:
	if equipped != UNARMED and (inventory == null or inventory.has(equipped)):
		return equipped
	return PlayerLoadout.best_weapon(inventory)


# Three sines at unrelated rates read as a guttering flame; in [-1, 1], never settles, costs nothing.
static func flicker(t: float) -> float:
	return 0.5 * sin(t * 13.0) + 0.3 * sin(t * 29.0 + 1.7) + 0.2 * sin(t * 53.0 + 0.4)


## One-handed war hammer, ~0.62 m: wooden shaft with two iron bands, iron head whose faces strike along X,
## the sword's blade-width axis, so a slash lands it face first. Four primitives, ~140 vertices.
static func build_hammer(wood: Material, iron: Material, iron_dark: Material) -> Node3D:
	var root := Node3D.new()
	root.name = "Hammer"
	_cylinder(root, "Shaft", 0.016, 0.02, 0.62, -0.19, wood)
	_box(root, "Head", Vector3(0.24, 0.11, 0.1), -0.46, iron)
	_cylinder(root, "BandTop", 0.023, 0.023, 0.03, -0.37, iron_dark)
	_cylinder(root, "BandButt", 0.023, 0.023, 0.03, 0.1, iron_dark)
	return root


## Torch, ~0.55 m: wooden shaft, a wrapped head, a charred rim and an ember core. The Ember child marks where
## the light sits. Four primitives, ~150 vertices.
static func build_torch(wood: Material, wrap: Material, char_mat: Material, ember: Material) -> Node3D:
	var root := Node3D.new()
	root.name = "Torch"
	_cylinder(root, "Shaft", 0.017, 0.02, 0.5, -0.13, wood)
	_cylinder(root, "Wrap", 0.045, 0.04, 0.16, -0.4, wrap)
	_cylinder(root, "Char", 0.035, 0.045, 0.05, -0.505, char_mat)
	_cylinder(root, EMBER_NAME, 0.028, 0.034, 0.04, -0.545, ember)
	return root


static func vertex_count(node: Node) -> int:
	var total: int = 0
	if node is MeshInstance3D:
		var mesh: Mesh = (node as MeshInstance3D).mesh
		if mesh != null and mesh.get_surface_count() > 0:
			total += (mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	for child: Node in node.get_children():
		total += vertex_count(child)
	return total


func _build_props() -> void:
	_hammer = build_hammer(wood_material, iron_material, iron_dark_material)
	_torch = build_torch(wood_material, wrap_material, char_material, ember_material)
	_ember = _torch.get_node(NodePath(EMBER_NAME))
	var grip: Transform3D = _sword.transform if _sword != null else DEFAULT_GRIP
	for prop: Node3D in [_hammer, _torch]:
		prop.transform = grip.scaled_local(Vector3.ONE * HAND_METRE)
		prop.visible = false
		_hand.add_child(prop)
	_light = OmniLight3D.new()
	_light.name = "TorchLight"
	_light.light_color = torch_light_colour
	_light.light_energy = torch_light_energy
	_light.omni_range = torch_light_range
	_light.visible = false
	add_child(_light)


func _prop_for(id: StringName) -> Node3D:
	match id:
		SWORD:
			return _sword
		HAMMER:
			return _hammer
		TORCH:
			return _torch
	return null


# Eight sides is enough for a stick seen at arm's length and keeps every prop far under the 400-vertex budget.
static func _cylinder(parent: Node3D, name: String, r_top: float, r_bottom: float, height: float, y: float, mat: Material) -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = r_top
	mesh.bottom_radius = r_bottom
	mesh.height = height
	mesh.radial_segments = 8
	mesh.rings = 0
	mesh.material = mat
	_instance(parent, name, mesh, y)


static func _box(parent: Node3D, name: String, size: Vector3, y: float, mat: Material) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = mat
	_instance(parent, name, mesh, y)


static func _instance(parent: Node3D, name: String, mesh: Mesh, y: float) -> void:
	var instance := MeshInstance3D.new()
	instance.name = name
	instance.mesh = mesh
	instance.position = Vector3(0.0, y, 0.0)
	parent.add_child(instance)


func _on_weapon_changed(_id: StringName) -> void:
	refresh()


func _on_inventory_changed(_id: StringName, _amount: int) -> void:
	refresh()
