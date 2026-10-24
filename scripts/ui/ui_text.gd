extends RefCounted
class_name UiText
## Every player-facing UI string comes from data/ui_text.json. The English table below is only the fallback
## so a missing or broken file never leaves a blank button.

const PATH := "res://data/ui_text.json"
const DEFAULTS: Dictionary = {
	"title": "DEV SOULS",
	"subtitle": "Hollowmere lies cold",
	"continue": "Continue",
	"new_journey": "New Journey",
	"settings": "Settings",
	"quit": "Quit",
	"confirm_unmake": "This will unmake your journey.",
	"begin_anew": "Begin anew",
	"keep": "Keep",
	"loading": "Awakening…",
	"you_faded": "YOU FADED",
	"resume": "Resume",
	"save_and_quit": "Save and Quit to Title",
	"prompt_format": "[%s]  %s",
	"acquired": "Acquired — %s",
	"acquired_amount": "%s ×%d",
	"lore_dismiss": "[%s]  close",
	"settings_title": "Settings",
	"master_volume": "Master volume",
	"music_volume": "Music volume",
	"sfx_volume": "Effects volume",
	"mouse_sensitivity": "Mouse sensitivity",
	"invert_y": "Invert vertical look",
	"fullscreen": "Fullscreen",
	"vsync": "Vertical sync",
	"fps_cap": "Frame cap",
	"fps_unlimited": "Unlimited",
	"reset_defaults": "Reset to defaults",
	"back": "Back",
	"unarmed": "Unarmed",
	"inventory_title": "Carried",
	"inventory_progress": "%d of %d found",
	"kindling_progress": "Kindling  %d of %d",
	"unknown_item": "???",
	"not_yet_found": "Not yet found.",
	"row_count": "%s  ×%d",
	"count_line": "Carried  ×%d",
	"kind_kindling": "Kindling",
	"kind_fragment": "Name Fragments",
	"kind_key": "Keys",
	"kind_tool": "Tools",
	"kind_lore": "Writings",
	"equip": "Equip",
	"equipped": "Equipped",
	"inventory_hint": "[%s]  close    [%s]  equip",
	"item_card_hint": "[%s]  continue",
}

static var _table: Dictionary = {}
static var _loaded: bool = false


static func text(key: String) -> String:
	if not _loaded:
		_table = _load(PATH)
		_loaded = true
	if _table.has(key) and _table[key] is String:
		return _table[key]
	if DEFAULTS.has(key):
		return DEFAULTS[key]
	push_warning("UiText: no string for '%s'" % key)
	return key


## Tests use this to point at a throwaway file; the game never calls it.
static func reload_from(path: String = PATH) -> void:
	_table = _load(path)
	_loaded = true


static func _load(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_error("UiText: %s missing, using built-in English" % path)
		return {}
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(path)) != OK or not json.data is Dictionary:
		push_error("UiText: %s is not a valid JSON object, using built-in English" % path)
		return {}
	return json.data
