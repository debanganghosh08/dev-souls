extends "res://tests/test_case.gd"
## W21-D: the owner's "completely pixelated" grass and foliage -- neon white-green blades up close, a mown
## lawn by the castle, conifers crawling with speckle. These pin the foliage shaders' alpha-to-coverage,
## the grass shader's shade decode against GrassMesh, the sRGB-to-linear palette path and its luminance
## band (so neon cannot silently return), the fill work per cell (so D-037's near-field guarantee keeps
## the same CPU budget), the lattice reach round a 30 m disc, zone palettes differing, and the wind
## amplitude TAA has to reproject without motion vectors. Each assertion names the broken input it
## catches. Nothing here sees a frame: the look is the owner's to judge.

const GRASS_SHADER := "res://scripts/systems/grass.gdshader"
const TWIG_SHADER := "res://scripts/systems/twig_card.gdshader"
const PATCH_SHADER := "res://scripts/systems/ground_patch.gdshader"
const GRASS_SCRIPT := "res://scripts/systems/grass.gd"
const LEVEL := "res://scenes/levels/vale.tscn"
const VALE := "res://data/areas/vale.json"
const GRASS_DATA := "res://data/grass/vale.json"
const ZONES := "res://data/grass/zones_vale.json"
## D-037: 15 m cells, 60 m radius, written on the vale's Grass node. The sprint probe's guarantee is 30 m.
const CELL := 15.0
const RADIUS := 60.0
const NEAR := 30.0
const SCENE_DENSITY := 1.3
## Sum of max_per_cell over the vale's layers before W21-D, and the base layer's candidate pool per cell.
const FILL_CAP_BEFORE := 1721
const GRASS_POOL_BEFORE := 977
## sRGB luminance (Color.get_luminance on the hex as written) a tip / root may be authored in.
const TIP_LUM := Vector2(0.40, 0.60)
const ROOT_LUM := Vector2(0.14, 0.28)
## Linear luminance of what is actually uploaded as the instance tip, colour noise included.
const UPLOAD_TIP_LUM := Vector2(0.08, 0.38)
## Fastest the gust function moves a tip, m/s, per unit wind_strength and wind_speed: d/dt of
## 0.4 * (0.7 sin(t) + 0.3 sin(2.17 t)) peaks at 0.4 * (0.7 + 0.65).
const GUST_RATE := 0.54
## Tip speed, m/s, that stays under a pixel per frame from about 3 m at 60 fps, 1080p, 70 degrees.
const WIND_TIP_SPEED_MAX := 0.2


func _text(path: String) -> String:
	return FileAccess.get_file_as_string(path)


func _render_mode(code: String) -> String:
	var start: int = code.find("render_mode")
	return code.substr(start, code.find(";", start) - start)


func _uniform_default(code: String, name: String) -> float:
	var regex := RegEx.new()
	regex.compile("uniform\\s+float\\s+%s\\s*(?::[^=;]*)?=\\s*([0-9.]+)" % name)
	var m: RegExMatch = regex.search(code)
	return float(m.get_string(1)) if m != null else NAN


func _layer(data: Dictionary, name: String) -> Dictionary:
	for raw: Variant in data.get("layers", []):
		if str((raw as Dictionary).get("name", "")) == name:
			return raw as Dictionary
	return {}


