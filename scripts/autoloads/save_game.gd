extends Node
## Single-slot JSON save. Flags/Inventory/Game are injectable (_inject) so tests run without autoloads.

const SAVE_VERSION := 1
const SAVE_PATH := "user://save_slot_0.json"
const TMP_PATH := "user://save_slot_0.tmp"
const AUTOSAVE_INTERVAL_SEC := 5.0

signal saved()
signal loaded()

var _flags: Node
var _inventory: Node
var _game: Node
var _autosave_pending: bool = false
var _autosave_timer: float = 0.0


func _ready() -> void:
	if _flags == null:
		_inject(get_node_or_null("/root/Flags"), get_node_or_null("/root/Inventory"), get_node_or_null("/root/Game"))


func _inject(flags: Node, inventory: Node, game: Node) -> void:
	_flags = flags
	_inventory = inventory
	_game = game


func _process(delta: float) -> void:
	if _autosave_timer > 0.0:
		_autosave_timer -= delta
	if _autosave_pending and _autosave_timer <= 0.0:
		_autosave_pending = false
		save()


func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)


func save() -> bool:
	var text: String = JSON.stringify(_collect(), "\t")
	var file: FileAccess = FileAccess.open(TMP_PATH, FileAccess.WRITE)
	if file == null:
		push_error("SaveGame: cannot open %s (%s)" % [TMP_PATH, error_string(FileAccess.get_open_error())])
		return false
	file.store_string(text)
	file.close()
	var err: Error = DirAccess.rename_absolute(
		ProjectSettings.globalize_path(TMP_PATH), ProjectSettings.globalize_path(SAVE_PATH))
	if err != OK:
		push_error("SaveGame: rename failed (%s)" % error_string(err))
		return false
	_autosave_timer = AUTOSAVE_INTERVAL_SEC
	saved.emit()
	return true


func load_slot() -> bool:
	if not has_save():
		return false
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(SAVE_PATH)) != OK or not _is_valid(json.data):
		push_warning("SaveGame: %s is corrupt or unreadable" % SAVE_PATH)
		return false
	if int(json.data["version"]) > SAVE_VERSION:
		push_warning("SaveGame: save version %d is newer than %d" % [int(json.data["version"]), SAVE_VERSION])
		return false
	_apply(json.data)
	loaded.emit()
	return true


func delete() -> void:
	if has_save():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))


func request_autosave() -> void:
	_autosave_pending = true


func _collect() -> Dictionary:
	return {
		"version": SAVE_VERSION,
		"flags": _flags.all_flags().map(func(id: StringName) -> String: return String(id)),
		"inventory": _inventory.to_dict(),
		"respawn_area": String(_game.respawn_area),
		"respawn_point": _vec_to_dict(_game.respawn_point),
		"player_position": _vec_to_dict(_game.player_position),
		"time_of_day": _game.time_of_day,
		"playtime_seconds": _game.playtime_seconds,
	}


func _apply(data: Dictionary) -> void:
	_flags.restore(data["flags"])
	_inventory.restore(data["inventory"])
	_game.respawn_area = StringName(data["respawn_area"])
	_game.respawn_point = _dict_to_vec(data["respawn_point"])
	_game.player_position = _dict_to_vec(data["player_position"])
	_game.time_of_day = float(data["time_of_day"])
	_game.playtime_seconds = float(data["playtime_seconds"])


func _is_valid(data: Variant) -> bool:
	if not data is Dictionary:
		return false
	var expected: Dictionary = {
		"version": TYPE_FLOAT, "flags": TYPE_ARRAY, "inventory": TYPE_DICTIONARY,
		"respawn_area": TYPE_STRING, "respawn_point": TYPE_DICTIONARY,
		"player_position": TYPE_DICTIONARY, "time_of_day": TYPE_FLOAT, "playtime_seconds": TYPE_FLOAT,
	}
	for key: String in expected:
		if not data.has(key) or typeof(data[key]) != expected[key]:
			return false
	for key: String in ["respawn_point", "player_position"]:
		for axis: String in ["x", "y", "z"]:
			if typeof(data[key].get(axis)) != TYPE_FLOAT:
				return false
	return true


func _vec_to_dict(v: Vector3) -> Dictionary:
	return {"x": v.x, "y": v.y, "z": v.z}


func _dict_to_vec(d: Dictionary) -> Vector3:
	return Vector3(float(d["x"]), float(d["y"]), float(d["z"]))
