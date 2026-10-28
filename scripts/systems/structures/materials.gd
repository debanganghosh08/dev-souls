class_name StructureMaterials
extends RefCounted
## One StandardMaterial3D per surface type, cached for the whole run so every wall, slab and roof in both
## structures shares the same handful of materials (same idea as TreeMaterials). Textures live in the
## git-ignored assets/ tree (D-005); when a map is missing the material falls back to a flat colour so
## headless runs and a fresh checkout still build. File names carry the 2k suffix: verified by listing
## assets/textures/shared/<folder>/ (castle_wall_slates_diff_2k.jpg etc.), never guessed.
##
## How each texture is scaled and shaded is tuning, not code: data/structures/materials.json gives every
## kind its metres_per_tile (how many metres of wall one copy of the image covers), normal_scale,
## roughness and ao_light_affect, merged over DEFAULTS field by field the way WeaponTable does it. The
## kit asks metres_per_tile() when it builds a piece, so a 2 m image stops repeating every metre.

const TEX_ROOT := "res://assets/textures/shared/"
const SUFFIX := "_2k.jpg"
const PATH := "res://data/structures/materials.json"

## Surface type -> Poly Haven texture folder. Anything not listed here is a flat untextured material.
const FOLDERS: Dictionary = {
	"castle_wall": "castle_wall_slates",
	"blocks": "medieval_blocks_03",
	"stone": "stone_wall_04",
	"roof": "roof_slates_02",
	"planks": "weathered_planks",
	"plaster": "rough_plaster_broken",
}

const FALLBACKS: Dictionary = {
	"castle_wall": Color(0.42, 0.40, 0.37),
	"blocks": Color(0.55, 0.50, 0.44),
	"stone": Color(0.48, 0.47, 0.45),
	"roof": Color(0.26, 0.27, 0.30),
	"planks": Color(0.40, 0.32, 0.24),
	"plaster": Color(0.72, 0.68, 0.60),
	"bronze": Color(0.36, 0.28, 0.16),
	"timber": Color(0.30, 0.22, 0.15),
	# The lit kit (W9-F). No texture exists for any of them, so they are honest flat colours: dark iron for
	# braziers and brackets, charcoal for burnt wood, dull rag, dry bone, and `ember` which is the only
	# material in the kit that gives off light of its own (see _build).
	"iron": Color(0.17, 0.16, 0.16),
	"char": Color(0.09, 0.085, 0.08),
	"cloth": Color(0.40, 0.36, 0.31),
	"bone": Color(0.78, 0.75, 0.67),
	"ember": Color(0.95, 0.33, 0.09),
	# The kitchen gardens (W9-G): turned earth and what is coming up in it.
	"soil": Color(0.23, 0.18, 0.13),
	"sprout": Color(0.30, 0.42, 0.18),
}

## What a kind gets when neither DEFAULTS nor the file names it: the pre-W6-02 behaviour (one tile per
## metre, the old hard-coded normal and AO strengths).
const BASE: Dictionary = {"metres_per_tile": 1.0, "normal_scale": 0.8, "roughness": 1.0, "ao_light_affect": 0.3}

## Built-in tuning, used when the file is missing or broken. The metres_per_tile values are an estimate of
## how much masonry each Poly Haven image depicts, not a measurement (UNVERIFIED: nobody has checked them
## against the textures yet) -- the owner tunes the real numbers in the JSON, not here.
const DEFAULTS: Dictionary = {
	"castle_wall": {"metres_per_tile": 2.0, "normal_scale": 1.0, "roughness": 1.0, "ao_light_affect": 0.3},
	"blocks": {"metres_per_tile": 1.5, "normal_scale": 1.0, "roughness": 1.0, "ao_light_affect": 0.3},
	"stone": {"metres_per_tile": 1.5, "normal_scale": 1.0, "roughness": 1.0, "ao_light_affect": 0.3},
	"roof": {"metres_per_tile": 1.0, "normal_scale": 0.8, "roughness": 1.0, "ao_light_affect": 0.3},
	"planks": {"metres_per_tile": 1.0, "normal_scale": 0.8, "roughness": 1.0, "ao_light_affect": 0.3},
	"plaster": {"metres_per_tile": 2.5, "normal_scale": 0.6, "roughness": 1.0, "ao_light_affect": 0.3},
}

static var _cache: Dictionary = {}
static var _tuning: Dictionary = {}


