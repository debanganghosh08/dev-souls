extends "res://tests/test_case.gd"
## Terrain tests. The runner has no scene tree or autoloads, so the live terrain (chunk streaming, LOD
## nodes, near-player collision, the player settling on the ground) runs in a child headless Godot that
## plays vale.tscn with `--probe` and prints machine-readable PROBE lines.

const VALE_SCENE := "res://scenes/levels/vale.tscn"
const VALE_DATA := "res://data/areas/vale.json"
const PROBE_FRAME_CAP := "1800"

var _text: String = ""
var _code: int = -1
var _drained_text: String = ""
var _drained_code: int = -1


func setup() -> void:
	_code = _run(false)
	_text = _last_text
	# A second child run with the pond already drained. This costs another terrain build, and it is worth it:
	# draining is the single gate on the whole endgame, and the branch that hides the water is only reachable
	# this way. "It is only three lines" is how the crypt floor came to have a hole in it.
	_drained_code = _run(true)
	_drained_text = _last_text


var _last_text: String = ""


func _run(drained: bool) -> int:
	var output: Array = []
	var args: PackedStringArray = [
		"--headless", "--path", ProjectSettings.globalize_path("res://"),
		VALE_SCENE, "--quit-after", PROBE_FRAME_CAP, "--", "--probe",
	]
	if drained:
		args.append("--probe-drained")
	var code: int = OS.execute(OS.get_executable_path(), args, output, true)
	_last_text = "\n".join(PackedStringArray(output))
	return code


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


func test_terrain_build_cost_is_split_by_phase() -> void:
	# CPU side only. build_ms is wall-clock across the budgeted frames, so the phases must fit inside it,
	# and sampling plus meshing inside the chunk total; collision is per near chunk and so small but not zero.
	var line: Dictionary = _probe_line(_text, "PROBE cost ")
	assert_true(not line.is_empty(), "probe printed the cost line")
	if line.is_empty():
		return
	var cpu: float = float(line["terrain_cpu_ms"])
	var sample: float = float(line["terrain_sample_ms"])
	var mesh: float = float(line["terrain_mesh_ms"])
	var collision: float = float(line["terrain_collision_ms"])
	assert_true(int(line["terrain_build_frames"]) >= 1, "the build spent at least the synchronous frame")
	assert_true(sample > 0.0 and mesh > 0.0 and collision > 0.0, "every phase cost time (%s / %s / %s ms)" % [sample, mesh, collision])
	assert_true(sample + mesh <= cpu + 0.1, "sampling and meshing fit inside the chunk total (%s + %s <= %s)" % [sample, mesh, cpu])
	assert_true(cpu <= float(line["terrain_build_ms"]) + 1.0, "CPU time fits inside the wall-clock build (%s <= %s)" % [cpu, line["terrain_build_ms"]])
	assert_true(collision < sample and collision < mesh, "collision is the small phase")


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


func test_the_pond_holds_its_water_until_the_sluice_is_opened() -> void:
	var line: Dictionary = _probe_line(_text, "PROBE pond ")
	assert_eq(line.get("drained", ""), "false", "an untouched vale still has its pond")
	assert_eq(line.get("water_visible", ""), "true", "the water disc is drawn")
	var water_y: float = float(line.get("water_y", "0"))
	var basin: float = float(line.get("basin_floor", "0"))
	assert_true(water_y > basin, "the water sits above the basin floor (%.2f > %.2f)" % [water_y, basin])
	assert_true(water_y - basin > 5.0, "the basin is deep enough to hide a way down (%.2f m)" % [water_y - basin])


func test_a_drained_pond_loads_empty_and_can_be_walked_into() -> void:
	# The endgame depends on this: with the Sluice Wheel fitted the basin must be dry, gone from the screen,
	# and gentle enough to walk down. A basin the player cannot enter is a dead end at the last door.
	assert_eq(_drained_code, 0, "the drained child run exits cleanly")
	assert_false("SCRIPT ERROR" in _drained_text, "draining the pond printed no script errors")
	var line: Dictionary = _probe_line(_drained_text, "PROBE pond ")
	assert_eq(line.get("drained", ""), "true", "the flag drained the pond")
	assert_eq(line.get("water_visible", ""), "false", "a pond drained before the session began is not drawn")
	# Slope, not sample_walkable: see the comment on the probe line. The heightfield still calls the basin
	# underwater on purpose, so asking it whether the floor is "walkable" would always answer no.
	assert_eq(line.get("slope_ok", ""), "true", "the basin floor is gentle enough to walk down into")


func test_the_settlements_spawned_every_house_with_its_props() -> void:
	# W8-H: twenty houses from data/sites/vale_houses.json, each with its loot, built by Settlements at load.
	var line: Dictionary = _probe_line(_text, "PROBE sites ")
	assert_true(not line.is_empty(), "probe printed the sites line")
	if line.is_empty():
		return
	var houses: int = 0
	var built: int = 0
	var props: int = 0
	for site: Dictionary in SiteRegistry.load_area("vale"):
		if bool(site.get("fixed", false)):
			continue
		built += 1
		if str(site.get("_file", "")) == "vale_houses.json":
			houses += 1
		props += (site.get("props", []) as Array).size()
	assert_eq(houses, 20, "twenty houses are placed in the Vale")
	assert_eq(line["fixed"], "3", "the castle, the village and the Hearth chamber are the fixed sites")
	assert_eq(int(line["spawned"]), built, "every non-fixed site was spawned (%d, of which %d houses)" % [built, houses])
	assert_true(int(line["spawned"]) >= 20, "at least the twenty houses were spawned")
	assert_eq(int(line["props"]), props, "every listed prop was instanced (%d)" % props)
	assert_true(int(line["pieces"]) >= 20 * 8, "each house built at least its eight pieces (%s)" % line["pieces"])


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
