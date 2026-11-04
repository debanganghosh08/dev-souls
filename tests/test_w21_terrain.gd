extends "res://tests/test_case.gd"
## W21-E: the owner's footage showed the ground as repeating stripes and one flat green. The fix is in
## terrain.gdshader (rotated-copy tile breaking, macro brightness mottle, dry/lush grass tint) with every
## knob defaulted in TerrainMaterial so data/areas/vale.json needs no new key. These tests pin what a
## headless run can see: the shader declares and uses the new uniforms, the material sets each with its
## default when the data omits it, the defaults sit in sane ranges and are large against the tile so the
## noise cannot collapse back onto the tile grid, data overrides and clamps work, and the slope, height,
## road and normal-strength paths are still there. Each comment says which deliberately broken input the
## assertion catches. Nothing here proves the picture is right: only the owner's eyes can.

const SHADER := "res://scripts/systems/terrain.gdshader"
const VALE_DATA := "res://data/areas/vale.json"
const WATER := -5.0
const FLOATS: Array[String] = ["tile_break_metres", "macro_metres", "macro_variation", "tint_metres"]
const COLOURS: Array[String] = ["grass_tint_dry", "grass_tint_lush"]
## Fetch budget for the whole shader source: 9 in planar_layer (6 broken + 3 plain), 9 triplanar rock.
const MAX_TEXTURE_CALLS := 20


func setup() -> void:
	TerrainMaterial.clear_cache()


func teardown() -> void:
	TerrainMaterial.clear_cache()


func _material(settings: Dictionary) -> ShaderMaterial:
	TerrainMaterial.clear_cache()
	return TerrainMaterial.get_material(settings, WATER)


func _code() -> String:
	return FileAccess.get_file_as_string(SHADER)


func _float(mat: ShaderMaterial, name: String) -> float:
	return float(mat.get_shader_parameter(name))


func _vec(mat: ShaderMaterial, name: String) -> Vector3:
	var v: Variant = mat.get_shader_parameter(name)
	if v is Vector3:
		return v as Vector3
	return Vector3(-1.0, -1.0, -1.0)


func _luminance(c: Vector3) -> float:
	return 0.2126 * c.x + 0.7152 * c.y + 0.0722 * c.z


func _vale_material() -> Dictionary:
	var json := JSON.new()
	json.parse(FileAccess.get_file_as_string(VALE_DATA))
	return (json.data as Dictionary).get("material", {})


func test_shader_declares_and_uses_every_new_uniform() -> void:
	var code: String = _code()
	for name: String in FLOATS:
		assert_true(code.contains("uniform float %s" % name), "the shader declares uniform float %s (rename it: caught)" % name)
		assert_true(code.count(name) >= 2, "%s is read, not only declared (a dead uniform does nothing: caught)" % name)
	for name: String in COLOURS:
		assert_true(code.contains("uniform vec3 %s" % name), "the shader declares uniform vec3 %s (rename it: caught)" % name)
		assert_true(code.count(name) >= 2, "%s is read, not only declared: caught" % name)
	# Metres become frequency by division of the world position, never by multiplying uv_scale in: a noise
	# built from `uv` or `* uv_scale` would be locked to the tile period it is meant to hide.
	for name: String in ["tile_break_metres", "macro_metres", "tint_metres"]:
		assert_true(code.contains("/ %s" % name) or code.contains("/ max(0.01, %s)" % name), "%s divides the world position (a noise on `uv` is tied to the tile: caught)" % name)
	assert_false(code.contains("uv / tile_break_metres") or code.contains("uv / macro_metres") or code.contains("uv / tint_metres"),
		"no noise is built from the tiled uv")


