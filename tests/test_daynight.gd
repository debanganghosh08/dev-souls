extends "res://tests/test_case.gd"
## DayNightCycle tests. The runner has no autoloads and no live tree, so the cycle is instanced from
## sky.tscn with a Game script injected (nodes outside the tree still accept property writes), and the
## full engine path (Game.time_changed in a running loop) is checked by a child headless Godot playing
## skytest.tscn with `--probe` and printing PROBE lines.

const SKY := "res://scenes/environment/sky.tscn"
const SKYTEST := "res://scenes/levels/skytest.tscn"
const GAME_SCRIPT := "res://scripts/autoloads/game.gd"
const DATA := "res://data/daynight.json"
const PROBE_FRAME_CAP := "900"

var _sky: DayNightCycle
var _game: Node


func _fresh() -> void:
	_cleanup()
	_sky = (load(SKY) as PackedScene).instantiate() as DayNightCycle
	_game = (load(GAME_SCRIPT) as GDScript).new()
	_game.state = _game.State.PLAYING
	_sky._inject(_game)
	_sky._ready()


func _cleanup() -> void:
	if _sky != null:
		_sky.free()
		_sky = null
	if _game != null:
		_game.free()
		_game = null


func teardown() -> void:
	_cleanup()


func test_sky_scene_is_self_contained() -> void:
	_fresh()
	assert_not_null(_sky, "sky.tscn root carries the DayNightCycle script")
	var world: WorldEnvironment = _sky.get_node_or_null(_sky.environment_path) as WorldEnvironment
	assert_not_null(world, "environment_path resolves to a WorldEnvironment")
	var env: Environment = world.environment
	assert_not_null(env, "WorldEnvironment has its own Environment")
	assert_eq(env.background_mode, Environment.BG_SKY, "background is the sky")
	assert_not_null(env.sky, "Environment has a Sky")
	assert_true(env.sky.sky_material is ShaderMaterial, "the sky uses the custom sky ShaderMaterial (W21)")
	assert_true(env.fog_enabled, "fog is enabled")
	assert_true(env.glow_enabled, "glow is enabled")
	assert_eq(env.tonemap_mode, Environment.TONE_MAPPER_ACES, "tonemapper is ACES")
	assert_true(env.tonemap_white > 1.0, "white point is raised above 1.0")
	assert_eq(env.ambient_light_source, Environment.AMBIENT_SOURCE_COLOR, "ambient is driven by colour so the profile controls it")
	var sun: DirectionalLight3D = _sky.get_node_or_null(_sky.sun_path) as DirectionalLight3D
	var moon: DirectionalLight3D = _sky.get_node_or_null(_sky.moon_path) as DirectionalLight3D
	assert_not_null(sun, "sun_path resolves to a DirectionalLight3D")
	assert_not_null(moon, "moon_path resolves to a DirectionalLight3D")


func test_profiles_load_three_areas_with_enough_keyframes() -> void:
	var profiles: Dictionary = DayNightCycle.load_profiles(DATA)
	for id: StringName in [&"vale", &"wood", &"barrens"]:
		assert_true(profiles.has(id), "daynight.json has a palette for %s" % id)
		if profiles.has(id):
			var p: SkyProfile = profiles[id]
			assert_true(p.keyframe_count() >= 6, "%s has at least 6 keyframes (got %d)" % [id, p.keyframe_count()])
			for hour: float in [0.0, 6.0, 12.0, 18.0, 22.0]:
				assert_true(float(p.sample(hour)["fog_density"]) > 0.0, "%s has fog at %s" % [id, hour])
			assert_true(float(p.sample(12.0)["sun_energy"]) > float(p.sample(0.0)["sun_energy"]), "%s noon sun beats midnight" % id)
			assert_true(float(p.sample(0.0)["ambient_energy"]) > 0.0, "%s midnight is not pitch black" % id)
			assert_true(float(p.sample(0.0)["ambient_energy"]) < float(p.sample(12.0)["ambient_energy"]), "%s night is darker than day" % id)
	assert_true(float(profiles[&"wood"].sample(12.0)["fog_density"]) > float(profiles[&"vale"].sample(12.0)["fog_density"]), "wood is foggier than vale")
	assert_true(float(profiles[&"barrens"].sample(12.0)["fog_density"]) < float(profiles[&"vale"].sample(12.0)["fog_density"]), "barrens is clearer than vale by day")


