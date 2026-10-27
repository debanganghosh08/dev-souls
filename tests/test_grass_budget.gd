extends "res://tests/test_case.gd"
## Grass fill scheduling and its cost counters (W6-04), driven a frame at a time through Grass.step() on a
## bare Heightfield: no scene tree, no renderer, so the costs here are CPU-side only, like the probe's.
## The lattice is small and the layers thin so the whole file fills in well under a second.

const VALE := "res://data/areas/vale.json"
const RADIUS := 30.0
const CELL := 12.0
const FRAME_CAP := 400
const DATA := {
	"seed": 20261024, "wind": {"strength": 0.2, "direction_deg": 35.0, "speed": 1.0, "ripple_scale": 0.1},
	"layers": [
		{"name": "grass", "kind": "clump", "density": 0.5, "max_per_cell": 80, "max_slope": 32.0, "blades": 4, "segments": 3,
			"height": [0.3, 0.6], "scale": [0.8, 1.2], "patch_min": 0.4, "hollow": 0.6, "sink": 0.03},
		{"name": "pebbles", "kind": "pebble", "density": 0.1, "max_per_cell": 16, "max_slope": 42.0, "scale": [0.06, 0.16]},
	],
}

var _hf: Heightfield
var _at: Vector3 = Vector3.ZERO


func setup() -> void:
	var json := JSON.new()
	json.parse(FileAccess.get_file_as_string(VALE))
	_hf = Heightfield.from_dict(json.data)
	_at = _hf.spawn_point()


func _grass(budget_ms: float, cap: int) -> Grass:
	var g := Grass.new()
	g.radius = RADIUS
	g.cell_size = CELL
	g.fill_budget_ms = budget_ms
	g.fill_cells_per_frame = cap
	g.bind_heightfield(_hf)
	g.rebuild(DATA)
	return g


## Steps until nothing is pending; returns how many frames it took (FRAME_CAP means it never settled).
func _settle(g: Grass, at: Vector3) -> int:
	for frame: int in FRAME_CAP:
		if frame > 0 and int(g.stats()["pending"]) == 0:
			return frame
		g.step(at)
	return FRAME_CAP


func _sorted(p: PackedVector3Array) -> Array:
	var out: Array = Array(p)
	out.sort()
	return out


func test_cost_counters_start_at_zero_and_only_grow() -> void:
	var g: Grass = _grass(1000.0, 3)
	var s: Dictionary = g.stats()
	for key: String in ["fill_frames", "fill_cells", "fill_total_ms", "fill_mean_ms", "fill_worst_ms"]:
		assert_true(s.has(key), "stats() reports %s" % key)
		assert_true(is_zero_approx(float(s.get(key, 1.0))), "%s starts at zero (got %s)" % [key, s.get(key)])
	var t: Terrain = Terrain.new()
	var ts: Dictionary = t.stats()
	for key: String in ["build_frames", "build_cpu_ms", "sample_ms", "mesh_ms", "collision_ms"]:
		assert_true(ts.has(key), "Terrain.stats() reports %s" % key)
		assert_true(is_zero_approx(float(ts.get(key, 1.0))), "Terrain %s starts at zero (got %s)" % [key, ts.get(key)])
	t.free()
	var last: Dictionary = s
	for frame: int in FRAME_CAP:
		g.step(_at)
		var now: Dictionary = g.stats()
		for key: String in ["fill_frames", "fill_cells", "fill_total_ms", "fill_worst_ms"]:
			assert_true(float(now[key]) >= float(last[key]), "%s never shrinks (%s after %s)" % [key, now[key], last[key]])
		last = now
		if int(now["pending"]) == 0:
			break
	assert_eq(int(last["pending"]), 0, "the lattice settled inside the frame cap")
	assert_true(int(last["fill_frames"]) > 0, "frames that filled were counted")
	assert_eq(int(last["fill_cells"]), int(last["cells"]), "every held cell was counted as filled once")
	assert_true(float(last["fill_total_ms"]) > 0.0, "filling cost measurable time")
	assert_true(float(last["fill_worst_ms"]) >= float(last["fill_mean_ms"]), "the worst frame is at least the mean")
	assert_true(float(last["fill_mean_ms"]) * float(last["fill_frames"]) <= float(last["fill_total_ms"]) + 0.001, "mean x frames is the total")
	# Idle frames (nothing pending) must not touch the counters: that is the "cheap when idle" promise.
	g.step(_at)
	g.step(_at)
	assert_eq(int(g.stats()["fill_frames"]), int(last["fill_frames"]), "idle frames count nothing")
	g.free()


