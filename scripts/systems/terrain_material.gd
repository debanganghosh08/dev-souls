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
## Matches the array in terrain.gdshader.
const MAX_ROAD_SEGMENTS := 8
## W21-E defaults, baked here so an area file that says nothing about them still gets unbroken tiles and a
## mottled field. Scales are metres. Keys of the same name in the area's "material" block override them.
## tile_break_metres: size of one rotation region of the planar textures. A few tiles, not one (every tile
## would flip and the blend zone would cover everything) and not thirty (the stripes return inside a region).
const TILE_BREAK_METRES := 9.0
## macro_metres: the slow brightness mottle; the shader adds a second octave at 0.27x of it.
const MACRO_METRES := 61.0
## macro_variation: +- fraction of albedo the mottle may move. Clamped to [0, MACRO_VARIATION_MAX].
const MACRO_VARIATION := 0.12
const MACRO_VARIATION_MAX := 0.5
## tint_metres: size of a dry or lush patch of grass.
const TINT_METRES := 31.0
## grass_tint_dry / grass_tint_lush: multipliers swung between by the tint noise, both near luminance 1 so
## they move hue (warm and yellow against cool and green), not brightness, which is the macro's job.
const GRASS_TINT_DRY := Vector3(1.08, 0.99, 0.84)
const GRASS_TINT_LUSH := Vector3(0.92, 1.02, 1.06)

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
	material.set_shader_parameter("grass_tint", _colour(settings.get("grass_tint", null)))
	_set_variation(material, settings)
	_set_road(material, settings)
	_cached = material
	return material


## W21-E anti-tiling and colour variation. Every value has a baked default (the constants above), so the
## area file needs no new key; a zero or negative tile_break_metres is allowed and turns the breaking off.
static func _set_variation(material: ShaderMaterial, settings: Dictionary) -> void:
	material.set_shader_parameter("tile_break_metres", maxf(0.0, float(settings.get("tile_break_metres", TILE_BREAK_METRES))))
	material.set_shader_parameter("macro_metres", maxf(1.0, float(settings.get("macro_metres", MACRO_METRES))))
	material.set_shader_parameter("macro_variation", clampf(float(settings.get("macro_variation", MACRO_VARIATION)), 0.0, MACRO_VARIATION_MAX))
	material.set_shader_parameter("tint_metres", maxf(1.0, float(settings.get("tint_metres", TINT_METRES))))
	material.set_shader_parameter("grass_tint_dry", _colour(settings.get("grass_tint_dry", null), GRASS_TINT_DRY))
	material.set_shader_parameter("grass_tint_lush", _colour(settings.get("grass_tint_lush", null), GRASS_TINT_LUSH))


## The worn track, from the same valley polyline the grass zones and the placement rules already use, so
## there is one road in the world and not two that drift apart. `road` in the area file's material block
## gives its half width and feather; MAX_ROAD_SEGMENTS is the shader array's size.
static func _set_road(material: ShaderMaterial, settings: Dictionary) -> void:
	var road: Dictionary = settings.get("road", {}) if settings.get("road", {}) is Dictionary else {}
	var points: Array = road.get("waypoints", [])
	var segments: Array[Plane] = []
	for i: int in range(points.size() - 1):
		if segments.size() >= MAX_ROAD_SEGMENTS:
			break
		var a: Array = points[i]
		var b: Array = points[i + 1]
		if a.size() < 2 or b.size() < 2:
			continue
		segments.append(Plane(float(a[0]), float(a[1]), float(b[0]), float(b[1])))
	while segments.size() < MAX_ROAD_SEGMENTS:
		segments.append(Plane(0.0, 0.0, 0.0, 0.0))
	material.set_shader_parameter("road_segments", segments)
	material.set_shader_parameter("road_count", mini(maxi(points.size() - 1, 0), MAX_ROAD_SEGMENTS))
	material.set_shader_parameter("road_half", maxf(0.0, float(road.get("half_width", 2.5))))
	material.set_shader_parameter("road_feather", maxf(0.01, float(road.get("feather", 4.0))))


## [r, g, b] from the area file, `fallback` (white unless said otherwise) when absent, so an area that says
## nothing looks as it always did.
static func _colour(value: Variant, fallback: Vector3 = Vector3.ONE) -> Vector3:
	if value is Array and (value as Array).size() >= 3:
		var a: Array = value
		return Vector3(float(a[0]), float(a[1]), float(a[2]))
	return fallback


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
