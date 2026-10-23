extends RefCounted
class_name WeaponTable
## Weapon multipliers from data/weapons.json. A missing or malformed file reports an error and yields the
## built-in DEFAULTS, so the game never crashes over tuning data. Pure and static: no nodes, unit-testable.

const PATH := "res://data/weapons.json"
const UNARMED := &"unarmed"
const DEFAULTS := {
	&"unarmed": {"name": "Bare hands", "damage_multiplier": 0.3, "stamina_multiplier": 0.8, "reach_bonus": -0.7},
	&"torch": {"name": "Torch", "damage_multiplier": 0.55, "stamina_multiplier": 0.9, "reach_bonus": -0.2},
	&"sword": {"name": "Sword", "damage_multiplier": 1.0, "stamina_multiplier": 1.0, "reach_bonus": 0.0},
	&"hammer": {"name": "Hammer", "damage_multiplier": 1.6, "stamina_multiplier": 1.5, "reach_bonus": 0.2},
}


# Entries in the file overlay the defaults field by field, so a partial entry keeps sane values.
static func load_from(path: String = PATH, report_errors: bool = true) -> Dictionary:
	var out: Dictionary = DEFAULTS.duplicate(true)
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		if report_errors:
			push_error("WeaponTable: cannot open %s (%s); using built-in weapon defaults" % [path, error_string(FileAccess.get_open_error())])
		return out
	var json: JSON = JSON.new()
	if json.parse(file.get_as_text()) != OK or not (json.data is Dictionary):
		if report_errors:
			push_error("WeaponTable: bad JSON in %s line %d: %s; using built-in weapon defaults" % [path, json.get_error_line(), json.get_error_message()])
		return out
	for key: Variant in (json.data as Dictionary).keys():
		var entry: Variant = json.data[key]
		if not (entry is Dictionary):
			continue
		var id: StringName = StringName(str(key))
		var merged: Dictionary = out.get(id, DEFAULTS[UNARMED]).duplicate()
		for field: Variant in entry.keys():
			merged[str(field)] = entry[field]
		out[id] = merged
	return out