func test_shader_breaks_tiles_with_rotated_copies_and_keeps_the_fetch_budget() -> void:
	var code: String = _code()
	assert_true(code.contains("void planar_layer(sampler2D"), "planar layers go through one shared sampling function (inline single samples: caught)")
	assert_true(code.count("planar_layer(") >= 4, "grass, mud and gravel all call planar_layer (one layer left on the bare tile: caught)")
	assert_true(code.contains("cos(angle)") and code.contains("sin(angle)"), "copies are ROTATED, not only offset (offset alone keeps every stripe pointing the same way: caught)")
	assert_true(code.contains("unrotate("), "the normal read at a rotated uv is turned back into the world frame (skip it and bumps light from the wrong side: caught)")
	assert_false(code.contains("texture(grass_albedo, uv)"), "no ungated single tile sample of the grass remains (the old `texture(grass_albedo, uv)`: caught)")
	assert_true(code.contains("grass_tint * mix(grass_tint_dry, grass_tint_lush"), "the grass tint is swung between dry and lush by noise (a constant tint: caught)")
	assert_true(code.contains("ALBEDO = albedo * macro"), "the macro mottle multiplies the final albedo (drop it and the field is flat again: caught)")
	assert_true(code.count("texture(") <= MAX_TEXTURE_CALLS, "fetch budget: at most %d texture() calls in the source (a third copy per map: caught), found %d" % [MAX_TEXTURE_CALLS, code.count("texture(")])
	assert_true(code.contains("if (w_mud > 0.001)") and code.contains("if (w_gravel_road > 0.001)"), "mud and gravel are only fetched where they weigh something (unconditional fetches: caught)")


func test_material_sets_every_default_when_the_data_omits_it() -> void:
	var mat: ShaderMaterial = _material({})
	assert_not_null(mat.shader, "the terrain shader loaded")
	for name: String in FLOATS + COLOURS:
		assert_not_null(mat.get_shader_parameter(name), "%s is set on the material (delete its set_shader_parameter line: caught)" % name)
	assert_eq(_float(mat, "tile_break_metres"), TerrainMaterial.TILE_BREAK_METRES, "tile_break_metres defaults to the constant")
	assert_eq(_float(mat, "macro_metres"), TerrainMaterial.MACRO_METRES, "macro_metres defaults to the constant")
	assert_eq(_float(mat, "macro_variation"), TerrainMaterial.MACRO_VARIATION, "macro_variation defaults to the constant")
	assert_eq(_float(mat, "tint_metres"), TerrainMaterial.TINT_METRES, "tint_metres defaults to the constant")
	assert_eq(_vec(mat, "grass_tint_dry"), TerrainMaterial.GRASS_TINT_DRY, "grass_tint_dry defaults to the constant (a white fallback would mean no dry patches: caught)")
	assert_eq(_vec(mat, "grass_tint_lush"), TerrainMaterial.GRASS_TINT_LUSH, "grass_tint_lush defaults to the constant")
	assert_eq(_vec(mat, "grass_tint"), Vector3.ONE, "grass_tint itself still falls back to white, as before W21-E (the new fallback leaking into it: caught)")