static func get_material(kind: String) -> StandardMaterial3D:
	if not _cache.has(kind):
		_cache[kind] = _build(kind)
	return _cache[kind]


static func kinds() -> Array:
	return FALLBACKS.keys()


## Drops the built materials and the loaded tuning, so the next request re-reads the file.
static func clear_cache() -> void:
	_cache = {}
	_tuning = {}


## The merged tuning for one kind; the file is read on first use.
static func tuning(kind: String) -> Dictionary:
	if _tuning.is_empty():
		_tuning = load_from()
	return _tuning.get(kind, BASE)


## Never zero or negative: a bad value would put the whole mesh's UVs at infinity, so it falls back to 1.
static func metres_per_tile(kind: String) -> float:
	var v: float = float(tuning(kind).get("metres_per_tile", 1.0))
	return v if v > 0.001 else 1.0


## Entries in the file overlay DEFAULTS field by field, so a partial entry keeps sane values. Only numbers
## are taken: a string or list where a number belongs is reported and skipped rather than crashing a build.
static func load_from(path: String = PATH, report_errors: bool = true) -> Dictionary:
	var out: Dictionary = DEFAULTS.duplicate(true)
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		if report_errors:
			push_error("StructureMaterials: cannot open %s (%s); using built-in material defaults" % [path, error_string(FileAccess.get_open_error())])
		return out
	var json: JSON = JSON.new()
	if json.parse(file.get_as_text()) != OK or not (json.data is Dictionary):
		if report_errors:
			push_error("StructureMaterials: bad JSON in %s line %d: %s; using built-in material defaults" % [path, json.get_error_line(), json.get_error_message()])
		return out
	for key: Variant in (json.data as Dictionary).keys():
		var entry: Variant = json.data[key]
		if not (entry is Dictionary):
			continue
		var kind: String = str(key)
		var merged: Dictionary = out.get(kind, BASE).duplicate()
		for field: Variant in entry.keys():
			var v: Variant = entry[field]
			if v is float or v is int:
				merged[str(field)] = float(v)
			elif report_errors:
				push_error("StructureMaterials: %s.%s in %s is not a number; keeping %s" % [kind, field, path, str(merged.get(str(field), "default"))])
		out[kind] = merged
	return out


static func _build(kind: String) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	var t: Dictionary = tuning(kind)
	m.albedo_color = FALLBACKS.get(kind, Color(0.5, 0.5, 0.5))
	m.roughness = float(t.get("roughness", 1.0))
	m.metallic = 0.0
	m.metallic_specular = 0.2
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	if kind == "bronze":
		m.metallic = 0.85
		m.roughness = 0.45
		m.metallic_specular = 0.6
		return m
	if kind == "iron":
		m.metallic = 0.7
		m.roughness = 0.55
		m.metallic_specular = 0.4
		return m
	# Coals in a brazier, in a hearth, in a lantern cage. Emission over the glow threshold in
	# scenes/environment/sky.tscn (1.2) so the bed of a fire blooms a little at night; it gives off no real
	# light, which is FireLight's job, so a coal bed costs nothing but its own pixels.
	if kind == "ember":
		m.emission_enabled = true
		m.emission = Color(1.0, 0.42, 0.1)
		m.emission_energy_multiplier = 2.6
		m.roughness = 0.85
		return m
	if not FOLDERS.has(kind):
		return m
	var folder: String = str(FOLDERS[kind])
	var base: String = TEX_ROOT + folder + "/" + folder
	var diff: Texture2D = _tex(base + "_diff" + SUFFIX)
	if diff != null:
		m.albedo_texture = diff
		m.albedo_color = Color.WHITE
	var nor: Texture2D = _tex(base + "_nor_gl" + SUFFIX)
	if nor != null:
		m.normal_enabled = true
		m.normal_texture = nor
		m.normal_scale = float(t.get("normal_scale", 0.8))
	var rough: Texture2D = _tex(base + "_rough" + SUFFIX)
	if rough != null:
		m.roughness_texture = rough
	var ao: Texture2D = _tex(base + "_ao" + SUFFIX)
	if ao != null:
		m.ao_enabled = true
		m.ao_texture = ao
		m.ao_light_affect = float(t.get("ao_light_affect", 0.3))
	return m


static func _tex(path: String) -> Texture2D:
	if not ResourceLoader.exists(path):
		return null
	return load(path) as Texture2D
