class_name StructureMaterials
extends RefCounted
## One StandardMaterial3D per surface type, cached for the whole run so every wall, slab and roof in both
## structures shares the same handful of materials (same idea as TreeMaterials). Textures live in the
## git-ignored assets/ tree (D-005); when a map is missing the material falls back to a flat colour so
## headless runs and a fresh checkout still build. File names carry the 2k suffix: verified by listing
## assets/textures/shared/<folder>/ (castle_wall_slates_diff_2k.jpg etc.), never guessed.

const TEX_ROOT := "res://assets/textures/shared/"
const SUFFIX := "_2k.jpg"

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
}

static var _cache: Dictionary = {}


static func get_material(kind: String) -> StandardMaterial3D:
	if not _cache.has(kind):
		_cache[kind] = _build(kind)
	return _cache[kind]


static func kinds() -> Array:
	return FALLBACKS.keys()


static func clear_cache() -> void:
	_cache = {}


static func _build(kind: String) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = FALLBACKS.get(kind, Color(0.5, 0.5, 0.5))
	m.roughness = 1.0
	m.metallic = 0.0
	m.metallic_specular = 0.2
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	if kind == "bronze":
		m.metallic = 0.85
		m.roughness = 0.45
		m.metallic_specular = 0.6
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
		m.normal_scale = 0.8
	var rough: Texture2D = _tex(base + "_rough" + SUFFIX)
	if rough != null:
		m.roughness_texture = rough
	var ao: Texture2D = _tex(base + "_ao" + SUFFIX)
	if ao != null:
		m.ao_enabled = true
		m.ao_texture = ao
		m.ao_light_affect = 0.3
	return m


static func _tex(path: String) -> Texture2D:
	if not ResourceLoader.exists(path):
		return null
	return load(path) as Texture2D