func test_both_foliage_shaders_feather_their_cutout_and_the_grass_shader_stays_opaque() -> void:
	for path: String in [TWIG_SHADER, PATCH_SHADER]:
		var code: String = _text(path)
		assert_not_null(load(path) as Shader, "%s loads as a Shader" % path)
		assert_true(_render_mode(code).contains("alpha_to_coverage"), "%s render_mode has alpha_to_coverage (drop it: caught)" % path)
		assert_true(code.contains("ALPHA_SCISSOR_THRESHOLD ="), "%s keeps its scissor, so the depth prepass and shadows keep the cut-out" % path)
		assert_true(code.contains("ALPHA_ANTIALIASING_EDGE = aa_edge"), "%s sets the AA edge from a uniform (delete the line: caught)" % path)
		# The engine adds the edge to the scissor threshold; the W21-B handoff's `= scissor` would centre
		# the feather at alpha 1.0 and hollow every crown and patch to half coverage.
		assert_false(code.contains("ALPHA_ANTIALIASING_EDGE = scissor") or code.contains("ALPHA_ANTIALIASING_EDGE = 0.5"), "%s does not hand the scissor value to the AA edge" % path)
		var edge: float = _uniform_default(code, "aa_edge")
		assert_true(edge > 0.0 and edge <= 0.25, "%s aa_edge default is small (%s): 0.5 or 0.0 caught" % [path, edge])
	var twig: String = _text(TWIG_SHADER)
	assert_true(twig.contains("ALPHA_TEXTURE_COORDINATE =") and twig.contains("textureSize(alpha_tex"), "the twig card gives the AA its alpha texel coordinate so distant mips do not thin away")
	var grass: String = _text(GRASS_SHADER)
	assert_not_null(load(GRASS_SHADER) as Shader, "the grass shader loads")
	assert_false(grass.contains("ALPHA =") or grass.contains("ALPHA_SCISSOR") or grass.contains("alpha_to_coverage"), "blades are opaque geometry: an ALPHA write would send 30k instances to the transparent pass")
	assert_true(_render_mode(grass).contains("depth_draw_opaque") and _render_mode(grass).contains("world_vertex_coords"), "the grass render_mode keeps depth and world-space wind")


func test_shade_decode_matches_grass_mesh_and_the_blade_widens_with_distance() -> void:
	var code: String = _text(GRASS_SHADER)
	assert_true(is_equal_approx(_uniform_default(code, "shade_min"), GrassMesh.SHADE_MIN), "shader shade_min == GrassMesh.SHADE_MIN (%s vs %s): change one side, caught" % [_uniform_default(code, "shade_min"), GrassMesh.SHADE_MIN])
	assert_true(is_equal_approx(_uniform_default(code, "shade_range"), GrassMesh.SHADE_RANGE), "shader shade_range == GrassMesh.SHADE_RANGE (%s vs %s)" % [_uniform_default(code, "shade_range"), GrassMesh.SHADE_RANGE])
	var decoded: float = GrassMesh.SHADE_MIN + GrassMesh.SHADE_RANGE * GrassMesh.shade_color(1.0).a
	assert_true(is_equal_approx(decoded, 1.0), "a shade of 1.0 round-trips through vertex alpha (%s)" % decoded)
	var widen: float = _uniform_default(code, "far_widen")
	assert_true(widen > 0.0 and widen <= 0.1, "far_widen is a few centimetres (%s): 0 (no widening) or 0.5 (ribbons) caught" % widen)
	assert_true(_uniform_default(code, "widen_start") < _uniform_default(code, "fade_start"), "widening ramps in before the fade starts")
	assert_true(code.contains("* UV.y *"), "widening scales by UV.y so a root and a pebble (UV.y 0) never move")
	assert_true(GrassMesh.TIP_WIDTH_FRACTION >= 0.2 and GrassMesh.TIP_WIDTH_FRACTION <= 0.4, "the tip keeps a fifth or more of the base width (%s): the old needle 0.12 caught" % GrassMesh.TIP_WIDTH_FRACTION)


