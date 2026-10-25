extends "res://tests/test_case.gd"
## Live checks for W3-04 beyond the pure Grass maths: the vale probe's new `PROBE grass` line (a child
## headless vale.tscn run, the same rig tests/test_terrain.gd uses), the split sun disc and dawn/dusk glow
## in sky.tscn + data/daynight.json, and LevelDressing's partial normal alignment, which must leave a level
## without a normal sampler (the greybox) exactly upright.

const VALE_SCENE := "res://scenes/levels/vale.tscn"
const SKY := "res://scenes/environment/sky.tscn"
const DAYNIGHT := "res://data/daynight.json"
const PROBE_FRAME_CAP := "1800"

var _code: int = -1
var _text: String = ""


func setup() -> void:
	var output: Array = []
	var args: PackedStringArray = [
		"--headless", "--path", ProjectSettings.globalize_path("res://"),
		VALE_SCENE, "--quit-after", PROBE_FRAME_CAP, "--", "--probe",
	]
	_code = OS.execute(OS.get_executable_path(), args, output, true)
	_text = "\n".join(PackedStringArray(output))


func test_vale_probe_prints_grass_after_the_original_five_lines() -> void:
	assert_eq(_code, 0, "child headless run of the vale exits cleanly")
	assert_false("SCRIPT ERROR" in _text, "child run printed no script errors")
	assert_false("SHADER ERROR" in _text, "the grass and patch shaders parsed")
	var order: Array[int] = []
	for prefix: String in ["PROBE terrain ", "PROBE heightfield ", "PROBE spawn ", "PROBE forest ", "PROBE dressing ", "PROBE grass "]:
		order.append(_text.find(prefix))
		assert_true(order[order.size() - 1] >= 0, "probe printed %s" % prefix)
	for i: int in order.size() - 1:
		assert_true(order[i] < order[i + 1], "probe lines keep their order (%d before %d)" % [i, i + 1])


func test_grass_grows_near_the_spawn_and_never_under_water_or_on_cliffs() -> void:
	var line: Dictionary = _probe_line(_text, "PROBE grass ")
	assert_true(not line.is_empty(), "probe printed the grass line")
	if line.is_empty():
		return
	assert_true(int(line["cells"]) > 50, "the lattice around the spawn is filled (%s cells)" % line["cells"])
	assert_true(int(line["instances"]) > 2000, "a real amount of cover was placed (%s)" % line["instances"])
	assert_true(int(line["blade_verts"]) > int(line["instances"]), "blade vertices were counted (%s)" % line["blade_verts"])
	assert_eq(int(line["underwater"]), 0, "nothing grows under water")
	assert_eq(int(line["steep"]), 0, "nothing grows above its layer's slope limit")
	assert_eq(int(line["floating"]), 0, "every instance sits on the heightfield")
	assert_eq(int(line["pending"]), 0, "the whole lattice was filled before the probe printed")
	assert_true(int(line["layers"]) >= 4, "grass, pebbles, leaves and foliage layers all built (%s)" % line["layers"])
	assert_true(int(line["cells"]) <= int(line["pool"]), "no more cells than pooled slots")


