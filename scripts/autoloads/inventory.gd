extends Node
## Item counts by id. Definitions come from data/items.json. References no other autoload.

signal item_added(id: StringName, amount: int)
signal item_removed(id: StringName, amount: int)

const ITEMS_PATH := "res://data/items.json"

var _counts: Dictionary = {}
var _definitions: Dictionary = {}


func _ready() -> void:
	_load_definitions()


func add(id: StringName, amount: int = 1) -> void:
	if not _definitions.has(id):
		push_warning("Inventory: unknown item id '%s' ignored" % id)
		return
	amount = maxi(amount, 1)
	_counts[id] = count(id) + amount
	item_added.emit(id, amount)


func remove(id: StringName, amount: int = 1) -> bool:
	amount = maxi(amount, 1)
	var held: int = count(id)
	if held < amount:
		return false
	if held == amount:
		_counts.erase(id)
	else:
		_counts[id] = held - amount
	item_removed.emit(id, amount)
	return true


func count(id: StringName) -> int:
	return int(_counts.get(id, 0))


func has(id: StringName) -> bool:
	return count(id) > 0


func items() -> Dictionary:
	return _counts.duplicate()


func definition(id: StringName) -> Dictionary:
	return _definitions.get(id, {})


func all_definitions() -> Dictionary:
	return _definitions


func to_dict() -> Dictionary:
	var out: Dictionary = {}
	for id: StringName in _counts:
		out[String(id)] = _counts[id]
	return out


func restore(data: Dictionary) -> void:
	_counts.clear()
	for key: Variant in data:
		var n: int = int(data[key])
		if n > 0:
			_counts[StringName(key)] = n


func _load_definitions() -> void:
	_definitions = {}
	if not FileAccess.file_exists(ITEMS_PATH):
		push_error("Inventory: %s missing" % ITEMS_PATH)
		return
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(ITEMS_PATH)) != OK or not json.data is Dictionary:
		push_error("Inventory: %s is not a valid JSON object" % ITEMS_PATH)
		return
	for key: Variant in json.data:
		if json.data[key] is Dictionary:
			_definitions[StringName(key)] = json.data[key]
