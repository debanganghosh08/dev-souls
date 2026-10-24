class_name TreeMaterials
extends RefCounted
## One bark material and one twig-card material per archetype, cached for the whole run so hundreds of
## trees share two materials each (the difference between a forest that batches and one that does not).
## Textures live under the git-ignored assets/ tree (D-005); when a map is missing (fresh checkout, no
## fetch yet) the material falls back to flat colours instead of failing, so tests and headless runs work.

const TEX_ROOT := "res://assets/textures/shared/"
const CARD_SHADER := "res://scripts/systems/twig_card.gdshader"
const ALPHA_SCISSOR := 0.5
const BARK_FALLBACK := Color(0.33, 0.27, 0.22)
const CARD_FALLBACK := Color(0.16, 0.22, 0.14)

static var _bark: Dictionary = {}
static var _cards: Dictionary = {}


static func bark_for(archetype: String) -> Material:
	if not _bark.has(archetype):
		_bark[archetype] = _build_bark(TreeParams.params_for(archetype))
	return _bark[archetype]


static func cards_for(archetype: String) -> Material:
	if not _cards.has(archetype):
		_cards[archetype] = _build_cards(TreeParams.params_for(archetype))
	return _cards[archetype]


static func clear_cache() -> void:
	_bark = {}
	_cards = {}


static func _build_bark(p: Dictionary) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	var folder: String = str(p["bark"])
	var base: String = TEX_ROOT + folder + "/" + folder
	m.albedo_color = BARK_FALLBACK
	var diff: Texture2D = _tex(base + "_diff_1k.jpg")
	if diff != null:
		m.albedo_texture = diff
		m.albedo_color = Color.WHITE
	var nor: Texture2D = _tex(base + "_nor_gl_1k.jpg")
	if nor != null:
		m.normal_enabled = true
		m.normal_texture = nor
	var rough: Texture2D = _tex(base + "_rough_1k.jpg")
	m.roughness = 1.0
	if rough != null:
		m.roughness_texture = rough
	var ao: Texture2D = _tex(base + "_ao_1k.jpg")
	if ao != null:
		m.ao_enabled = true
		m.ao_texture = ao
		m.ao_light_affect = 0.3
	m.metallic = 0.0
	m.metallic_specular = 0.15
	# TreeGen trunk UVs wrap once around and run 1 tile per bark_tile_m up the trunk; tiling bark_uv_around
	# times around keeps the grain roughly square on thick trunks instead of stretching one tile over 2 m.
	m.uv1_scale = Vector3(float(p["bark_uv_around"]), 1.0, 1.0)
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return m


static func _build_cards(p: Dictionary) -> Material:
	var folder: String = str(p["twig"])
	var base: String = TEX_ROOT + folder + "/" + str(p["twig_file"])
	var shader: Shader = _tex_any(CARD_SHADER) as Shader
	var tint: Color = _tint(p["card_tint"])
	if shader == null:
		push_error("TreeMaterials: missing %s; cards fall back to an opaque StandardMaterial3D" % CARD_SHADER)
		var fallback := StandardMaterial3D.new()
		fallback.albedo_color = CARD_FALLBACK
		fallback.cull_mode = BaseMaterial3D.CULL_DISABLED
		fallback.diffuse_mode = BaseMaterial3D.DIFFUSE_LAMBERT
		fallback.metallic_specular = 0.05
		return fallback
	var m := ShaderMaterial.new()
	m.shader = shader
	var diff: Texture2D = _tex(base + "_diff_1k.jpg")
	var alpha: Texture2D = _tex(base + "_alpha_1k.png")
	if diff != null:
		m.set_shader_parameter("albedo_tex", diff)
	else:
		tint = CARD_FALLBACK
	if alpha != null:
		m.set_shader_parameter("alpha_tex", alpha)
	m.set_shader_parameter("tint", Vector3(tint.r, tint.g, tint.b))
	m.set_shader_parameter("scissor", ALPHA_SCISSOR)
	return m


static func _tint(v: Variant) -> Color:
	if v is Array and (v as Array).size() >= 3:
		return Color(float(v[0]), float(v[1]), float(v[2]))
	return Color.WHITE


static func _tex(path: String) -> Texture2D:
	return _tex_any(path) as Texture2D


static func _tex_any(path: String) -> Resource:
	if not ResourceLoader.exists(path):
		return null
	return load(path)
