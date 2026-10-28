extends "res://tests/test_case.gd"
## Overlays: main.tscn's probe, extended past menu -> journey -> death with the inventory panel, the
## first-acquisition card and weapon switching through the real Melee, all driven by injected input actions
## in a child headless Godot. The three original PROBE lines must keep printing first and unchanged.

const MAIN := "res://scenes/main/main.tscn"
const PROBE_FRAME_CAP := "1200"
const ORIGINAL_PROBES: Array[String] = ["PROBE menu", "PROBE ingame", "PROBE death"]
const NEW_PROBES: Array[String] = ["PROBE inventory", "PROBE itemcard", "PROBE equip", "PROBE ending"]


func test_main_scene_carries_the_item_card_layer_between_hud_and_pause() -> void:
	var main: Node = (load(MAIN) as PackedScene).instantiate()
	var layer: CanvasLayer = main.get_node_or_null("%ItemCardLayer") as CanvasLayer
	assert_not_null(layer, "main has %ItemCardLayer for the acquisition card")
	main.free()
	var panel: CanvasLayer = (load("res://scenes/ui/inventory_panel.tscn") as PackedScene).instantiate() as CanvasLayer
	var pause: CanvasLayer = (load("res://scenes/ui/pause_menu.tscn") as PackedScene).instantiate() as CanvasLayer
	var death: CanvasLayer = (load("res://scenes/ui/death_screen.tscn") as PackedScene).instantiate() as CanvasLayer
	if layer != null:
		assert_true(layer.layer > 1 and layer.layer < pause.layer, "item card draws above the HUD and below the pause menu")
	assert_true(panel.layer > 1 and panel.layer < pause.layer, "inventory draws above the HUD and below the pause menu")
	assert_true(panel.layer > death.layer, "inventory draws above the death veil")
	panel.free()
	pause.free()
	death.free()


func test_ui_text_has_every_inventory_and_card_key() -> void:
	var json := JSON.new()
	assert_eq(json.parse(FileAccess.get_file_as_string(UiText.PATH)), OK, "data/ui_text.json parses")
	var table: Dictionary = json.data if json.data is Dictionary else {}
	for key: String in [
		"inventory_title", "inventory_progress", "kindling_progress", "unknown_item", "not_yet_found", "row_count",
		"count_line", "kind_kindling", "kind_fragment", "kind_key", "kind_tool", "kind_lore", "equip", "equipped",
		"inventory_hint", "item_card_hint", "kind_garment",
	]:
		assert_true(table.has(key) and table[key] is String and table[key] != "", "ui_text.json has '%s'" % key)
		assert_true(UiText.DEFAULTS.has(key), "built-in fallback covers '%s'" % key)


func test_items_json_gained_slot_and_order_without_losing_anything() -> void:
	var json := JSON.new()
	assert_eq(json.parse(FileAccess.get_file_as_string("res://data/items.json")), OK, "items.json parses")
	var table: Dictionary = json.data
	var items: int = 0
	for id: String in table:
		if table[id] is Dictionary:
			items += 1
	assert_eq(items, 38, "exactly 38 items (13, plus the 20 W8-H house items, plus the four W9-C garments and the spear)")
	var weapons: Array[String] = []
	for id: String in table:
		if not table[id] is Dictionary:
			continue
		var entry: Dictionary = table[id]
		for key: String in ["name", "kind", "lore", "slot", "order"]:
			assert_true(entry.has(key), "%s has '%s'" % [id, key])
		if entry.get("slot", "") == "weapon":
			weapons.append(id)
	weapons.sort()
	assert_eq(weapons, ["hammer", "spear", "sword", "torch"], "exactly the four melee weapons carry the weapon slot")


func test_headless_probe_opens_inventory_shows_the_card_and_equips() -> void:
	var output: Array = []
	var args: PackedStringArray = [
		"--headless", "--path", ProjectSettings.globalize_path("res://"),
		MAIN, "--quit-after", PROBE_FRAME_CAP, "--", "--probe",
	]
	var code: int = OS.execute(OS.get_executable_path(), args, output, true)
	var text: String = "\n".join(PackedStringArray(output))
	assert_eq(code, 0, "child headless run of main exits cleanly")
	assert_false("SCRIPT ERROR" in text, "child run printed no script errors")
	var last: int = -1
	for prefix: String in ORIGINAL_PROBES + NEW_PROBES:
		var at: int = text.find(prefix)
		assert_true(at >= 0, "%s printed" % prefix)
		assert_true(at > last, "%s keeps its place: originals first, new lines after" % prefix)
		last = maxi(last, at)
	var inventory: Dictionary = _probe_line(text, "PROBE inventory")
	if not inventory.is_empty():
		assert_eq(inventory["open"], "true", "an injected Tab opened the inventory panel")
		assert_eq(inventory["state"], "PAUSED", "the open panel holds PAUSED")
		assert_eq(inventory["rows"], "38", "every known item has a row")
		assert_eq(inventory["unknown"], "38", "a fresh journey holds nothing: all silhouettes")
	var card: Dictionary = _probe_line(text, "PROBE itemcard")
	if not card.is_empty():
		assert_eq(card["shown"], "true", "the first hammer showed its card")
		assert_eq(card["id"], "hammer", "the card is the hammer's")
		assert_eq(card["pending"], "1", "the torch waits behind it")
		assert_eq(card["state"], "PAUSED", "the card holds PAUSED")
	var equip: Dictionary = _probe_line(text, "PROBE equip")
	if not equip.is_empty():
		assert_eq(equip["ok"], "true", "equipping the torch through the real Melee succeeded")
		assert_eq(equip["weapon"], "Torch", "Melee reports the torch (auto-equip had chosen the hammer)")
		assert_eq(equip["state"], "PLAYING", "every overlay released the state by the end")
	var ending: Dictionary = _probe_line(text, "PROBE ending")
	if not ending.is_empty():
		assert_eq(ending["shown"], "true", "Game.end_journey raised the ending card")
		assert_eq(ending["which"], str(Hearth.Ending.REKINDLE), "it is the ending that was reached")
		assert_eq(ending["title"], "true", "the card resolved real words, not a bare key")
		assert_eq(ending["state"], "PAUSED", "the card holds the screen while it is up")
		assert_eq(ending["over"], "true", "the run is recorded as over")
		# The lockout is the point: the key still held from using the Hearth must not skip the last beat.
		assert_eq(ending["locked"], "true", "the card refuses input the instant it appears")
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