func test_defaults_sit_in_sane_ranges_and_are_large_against_the_tile() -> void:
	var tile: float = float(_vale_material().get("uv_metres_per_tile", 2.0))
	var mat: ShaderMaterial = _material({})
	assert_true(is_equal_approx(1.0 / _float(mat, "uv_scale"), 2.0), "uv_scale still means one tile per 2 m when the data says nothing")
	var tb: float = TerrainMaterial.TILE_BREAK_METRES
	assert_true(tb >= 3.0 * tile, "a rotation region spans at least three tiles (%.1f m against a %.1f m tile; one tile per region: caught)" % [tb, tile])
	assert_true(tb <= 16.0 * tile, "a rotation region spans at most sixteen tiles (thirty tiles per region shows the stripes again: caught)")
	assert_true(TerrainMaterial.MACRO_METRES >= 16.0 * tile, "the macro mottle is at least sixteen tiles wide (%.1f m; a 4 m mottle is just more texture noise: caught)" % TerrainMaterial.MACRO_METRES)
	assert_true(TerrainMaterial.MACRO_METRES <= 200.0, "the macro mottle is under 200 m, so a 1024 m area holds many (one blob per map: caught)")
	assert_true(TerrainMaterial.TINT_METRES >= 8.0 * tile and TerrainMaterial.TINT_METRES <= 120.0, "dry/lush patches are 16 to 120 m (%.1f m)" % TerrainMaterial.TINT_METRES)
	for scale: float in [tb, TerrainMaterial.MACRO_METRES, TerrainMaterial.TINT_METRES]:
		assert_false(is_zero_approx(fmod(scale, tile)), "%.1f m is not a whole number of tiles (8.0 lines the noise cells up with the tile grid: caught)" % scale)
	assert_true(TerrainMaterial.MACRO_VARIATION >= 0.05 and TerrainMaterial.MACRO_VARIATION <= 0.25, "macro_variation is visible but not blotchy (0.0 or 0.4: caught)")
	assert_true(TerrainMaterial.MACRO_VARIATION_MAX <= 0.5, "the clamp ceiling keeps albedo positive (0.6 could multiply by -0.2: caught)")
	var dry: Vector3 = TerrainMaterial.GRASS_TINT_DRY
	var lush: Vector3 = TerrainMaterial.GRASS_TINT_LUSH
	for c: Vector3 in [dry, lush]:
		for i: int in 3:
			assert_true(c[i] >= 0.75 and c[i] <= 1.25, "tint multipliers stay within 25 %% of unity (%s; a 2.0 channel is neon: caught)" % c)
		assert_true(absf(_luminance(c) - 1.0) < 0.05, "tint multipliers keep luminance near 1 (%s; hue, not brightness, is their job: caught)" % c)
	assert_true(dry.x > lush.x and dry.z < lush.z, "dry is warmer than lush (swap them: caught)")
	assert_true(lush.y >= dry.y, "lush has at least as much green as dry")


func test_data_overrides_and_clamps() -> void:
	var mat: ShaderMaterial = _material({
		"tile_break_metres": 0.0, "macro_metres": 0.1, "macro_variation": 2.0, "tint_metres": 45.0,
		"grass_tint_dry": [1.2, 1.0, 0.7], "grass_tint_lush": [0.8, 1.1, 1.2],
	})
	assert_eq(_float(mat, "tile_break_metres"), 0.0, "tile_break_metres 0 is allowed: it switches the breaking off")
	assert_eq(_float(mat, "macro_metres"), 1.0, "macro_metres is floored at 1 m (0.1 would divide the world by a hair: caught)")
	assert_eq(_float(mat, "macro_variation"), TerrainMaterial.MACRO_VARIATION_MAX, "macro_variation is clamped (2.0 would make albedo negative: caught)")
	assert_eq(_float(mat, "tint_metres"), 45.0, "tint_metres takes the data value")
	assert_eq(_vec(mat, "grass_tint_dry"), Vector3(1.2, 1.0, 0.7), "grass_tint_dry takes the data array")
	assert_eq(_vec(mat, "grass_tint_lush"), Vector3(0.8, 1.1, 1.2), "grass_tint_lush takes the data array")
	var neg: ShaderMaterial = _material({"tile_break_metres": -4.0, "macro_variation": -1.0})
	assert_eq(_float(neg, "tile_break_metres"), 0.0, "a negative tile_break_metres becomes 0 (off), not a negative divisor")
	assert_eq(_float(neg, "macro_variation"), 0.0, "a negative macro_variation becomes 0")


