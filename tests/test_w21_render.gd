extends "res://tests/test_case.gd"
## W21-B: the owner called the game "completely pixelated" over his own footage and played Elden Ring as
## the reference. It was aliasing and an empty, over-cooked image, not resolution. These tests pin the
## project settings, the Environment's exposure band, the two fog layers sharing one curve, the cloud
## parameters on the sky shader, and every profile still resolving every key. Each comment says which
## deliberately broken input the assertion catches. Nothing here proves the picture is right: only the
## owner's eyes can.

const SKY := "res://scenes/environment/sky.tscn"
const SKY_SHADER := "res://scripts/systems/sky.gdshader"
const PROJECT := "res://project.godot"
const GAME_SCRIPT := "res://scripts/autoloads/game.gd"
const DATA := "res://data/daynight.json"
const AREAS: Array[StringName] = [&"vale", &"wood", &"barrens"]
const HOURS: Array[float] = [0.0, 4.5, 6.0, 6.75, 9.0, 12.0, 15.0, 18.0, 20.0, 22.0]
## Fog ceiling for the built area: W9-G called classic fog alone a wall at 0.034; W20 found classic +
## volumetric at 0.028 was the same wall. The vale's thickest hour (06:00) now sums to about 0.017.
const VALE_FOG_SUM_MAX := 0.02

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


func _env() -> Environment:
	return (_sky.get_node(_sky.environment_path) as WorldEnvironment).environment


func _mat() -> ShaderMaterial:
	return _env().sky.sky_material as ShaderMaterial


func _jump(hour: float) -> void:
	_game.time_of_day = hour
	_sky._on_time_changed(hour)


func _param_color(name: StringName) -> Color:
	return _mat().get_shader_parameter(name) as Color


func _param_float(name: StringName) -> float:
	return float(_mat().get_shader_parameter(name))


func test_project_turns_on_taa_anisotropy_debanding_and_sharper_shadows() -> void:
	# Both the live setting and the file text: ProjectSettings would fall back to the default silently
	# if the line were deleted from project.godot, and the text check alone would not prove Godot reads it.
	var text: String = FileAccess.get_file_as_string(PROJECT)
	assert_true(text.contains("anti_aliasing/quality/use_taa=true"), "project.godot enables TAA (delete the line: caught)")
	assert_true(bool(ProjectSettings.get_setting("rendering/anti_aliasing/quality/use_taa", false)), "TAA is on at runtime")
	assert_eq(int(ProjectSettings.get_setting("rendering/anti_aliasing/quality/screen_space_aa", 0)), 0,
		"no FXAA on top of TAA (setting screen_space_aa=1 stacks two blurs: caught)")
	assert_eq(int(ProjectSettings.get_setting("rendering/anti_aliasing/quality/msaa_3d", 0)), 2,
		"MSAA 2x stays: alpha-to-coverage on the foliage shaders needs a multisampled target (msaa_3d=0: caught)")
	assert_true(text.contains("anti_aliasing/quality/use_debanding=true"), "debanding is on for the night sky gradient")
	assert_true(int(ProjectSettings.get_setting("rendering/textures/default_filters/anisotropic_filtering_level", 2)) >= 3,
		"anisotropic filtering is 8x or 16x (level 2 = the 4x default: caught)")
	assert_true(text.contains("textures/default_filters/anisotropic_filtering_level="), "the anisotropic level is written in project.godot, not inherited")
	assert_true(int(ProjectSettings.get_setting("rendering/lights_and_shadows/directional_shadow/size", 4096)) >= 8192,
		"directional shadow atlas is at least 8192 for a 260 m reach (4096 default: caught)")
	assert_true(int(ProjectSettings.get_setting("rendering/lights_and_shadows/directional_shadow/soft_shadow_filter_quality", 2)) >= 3,
		"soft shadow filter is Soft Medium or better (Soft Low default: caught)")