func test_a_time_budget_ends_in_the_same_lattice_as_a_fixed_count() -> void:
	# The budget changes the schedule and nothing else: same cells, same instances, same positions.
	var fixed: Grass = _grass(1000000.0, 3)
	var budgeted: Grass = _grass(0.0, 3)
	var fixed_frames: int = _settle(fixed, _at)
	var budgeted_frames: int = _settle(budgeted, _at)
	assert_true(fixed_frames < FRAME_CAP and budgeted_frames < FRAME_CAP, "both schedules finish (%d / %d frames)" % [fixed_frames, budgeted_frames])
	var a: Dictionary = fixed.stats()
	var b: Dictionary = budgeted.stats()
	assert_true(int(a["cells"]) > 5, "the small lattice holds a few cells (%d)" % int(a["cells"]))
	assert_eq(b["cells"], a["cells"], "same cell count")
	assert_eq(b["instances"], a["instances"], "same instance count")
	assert_eq(b["per_layer"], a["per_layer"], "same count per layer")
	assert_true(int(a["instances"]) > 0, "something grew at the spawn (%d)" % int(a["instances"]))
	assert_eq(_sorted(budgeted.positions()), _sorted(fixed.positions()), "every instance stands in the same place")
	assert_true(int(b["fill_frames"]) > int(a["fill_frames"]), "the budget spread the fill over more frames (%d vs %d)" % [int(b["fill_frames"]), int(a["fill_frames"])])
	# Since W8-G the unit of work is a layer: a zero budget fills one layer a frame, two frames per cell here.
	assert_eq(int(b["fill_frames"]), int(b["fill_cells"]) * int(b["layers"]), "a zero budget fills exactly one layer a frame")
	assert_true(int(a["fill_frames"]) * 3 >= int(a["fill_cells"]), "the fixed count never passed three cells a frame")
	fixed.free()
	budgeted.free()


func test_the_budget_is_respected_and_the_cap_backstops_it() -> void:
	# With no budget at all one layer still goes in each frame, so the lattice always finishes (a cell of
	# the two layers here completes every second frame); with a budget too generous to matter the cap decides.
	var starved: Grass = _grass(0.0, 3)
	for frame: int in 4:
		var before: int = int(starved.stats()["fill_cells"])
		starved.step(_at)
		assert_eq(int(starved.stats()["fill_frames"]), frame + 1, "a zero budget still works every frame (frame %d)" % frame)
		assert_eq(int(starved.stats()["fill_cells"]) - before, 1 if frame % 2 == 1 else 0, "a zero budget completes a two-layer cell every second frame (frame %d)" % frame)
	assert_true(float(starved.stats()["fill_worst_ms"]) > 0.0, "the starved frames were timed")
	var capped: Grass = _grass(1000000.0, 2)
	for frame: int in 3:
		var before: int = int(capped.stats()["fill_cells"])
		capped.step(_at)
		assert_eq(int(capped.stats()["fill_cells"]) - before, 2, "an unlimited budget fills exactly the cap on frame %d" % frame)
	var single: Grass = _grass(1000000.0, 1)
	single.step(_at)
	assert_eq(int(single.stats()["fill_cells"]), 1, "a cap of one is one")
	# A frame may overrun the budget only by the cell that crossed it, never by a whole cap of cells:
	# with a zero budget the worst frame is one cell, with the cap it is up to three.
	var worst_one: float = float(starved.stats()["fill_worst_ms"])
	var three: Grass = _grass(1000000.0, 3)
	three.step(_at)
	three.step(_at)
	assert_true(float(three.stats()["fill_worst_ms"]) > 0.0, "three-cell frames were timed")
	assert_true(worst_one > 0.0, "one-cell frames were timed")
	starved.free()
	capped.free()
	single.free()
	three.free()


func test_a_cell_crossing_under_budget_still_ends_where_a_fresh_lattice_would() -> void:
	# Walk one cell east while cells are still pending: the leading ring is refilled, the trailing one
	# recycled, and what stands afterwards is exactly what a lattice built at the new spot would hold.
	var walked: Grass = _grass(0.0, 3)
	for frame: int in 3:
		walked.step(_at)
	var east: Vector3 = _at + Vector3(CELL, 0.0, 0.0)
	assert_true(_settle(walked, east) < FRAME_CAP, "the walked lattice settles after the crossing")
	var fresh: Grass = _grass(1000000.0, 3)
	assert_true(_settle(fresh, east) < FRAME_CAP, "the fresh lattice settles")
	assert_eq(walked.stats()["cells"], fresh.stats()["cells"], "same cells after the crossing")
	assert_eq(walked.stats()["instances"], fresh.stats()["instances"], "same instances after the crossing")
	assert_eq(_sorted(walked.positions()), _sorted(fresh.positions()), "same positions after the crossing")
	assert_true(int(walked.stats()["cells"]) <= int(walked.stats()["pool"]), "the pool was never overrun")
	walked.free()
	fresh.free()