func test_the_fade_completes_inside_the_lattice_and_the_near_field_is_whole() -> void:
	var data: Dictionary = Terrain.load_data(GRASS_DATA)
	var scene: String = _text(LEVEL)
	assert_true(scene.contains("radius = %.1f" % RADIUS) and scene.contains("cell_size = %.1f" % CELL), "the vale Grass node still runs D-037's 15 m cells at 60 m (12 m or 50 m: caught)")
	var grass_node: Node = (load(GRASS_SCRIPT) as GDScript).new()
	var near_fraction: float = float(grass_node.get("near_fraction"))
	grass_node.free()
	var near_radius: float = RADIUS * near_fraction
	for name: String in ["grass", "tall_grass"]:
		var layer: Dictionary = _layer(data, name)
		var fade: Array = layer["fade"]
		assert_true(float(fade[0]) >= near_radius, "%s fade starts outside the always-full near field (%s >= %.1f)" % [name, fade[0], near_radius])
		assert_true(float(fade[1]) <= RADIUS, "%s fade ends inside the lattice radius (%s <= %.0f): the old 70 m, beyond the lattice, caught" % [name, fade[1], RADIUS])
		assert_true(float(layer["far_fraction"]) >= 0.5, "%s keeps at least half its blades at the edge (%s): the old 0.45 caught" % [name, layer["far_fraction"]])
		var material: ShaderMaterial = GrassMesh.grass_material(Vector2(float(fade[0]), float(fade[1])))
		assert_true(is_equal_approx(float(material.get_shader_parameter("fade_end")), float(fade[1])), "%s material carries its fade_end" % name)
	var far: float = float(_layer(data, "grass")["far_fraction"])
	assert_true(GrassLattice.thin_factor(NEAR, RADIUS, near_radius, far) >= 0.95, "at 30 m nearly every placed blade still shows (%.2f)" % GrassLattice.thin_factor(NEAR, RADIUS, near_radius, far))
	assert_true(is_equal_approx(GrassLattice.thin_factor(near_radius, RADIUS, near_radius, far), 1.0), "inside the near radius nothing is thinned")
	# Every cell that touches the 30 m disc round a player on a cell centre is in the lattice: the
	# probe's "nothing unfilled within 30 m" needs the cell to exist before it can be filled.
	var offsets: Array[Vector2i] = GrassLattice.lattice_offsets(RADIUS, CELL)
	var touching: int = 0
	for j: int in range(-4, 5):
		for i: int in range(-4, 5):
			var nearest := Vector2(maxf(0.0, absf(float(i)) * CELL - CELL * 0.5), maxf(0.0, absf(float(j)) * CELL - CELL * 0.5))
			if nearest.length() <= NEAR:
				touching += 1
				assert_true(offsets.has(Vector2i(i, j)), "cell %s touches the 30 m disc and is in the lattice (a 25 m radius: caught)" % Vector2i(i, j))
	assert_true(touching >= 21, "the 30 m disc touches a 5x5 block at least (%d cells)" % touching)


func test_fill_work_per_cell_is_no_larger_than_before_w21_d() -> void:
	var data: Dictionary = Terrain.load_data(GRASS_DATA)
	var total_cap: int = 0
	var grass: GrassLayer = null
	var flat: Callable = func(_x: float, _z: float) -> float: return 2.0
	# A zone as dense as the vale's densest (1.4x) with every channel on, so each zoned layer sizes its
	# pool the way it does in the game.
	var zones: GrassZones = GrassZones.from_dict({"zones": [{"name": "dense", "shape": {"type": "base"}, "density": 1.4, "tall": 1.0, "flowers": 1.0}]}, null)
	var cell := GrassCell.new()
	cell.prepare(Vector2i(0, 0), CELL, flat, -5.0, PackedVector3Array(), 0.0, zones)
	var index: int = 0
	for raw: Variant in data["layers"]:
		var entry: Dictionary = raw
		total_cap += int(entry["max_per_cell"])
		if entry["kind"] in ["clump", "flower", "pebble"]:
			var layer: GrassLayer = GrassLayer.from_dict(entry, 20261024, index)
			layer.density *= SCENE_DENSITY
			layer.zone_max = zones.max_density()
			layer.begin(Vector2i(0, 0), index, 20261024, cell)
			assert_true(layer.candidates() <= layer.max_per_cell, "%s draws at most max_per_cell candidates (%d)" % [layer.name, layer.candidates()])
			if layer.name == "grass":
				grass = layer
		index += 1
	assert_true(total_cap <= FILL_CAP_BEFORE, "the vale's per-cell instance cap is no larger than before (%d <= %d): raising density or max_per_cell to get coverage is caught" % [total_cap, FILL_CAP_BEFORE])
	assert_not_null(grass, "the base layer builds")
	assert_eq(grass.candidates(), GRASS_POOL_BEFORE, "the base layer's candidate pool per cell is exactly what D-037 settled")
	assert_eq(grass.vertex_count, 3 * (3 + 1) * 2, "a base clump is still 3 blades of 3 segments (a 4th blade: caught); coverage came from width, height and the shader")