func test_environment_has_exposure_control_and_a_sane_tonemap() -> void:
	_fresh()
	var world: WorldEnvironment = _sky.get_node(_sky.environment_path) as WorldEnvironment
	var attrs: CameraAttributesPractical = world.camera_attributes as CameraAttributesPractical
	assert_not_null(attrs, "WorldEnvironment carries a CameraAttributesPractical (remove the node property: caught)")
	if attrs != null:
		assert_true(attrs.exposure_multiplier >= 0.7 and attrs.exposure_multiplier <= 1.3,
			"exposure multiplier is within 0.7..1.3 (%s; 0.5 or 2.0 would re-crush or re-wash: caught)" % attrs.exposure_multiplier)
		assert_false(attrs.auto_exposure_enabled, "auto exposure stays off until the owner has judged a fixed exposure")
	var env: Environment = _env()
	assert_eq(env.tonemap_mode, Environment.TONE_MAPPER_ACES, "tonemapper stays ACES")
	assert_true(env.tonemap_white >= 1.0 and env.tonemap_white <= 2.5,
		"white point is within 1.0..2.5 (%s; the old 4.0 flattened highlights: caught)" % env.tonemap_white)
	var neutral: bool = not env.adjustment_enabled or (env.adjustment_saturation <= 1.05 and env.adjustment_contrast <= 1.05)
	assert_true(neutral, "no saturation or contrast crank on top of ACES (saturation 1.14 made the grass neon: caught)")


func test_both_fog_layers_follow_the_profile_and_stay_thin() -> void:
	_fresh()
	var env: Environment = _env()
	var ratio: float = _sky.volumetric_fog_ratio
	assert_true(ratio >= 0.5 and ratio <= 2.0, "volumetric ratio is within 0.5..2.0 (%s)" % ratio)
	var seen: Array[float] = []
	var worst_sum: float = 0.0
	for hour: float in HOURS:
		_jump(hour)
		var classic: float = float(_sky.current()["fog_density"])
		assert_true(is_equal_approx(env.fog_density, classic), "classic fog follows the profile at %s" % hour)
		assert_true(is_equal_approx(env.volumetric_fog_density, classic * ratio),
			"volumetric fog is classic x ratio at %s (a fixed number in sky.tscn: caught)" % hour)
		assert_true(env.volumetric_fog_density > 0.0, "volumetric fog never drops to zero at %s" % hour)
		worst_sum = maxf(worst_sum, env.fog_density + env.volumetric_fog_density)
		if not seen.has(env.volumetric_fog_density):
			seen.append(env.volumetric_fog_density)
	assert_true(seen.size() >= 3, "volumetric fog takes several values across the day (static: caught; got %d)" % seen.size())
	assert_true(worst_sum <= VALE_FOG_SUM_MAX,
		"vale classic + volumetric never exceeds %.3f at any hour (%.4f; ratio 2.0 or W20's 0.028 pair: caught)" % [VALE_FOG_SUM_MAX, worst_sum])
	# The authored rest value in the scene is the vale-noon value, so the editor preview matches play.
	_jump(12.0)
	var scene: String = FileAccess.get_file_as_string(SKY)
	assert_true(scene.contains("volumetric_fog_density = %.4f" % env.volumetric_fog_density),
		"sky.tscn's volumetric_fog_density equals vale noon x ratio (%.4f)" % env.volumetric_fog_density)


