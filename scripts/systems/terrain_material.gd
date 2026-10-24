class_name TerrainMaterial
extends RefCounted
## Builds and caches the one ShaderMaterial every terrain chunk shares. One shader instead of four
## materials because the four surfaces (grass, mud, gravel, rock) have to blend INSIDE a triangle by
## slope and height: with separate materials a vertex would have to belong to exactly one surface and
## every transition would be a hard edge along a mesh seam. The shader maps textures in world space, so
## a single material also serves every chunk and LOD without per-chunk UV bookkeeping. Thresholds come
## from data/areas/*.json "material"; albedo is left neutral because the day/night cycle grades colour.

const SHADER_PATH := "res://scripts/systems/terrain.gdshader"
const TEX_ROOT := "res://assets/textures/vale/"
const LAYERS := {
	"grass": "aerial_grass_rock", "mud": "brown_mud_03", "gravel": "brown_mud_rocks_01", "rock": "coast_land_rocks_01",
}
const MAPS := {"albedo": "diff", "normal": "nor_gl", "rough": "rough"}
const FALLBACK := {"albedo": Color(0.45, 0.45, 0.43), "normal": Color(0.5, 0.5, 1.0), "rough": Color(0.9, 0.9, 0.9)}

static var _cached: ShaderMaterial
static var _missing: int = 0


static func get_material(settings: Dictionary, water_level: float) -> ShaderMaterial:
	if _cached != null:
		return _cached
	var shader: Shader = load(SHADER_PATH) as Shader
	var material := ShaderMaterial.new()
	material.shader = shader
	for layer: String in LAYERS:
		for map: String in MAPS:
			material.set_shader_parameter("%s_%s" % [layer, map], _texture(LAYERS[layer], MAPS[map], map))
	var tile: float = maxf(0.01, float(settings.get("uv_metres_per_tile", 2.0)))
	material.set_shader_parameter("uv_scale", 1.0 / tile)
	material.set_shader_parameter("grass_slope_deg", float(settings.get("grass_slope_deg", 20.0)))
	material.set_shader_parameter("gravel_slope_deg", float(settings.get("gravel_slope_deg", 28.0)))
	material.set_shader_parameter("rock_slope_deg", float(settings.get("rock_slope_deg", 36.0)))
	material.set_shader_parameter("mud_height", water_level + float(settings.get("mud_height", 1.5)))
	material.set_shader_parameter("mud_blend", maxf(0.01, float(settings.get("mud_blend", 2.0))))
	material.set_shader_parameter("normal_strength", float(settings.get("normal_strength", 0.8)))
	_cached = material
	return material


static func clear_cache() -> void:
	_cached = null
	_missing = 0


## Number of texture files that were missing and replaced by flat colours in the cached material.
static func missing_textures() -> int:
	return _missing


# Textures carry a resolution suffix (…_2k.jpg); find whichever is imported rather than hard-coding one.
static func _texture(folder: String, suffix: String, map: String) -> Texture2D:
	var dir: String = TEX_ROOT + folder + "/"
	for res: String in ["2k", "1k", "4k"]:
		var path: String = "%s%s_%s_%s.jpg" % [dir, folder, suffix, res]
		if ResourceLoader.exists(path):
			var tex: Texture2D = load(path) as Texture2D
			if tex != null:
				return tex
	_missing += 1
	var image: Image = Image.create(2, 2, false, Image.FORMAT_RGB8)
	image.fill(FALLBACK[map])
	return ImageTexture.create_from_image(image)