func test_sky_splits_scene_sun_from_sky_disc_and_fog_hazes_the_halo() -> void:
	var sky: DayNightCycle = (load(SKY) as PackedScene).instantiate() as DayNightCycle
	var sun: DirectionalLight3D = sky.get_node(sky.sun_path) as DirectionalLight3D
	var disc: DirectionalLight3D = sky.get_node_or_null(sky.sun_disc_path) as DirectionalLight3D
	assert_not_null(disc, "sun_disc_path resolves to a DirectionalLight3D")
	assert_eq(sun.sky_mode, DirectionalLight3D.SKY_MODE_LIGHT_ONLY, "the scene sun no longer paints the sky")
	if disc != null:
		assert_eq(disc.sky_mode, DirectionalLight3D.SKY_MODE_SKY_ONLY, "the disc light paints the sky only")
		assert_false(disc.shadow_enabled, "the disc casts no shadows")
		assert_true(disc.light_angular_distance < 2.0, "the disc core is small (%s deg)" % disc.light_angular_distance)
	var game: Node = (load("res://scripts/autoloads/game.gd") as GDScript).new()
	game.state = game.State.PLAYING
	sky._inject(game)
	sky._ready()
	var mat: ProceduralSkyMaterial = (sky.get_node(sky.environment_path) as WorldEnvironment).environment.sky.sky_material
	sky.start_hour = 12.0
	game.time_of_day = 12.0
	sky._on_time_changed(12.0)
	var noon_glow: float = mat.sun_angle_max
	var noon_energy: float = disc.light_energy if disc != null else 0.0
	assert_true(noon_glow < 20.0, "noon halo is narrower than the old 20 degree disc (%s)" % noon_glow)
	assert_true(noon_glow > 5.0, "noon halo is still a soft glow, not a hard point (%s)" % noon_glow)
	assert_true(noon_energy > 1.2, "noon disc is HDR-bright so it blooms (%s)" % noon_energy)
	game.time_of_day = 6.25
	sky._on_time_changed(6.25)
	assert_true(mat.sun_angle_max > noon_glow, "the foggy dawn halo is wider than noon (%s vs %s)" % [mat.sun_angle_max, noon_glow])
	if disc != null:
		assert_true(disc.light_energy < noon_energy and disc.light_energy > 0.0, "the dawn disc is dimmer than noon (%s)" % disc.light_energy)
	game.time_of_day = 0.0
	sky._on_time_changed(0.0)
	if disc != null:
		assert_false(disc.visible, "the disc is hidden at night")
	sky.free()
	game.free()


func test_vale_palette_has_a_horizon_glow_at_dawn_and_dusk() -> void:
	var profiles: Dictionary = DayNightCycle.load_profiles(DAYNIGHT)
	assert_eq(profiles.size(), 3, "the top-level comment is not mistaken for an area")
	var vale: SkyProfile = profiles[&"vale"]
	for hour: float in [6.0, 18.0]:
		var s: Dictionary = vale.sample(hour)
		var horizon: float = (s["sky_horizon"] as Color).get_luminance()
		var top: float = (s["sky_top"] as Color).get_luminance()
		assert_true(horizon > top * 2.5, "at %s the horizon band glows against a dark dome (%s vs %s)" % [hour, horizon, top])
		assert_true(float(s["sky_curve"]) < 0.15, "at %s the glow band is tighter than by day" % hour)
		assert_true(float(s["sun_glow_deg"]) > float(vale.sample(12.0)["sun_glow_deg"]), "at %s the sun halo is wider than at noon" % hour)
	var before: float = (vale.sample(5.0)["sky_horizon"] as Color).get_luminance()
	var glow: float = (vale.sample(6.0)["sky_horizon"] as Color).get_luminance()
	var after: float = (vale.sample(9.0)["sky_horizon"] as Color).get_luminance()
	assert_true(glow > before * 2.0, "the horizon brightens into sunrise, not a step (%s vs %s)" % [glow, before])
	assert_true(after > glow * 0.8, "daylight keeps the horizon lit after the glow")
	assert_true(float(vale.sample(0.0)["ambient_energy"]) >= 0.1, "midnight keeps enough ambient for silhouettes")
	assert_true(float(vale.sample(12.0)["fog_density"]) >= 0.03, "the vale stays foggy at noon")


