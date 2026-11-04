class_name DayNightCycle
extends Node
## Drives Game's clock and paints the world from the active area's SkyProfile: sun/moon lights, the sky
## ShaderMaterial (scripts/systems/sky.gdshader: gradient, halo, clouds, stars), both fog layers and ambient
## on the Environment. Game owns the hour; this node only advances it through Game.advance_time() and reacts
## to Game.time_changed. Palettes come from data/daynight.json.

const DATA_PATH := "res://data/daynight.json"
## Sky shader uniforms written per repaint. Named after the ProceduralSkyMaterial properties they replaced.
const SKY_TOP := &"sky_top_color"
const SKY_HORIZON := &"sky_horizon_color"
const SKY_CURVE := &"sky_curve"
const GROUND_HORIZON := &"ground_horizon_color"
const GROUND_BOTTOM := &"ground_bottom_color"
const SUN_ANGLE_MAX := &"sun_angle_max"
const SUN_CURVE := &"sun_curve"
const CLOUD_COVER := &"cloud_cover"
const CLOUD_COLOR := &"cloud_color"
const CLOUD_SHADE := &"cloud_shade"
const STAR_ALPHA := &"star_alpha"
const FALLBACK_AREA := &"vale"
const HOURS_PER_DAY := 24.0
const SUNRISE_HOUR := 6.0
const DAY_LENGTH_HOURS := 12.0
## Below this change in hours the world is not repainted (see _on_time_changed).
const APPLY_THRESHOLD_HOURS := 0.01

@export var minutes_per_day: float = 20.0
@export var paused: bool = false
@export var area: StringName = &"vale"
## Hour written into Game.time_of_day on _ready. Negative leaves whatever the clock already holds
## (a loaded save, or a previous level) untouched.
@export var start_hour: float = 8.0
@export var environment_path: NodePath
@export var sun_path: NodePath
@export var moon_path: NodePath
## A sky-only DirectionalLight3D (sky_mode SKY_ONLY) that draws the sun disc. The real Sun is LIGHT_ONLY:
## the disc the sky shows is LIGHT_COLOR * LIGHT_ENERGY, and a sun weak enough for this valley (0.7) paints
## a flat grey blob, while a disc bright enough to bloom would over-light the ground. Splitting them lets
## the disc run HDR-bright and small while the scene light stays weak.
@export var sun_disc_path: NodePath
## Fog widens the sun's halo (glow_deg * (1 + fog_density * haze_widen)) and dims the disc
## (disc_energy / (1 + fog_density * haze_dim)): a hazy morning sun is a smear, a clear noon one a point.
@export var haze_widen: float = 12.0
@export var haze_dim: float = 8.0
## Yaw of the sun's arc so noon shadows are not perfectly axis-aligned. 0 = rises on +Z, sets on -Z.
@export var sun_yaw_deg: float = 25.0
## Peak moon light energy, scaled by the profile's star_alpha so a dusk moon is dimmer than a midnight one.
@export var moon_energy: float = 0.12
@export var moon_color: Color = Color(0.62, 0.7, 0.86)
## Volumetric fog density as a multiple of the profile's classic fog_density, so the two layers rise and
## fall together. W20 found them multiplying into a grey wall because one was animated and the other was a
## fixed number in sky.tscn; 1.25 reproduces W20's tuned noon pair (0.0036 classic, 0.0045 volumetric).
@export var volumetric_fog_ratio: float = 1.25

var _game: Node
var _profiles: Dictionary = {}
var _profile: SkyProfile = SkyProfile.new()
var _env: Environment
var _sky_mat: ShaderMaterial
var _sun: DirectionalLight3D
var _moon: DirectionalLight3D
var _sun_disc: DirectionalLight3D
var _current: Dictionary = {}
var _last_hour: float = -1000.0


func _ready() -> void:
	_bind_nodes()
	_profiles = load_profiles(DATA_PATH)
	_profile = _profile_for(area)
	if _game == null and is_inside_tree():
		_inject(get_node_or_null(^"/root/Game"))
	if _game != null:
		if start_hour >= 0.0:
			_game.time_of_day = start_hour
		if not _game.time_changed.is_connected(_on_time_changed):
			_game.time_changed.connect(_on_time_changed)
	_apply(hour())


## Tests run without autoloads; mirrors Game._inject / PlayerController._inject.
func _inject(game: Node) -> void:
	_game = game


func _process(delta: float) -> void:
	if paused or _game == null or minutes_per_day <= 0.0:
		return
	if _game.state != _game.State.PLAYING:
		return
	_game.advance_time(delta * HOURS_PER_DAY / (minutes_per_day * 60.0))


func set_area(new_area: StringName) -> void:
	area = new_area
	_profile = _profile_for(new_area)
	_apply(hour())


func current() -> Dictionary:
	return _current


func hour() -> float:
	return _game.time_of_day if _game != null else fposmod(maxf(start_hour, 0.0), HOURS_PER_DAY)


func sun_is_up() -> bool:
	return _is_above_horizon(_sun_elevation_deg(hour()))


func area_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for key: Variant in _profiles.keys():
		out.append(key)
	return out


