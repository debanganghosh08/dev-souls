extends Area3D
class_name Interactable
## Base of every interactive thing (chests, pickups, inscriptions, levers, doors, later NPCs). Owns all the
## gating and bookkeeping: spent/required flag/required item, item consumption, flag setting, autosave.
## Subclasses override only _on_interact (what happens) and optionally set_focused (how it shimmers).
## It is detected by InteractionDetector; it never detects anything itself (layer interactable, mask 0).

signal interacted(who: Node)
signal refused(reason: String)

const INTERACTABLE_LAYER := 4 # 3d_physics/layer_3 "interactable" (bit 3 = value 4)
const GLOW_NEAR := 0.35
const GLOW_FOCUSED := 1.2
const GLOW_PULSE_HZ := 1.1

@export var id: StringName
@export var prompt: String = "Examine"
@export var once_flag: StringName
@export var required_item: StringName
@export var consumes_item: bool = false
@export var required_flag: StringName
@export var sets_flag: StringName
## When true, a successful use clears sets_flag if it is already set instead of setting it (levers, valves).
@export var toggles_flag: bool = false
@export var refusal_text: String = "It does not yield."
## %s is replaced with the missing item's in-world name from data/items.json.
@export var need_item_text: String = "You need the %s."
@export var glow_range: float = 6.0

var _flags: Node
var _inventory: Node
var _save: Node
var _game: Node
var _glow: MeshInstance3D
var _glow_material: StandardMaterial3D
var _focused: bool = false


func _ready() -> void:
	# Area3D defaults to layer 1 (world); an interactable must sit on its own layer or the detector is blind to it.
	if collision_layer & INTERACTABLE_LAYER == 0:
		collision_layer = INTERACTABLE_LAYER
	collision_mask = 0
	if _flags == null and _inventory == null and _save == null:
		_inject(get_node_or_null(^"/root/Flags"), get_node_or_null(^"/root/Inventory"), get_node_or_null(^"/root/SaveGame"))
	_game = get_node_or_null(^"/root/Game")
	_setup_glow()


# Autoloads are looked up by path and injectable, not referenced by their globals: the test runner executes
# before any autoload exists, so tests hand in instances of the real scripts (same idiom as SaveGame._inject).
func _inject(flags: Node, inventory: Node, save: Node) -> void:
	_flags = flags
	_inventory = inventory
	_save = save


func is_spent() -> bool:
	return once_flag != &"" and _has_flag(once_flag)


func can_interact() -> bool:
	if is_spent():
		return false
	if required_flag != &"" and not _has_flag(required_flag):
		return false
	if required_item != &"" and not _has_item(required_item):
		return false
	return true


func refusal_reason() -> String:
	if is_spent() or (required_flag != &"" and not _has_flag(required_flag)):
		return refusal_text
	if required_item != &"" and not _has_item(required_item):
		var item_name: String = _item_name(required_item)
		if item_name != "":
			return need_item_text % item_name
	return refusal_text


func prompt_text() -> String:
	return "" if is_spent() else prompt


func interact(who: Node) -> bool:
	if not can_interact():
		refused.emit(refusal_reason())
		return false
	if consumes_item and required_item != &"" and _inventory != null:
		_inventory.remove(required_item, 1)
	_on_interact(who)
	if _flags != null:
		if sets_flag != &"":
			if toggles_flag and _flags.has(sets_flag):
				_flags.clear_flag(sets_flag)
			else:
				_flags.set_flag(sets_flag)
		if once_flag != &"":
			_flags.set_flag(once_flag)
	interacted.emit(who)
	if _save != null:
		_save.request_autosave()
	return true


## Override: what happens on a successful use. Never touch flags or items here; the base does that.
func _on_interact(_who: Node) -> void:
	pass


## Override for a custom cue. Default: brighten an optional %Glow mesh's emission while focused.
func set_focused(value: bool) -> void:
	_focused = value
	if _glow_material != null and not _focused:
		_glow_material.emission_energy_multiplier = 0.0


func _physics_process(_delta: float) -> void:
	if _glow_material == null:
		return
	var near: bool = _game != null and _game.player_position.distance_squared_to(global_position) <= glow_range * glow_range
	if not near and not _focused:
		_glow_material.emission_energy_multiplier = 0.0
		return
	var pulse: float = 0.75 + 0.25 * sin(Time.get_ticks_msec() * 0.001 * TAU * GLOW_PULSE_HZ)
	_glow_material.emission_energy_multiplier = (GLOW_FOCUSED if _focused else GLOW_NEAR) * pulse


func _has_flag(flag: StringName) -> bool:
	return _flags != null and _flags.has(flag)


func _has_item(item: StringName) -> bool:
	return _inventory != null and _inventory.has(item)


func _item_name(item: StringName) -> String:
	if _inventory == null:
		return ""
	return str(_inventory.definition(item).get("name", ""))


func _setup_glow() -> void:
	_glow = get_node_or_null(^"%Glow") as MeshInstance3D
	if _glow == null or glow_range <= 0.0:
		set_physics_process(false)
		return
	# Duplicated so two instances of one prop scene never share (and both light) the same material.
	var source: Material = _glow.material_override if _glow.material_override != null else _glow.get_active_material(0)
	_glow_material = source.duplicate() as StandardMaterial3D if source != null else null
	if _glow_material == null:
		set_physics_process(false)
		return
	_glow_material.emission_enabled = true
	_glow_material.emission_energy_multiplier = 0.0
	_glow.material_override = _glow_material


# Tween helper for subclasses: animates in a live tree, snaps when there is none (tests, spent-on-load).
func _pose(node: Node3D, property: StringName, target: Variant, seconds: float) -> void:
	if node == null:
		return
	if not is_inside_tree() or seconds <= 0.0:
		node.set(property, target)
		return
	create_tween().tween_property(node, NodePath(property), target, seconds).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
