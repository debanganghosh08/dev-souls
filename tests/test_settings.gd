extends "res://tests/test_case.gd"
## GameSettings is pure (RefCounted + ConfigFile), so it is exercised directly on a throwaway file.

const TEST_PATH := "user://test_settings.cfg"


func teardown() -> void:
	_remove()


func _remove() -> void:
	if FileAccess.file_exists(TEST_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH))


func _write_raw(text: String) -> void:
	var file: FileAccess = FileAccess.open(TEST_PATH, FileAccess.WRITE)
	file.store_string(text)
	file.close()


func test_defaults_are_sane() -> void:
	var s := GameSettings.new()
	assert_true(s.mouse_sensitivity > 0.0 and s.mouse_sensitivity < 0.01, "sensitivity default is a small positive")
	assert_false(s.invert_y, "invert_y defaults off")
	assert_true(s.master_volume > 0.0 and s.master_volume <= 1.0, "master volume audible and in range")
	assert_true(s.music_volume > 0.0 and s.music_volume <= 1.0, "music volume audible and in range")
	assert_true(s.sfx_volume > 0.0 and s.sfx_volume <= 1.0, "sfx volume audible and in range")
	assert_false(s.fullscreen, "windowed by default")
	assert_eq(s.fps_cap, 60, "fps cap defaults to 60")
	assert_true(s.vsync, "vsync on by default")
	assert_eq(s.path, GameSettings.DEFAULT_PATH, "a bare instance points at the real settings file")


func test_missing_file_loads_defaults() -> void:
	_remove()
	var s: GameSettings = GameSettings.load_settings(TEST_PATH)
	var fresh := GameSettings.new()
	assert_eq(s.path, TEST_PATH, "load_settings keeps the path it was given")
	assert_eq(s.fps_cap, fresh.fps_cap, "no file means defaults")
	assert_true(is_equal_approx(s.master_volume, fresh.master_volume), "no file means default volume")


func test_save_then_load_round_trips_every_field() -> void:
	_remove()
	var s: GameSettings = GameSettings.load_settings(TEST_PATH)
	s.mouse_sensitivity = 0.004
	s.invert_y = true
	s.master_volume = 0.35
	s.music_volume = 0.1
	s.sfx_volume = 0.55
	s.fullscreen = true
	s.fps_cap = 144
	s.vsync = false
	s.save_settings()
	assert_true(FileAccess.file_exists(TEST_PATH), "save wrote the file")
	var back: GameSettings = GameSettings.load_settings(TEST_PATH)
	assert_true(is_equal_approx(back.mouse_sensitivity, 0.004), "sensitivity round-trips")
	assert_true(back.invert_y, "invert_y round-trips")
	assert_true(is_equal_approx(back.master_volume, 0.35), "master volume round-trips")
	assert_true(is_equal_approx(back.music_volume, 0.1), "music volume round-trips")
	assert_true(is_equal_approx(back.sfx_volume, 0.55), "sfx volume round-trips")
	assert_true(back.fullscreen, "fullscreen round-trips")
	assert_eq(back.fps_cap, 144, "fps cap round-trips")
	assert_false(back.vsync, "vsync round-trips")


func test_out_of_range_values_are_clamped_on_load() -> void:
	_remove()
	var cfg := ConfigFile.new()
	cfg.set_value(GameSettings.SECTION, "master_volume", -0.5)
	cfg.set_value(GameSettings.SECTION, "music_volume", 7.0)
	cfg.set_value(GameSettings.SECTION, "sfx_volume", 1.5)
	cfg.set_value(GameSettings.SECTION, "fps_cap", -5)
	cfg.set_value(GameSettings.SECTION, "mouse_sensitivity", 900.0)
	cfg.save(TEST_PATH)
	var s: GameSettings = GameSettings.load_settings(TEST_PATH)
	assert_true(is_zero_approx(s.master_volume), "negative volume clamps to silent")
	assert_true(is_equal_approx(s.music_volume, 1.0), "volume above 1 clamps to full")
	assert_true(is_equal_approx(s.sfx_volume, 1.0), "sfx volume above 1 clamps to full")
	assert_true(s.fps_cap >= 0, "negative fps cap clamps to a non-negative value (got %d)" % s.fps_cap)
	assert_true(s.mouse_sensitivity <= GameSettings.SENSITIVITY_MAX,
		"absurd sensitivity clamps to the ceiling (got %f)" % s.mouse_sensitivity)
	assert_true(s.mouse_sensitivity >= GameSettings.SENSITIVITY_MIN, "sensitivity never below the floor")


func test_wrong_types_fall_back_to_defaults() -> void:
	_remove()
	var cfg := ConfigFile.new()
	cfg.set_value(GameSettings.SECTION, "master_volume", "loud")
	cfg.set_value(GameSettings.SECTION, "invert_y", 3)
	cfg.set_value(GameSettings.SECTION, "fps_cap", "fast")
	cfg.save(TEST_PATH)
	var s: GameSettings = GameSettings.load_settings(TEST_PATH)
	var fresh := GameSettings.new()
	assert_true(is_equal_approx(s.master_volume, fresh.master_volume), "a string volume falls back to default")
	assert_eq(s.invert_y, fresh.invert_y, "a numeric bool falls back to default")
	assert_eq(s.fps_cap, fresh.fps_cap, "a string fps cap falls back to default")


func test_garbage_file_falls_back_to_defaults_without_crashing() -> void:
	_remove()
	_write_raw("{{{{ this is not a config file ]]]] = = =\n[unterminated\nkey = = value\n")
	var s: GameSettings = GameSettings.load_settings(TEST_PATH)
	var fresh := GameSettings.new()
	assert_not_null(s, "garbage still yields an instance")
	assert_eq(s.fps_cap, fresh.fps_cap, "garbage file means default fps cap")
	assert_true(is_equal_approx(s.mouse_sensitivity, fresh.mouse_sensitivity), "garbage file means default sensitivity")
	assert_eq(s.vsync, fresh.vsync, "garbage file means default vsync")


func test_reset_to_defaults_restores_every_field() -> void:
	var s := GameSettings.new()
	s.mouse_sensitivity = 0.01
	s.invert_y = true
	s.master_volume = 0.0
	s.music_volume = 0.0
	s.sfx_volume = 0.0
	s.fullscreen = true
	s.fps_cap = 0
	s.vsync = false
	s.reset_to_defaults()
	var fresh := GameSettings.new()
	assert_true(is_equal_approx(s.mouse_sensitivity, fresh.mouse_sensitivity), "sensitivity reset")
	assert_eq(s.invert_y, fresh.invert_y, "invert_y reset")
	assert_true(is_equal_approx(s.master_volume, fresh.master_volume), "master volume reset")
	assert_true(is_equal_approx(s.music_volume, fresh.music_volume), "music volume reset")
	assert_true(is_equal_approx(s.sfx_volume, fresh.sfx_volume), "sfx volume reset")
	assert_eq(s.fullscreen, fresh.fullscreen, "fullscreen reset")
	assert_eq(s.fps_cap, fresh.fps_cap, "fps cap reset")
	assert_eq(s.vsync, fresh.vsync, "vsync reset")


func test_apply_is_safe_headless_and_sets_fps_cap() -> void:
	var s := GameSettings.new()
	s.fps_cap = 120
	var before: int = Engine.max_fps
	s.apply()
	assert_eq(Engine.max_fps, 120, "apply pushes the fps cap into the engine")
	Engine.max_fps = before