func test_missing_file_degrades_to_defaults() -> void:
	# Expected to print one ERROR line from push_error; the point is that it returns instead of crashing.
	var profiles: Dictionary = DayNightCycle.load_profiles("res://data/does_not_exist.json")
	assert_true(profiles.is_empty(), "a missing palette file yields no profiles")


func test_ready_sets_start_hour_and_paints() -> void:
	_fresh()
	assert_true(is_equal_approx(_game.time_of_day, _sky.start_hour), "Game clock is set to start_hour on ready")
	assert_true(_game.time_changed.is_connected(_sky._on_time_changed), "cycle listens to Game.time_changed")
	var c: Dictionary = _sky.current()
	assert_true(c.has("fog_density") and c.has("sun_color"), "current() holds the sampled values after ready")


func test_noon_and_midnight_light_states() -> void:
	_fresh()
	var sun: DirectionalLight3D = _sky.get_node(_sky.sun_path) as DirectionalLight3D
	var moon: DirectionalLight3D = _sky.get_node(_sky.moon_path) as DirectionalLight3D
	var env: Environment = (_sky.get_node(_sky.environment_path) as WorldEnvironment).environment
	var sky_mat: ShaderMaterial = env.sky.sky_material as ShaderMaterial
	_game.advance_time(12.0 - _game.time_of_day)
	assert_true(_sky.sun_is_up(), "sun is up at noon")
	assert_true(sun.visible and sun.shadow_enabled, "sun is visible and casts shadows at noon")
	assert_false(moon.visible or moon.shadow_enabled, "moon is hidden and casts nothing at noon")
	assert_true(is_equal_approx(sun.rotation_degrees.x, -90.0), "noon sun points straight down (x=%s)" % sun.rotation_degrees.x)
	var noon: Dictionary = _sky.current()
	assert_true(float(noon["sun_energy"]) > 0.5, "noon sun energy is strong")
	assert_true(is_equal_approx(sun.light_energy, noon["sun_energy"]), "sun light energy follows the profile")
	assert_true(sun.light_color.is_equal_approx(noon["sun_color"]), "sun colour follows the profile")
	assert_true(is_equal_approx(env.fog_density, noon["fog_density"]), "fog density follows the profile")
	assert_true(env.fog_light_color.is_equal_approx(noon["fog_color"]), "fog colour follows the profile")
	assert_true((sky_mat.get_shader_parameter(DayNightCycle.SKY_TOP) as Color).is_equal_approx(noon["sky_top"]), "sky top follows the profile")
	assert_true((sky_mat.get_shader_parameter(DayNightCycle.SKY_HORIZON) as Color).is_equal_approx(noon["sky_horizon"]), "sky horizon follows the profile")
	assert_true(is_equal_approx(env.volumetric_fog_density, float(noon["fog_density"]) * _sky.volumetric_fog_ratio), "volumetric fog follows the profile at the fixed ratio")
	assert_true(is_equal_approx(env.ambient_light_energy, noon["ambient_energy"]), "ambient energy follows the profile")
	_game.advance_time(12.0)
	assert_true(is_equal_approx(_game.time_of_day, 0.0), "clock wrapped to midnight")
	assert_false(_sky.sun_is_up(), "sun is down at midnight")
	assert_false(sun.visible or sun.shadow_enabled, "sun is hidden and casts nothing at midnight")
	assert_true(moon.visible and moon.shadow_enabled, "moon is visible and is the only shadow caster at midnight")
	assert_true(moon.light_energy > 0.0, "moon lights faintly at midnight")
	assert_true(is_equal_approx(sun.light_energy, 0.0), "sun energy is zero at midnight")
	assert_true(env.fog_density > 0.0, "fog persists at night")
	_game.advance_time(6.0)
	assert_false(_sky.sun_is_up(), "06:00 is the horizon, not yet up")
	_game.advance_time(0.5)
	assert_true(_sky.sun_is_up(), "06:30 the sun has risen")
	assert_true(sun.rotation_degrees.x < 0.0 and sun.rotation_degrees.x > -90.0, "a morning sun is low on one side")
	_game.advance_time(11.0)
	assert_true(sun.rotation_degrees.x < -90.0 and sun.rotation_degrees.x > -180.0, "an evening sun is low on the other side")
	_game.advance_time(0.5)
	assert_false(_sky.sun_is_up(), "18:00 the sun has set")


