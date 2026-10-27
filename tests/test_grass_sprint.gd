extends "res://tests/test_case.gd"
## The sprint probe (W8-G): a child headless vale.tscn run with `--probe-sprint` (the rig
## tests/test_terrain.gd uses) runs the player at sprint speed along a straight line from the spawn toward
## the castle hill, steps the grass lattice once per simulated 60 fps frame, and counts every frame the
## lattice cells still unfilled within 30 m of the player. The failure D-019 guards against is not a slow
## frame but bare ground in front of a sprinting player, and denser zones make every cell dearer, so this
## is the number that has to stay at zero. CPU side only: headless has no renderer.

const VALE_SCENE := "res://scenes/levels/vale.tscn"
## Terrain build, the settle, then 1500 sprint frames; the scene quits itself long before this.
const PROBE_FRAME_CAP := "8000"

var _code: int = -1
var _text: String = ""


func setup() -> void:
	var output: Array = []
	var args: PackedStringArray = [
		"--headless", "--path", ProjectSettings.globalize_path("res://"),
		VALE_SCENE, "--quit-after", PROBE_FRAME_CAP, "--", "--probe-sprint",
	]
	_code = OS.execute(OS.get_executable_path(), args, output, true)
	_text = "\n".join(PackedStringArray(output))


func test_child_sprint_run_is_clean() -> void:
	assert_eq(_code, 0, "child headless sprint run of the vale exits cleanly")
	assert_false("SCRIPT ERROR" in _text, "child run printed no script errors")
	assert_false("SHADER ERROR" in _text, "the grass shader parsed")
	assert_true(_text.find("PROBE sprint ") >= 0, "the probe printed the sprint line before the frame cap")


func test_no_lattice_cell_within_30_m_is_unfilled_while_sprinting() -> void:
	var line: Dictionary = _probe_line(_text, "PROBE sprint ")
	assert_true(not line.is_empty(), "probe printed the sprint line")
	if line.is_empty():
		return
	assert_eq(int(line["frames"]), 1500, "the sprint ran its full length")
	assert_eq(line["settled_before"], "true", "the lattice had settled before the sprint began")
	assert_true(float(line["distance"]) >= 170.0, "the player covered a long straight path (%s m)" % line["distance"])
	assert_true(int(line["cells_filled"]) >= 100, "the sprint crossed cells and refilled the leading ring (%s cells)" % line["cells_filled"])
	assert_eq(int(line["max_unfilled_30m"]), 0, "at sprint speed no lattice cell within 30 m was ever unfilled (%s frames had one)" % line["frames_with_unfilled"])
	assert_true(float(line["fill_worst_ms"]) >= float(line["fill_mean_ms"]), "the worst sprint frame is at least the mean")


func test_the_castle_hill_grows_tall_grass_in_the_live_scene() -> void:
	# The sprint ends on the castle hill's skirt (about 130 m from the castle's centre), where the old rule
	# grew nothing: the lattice around the player there must hold tall grass and zoned blades.
	var grass: Dictionary = _probe_line(_text, "PROBE grass ")
	assert_true(not grass.is_empty(), "probe printed the grass line")
	if grass.is_empty():
		return
	assert_eq(grass["zones"], "true", "the vale's grass is zoned")
	assert_true(int(grass["tall"]) > 300, "tall grass stands on the castle hill (%s instances)" % grass["tall"])
	assert_true(int(grass["instances"]) > 8000, "the hill is covered, not bare (%s instances)" % grass["instances"])
	# The player is still moving when the sprint stops, so at most the cell being filled is outstanding.
	assert_true(int(grass["pending"]) <= 1, "at most one cell was mid-fill when the sprint ended (%s pending)" % grass["pending"])
	assert_eq(int(grass["floating"]), 0, "every instance sits on the heightfield")
	assert_eq(int(grass["steep"]), 0, "nothing grows above its layer's slope limit")


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
