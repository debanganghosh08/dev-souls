extends "res://tests/test_case.gd"
## Live interaction tests. Scene structure is checked on out-of-tree instances; detection through the real
## camera, the focus choice and the chest -> lever -> key -> door chain run in a child headless Godot playing
## greybox.tscn with `--probe` (same pattern and parser as tests/test_player.gd).

const GREYBOX := "res://scenes/levels/greybox.tscn"
const PLAYER := "res://scenes/player/player.tscn"
const PROPS_DIR := "res://scenes/props/"
const PROBE_FRAME_CAP := "900"

var _scenes: Array[Node] = []


func _instance(path: String) -> Node:
	var node: Node = (load(path) as PackedScene).instantiate()
	_scenes.append(node)
	return node


func teardown() -> void:
	for node: Node in _scenes:
		node.free()
	_scenes.clear()


func test_player_carries_a_detector_aimed_at_its_camera() -> void:
	var player: Node = _instance(PLAYER)
	var detector: InteractionDetector = player.get_node_or_null("%InteractionDetector") as InteractionDetector
	assert_not_null(detector, "player has a unique InteractionDetector")
	if detector == null:
		return
	assert_eq(detector.collision_layer, 0, "detector is on no layer")
	assert_eq(detector.collision_mask, 4, "detector looks only at the interactable layer")
	assert_false(detector.monitorable, "detector cannot itself be detected")
	var camera: Camera3D = detector.get_node_or_null(detector.camera_path) as Camera3D
	assert_not_null(camera, "camera_path resolves to the player's Camera3D")
	assert_null(detector.current_target(), "no target before anything is near")
	assert_false(detector.try_interact(), "try_interact with no target returns false")


func test_prop_scenes_are_interactables_with_their_named_parts() -> void:
	var expected: Dictionary = {
		"chest": ["%Lid", "%Glow"], "pickup": ["%Glow"], "lore_stone": ["%Glow"],
		"lever": ["%Handle", "%Glow"], "door": ["%Leaf", "%Blocker", "%Glow"],
	}
	for name: String in expected:
		var root: Node = _instance(PROPS_DIR + name + ".tscn")
		var it: Interactable = root as Interactable
		assert_not_null(it, "%s root is an Interactable" % name)
		if it == null:
			continue
		assert_eq(it.collision_layer, 4, "%s sits on the interactable layer" % name)
		assert_eq(it.collision_mask, 0, "%s detects nothing itself" % name)
		assert_not_null(root.get_node_or_null("CollisionShape3D"), "%s has a collision shape" % name)
		for part: String in expected[name]:
			assert_not_null(root.get_node_or_null(part), "%s has %s" % [name, part])
	var door: Door = _instance(PROPS_DIR + "door.tscn") as Door
	var blocker: StaticBody3D = door.get_node_or_null("%Blocker") as StaticBody3D
	assert_eq(blocker.collision_layer, 1, "door blocker is world geometry until opened")


func test_greybox_places_the_demo_props_with_the_real_rules() -> void:
	var level: Node = _instance(GREYBOX)
	var chest: Chest = level.get_node("%KindlingChest") as Chest
	var hammer: Pickup = level.get_node("%HammerPickup") as Pickup
	var grave: LoreStone = level.get_node("%GraveMarker") as LoreStone
	var lever: Lever = level.get_node("%GateLever") as Lever
	var door: Door = level.get_node("%GateDoor") as Door
	var key: Pickup = level.get_node("%KeyPickup") as Pickup
	assert_eq(int(chest.contents.get("kindling_grey", 0)), 1, "chest grants one grey kindling")
	assert_ne(chest.once_flag, &"", "chest has a once_flag")
	assert_eq(hammer.item, &"hammer", "pickup grants the hammer")
	assert_eq(grave.lore_key, "grave_marker", "stone reads the grave marker")
	assert_ne(lever.sets_flag, &"", "lever toggles a flag")
	assert_eq(door.locked_flag, lever.sets_flag, "door is locked until the lever flag")
	assert_eq(door.required_item, &"castle_key", "door needs the castle key")
	assert_eq(key.item, &"castle_key", "second pickup grants the castle key")
	assert_true(key.position.distance_to(door.position) > 5.0, "key lies a little further away than the door")


func test_headless_probe_detects_and_interacts() -> void:
	var output: Array = []
	var args: PackedStringArray = [
		"--headless", "--path", ProjectSettings.globalize_path("res://"),
		GREYBOX, "--quit-after", PROBE_FRAME_CAP, "--", "--probe",
	]
	var code: int = OS.execute(OS.get_executable_path(), args, output, true)
	var text: String = "\n".join(PackedStringArray(output))
	assert_eq(code, 0, "child headless run of greybox exits cleanly")
	assert_false("SCRIPT ERROR" in text, "child run printed no script errors")
	var focus: Dictionary = _probe_line(text, "PROBE focus")
	assert_true(not focus.is_empty(), "probe printed the focus line")
	if not focus.is_empty():
		assert_eq(focus["id"], "greybox_chest", "the detector focused the chest straight ahead")
		assert_eq(focus["prompt"], "Open", "and offers its prompt")
	var chest: Dictionary = _probe_line(text, "PROBE chest")
	assert_true(not chest.is_empty(), "probe printed the chest line")
	if not chest.is_empty():
		assert_eq(chest["opened"], "true", "try_interact opened the focused chest")
		assert_eq(chest["kindling"], "1", "the live Inventory received the kindling")
		assert_eq(chest["spent"], "true", "the live Flags marked the chest spent")
		assert_eq(chest["prompt_after"], "empty", "the opened chest offers no prompt")
	var door: Dictionary = _probe_line(text, "PROBE door")
	assert_true(not door.is_empty(), "probe printed the door line")
	if not door.is_empty():
		assert_eq(door["barred"], "true", "door refused before the lever")
		assert_eq(door["lever_on"], "true", "lever pulled on")
		assert_eq(door["keyless"], "true", "door refused without the key (locked_flag forwarded)")
		assert_eq(door["opened"], "true", "door opened with lever and key")
		assert_eq(door["is_open"], "true", "door reports open")
	for prefix: String in ["PROBE landed", "PROBE stairs", "PROBE pit"]:
		assert_true(not _probe_line(text, prefix).is_empty(), "%s line still printed" % prefix)


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