func test_sky_shader_carries_clouds_that_change_with_the_hour() -> void:
	_fresh()
	var mat: ShaderMaterial = _mat()
	assert_not_null(mat, "the sky material is a ShaderMaterial (ProceduralSkyMaterial has no clouds: caught)")
	if mat == null:
		return
	assert_eq(mat.shader.resource_path, SKY_SHADER, "the material uses scripts/systems/sky.gdshader")
	var code: String = mat.shader.code
	assert_true(code.contains("use_half_res_pass"), "clouds are computed in the half-resolution pass")
	assert_true(code.contains("AT_HALF_RES_PASS") and code.contains("HALF_RES_COLOR"), "the full pass composites the half-res cloud layer")
	for name: String in ["cloud_cover", "cloud_color", "cloud_shade", "star_alpha", "sun_angle_max", "sun_curve", "sky_curve"]:
		assert_true(code.contains("uniform float %s" % name) or code.contains("uniform vec3 %s" % name), "the shader declares uniform %s" % name)
	_jump(12.0)
	var noon_cover: float = _param_float(DayNightCycle.CLOUD_COVER)
	var noon_cloud: Color = _param_color(DayNightCycle.CLOUD_COLOR)
	var noon_shade: Color = _param_color(DayNightCycle.CLOUD_SHADE)
	var noon_top: Color = _param_color(DayNightCycle.SKY_TOP)
	var noon_halo: float = _param_float(DayNightCycle.SUN_ANGLE_MAX)
	assert_true(noon_cover >= 0.4 and noon_cover <= 0.8, "vale noon is a soft overcast, not clear and not a lid (%s)" % noon_cover)
	assert_true(noon_cloud.get_luminance() > noon_top.get_luminance(), "noon clouds read brighter than the dome behind them")
	assert_true(noon_shade.get_luminance() < noon_cloud.get_luminance(), "a cloud's core is darker than its lit edge")
	assert_true(is_equal_approx(_param_float(DayNightCycle.STAR_ALPHA), 0.0), "no stars at noon")
	assert_true(noon_halo > 5.0 and noon_halo < 20.0, "noon halo is a soft glow (%s deg)" % noon_halo)
	_jump(0.0)
	var night_cloud: Color = _param_color(DayNightCycle.CLOUD_COLOR)
	assert_false(night_cloud.is_equal_approx(noon_cloud), "cloud colour changes between noon and midnight (a static uniform: caught)")
	assert_true(night_cloud.get_luminance() < 0.08, "midnight clouds are near-black (%.3f; the grey DEFAULTS at night would glow: caught)" % night_cloud.get_luminance())
	assert_true(_param_float(DayNightCycle.STAR_ALPHA) > 0.5, "stars are up at midnight")
	_jump(6.25)
	assert_true(_param_float(DayNightCycle.SUN_ANGLE_MAX) > noon_halo, "the foggy dawn halo is wider than noon (same claim test_ground_cover made of the old material)")
	assert_false(_param_color(DayNightCycle.CLOUD_COLOR).is_equal_approx(noon_cloud), "dawn clouds are not noon clouds")


func test_every_profile_resolves_every_key_including_fallbacks() -> void:
	var profiles: Dictionary = DayNightCycle.load_profiles(DATA)
	assert_eq(profiles.size(), 3, "three areas loaded")
	var keys: Array = SkyProfile.COLOR_KEYS + SkyProfile.FLOAT_KEYS
	for id: StringName in AREAS:
		assert_true(profiles.has(id), "profile %s exists" % id)
		if not profiles.has(id):
			continue
		var p: SkyProfile = profiles[id]
		for hour: float in HOURS:
			var s: Dictionary = p.sample(hour)
			for key: String in keys:
				assert_true(s.has(key), "%s at %s resolves %s (a key missing from DEFAULTS: caught)" % [id, hour, key])
		var night: Dictionary = p.sample(0.0)
		var noon: Dictionary = p.sample(12.0)
		assert_true((night["cloud_color"] as Color).get_luminance() < 0.08, "%s midnight clouds are dark (%.3f)" % [id, (night["cloud_color"] as Color).get_luminance()])
		assert_true((noon["cloud_color"] as Color).get_luminance() > (night["cloud_color"] as Color).get_luminance() * 4.0, "%s clouds are lit by day" % id)
		assert_true((noon["cloud_shade"] as Color).get_luminance() < (noon["cloud_color"] as Color).get_luminance(), "%s cloud cores are darker than edges" % id)
		assert_true(float(noon["cloud_cover"]) > 0.0 and float(noon["cloud_cover"]) <= 1.0, "%s cloud cover is in (0, 1]" % id)
	# wood and barrens never wrote sun_disc_energy / sun_glow_* / sky_curve; they must still fall back.
	for id: StringName in [&"wood", &"barrens"]:
		var s: Dictionary = profiles[id].sample(12.0)
		assert_true(is_equal_approx(float(s["sun_disc_energy"]), SkyProfile.DEFAULTS["sun_disc_energy"]), "%s sun_disc_energy falls back to DEFAULTS" % id)
		assert_true(is_equal_approx(float(s["sky_curve"]), SkyProfile.DEFAULTS["sky_curve"]), "%s sky_curve falls back to DEFAULTS" % id)
	var wood_cover: float = float(profiles[&"wood"].sample(12.0)["cloud_cover"])
	var vale_cover: float = float(profiles[&"vale"].sample(12.0)["cloud_cover"])
	var barrens_cover: float = float(profiles[&"barrens"].sample(12.0)["cloud_cover"])
	assert_true(wood_cover > vale_cover and vale_cover > barrens_cover,
		"the Wood is the most overcast and the Barrens the most open (%s > %s > %s)" % [wood_cover, vale_cover, barrens_cover])