func test_the_vale_file_needs_no_new_key_and_keeps_its_old_ones() -> void:
	# Another task owns data/areas/vale.json right now, so this reads whatever is there and checks the
	# material against the file with the same defaults the code uses: new keys absent -> constants; present
	# -> their values. The old keys must land exactly as they did before W21-E.
	var m: Dictionary = _vale_material()
	var mat: ShaderMaterial = _material(m)
	assert_eq(_float(mat, "tile_break_metres"), float(m.get("tile_break_metres", TerrainMaterial.TILE_BREAK_METRES)), "vale tile_break_metres")
	assert_eq(_float(mat, "macro_metres"), float(m.get("macro_metres", TerrainMaterial.MACRO_METRES)), "vale macro_metres")
	assert_eq(_float(mat, "macro_variation"), float(m.get("macro_variation", TerrainMaterial.MACRO_VARIATION)), "vale macro_variation")
	assert_eq(_float(mat, "tint_metres"), float(m.get("tint_metres", TerrainMaterial.TINT_METRES)), "vale tint_metres")
	assert_true(is_equal_approx(_float(mat, "uv_scale"), 1.0 / float(m.get("uv_metres_per_tile", 2.0))), "uv_scale is still 1 / uv_metres_per_tile")
	assert_eq(_float(mat, "grass_slope_deg"), float(m.get("grass_slope_deg", 20.0)), "grass slope unchanged")
	assert_eq(_float(mat, "gravel_slope_deg"), float(m.get("gravel_slope_deg", 28.0)), "gravel slope unchanged")
	assert_eq(_float(mat, "rock_slope_deg"), float(m.get("rock_slope_deg", 36.0)), "rock slope unchanged")
	assert_true(is_equal_approx(_float(mat, "mud_height"), WATER + float(m.get("mud_height", 1.5))), "mud_height is still water level plus the data offset")
	assert_eq(_float(mat, "normal_strength"), float(m.get("normal_strength", 0.8)), "normal_strength unchanged")
	var tint: Variant = m.get("grass_tint", null)
	if tint is Array:
		assert_eq(_vec(mat, "grass_tint"), Vector3(float(tint[0]), float(tint[1]), float(tint[2])), "grass_tint still comes from the file")
	else:
		assert_eq(_vec(mat, "grass_tint"), Vector3.ONE, "grass_tint is white when the file has none")
	var road: Dictionary = m.get("road", {})
	var points: Array = road.get("waypoints", [])
	assert_eq(int(mat.get_shader_parameter("road_count")), mini(maxi(points.size() - 1, 0), TerrainMaterial.MAX_ROAD_SEGMENTS), "road segment count unchanged")
	assert_eq(_float(mat, "road_half"), maxf(0.0, float(road.get("half_width", 2.5))), "road half width unchanged")


func test_shader_keeps_slope_height_road_and_normal_strength() -> void:
	var code: String = _code()
	assert_true(code.contains("smoothstep(gravel_slope_deg, rock_slope_deg, slope)"), "rock still blends in by slope (drop the band: caught)")
	assert_true(code.contains("smoothstep(grass_slope_deg, gravel_slope_deg, slope)"), "gravel still blends in by slope")
	assert_true(code.contains("smoothstep(mud_height, mud_height + mud_blend, world_pos.y)"), "mud still blends in by height")
	assert_true(code.contains("road_weight(world_pos.xz) * (1.0 - w_rock)"), "the road still wears the ground and fades out on rock")
	assert_true(code.count("* normal_strength") >= 2, "normal_strength still scales both the planar and the rock perturbation")
	assert_true(code.contains("uniform vec4 road_segments[%d]" % TerrainMaterial.MAX_ROAD_SEGMENTS), "the road array still matches MAX_ROAD_SEGMENTS")
	assert_true(code.contains("ROUGHNESS = clamp(rough, 0.3, 1.0)") and code.contains("SPECULAR = 0.3"), "roughness clamp and specular are as before")
	var mat: ShaderMaterial = _material({})
	assert_eq(mat.shader.resource_path, SHADER, "the material uses scripts/systems/terrain.gdshader")
	assert_true(is_same(mat, TerrainMaterial.get_material({"tile_break_metres": 1.0}, WATER)), "the material is still cached: a second call returns the same object")
