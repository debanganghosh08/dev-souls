extends "res://tests/test_case.gd"
## UI layer. Structure and text are checked in-process; the live flow (menu -> journey -> death) runs in a
## child headless Godot playing main.tscn with `--probe`, on a throwaway save slot, and prints PROBE lines.

const MAIN := "res://scenes/main/main.tscn"
const PROBE_FRAME_CAP := "900"
const REQUIRED_TEXT_KEYS: Array[String] = [
	"title", "subtitle", "continue", "new_journey", "settings", "quit", "confirm_unmake", "begin_anew",
	"keep", "loading", "you_faded", "resume", "save_and_quit", "prompt_format", "acquired",
	"acquired_amount", "lore_dismiss", "settings_title", "master_volume", "music_volume", "sfx_volume",
	"mouse_sensitivity", "invert_y", "fullscreen", "vsync", "fps_cap", "fps_unlimited", "reset_defaults", "back",
]


func test_ui_text_file_has_every_key_and_matches_defaults_keys() -> void:
	var json := JSON.new()
	assert_eq(json.parse(FileAccess.get_file_as_string(UiText.PATH)), OK, "data/ui_text.json parses")
	var table: Dictionary = json.data if json.data is Dictionary else {}
	for key: String in REQUIRED_TEXT_KEYS:
		assert_true(table.has(key) and table[key] is String and table[key] != "",
			"ui_text.json has a non-empty '%s'" % key)
		assert_true(UiText.DEFAULTS.has(key), "built-in fallback covers '%s'" % key)
	assert_false("FromSoftware" in UiText.text("you_faded") or UiText.text("you_faded") == "YOU DIED",
		"death text is our own wording")


func test_ui_text_falls_back_when_file_is_missing() -> void:
	UiText.reload_from("user://does_not_exist_ui_text.json")
	assert_eq(UiText.text("resume"), UiText.DEFAULTS["resume"], "missing file falls back to built-in English")
	assert_eq(UiText.text("no_such_key"), "no_such_key", "an unknown key returns the key, never blank")
	UiText.reload_from()
	assert_ne(UiText.text("title"), "", "real file reloaded")


func test_scenes_instantiate_with_expected_nodes() -> void:
	var hud: Node = (load("res://scenes/ui/hud.tscn") as PackedScene).instantiate()
	assert_true(hud is CanvasLayer, "HUD root is a CanvasLayer")
	for name: String in ["%StaminaBar", "%Prompt", "%Refusal", "%Toasts", "%LoreCard"]:
		assert_not_null(hud.get_node_or_null(name), "HUD has %s" % name)
	hud.free()
	var death: Node = (load("res://scenes/ui/death_screen.tscn") as PackedScene).instantiate()
	assert_true(death is CanvasLayer and not death.visible, "death screen is a hidden CanvasLayer")
	assert_eq(death.process_mode, Node.PROCESS_MODE_ALWAYS, "death screen runs while paused")
	death.free()
	var pause: Node = (load("res://scenes/ui/pause_menu.tscn") as PackedScene).instantiate()
	assert_eq(pause.process_mode, Node.PROCESS_MODE_ALWAYS, "pause menu runs while paused")
	assert_not_null(pause.get_node_or_null("%SettingsPanel"), "pause menu embeds the settings panel")
	pause.free()
	var menu: Node = (load("res://scenes/ui/main_menu.tscn") as PackedScene).instantiate()
	for name: String in ["%Continue", "%NewJourney", "%SettingsButton", "%Quit", "%Confirm", "%SettingsPanel"]:
		assert_not_null(menu.get_node_or_null(name), "main menu has %s" % name)
	menu.free()
	var main: Node = (load(MAIN) as PackedScene).instantiate()
	for name: String in ["%MainMenu", "%LevelRoot", "%Overlays", "%Loading"]:
		assert_not_null(main.get_node_or_null(name), "main has %s" % name)
	main.free()


func test_player_scene_is_in_the_player_group() -> void:
	var player: Node = (load("res://scenes/player/player.tscn") as PackedScene).instantiate()
	assert_true(player.is_in_group(&"player"), "player.tscn root is in group 'player' so the HUD can find it")
	player.free()


func test_main_scene_is_the_project_entry_point() -> void:
	assert_eq(ProjectSettings.get_setting("application/run/main_scene"), MAIN, "project boots into main.tscn")


func test_headless_probe_menu_journey_and_death() -> void:
	var output: Array = []
	var args: PackedStringArray = [
		"--headless", "--path", ProjectSettings.globalize_path("res://"),
		MAIN, "--quit-after", PROBE_FRAME_CAP, "--", "--probe",
	]
	var code: int = OS.execute(OS.get_executable_path(), args, output, true)
	var text: String = "\n".join(PackedStringArray(output))
	assert_eq(code, 0, "child headless run of main exits cleanly")
	assert_false("SCRIPT ERROR" in text, "child run printed no script errors")
	var menu: Dictionary = _probe_line(text, "PROBE menu")
	assert_true(not menu.is_empty(), "probe printed the menu line")
	if not menu.is_empty():
		assert_eq(menu["state"], "MENU", "the title screen puts Game into MENU")
		assert_eq(menu["continue_enabled"], "false", "Continue is disabled on a fresh slot")
	var ingame: Dictionary = _probe_line(text, "PROBE ingame")
	assert_true(not ingame.is_empty(), "probe printed the ingame line")
	if not ingame.is_empty():
		assert_eq(ingame["level"], "true", "the level is in the tree after New Journey")
		assert_eq(ingame["hud"], "true", "the HUD is in the tree after New Journey")
		assert_eq(ingame["state"], "PLAYING", "a new journey reaches PLAYING")
	var death: Dictionary = _probe_line(text, "PROBE death")
	assert_true(not death.is_empty(), "probe printed the death line")
	if not death.is_empty():
		assert_eq(death["veil"], "true", "the death veil is showing after kill_player")
		assert_eq(death["state"], "DEAD", "killing the player reaches DEAD")
	assert_false(FileAccess.file_exists("user://probe_ui_slot.json"), "the probe removed its throwaway slot")


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