func test_blade_palettes_sit_in_the_luminance_band_differ_by_zone_and_upload_linear() -> void:
	var zones_doc: Dictionary = Terrain.load_data(ZONES)
	var grass_doc: Dictionary = Terrain.load_data(GRASS_DATA)
	var tips: Dictionary = {}
	var palettes: Array[Array] = []
	for raw: Variant in zones_doc["zones"]:
		var zone: Dictionary = raw
		if zone.has("tip"):
			palettes.append([zone["name"], str(zone["root"]), str(zone["tip"])])
			tips[str(zone["tip"])] = true
	for raw: Variant in grass_doc["layers"]:
		var layer: Dictionary = raw
		if layer.has("tip_color"):
			palettes.append([layer["name"], str(layer["root_color"]), str(layer["tip_color"])])
	for p: Array in palettes:
		var root_lum: float = Color.html(p[1]).get_luminance()
		var tip_lum: float = Color.html(p[2]).get_luminance()
		assert_true(tip_lum >= TIP_LUM.x and tip_lum <= TIP_LUM.y, "%s tip %s luminance %.3f in %s (a #c8ff80 neon or a #3a4a20 mud: caught)" % [p[0], p[2], tip_lum, TIP_LUM])
		assert_true(root_lum >= ROOT_LUM.x and root_lum <= ROOT_LUM.y, "%s root %s luminance %.3f in %s" % [p[0], p[1], root_lum, ROOT_LUM])
		assert_true(tip_lum > root_lum * 1.5, "%s tip is well paler than its root" % p[0])
		# Negative control for the colour-space fix: the hex taken as linear, which is what was uploaded
		# until W21-D, is outside the upload band every time.
		assert_true(tip_lum > UPLOAD_TIP_LUM.y, "%s hex read as linear (%.3f) would fail the upload band: the old path caught" % [p[0], tip_lum])
	assert_true(tips.size() >= 5, "the vale's zones use at least five different tips (%d): one green everywhere caught" % tips.size())
	var by_name: Dictionary = {}
	for p: Array in palettes:
		by_name[p[0]] = p[2]
	for pair: Array in [["meadow", "castle_hill"], ["meadow", "pond_shore"], ["castle_hill", "tall_patches"], ["meadow", "north_hilltops"], ["meadow", "castle_courtyard"]]:
		assert_ne(by_name[pair[0]], by_name[pair[1]], "%s and %s have different tips" % pair)
	# What is uploaded: linear, inside the band, over the real valley with the colour noise on.
	var linear: Color = GrassZones.palette("#6f8a3c", Color.BLACK)
	assert_eq(linear, Color.html("#6f8a3c").srgb_to_linear(), "palette() converts sRGB hex to linear")
	assert_true(linear.g < Color.html("#6f8a3c").g * 0.6, "linear green is well under the hex's (%.3f vs %.3f)" % [linear.g, Color.html("#6f8a3c").g])
	var hf: Heightfield = Heightfield.from_dict(Terrain.load_data(VALE))
	var zones: GrassZones = GrassZones.load_file(ZONES, hf)
	var lowest: float = INF
	var highest: float = -INF
	for x: int in range(-300, 301, 20):
		for z: int in range(-300, 301, 20):
			zones.sample(x, z)
			lowest = minf(lowest, zones.tip.get_luminance())
			highest = maxf(highest, zones.tip.get_luminance())
			assert_true(zones.root.get_luminance() < zones.tip.get_luminance(), "root darker than tip at (%d, %d)" % [x, z])
	assert_true(lowest >= UPLOAD_TIP_LUM.x and highest <= UPLOAD_TIP_LUM.y, "uploaded tips over the valley stay in %s (%.3f..%.3f): hex-as-linear or a 0.5 light noise caught" % [UPLOAD_TIP_LUM, lowest, highest])
	# A field is not one flat green: along 100 m of the south meadow the tip's lightness varies by the
	# colour noise and its mottle; the same walk with the noise zeroed varies only by what the zones
	# themselves feather in, so the noise must add a clear spread on top of that.
	var flat_doc: Dictionary = zones_doc.duplicate(true)
	flat_doc["colour_noise"] = {}
	var flat_zones: GrassZones = GrassZones.from_dict(flat_doc, hf)
	var spread: float = _lum_spread(zones)
	var control: float = _lum_spread(flat_zones)
	assert_true(spread >= 0.08, "tip luminance varies by %.0f%% across the south meadow (need 8%%; colour_noise removed: caught)" % (spread * 100.0))
	assert_true(spread >= control + 0.05, "the colour noise adds spread the zones alone do not (%.3f against %.3f without it)" % [spread, control])
	# And a filled layer uploads its tip as a shade of the linear palette, never the hex.
	var layer: GrassLayer = GrassLayer.from_dict(_layer(grass_doc, "grass"), 20261024, 0)
	layer.dry_amount = 0.0
	var mmi: MultiMeshInstance3D = layer.make_instance(0)
	var cell := GrassCell.new()
	var out := PackedVector3Array()
	out.resize(layer.max_per_cell)
	var flat: Callable = func(_x: float, _z: float) -> float: return 2.0
	cell.prepare(Vector2i(1, 1), CELL, flat, -5.0, PackedVector3Array(), 0.0)
	assert_true(layer.fill(Vector2i(1, 1), 0, 20261024, cell, mmi, out, Callable(), Callable()) > 0, "the vale's base layer fills a flat cell")
	var k: float = layer.last_tint.g / linear.g
	assert_true(k >= GrassMesh.SHADE_MIN - 0.001 and k <= GrassMesh.SHADE_MIN + GrassMesh.SHADE_RANGE + 0.001, "the uploaded tip is the linear palette times its shade (%.3f)" % k)
	assert_true(absf(layer.last_tint.r - linear.r * k) < 0.002 and absf(layer.last_tint.b - linear.b * k) < 0.002, "the uploaded tip keeps the palette's hue")
	mmi.free()