func test_small_ticks_do_not_repaint() -> void:
	_fresh()
	_game.advance_time(4.0)
	var before: Dictionary = _sky.current()
	_game.advance_time(0.004)
	assert_true(_sky.current() == before, "a 0.004 h tick leaves the last sample untouched (same Dictionary)")
	_game.advance_time(0.02)
	assert_false(_sky.current() == before, "a 0.024 h change repaints")


func test_set_area_swaps_palette_immediately() -> void:
	_fresh()
	_game.advance_time(12.0 - _game.time_of_day)
	var vale_fog: float = _sky.current()["fog_density"]
	_sky.set_area(&"wood")
	assert_eq(_sky.area, &"wood", "area export follows set_area")
	assert_true(float(_sky.current()["fog_density"]) > vale_fog, "wood is foggier than vale at noon, applied without a clock tick")
	var env: Environment = (_sky.get_node(_sky.environment_path) as WorldEnvironment).environment
	assert_true(is_equal_approx(env.fog_density, _sky.current()["fog_density"]), "environment fog updated on set_area")
	assert_eq(_sky.area_ids().size(), 3, "three areas are loaded")


func test_headless_probe_steps_through_a_day() -> void:
	var output: Array = []
	var args: PackedStringArray = [
		"--headless", "--path", ProjectSettings.globalize_path("res://"),
		SKYTEST, "--quit-after", PROBE_FRAME_CAP, "--", "--probe",
	]
	var code: int = OS.execute(OS.get_executable_path(), args, output, true)
	var text: String = "\n".join(PackedStringArray(output))
	assert_eq(code, 0, "child headless run of skytest exits cleanly")
	assert_false("SCRIPT ERROR" in text, "child run printed no script errors")
	var lines: Dictionary = {}
	for hour: String in ["0.00", "6.00", "12.00", "18.00", "22.00"]:
		lines[hour] = _probe_line(text, "PROBE hour=%s " % hour)
		assert_true(not lines[hour].is_empty(), "probe printed the %s line" % hour)
	if lines["0.00"].is_empty() or lines["12.00"].is_empty() or lines["22.00"].is_empty():
		return
	assert_true(float(lines["12.00"]["sun_energy"]) > float(lines["0.00"]["sun_energy"]), "noon sun energy beats midnight")
	assert_eq(lines["22.00"]["night"], "true", "22:00 is night")
	assert_eq(lines["0.00"]["night"], "true", "00:00 is night")
	assert_eq(lines["12.00"]["night"], "false", "12:00 is day")
	assert_eq(lines["12.00"]["sun_up"], "true", "sun is up at noon")
	assert_eq(lines["0.00"]["sun_up"], "false", "sun is down at midnight")
	for hour: String in lines.keys():
		if not lines[hour].is_empty():
			assert_true(float(lines[hour]["fog"]) > 0.0, "fog is non-zero at %s" % hour)
	var wood: Dictionary = _probe_line(text, "PROBE area id=wood")
	var vale: Dictionary = _probe_line(text, "PROBE area id=vale")
	assert_true(not wood.is_empty() and not vale.is_empty(), "probe printed the per-area lines")
	if not wood.is_empty() and not vale.is_empty():
		assert_true(float(wood["fog"]) > float(vale["fog"]), "set_area switched to the foggier wood palette in a live tree")


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
