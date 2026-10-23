extends Interactable
class_name LoreStone
## An inscription. Re-readable; emits the text from data/lore.json and draws nothing (a UI system listens).

signal reading_requested(title: String, body: String)

const LORE_PATH := "res://data/lore.json"
const MISSING_KEY := "_missing"

@export var lore_key: String

static var _lore: Dictionary = {}
static var _lore_loaded: bool = false


func _on_interact(_who: Node) -> void:
	var entry: Dictionary = lore_entry(lore_key)
	reading_requested.emit(str(entry.get("title", "")), str(entry.get("body", "")))


static func lore_entry(key: String) -> Dictionary:
	if not _lore_loaded:
		_lore = _load_lore()
		_lore_loaded = true
	if _lore.has(key) and _lore[key] is Dictionary:
		return _lore[key]
	push_warning("LoreStone: no lore entry '%s'" % key)
	return _lore.get(MISSING_KEY, {})


static func _load_lore() -> Dictionary:
	if not FileAccess.file_exists(LORE_PATH):
		push_error("LoreStone: %s missing" % LORE_PATH)
		return {}
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(LORE_PATH)) != OK or not json.data is Dictionary:
		push_error("LoreStone: %s is not a valid JSON object" % LORE_PATH)
		return {}
	return json.data
