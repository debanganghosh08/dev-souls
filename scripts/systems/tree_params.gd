class_name TreeParams
extends RefCounted
## Loads data/trees.json for TreeGen and merges every archetype over BASE so the generator never has to
## guess a missing key. A missing or malformed file logs an error and yields the built-in DEFAULTS.

const DATA_PATH := "res://data/trees.json"

## Every key TreeGen reads, with a safe value. Archetypes only override what differs.
const BASE: Dictionary = {
	"height": [12.0, 16.0], "base_radius": [0.3, 0.4], "tip_ratio": 0.08, "taper_power": 0.8,
	"segments": 8, "rings": 10, "lean_deg": 3.0, "bend": 0.04, "gnarl": 0.0,
	"whorls": 8, "branches_per_whorl": 6, "crown_start": 0.3, "card_length": 2.0, "tip_scale": 0.4,
	"pitch_deg": -15.0, "pitch_jitter_deg": 8.0, "roll_jitter_deg": 50.0, "yaw_jitter_deg": 12.0,
	"length_jitter": 0.2, "card_tint": [0.55, 0.6, 0.5],
	"bark": "bark_brown_01", "bark_tile_m": 1.0, "bark_uv_around": 2,
	"twig": "twig_fir", "twig_file": "fir_tree_01_twig", "atlas_size": [1024, 1024], "atlas_grid": [1, 1],
	"atlas_cells": [],
	"lod1_whorl_scale": 0.5, "lod1_branch_scale": 0.6, "lod1_card_scale": 1.35,
}

## Fallback archetypes when the JSON is unusable. Deliberately minimal: the real tuning lives in data/.
const DEFAULTS: Dictionary = {
	"fir": {"height": [14.0, 20.0], "whorls": 12, "branches_per_whorl": 7, "crown_start": 0.2},
	"pine": {"height": [18.0, 26.0], "whorls": 6, "crown_start": 0.55, "bark": "pine_bark",
		"twig": "twig_pine", "twig_file": "pine_tree_01_twig"},
	"dead": {"height": [9.0, 14.0], "whorls": 0, "branches_per_whorl": 0, "gnarl": 0.18, "bend": 0.12},
	"ancient": {"height": [9.0, 12.0], "base_radius": [1.3, 1.7], "tip_ratio": 0.25, "gnarl": 0.22,
		"whorls": 7, "branches_per_whorl": 10, "card_length": 4.5, "bark": "bark_brown_02"},
}

static var _cache: Dictionary = {}
static var _cache_path: String = ""


static func archetypes() -> PackedStringArray:
	var out := PackedStringArray()
	for key: String in _data().keys():
		out.append(key)
	return out


## Full parameter dictionary for one archetype (a copy; callers may edit it). Unknown names get BASE.
static func params_for(archetype: String) -> Dictionary:
	var data: Dictionary = _data()
	if not data.has(archetype):
		push_warning("TreeParams: unknown archetype '%s'; using BASE" % archetype)
		return BASE.duplicate(true)
	return (data[archetype] as Dictionary).duplicate(true)


## Forget the parsed file so the next call re-reads it (tests).
static func reset() -> void:
	_cache = {}
	_cache_path = ""


## Parse one file into {archetype: full params}. Never throws: any failure logs and returns the defaults.
static func load_file(path: String) -> Dictionary:
	var raw: Dictionary = _read_json(path)
	if raw.is_empty():
		raw = DEFAULTS
	var out: Dictionary = {}
	for key: Variant in raw.keys():
		var entry: Variant = raw[key]
		if entry is Dictionary and not str(key).begins_with("_"):
			out[str(key)] = merge_over_base(entry)
	if out.is_empty():
		push_error("TreeParams: %s holds no archetypes; using built-in defaults" % path)
		for key: String in DEFAULTS.keys():
			out[key] = merge_over_base(DEFAULTS[key])
	return out


static func merge_over_base(overrides: Dictionary) -> Dictionary:
	var out: Dictionary = BASE.duplicate(true)
	for key: Variant in overrides.keys():
		out[str(key)] = overrides[key]
	return out


static func _data() -> Dictionary:
	if _cache.is_empty() or _cache_path != DATA_PATH:
		_cache = load_file(DATA_PATH)
		_cache_path = DATA_PATH
	return _cache


static func _read_json(path: String) -> Dictionary:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("TreeParams: cannot open %s (%s); using built-in defaults" % [path, error_string(FileAccess.get_open_error())])
		return {}
	var json: JSON = JSON.new()
	var err: Error = json.parse(file.get_as_text())
	if err != OK or not (json.data is Dictionary):
		push_error("TreeParams: bad JSON in %s line %d: %s" % [path, json.get_error_line(), json.get_error_message()])
		return {}
	return json.data as Dictionary
