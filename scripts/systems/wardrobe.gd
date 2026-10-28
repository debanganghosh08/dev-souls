class_name Wardrobe
extends Node3D
## What the player is wearing (W9-C). The owner asked for the simplest thing that works: "if I just press E
## and pick it up, I will automatically wear it". So this listens to Inventory.item_added, and the moment a
## garment arrives it is on: the last one found wins, which is also what a player expects after walking up
## to a better coat.
##
## The garment hangs off the chest bone when one can be found, so it moves with the body. The character
## model is a downloaded glTF whose bone names are not ours to rely on, so BONES lists the usual spellings
## and the first that exists is used; failing all of them the cloth hangs off this node at `fallback_height`
## and still looks right standing still. Which way the cloth faces and how high it sits are data
## (data/garments.json), so the owner can turn a cloak the right way round without touching code.

const DATA_PATH := "res://data/garments.json"
const WEAR_SLOT := "wear"
## Tried in order. Quaternius, Mixamo and Blender rigs between them use all of these for the upper spine.
const BONES: Array[String] = ["Chest", "Spine2", "Spine_02", "spine_02", "UpperChest", "Spine1", "Spine_01",
		"Spine", "spine", "Torso"]

@export var skeleton_path: NodePath = ^"../Body/Model/RootNode/CharacterArmature/Skeleton3D"
## Where the cloth hangs when no bone matched: metres above this node.
@export var fallback_height: float = 1.25
## Turned off by the tests that build a player without a model.
@export var auto_equip: bool = true

var _definitions: Dictionary = {}
var _worn: StringName = &""
var _node: Node3D = null
var _attach: Node3D = null
var _inventory: Node = null


func _ready() -> void:
	_definitions = load_from()
	_attach = _find_attachment()
	if _inventory == null and is_inside_tree():
		_inventory = get_node_or_null(^"/root/Inventory")
	if _inventory != null:
		if not _inventory.item_added.is_connected(_on_item_added):
			_inventory.item_added.connect(_on_item_added)
		if auto_equip:
			# A loaded save may already be carrying one.
			for id: Variant in _inventory.items():
				if is_garment(StringName(str(id))):
					wear(StringName(str(id)))


## Tests hand in a fake inventory the same way the melee and weapon tests do.
func _inject(inventory: Node) -> void:
	_inventory = inventory


func worn() -> StringName:
	return _worn


func worn_node() -> Node3D:
	return _node


func definitions() -> Dictionary:
	return _definitions


func is_garment(id: StringName) -> bool:
	return _definitions.has(String(id))


## Puts a garment on, replacing whatever was on before. An unknown id takes everything off.
func wear(id: StringName) -> bool:
	if _node != null:
		_node.get_parent().remove_child(_node)
		_node.queue_free()
		_node = null
	_worn = &""
	if not is_garment(id):
		return false
	var entry: Dictionary = _definitions[String(id)]
	_node = GarmentKit.make(entry, "Worn_" + String(id))
	var host: Node3D = _attach if _attach != null else self
	if _attach == null:
		_node.position += Vector3(0.0, fallback_height, 0.0)
	host.add_child(_node)
	_worn = id
	return true


func take_off() -> void:
	wear(&"")


## data/garments.json: id -> {colour, trim, length, spread_deg, radius, flare, lean, collar, lift, back,
## yaw_deg}. Missing fields fall back to GarmentKit's defaults, so a new garment is three lines.
static func load_from(path: String = DATA_PATH) -> Dictionary:
	var out: Dictionary = {}
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("Wardrobe: cannot open %s (%s)" % [path, error_string(FileAccess.get_open_error())])
		return out
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK or not json.data is Dictionary:
		push_error("Wardrobe: bad JSON in %s line %d: %s" % [path, json.get_error_line(), json.get_error_message()])
		return out
	for key: Variant in (json.data as Dictionary).keys():
		var entry: Variant = (json.data as Dictionary)[key]
		if entry is Dictionary:
			out[str(key)] = entry
	return out


## Every item whose definition carries the wear slot, from data/items.json. The two files have to agree:
## tests/test_garments.gd is what holds them together.
static func wearable_ids(definitions: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for id: Variant in definitions:
		var entry: Variant = definitions[id]
		if entry is Dictionary and str((entry as Dictionary).get("slot", "")) == WEAR_SLOT:
			out.append(str(id))
	out.sort()
	return out


func _on_item_added(id: StringName, _amount: int) -> void:
	if auto_equip and is_garment(id):
		wear(id)


## A BoneAttachment3D on the first chest bone the model actually has, or null when the model is not there
## (every test, and any level without the character).
func _find_attachment() -> Node3D:
	var skeleton: Skeleton3D = get_node_or_null(skeleton_path) as Skeleton3D
	if skeleton == null:
		return null
	for bone: String in BONES:
		var index: int = skeleton.find_bone(bone)
		if index < 0:
			continue
		var attach := BoneAttachment3D.new()
		attach.name = "WardrobeAttach"
		attach.bone_name = bone
		attach.bone_idx = index
		skeleton.add_child(attach)
		return attach
	push_warning("Wardrobe: no chest bone in %s; clothes will hang off the player instead" % skeleton.name)
	return null