func test_wind_stays_sub_pixel_per_frame_for_taa() -> void:
	# Godot writes no motion vectors for TIME-driven vertex motion, so TAA reprojects a bent blade as
	# if it stood still; what keeps that invisible is the tip moving well under a pixel per frame.
	var wind: Dictionary = Terrain.load_data(GRASS_DATA)["wind"]
	var speed: float = float(wind["strength"]) * float(wind["speed"]) * GUST_RATE
	assert_true(speed <= WIND_TIP_SPEED_MAX, "a tip moves at most %.3f m/s under the vale's wind (cap %.2f; strength 0.8 caught)" % [speed, WIND_TIP_SPEED_MAX])
	var code: String = _text(GRASS_SHADER)
	assert_true(_uniform_default(code, "wind_strength") * _uniform_default(code, "wind_speed") * GUST_RATE <= WIND_TIP_SPEED_MAX, "the shader's own defaults obey the same cap")
	assert_true(float(wind["ripple_scale"]) <= 0.2, "ripple bands are tens of metres wide, so neighbouring blades move together and TAA's neighbourhood clamp holds (%s)" % wind["ripple_scale"])


## Largest relative tip-luminance spread along a 100 m east-west walk through the south meadow.
func _lum_spread(zones: GrassZones) -> float:
	var lo: float = INF
	var hi: float = -INF
	for x: int in range(0, 101, 5):
		zones.sample(float(x), 280.0)
		lo = minf(lo, zones.tip.get_luminance())
		hi = maxf(hi, zones.tip.get_luminance())
	return (hi - lo) / maxf(lo, 0.0001)