static func load_profiles(path: String) -> Dictionary:
	var out: Dictionary = {}
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("DayNightCycle: cannot open %s (%s); using built-in defaults" % [path, error_string(FileAccess.get_open_error())])
		return out
	var json: JSON = JSON.new()
	var err: Error = json.parse(file.get_as_text())
	if err != OK or not (json.data is Dictionary):
		push_error("DayNightCycle: bad JSON in %s line %d: %s" % [path, json.get_error_line(), json.get_error_message()])
		return out
	for key: Variant in (json.data as Dictionary).keys():
		var entry: Variant = json.data[key]
		if entry is Dictionary:
			out[StringName(str(key))] = SkyProfile.from_dict(entry)
	return out


func _bind_nodes() -> void:
	var world: WorldEnvironment = get_node_or_null(environment_path) as WorldEnvironment
	if world != null:
		_env = world.environment
		if _env != null and _env.sky != null:
			_sky_mat = _env.sky.sky_material as ShaderMaterial
	_sun = get_node_or_null(sun_path) as DirectionalLight3D
	_moon = get_node_or_null(moon_path) as DirectionalLight3D
	_sun_disc = get_node_or_null(sun_disc_path) as DirectionalLight3D


func _profile_for(id: StringName) -> SkyProfile:
	if _profiles.has(id):
		return _profiles[id]
	push_warning("DayNightCycle: no palette for area '%s'" % id)
	return _profiles.get(FALLBACK_AREA, SkyProfile.new())


func _on_time_changed(hours: float) -> void:
	# The clock moves a fraction of a minute per frame; repainting every frame would re-sample the profile
	# (a Dictionary allocation) and touch three resources for a change nobody can see. ~0.01 h is a few
	# seconds of real time at the default speed, well under the eye's threshold for a sky gradient.
	if absf(hours - _last_hour) < APPLY_THRESHOLD_HOURS:
		return
	_apply(hours)


func _apply(hours: float) -> void:
	_last_hour = hours
	_current = _profile.sample(hours)
	var elevation: float = _sun_elevation_deg(hours)
	var sun_up: bool = _is_above_horizon(elevation)
	# Existing resources are mutated in place: new Materials/Environments at runtime would recompile shaders
	# and drop the radiance map mid-play.
	if _sun != null:
		_sun.rotation_degrees = Vector3(-elevation, sun_yaw_deg, 0.0)
		_sun.light_color = _current["sun_color"]
		_sun.light_energy = _current["sun_energy"] if sun_up else 0.0
		_sun.visible = sun_up
		_sun.shadow_enabled = sun_up
	if _moon != null:
		_moon.rotation_degrees = Vector3(-(elevation + 180.0), sun_yaw_deg, 0.0)
		_moon.light_color = moon_color
		_moon.light_energy = moon_energy * float(_current["star_alpha"]) if not sun_up else 0.0
		_moon.visible = not sun_up
		_moon.shadow_enabled = not sun_up
	var fog: float = maxf(0.0, float(_current["fog_density"]))
	if _sun_disc != null:
		_sun_disc.rotation_degrees = Vector3(-elevation, sun_yaw_deg, 0.0)
		_sun_disc.light_color = _current["sun_color"]
		_sun_disc.light_energy = float(_current["sun_disc_energy"]) / (1.0 + fog * haze_dim) if sun_up else 0.0
		_sun_disc.visible = sun_up
	if _sky_mat != null:
		_sky_mat.set_shader_parameter(SKY_TOP, _current["sky_top"])
		_sky_mat.set_shader_parameter(SKY_HORIZON, _current["sky_horizon"])
		_sky_mat.set_shader_parameter(GROUND_HORIZON, _current["fog_color"])
		_sky_mat.set_shader_parameter(GROUND_BOTTOM, _current["ground_color"])
		_sky_mat.set_shader_parameter(SKY_CURVE, maxf(0.01, float(_current["sky_curve"])))
		_sky_mat.set_shader_parameter(SUN_ANGLE_MAX, clampf(float(_current["sun_glow_deg"]) * (1.0 + fog * haze_widen), 1.0, 90.0))
		_sky_mat.set_shader_parameter(SUN_CURVE, maxf(0.01, float(_current["sun_glow_curve"])))
		_sky_mat.set_shader_parameter(CLOUD_COVER, clampf(float(_current["cloud_cover"]), 0.0, 1.0))
		_sky_mat.set_shader_parameter(CLOUD_COLOR, _current["cloud_color"])
		_sky_mat.set_shader_parameter(CLOUD_SHADE, _current["cloud_shade"])
		_sky_mat.set_shader_parameter(STAR_ALPHA, clampf(float(_current["star_alpha"]), 0.0, 1.0))
	if _env != null:
		_env.fog_light_color = _current["fog_color"]
		_env.fog_density = fog
		# Same curve, fixed ratio: there is one haze knob per hour, not two that can drift apart.
		_env.volumetric_fog_density = fog * maxf(0.0, volumetric_fog_ratio)
		_env.ambient_light_color = _current["sky_horizon"]
		_env.ambient_light_energy = _current["ambient_energy"]


## 0 at sunrise (06:00), 90 overhead at noon, 180 at sunset (18:00), on round to 360 through the night.
func _sun_elevation_deg(hours: float) -> float:
	return fposmod(hours - SUNRISE_HOUR, HOURS_PER_DAY) / DAY_LENGTH_HOURS * 180.0


static func _is_above_horizon(elevation_deg: float) -> bool:
	return elevation_deg > 0.0 and elevation_deg < 180.0
