extends RefCounted
class_name GameSettings
## Player options persisted to user://settings.cfg. Not an autoload: main.gd owns one instance and hands it
## to the settings panel. Every value is clamped on load so a hand-edited file cannot break the game.

const DEFAULT_PATH := "user://settings.cfg"
const SECTION := "settings"
const SENSITIVITY_MIN := 0.0005
const SENSITIVITY_MAX := 0.02
const FPS_CAP_MAX := 480
const FPS_CAP_UNLIMITED := 0
const SILENT_LINEAR := 0.0001

var path: String = DEFAULT_PATH
var mouse_sensitivity: float = 0.0025
var invert_y: bool = false
var master_volume: float = 0.8
var music_volume: float = 0.7
var sfx_volume: float = 0.8
var fullscreen: bool = false
var fps_cap: int = 60
var vsync: bool = true


static func load_settings(from_path: String = DEFAULT_PATH) -> GameSettings:
	var settings := GameSettings.new()
	settings.path = from_path
	var cfg := ConfigFile.new()
	if not FileAccess.file_exists(from_path):
		return settings
	var err: Error = cfg.load(from_path)
	if err != OK:
		push_warning("GameSettings: %s unreadable (%s), using defaults" % [from_path, error_string(err)])
		return settings
	settings.mouse_sensitivity = _read_float(cfg, "mouse_sensitivity", settings.mouse_sensitivity,
		SENSITIVITY_MIN, SENSITIVITY_MAX)
	settings.invert_y = _read_bool(cfg, "invert_y", settings.invert_y)
	settings.master_volume = _read_float(cfg, "master_volume", settings.master_volume, 0.0, 1.0)
	settings.music_volume = _read_float(cfg, "music_volume", settings.music_volume, 0.0, 1.0)
	settings.sfx_volume = _read_float(cfg, "sfx_volume", settings.sfx_volume, 0.0, 1.0)
	settings.fullscreen = _read_bool(cfg, "fullscreen", settings.fullscreen)
	settings.fps_cap = _read_int(cfg, "fps_cap", settings.fps_cap, FPS_CAP_UNLIMITED, FPS_CAP_MAX)
	settings.vsync = _read_bool(cfg, "vsync", settings.vsync)
	return settings


func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value(SECTION, "mouse_sensitivity", mouse_sensitivity)
	cfg.set_value(SECTION, "invert_y", invert_y)
	cfg.set_value(SECTION, "master_volume", master_volume)
	cfg.set_value(SECTION, "music_volume", music_volume)
	cfg.set_value(SECTION, "sfx_volume", sfx_volume)
	cfg.set_value(SECTION, "fullscreen", fullscreen)
	cfg.set_value(SECTION, "fps_cap", fps_cap)
	cfg.set_value(SECTION, "vsync", vsync)
	var err: Error = cfg.save(path)
	if err != OK:
		push_error("GameSettings: cannot save %s (%s)" % [path, error_string(err)])


func reset_to_defaults() -> void:
	var fresh := GameSettings.new()
	mouse_sensitivity = fresh.mouse_sensitivity
	invert_y = fresh.invert_y
	master_volume = fresh.master_volume
	music_volume = fresh.music_volume
	sfx_volume = fresh.sfx_volume
	fullscreen = fresh.fullscreen
	fps_cap = fresh.fps_cap
	vsync = fresh.vsync


## Pushes the values into the engine. Creates nothing: a missing audio bus is skipped quietly, and a headless
## run (no window) touches neither the window mode nor vsync.
func apply() -> void:
	Engine.max_fps = fps_cap
	_apply_bus("Master", master_volume)
	_apply_bus("Music", music_volume)
	_apply_bus("SFX", sfx_volume)
	if UiUtil.is_headless():
		return
	var mode: DisplayServer.WindowMode = DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen \
		else DisplayServer.WINDOW_MODE_WINDOWED
	if DisplayServer.window_get_mode() != mode:
		DisplayServer.window_set_mode(mode)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED)


func _apply_bus(bus_name: String, linear: float) -> void:
	var index: int = AudioServer.get_bus_index(bus_name)
	if index < 0:
		return
	AudioServer.set_bus_volume_db(index, linear_to_db(maxf(linear, SILENT_LINEAR)))


static func _read_float(cfg: ConfigFile, key: String, fallback: float, lo: float, hi: float) -> float:
	var raw: Variant = cfg.get_value(SECTION, key, fallback)
	if typeof(raw) != TYPE_FLOAT and typeof(raw) != TYPE_INT:
		return fallback
	var value: float = float(raw)
	if is_nan(value):
		return fallback
	return clampf(value, lo, hi)


static func _read_int(cfg: ConfigFile, key: String, fallback: int, lo: int, hi: int) -> int:
	var raw: Variant = cfg.get_value(SECTION, key, fallback)
	if typeof(raw) != TYPE_FLOAT and typeof(raw) != TYPE_INT:
		return fallback
	return clampi(int(raw), lo, hi)


static func _read_bool(cfg: ConfigFile, key: String, fallback: bool) -> bool:
	var raw: Variant = cfg.get_value(SECTION, key, fallback)
	if typeof(raw) != TYPE_BOOL:
		return fallback
	return raw
