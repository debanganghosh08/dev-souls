extends "res://tests/test_case.gd"

const FlagsScript := preload("res://scripts/autoloads/flags.gd")
const InventoryScript := preload("res://scripts/autoloads/inventory.gd")
const SaveScript := preload("res://scripts/autoloads/save_game.gd")
const GameScript := preload("res://scripts/autoloads/game.gd")
# Never the real slot: a test run must not be able to destroy the player's save.
const TEST_SLOT := "user://test_save_slot.json"

var flags: Node
var inv: Node
var game: Node
var save: Node


func setup() -> void:
	flags = FlagsScript.new()
	inv = InventoryScript.new()
	inv._load_definitions()
	game = GameScript.new()
	save = SaveScript.new()
	save._inject(flags, inv, game)
	game._inject(save)
	save.use_slot_path(TEST_SLOT)


func teardown() -> void:
	save.delete()
	save.free()
	game.free()
	inv.free()
	flags.free()


func _write_raw(text: String) -> void:
	var f: FileAccess = FileAccess.open(save.slot_path, FileAccess.WRITE)
	f.store_string(text)
	f.close()


func _fill_state() -> void:
	flags.restore([&"kindling_grey_taken", &"met_wick"])
	inv.restore({"torch": 2, "castle_key": 1})
	game.respawn_area = &"wood"
	game.respawn_point = Vector3(1.5, 2.0, -3.25)
	game.player_position = Vector3(10.0, 0.0, 4.0)
	game.time_of_day = 21.5
	game.playtime_seconds = 123.5


func _clear_state() -> void:
	flags.restore([])
	inv.restore({})
	game.respawn_area = &"vale"
	game.respawn_point = Vector3.ZERO
	game.player_position = Vector3.ZERO
	game.time_of_day = 8.0
	game.playtime_seconds = 0.0


func test_no_save_initially() -> void:
	save.delete()
	assert_false(save.has_save(), "no file before saving")
	assert_false(save.load_slot(), "load without file returns false")


func test_save_load_round_trip() -> void:
	_fill_state()
	var saved_count: Array = [0]
	save.saved.connect(func() -> void: saved_count[0] += 1)
	assert_true(save.save(), "save succeeds")
	assert_eq(saved_count[0], 1, "saved emitted")
	assert_true(save.has_save(), "file exists after save")
	assert_false(FileAccess.file_exists(save._tmp_path), "tmp file renamed away")
	_clear_state()
	assert_true(save.load_slot(), "load succeeds")
	assert_eq(flags.all_flags(), [&"kindling_grey_taken", &"met_wick"], "flags restored")
	assert_eq(inv.items(), {&"torch": 2, &"castle_key": 1}, "inventory restored")
	assert_eq(game.respawn_area, &"wood", "respawn area restored")
	assert_eq(game.respawn_point, Vector3(1.5, 2.0, -3.25), "respawn point restored")
	assert_eq(game.player_position, Vector3(10.0, 0.0, 4.0), "player position restored")
	assert_eq(game.time_of_day, 21.5, "time restored")
	assert_eq(game.playtime_seconds, 123.5, "playtime restored")


func test_saved_json_shape() -> void:
	_fill_state()
	save.save()
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(save.slot_path))
	assert_true(data is Dictionary, "save is a JSON object")
	for key: String in ["version", "flags", "inventory", "respawn_area", "respawn_point",
			"player_position", "time_of_day", "playtime_seconds"]:
		assert_true(data.has(key), "save has key " + key)
	assert_eq(int(data["version"]), SaveScript.SAVE_VERSION, "version written")
	assert_eq(data["respawn_point"], {"x": 1.5, "y": 2.0, "z": -3.25}, "vector as xyz dict")


func test_corrupt_file_returns_false_and_keeps_state() -> void:
	_fill_state()
	_write_raw("{\"version\": 1, \"flags\": [\"a\"")
	assert_false(save.load_slot(), "truncated JSON rejected")
	_write_raw("not json at all")
	assert_false(save.load_slot(), "garbage rejected")
	_write_raw("[1, 2, 3]")
	assert_false(save.load_slot(), "non-object rejected")
	_write_raw("{\"version\": 1, \"flags\": \"oops\"}")
	assert_false(save.load_slot(), "missing/mistyped fields rejected")
	assert_eq(flags.all_flags(), [&"kindling_grey_taken", &"met_wick"], "flags untouched")
	assert_eq(inv.count(&"torch"), 2, "inventory untouched")
	assert_eq(game.respawn_area, &"wood", "respawn untouched")
	assert_eq(game.time_of_day, 21.5, "time untouched")


func test_newer_version_returns_false() -> void:
	_fill_state()
	save.save()
	var text: String = FileAccess.get_file_as_string(save.slot_path)
	_write_raw(text.replace("\"version\": 1", "\"version\": %d" % (SaveScript.SAVE_VERSION + 1)))
	_clear_state()
	assert_false(save.load_slot(), "newer version rejected")
	assert_eq(flags.all_flags(), [], "flags untouched after rejected load")
	assert_eq(game.respawn_area, &"vale", "respawn untouched after rejected load")


func test_delete_removes_file() -> void:
	_fill_state()
	save.save()
	save.delete()
	assert_false(save.has_save(), "deleted")
	save.delete()
	assert_false(save.has_save(), "delete twice is harmless")


func test_autosave_is_throttled() -> void:
	_fill_state()
	save.delete()
	save._process(SaveScript.AUTOSAVE_INTERVAL_SEC)
	save.request_autosave()
	save.request_autosave()
	save._process(0.1)
	assert_true(save.has_save(), "first request writes on next frame once the throttle is clear")
	var first: String = FileAccess.get_file_as_string(save.slot_path)
	game.time_of_day = 3.0
	save.request_autosave()
	save._process(1.0)
	assert_eq(FileAccess.get_file_as_string(save.slot_path), first, "second write held within 5 s")
	save._process(SaveScript.AUTOSAVE_INTERVAL_SEC)
	assert_ne(FileAccess.get_file_as_string(save.slot_path), first, "coalesced write lands after 5 s")


func test_set_respawn_requests_autosave() -> void:
	save.delete()
	game.set_respawn(&"barrens", Vector3(7.0, 0.0, 7.0))
	assert_eq(game.respawn_area, &"barrens", "area stored")
	save._process(SaveScript.AUTOSAVE_INTERVAL_SEC + 0.1)
	assert_true(save.has_save(), "shrine triggers an autosave within the throttle interval")


func test_slot_path_can_be_redirected_for_tests() -> void:
	assert_eq(save.slot_path, TEST_SLOT, "setup redirected the slot away from the real save")
	assert_true(save._tmp_path.ends_with(".tmp"), "tmp path derives from the slot path")
	assert_ne(save.slot_path, SaveScript.SAVE_PATH, "test slot is not the player's real slot")


func test_slot_path_outside_user_dir_is_rejected() -> void:
	var before: String = save.slot_path
	save.use_slot_path("res://evil.json")
	assert_eq(save.slot_path, before, "a non-user:// slot path is refused")
	save.use_slot_path("/etc/passwd")
	assert_eq(save.slot_path, before, "an absolute system path is refused")
