extends "res://tests/test_case.gd"
## Forest tests. Placement is a pure static function, checked directly; the live scene (multimeshes,
## colliders, rendering counters) runs in a child headless Godot playing treetest.tscn with `--probe`.

const TREETEST := "res://scenes/levels/treetest.tscn"
const PROBE_FRAME_CAP := "900"
const MIX := {"fir": 6.0, "pine": 3.0, "dead": 1.0, "ancient": 0.0}


func test_layout_count_clearing_and_bounds() -> void:
	var layout: Dictionary = Forest.plan_layout(200, 60.0, 8.0, 1, MIX)
	var positions: PackedVector3Array = layout["positions"]
	assert_eq(positions.size(), 200, "layout places exactly count trees")
	var inside_clearing: int = 0
	var outside: int = 0
	for p: Vector3 in positions:
		var d: float = Vector2(p.x, p.z).length()
		if d < 8.0:
			inside_clearing += 1
		if d > 60.0:
			outside += 1
		if not is_zero_approx(p.y):
			_fail("tree placed off the ground plane: %s" % p)
			break
	assert_eq(inside_clearing, 0, "no tree inside the clearing radius")
	assert_eq(outside, 0, "no tree beyond the forest radius")


func test_layout_is_seeded() -> void:
	var a: Dictionary = Forest.plan_layout(120, 50.0, 6.0, 7, MIX)
	var b: Dictionary = Forest.plan_layout(120, 50.0, 6.0, 7, MIX)
	var c: Dictionary = Forest.plan_layout(120, 50.0, 6.0, 8, MIX)
	assert_true(a["positions"] == b["positions"], "same seed reproduces every position")
	assert_true(a["archetypes"] == b["archetypes"] and a["yaws"] == b["yaws"] and a["scales"] == b["scales"], "same seed reproduces archetypes, yaws and scales")
	assert_true(a["positions"] != c["positions"], "another seed gives another layout")


func test_layout_respects_mix_and_spacing() -> void:
	var layout: Dictionary = Forest.plan_layout(150, 60.0, 8.0, 3, MIX)
	var names: PackedStringArray = layout["archetypes"]
	var counts: Dictionary = {}
	for n: String in names:
		counts[n] = int(counts.get(n, 0)) + 1
	assert_false(counts.has("ancient"), "zero-weight archetypes are never placed")
	assert_true(int(counts.get("fir", 0)) > int(counts.get("dead", 0)), "weights bias the mix (fir %s > dead %s)" % [counts.get("fir", 0), counts.get("dead", 0)])
	var positions: PackedVector3Array = layout["positions"]
	var close_pairs: int = 0
	for i: int in positions.size():
		for j: int in range(i + 1, positions.size()):
			if positions[i].distance_to(positions[j]) < 0.5:
				close_pairs += 1
	assert_eq(close_pairs, 0, "no two trees share a spot")
	var scales: PackedFloat32Array = layout["scales"]
	assert_true(scales[0] != scales[1] or scales[1] != scales[2], "per-instance scale varies")


func test_zero_count_and_empty_mix_are_safe() -> void:
	var empty: Dictionary = Forest.plan_layout(0, 60.0, 8.0, 1, MIX)
	assert_eq((empty["positions"] as PackedVector3Array).size(), 0, "zero count places nothing")
	var no_mix: Dictionary = Forest.plan_layout(5, 60.0, 8.0, 1, {})
	assert_eq((no_mix["archetypes"] as PackedStringArray).size(), 5, "an empty mix still places trees (default archetype)")


func test_headless_forest_probe() -> void:
	var output: Array = []
	var args: PackedStringArray = [
		"--headless", "--path", ProjectSettings.globalize_path("res://"),
		TREETEST, "--quit-after", PROBE_FRAME_CAP, "--", "--probe",
	]
	var code: int = OS.execute(OS.get_executable_path(), args, output, true)
	var text: String = "\n".join(PackedStringArray(output))
	assert_eq(code, 0, "child headless run of treetest exits cleanly")
	assert_false("SCRIPT ERROR" in text, "child run printed no script errors")
	for archetype: String in ["fir", "pine", "dead", "ancient"]:
		var line: Dictionary = _probe_line(text, "PROBE treegen archetype=%s" % archetype)
		assert_true(not line.is_empty(), "probe printed the treegen line for %s" % archetype)
		if line.is_empty():
			continue
		assert_eq(line["deterministic"], "true", "%s builds deterministically in the live scene" % archetype)
		assert_true(int(line["trunk_verts"]) > 0, "%s has trunk vertices" % archetype)
		if archetype == "dead":
			assert_eq(int(line["card_verts"]), 0, "dead has no card vertices")
		else:
			assert_true(int(line["card_verts"]) > 0, "%s has card vertices" % archetype)
	var forest: Dictionary = _probe_line(text, "PROBE forest ")
	assert_true(not forest.is_empty(), "probe printed the forest line")
	if not forest.is_empty():
		assert_eq(forest["trees"], forest["count"], "tree count matches the count export")
		assert_true(int(forest["trees"]) > 0, "forest placed trees")
		assert_true(float(forest["min_dist"]) >= float(forest["clearing"]), "clearing is empty (nearest tree %s >= %s)" % [forest["min_dist"], forest["clearing"]])
		assert_true(int(forest["multimeshes"]) > 0, "forest created multimesh instances")
		assert_true(int(forest["colliders"]) > 0, "forest created colliders")
	var repeat: Dictionary = _probe_line(text, "PROBE forest_repeat")
	assert_true(not repeat.is_empty(), "probe printed the repeat line")
	if not repeat.is_empty():
		assert_eq(repeat["same"], "true", "rebuilding with the same seed reproduces the layout")
	var reseed: Dictionary = _probe_line(text, "PROBE forest_reseed")
	if not reseed.is_empty():
		assert_eq(reseed["differs"], "true", "a new seed changes the layout")


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
