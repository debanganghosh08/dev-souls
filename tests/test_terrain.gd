extends "res://tests/test_case.gd"
## Terrain tests. The runner has no scene tree or autoloads, so the live terrain (chunk streaming, LOD
## nodes, near-player collision, the player settling on the ground) runs in a child headless Godot that
## plays vale.tscn with `--probe` and prints machine-readable PROBE lines.

const VALE_SCENE := "res://scenes/levels/vale.tscn"
const VALE_DATA := "res://data/areas/vale.json"
const PROBE_FRAME_CAP := "1800"

var _text: String = ""
var _code: int = -1


func setup() -> void:
	var output: Array = []
	var args: PackedStringArray = [
		"--headless", "--path", ProjectSettings.globalize_path("res://"),
		VALE_SCENE, "--quit-after", PROBE_FRAME_CAP, "--", "--probe",
	]
	_code = OS.execute(OS.get_executable_path(), args, output, true)
	_text = "\n".join(PackedStringArray(output))


func test_child_run_is_clean() -> void:
	assert_eq(_code, 0, "child headless run of the vale exits cleanly")
	assert_false("SCRIPT ERROR" in _text, "child run printed no script errors")
	assert_false("SHADER ERROR" in _text, "the terrain shader parsed")


func test_terrain_builds_every_chunk_and_collides_near_the_player() -> void:
	var line: Dictionary = _probe_line(_text, "PROBE terrain ")
	assert_true(not line.is_empty(), "probe printed the terrain line")
	if line.is_empty():
		return
	var json := JSON.new()
	json.parse(FileAccess.get_file_as_string(VALE_DATA))
	var per_side: int = roundi(float(json.data["size"]) / float(line["chunk_size"]))
	assert_eq(int(line["chunks"]), per_side * per_side, "chunk count matches area size over chunk size")
	assert_eq(line["built"], "true", "the full build completed inside the probe window")
	assert_true(int(line["build_ms"]) >= 0, "build time was measured")
	assert_true(int(line["collision_chunks"]) > 0, "collision exists near the player")
	assert_true(int(line["collision_chunks"]) < int(line["chunks"]), "collision is not built for every chunk")
	assert_true(int(line["lod_levels"]) >= 2, "more than one LOD level per chunk")
	assert_eq(line["winding_up"], "true", "chunk triangles face upward")


func test_heightfield_in_the_live_scene() -> void:
	var line: Dictionary = _probe_line(_text, "PROBE heightfield ")
	assert_true(not line.is_empty(), "probe printed the heightfield line")
	if line.is_empty():
		return
	assert_true(float(line["pond_depth"]) > 1.0, "pond centre is under water (depth %s)" % line["pond_depth"])
	assert_true(float(line["ridge_height"]) > 30.0, "ridge rises above the floor (%s)" % line["ridge_height"])
	assert_eq(line["village_flat"], "true", "village plateau is flat")
	assert_eq(line["castle_flat"], "true", "castle plateau is flat")
	assert_eq(line["deterministic"], "true", "a second heightfield from the same data matches")


func test_spawn_is_walkable_and_player_settles() -> void:
	var line: Dictionary = _probe_line(_text, "PROBE spawn ")
	assert_true(not line.is_empty(), "probe printed the spawn line")
	if line.is_empty():
		return
	assert_eq(line["walkable"], "true", "spawn point is walkable")
	assert_eq(line["settled"], "true", "player settled on the terrain surface (y %s, ground %s)" % [line["y"], line["ground"]])
	assert_true(float(line["y"]) >= float(line["ground"]) - 0.5, "player did not fall through the ground")


func test_forest_and_dressing_sit_on_the_ground() -> void:
	var forest: Dictionary = _probe_line(_text, "PROBE forest ")
	assert_true(not forest.is_empty(), "probe printed the forest line")
	if not forest.is_empty():
		assert_true(int(forest["trees"]) > 0, "trees were placed")
		assert_eq(forest["on_ground"], "true", "every tree sits on the terrain")
	var dressing: Dictionary = _probe_line(_text, "PROBE dressing ")
	assert_true(not dressing.is_empty(), "probe printed the dressing line")
	if not dressing.is_empty():
		assert_true(int(dressing["instances"]) > 0, "dressing placed props")


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