func test_aligned_basis_tilts_part_way_and_stays_upright_without_a_normal() -> void:
	var upright: Basis = GroundPlacement.aligned_basis(Vector3.UP, 0.7, 0.6, 1.3)
	var plain: Basis = Basis.from_euler(Vector3(0.0, 0.7, 0.0)).scaled(Vector3.ONE * 1.3)
	assert_true(upright.is_equal_approx(plain), "a flat normal gives exactly the old yaw-and-scale basis")
	var n: Vector3 = Vector3(0.5, 1.0, 0.0).normalized()
	var flat: Basis = GroundPlacement.aligned_basis(n, 0.0, 1.0, 1.0)
	assert_true(flat.y.is_equal_approx(n), "align 1 lies the prop along the normal")
	var half: Basis = GroundPlacement.aligned_basis(n, 0.0, 0.5, 1.0)
	var tilt: float = rad_to_deg(half.y.angle_to(Vector3.UP))
	var full: float = rad_to_deg(n.angle_to(Vector3.UP))
	assert_true(tilt > full * 0.4 and tilt < full * 0.6, "align 0.5 tilts about halfway (%.1f of %.1f deg)" % [tilt, full])
	assert_true(is_equal_approx(half.get_scale().x, 1.0) and is_equal_approx(half.determinant(), 1.0), "alignment keeps the scale")
	var zero: Basis = GroundPlacement.aligned_basis(Vector3.ZERO, 0.0, 1.0, 1.0)
	assert_true(zero.y.is_equal_approx(Vector3.UP), "a degenerate normal falls back to upright")


func test_dressing_tilts_scatter_only_when_a_normal_sampler_is_set() -> void:
	var data: Dictionary = {"seed": 3, "align_default": 0.6, "sink_default": 0.1, "sets": [{
		"name": "rocks", "model": "res://assets/models/rocks/rock_moss_set_02/rock_moss_set_02_1k.gltf", "mesh": "rock_moss_set_02_rock08",
		"y": 0.0, "scale": [1.0, 1.0], "collide": true, "scatter": [{"zone": {"min": [0, 0], "max": [20, 20]}, "count": 6, "min_gap": 1.0}]}]}
	if not ResourceLoader.exists(str(data["sets"][0]["model"])):
		return
	var flat: LevelDressing = LevelDressing.new()
	flat.height_sampler = func(_x: float, _z: float) -> float: return 1.0
	flat.build(data)
	var sloped: LevelDressing = LevelDressing.new()
	sloped.height_sampler = func(x: float, _z: float) -> float: return 1.0 + x * 0.5
	sloped.normal_sampler = func(_x: float, _z: float) -> Vector3: return Vector3(-0.5, 1.0, 0.0).normalized()
	sloped.build(data)
	assert_eq(flat.stats()["instances"], sloped.stats()["instances"], "alignment changes no placement counts")
	var flat_t: Array[Transform3D] = _transforms(flat)
	var sloped_t: Array[Transform3D] = _transforms(sloped)
	for t: Transform3D in flat_t:
		assert_true(t.basis.y.normalized().is_equal_approx(Vector3.UP), "without a normal sampler props stand upright")
	var tilted: int = 0
	for i: int in sloped_t.size():
		if not sloped_t[i].basis.y.normalized().is_equal_approx(Vector3.UP):
			tilted += 1
		var expect: float = 1.0 + sloped.origins()[i].x * 0.5 - 0.1
		assert_true(absf(sloped_t[i].origin.y - expect) < 0.01, "prop sinks 0.1 m into the bank (y %s vs %s)" % [sloped_t[i].origin.y, expect])
	assert_eq(tilted, sloped_t.size(), "every prop on the bank leans with it")
	flat.free()
	sloped.free()


func _transforms(dressing: LevelDressing) -> Array[Transform3D]:
	var out: Array[Transform3D] = []
	for child: Node in dressing.get_children():
		if child is StaticBody3D:
			out.append((child as StaticBody3D).transform)
	return out


func _probe_line(text: String, prefix: String) -> Dictionary:
	var out: Dictionary = {}
	for line: String in text.split("\n"):
		line = line.strip_edges()
		if not line.begins_with(prefix):
			continue
		for token: String in line.substr(prefix.length()).split(" ", false):
			var kv: PackedStringArray = token.split("=", true, 1)
			if kv.size() == 2:
				out[kv[0]] = kv[1]
		return out
	return out
