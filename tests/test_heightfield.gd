extends "res://tests/test_case.gd"
## Heightfield tests: pure maths from data/areas/vale.json, no scene or autoload needed. Also covers the
## chunk mesh builder (TerrainMesh) because it is pure too.

const VALE := "res://data/areas/vale.json"
const RING_STEP := 1.5
const FLAT_TOLERANCE := 0.05
## Largest height change allowed between neighbouring RING_STEP samples across a plateau skirt: 1.26 m
## per 1.5 m is a 40 deg slope, under the player's 45 deg floor limit.
const MAX_SKIRT_STEP := 1.26
const SAMPLES: Array[Vector2] = [Vector2(0, 0), Vector2(123.4, -77.9), Vector2(-301.0, 210.5), Vector2(410.0, 410.0), Vector2(-33.3, 480.2)]

var _data: Dictionary = {}
var _hf: Heightfield


func setup() -> void:
	var json := JSON.new()
	json.parse(FileAccess.get_file_as_string(VALE))
	_data = json.data
	_hf = Heightfield.from_dict(_data)


func test_same_seed_is_identical_and_other_seed_differs() -> void:
	var twin: Heightfield = Heightfield.from_dict(_data)
	var other_data: Dictionary = _data.duplicate(true)
	other_data["seed"] = int(_data["seed"]) + 1
	var other: Heightfield = Heightfield.from_dict(other_data)
	var differs: bool = false
	for p: Vector2 in SAMPLES:
		assert_true(is_equal_approx(_hf.height_at(p.x, p.y), twin.height_at(p.x, p.y)), "same seed reproduces height at %s" % p)
		differs = differs or not is_equal_approx(_hf.height_at(p.x, p.y), other.height_at(p.x, p.y))
	assert_true(differs, "another seed changes the land")


func test_pond_is_below_water_and_ridge_above_floor() -> void:
	var c: Vector2 = _hf.pond_centre()
	assert_true(_hf.height_at(c.x, c.y) < _hf.water_level() - 1.0, "pond centre is at least 1 m under water (h %.2f, water %.2f)" % [_hf.height_at(c.x, c.y), _hf.water_level()])
	assert_true(_hf.is_underwater(c.x, c.y), "is_underwater agrees at the pond centre")
	var floor_h: float = _hf.height_at(_hf.ridge_inner_radius() * 0.5, 0.0)
	var ridge_h: float = _hf.height_at(_hf.size() * 0.5, 0.0)
	assert_true(ridge_h > floor_h + 30.0, "ridge stands well above the valley floor (%.1f vs %.1f)" % [ridge_h, floor_h])
	var ridge: Dictionary = _data["ridge"]
	var mid: float = (float(ridge["inner_radius"]) + float(ridge["outer_radius"])) * 0.5
	var steep: float = 0.0
	for k: int in 24:
		var d: Vector2 = Vector2.from_angle(float(k) * TAU / 24.0) * mid
		steep = maxf(steep, _hf.slope_at(d.x, d.y))
	assert_true(steep > 45.0, "somewhere on the ridge ring the slope beats the player's 45 deg (max %.1f)" % steep)


func test_plateaus_are_flat_and_blend_smoothly() -> void:
	assert_eq(_hf.plateaus().size(), 2, "the vale has a village and a castle plateau")
	for site: Dictionary in _hf.plateaus():
		var c: Vector2 = site["centre"]
		var r: float = site["radius"]
		var target: float = site["height"]
		var worst: float = 0.0
		var step: float = 0.0
		var centre_slope: float = _hf.slope_at(c.x, c.y)
		for k: int in 36:
			var dir: Vector2 = Vector2.from_angle(float(k) * TAU / 36.0)
			for f: float in [0.0, 0.3, 0.6, 0.9, 1.0]:
				var p: Vector2 = c + dir * r * f
				worst = maxf(worst, absf(_hf.height_at(p.x, p.y) - target))
			var prev: float = _hf.height_at(c.x + dir.x * r, c.y + dir.y * r)
			var samples: int = int(ceil((float(site["blend"]) + 10.0) / RING_STEP))
			for n: int in samples:
				var p: Vector2 = c + dir * (r + float(n + 1) * RING_STEP)
				var h: float = _hf.height_at(p.x, p.y)
				step = maxf(step, absf(h - prev))
				prev = h
		assert_true(worst <= FLAT_TOLERANCE, "%s is flat across its radius (max deviation %.3f)" % [site["name"], worst])
		assert_true(step <= MAX_SKIRT_STEP, "%s skirt has no step over %.2f m per %.1f m (worst %.2f)" % [site["name"], MAX_SKIRT_STEP, RING_STEP, step])
		assert_true(centre_slope < 0.5, "%s centre reads as level (slope %.2f)" % [site["name"], centre_slope])


func test_slope_and_normal() -> void:
	var village: Vector2 = _hf.plateaus()[0]["centre"]
	assert_true(_hf.slope_at(village.x, village.y) < 0.5, "slope is ~0 on the plateau")
	var ridge: Dictionary = _data["ridge"]
	var mid: float = (float(ridge["inner_radius"]) + float(ridge["outer_radius"])) * 0.5
	assert_true(_hf.slope_at(mid, 0.0) > 30.0 or _hf.slope_at(0.0, mid) > 30.0, "slope is steep on the ridge")
	for p: Vector2 in SAMPLES:
		var n: Vector3 = _hf.normal_at(p.x, p.y)
		assert_true(is_equal_approx(n.length(), 1.0), "normal is unit length at %s" % p)
		assert_true(n.y > 0.0, "normal points up at %s" % p)
	assert_true(_hf.sample_walkable(village.x, village.y, 45.0), "plateau centre is walkable")
	assert_false(_hf.sample_walkable(0.0, 0.0, 45.0), "the pond floor is not walkable (under water)")


func test_out_of_bounds_and_nan_safety() -> void:
	for p: Vector2 in [Vector2(1.0e6, -1.0e6), Vector2(-99999.0, 0.0), Vector2(0.0, 1.0e9), Vector2(INF, 0.0), Vector2(NAN, NAN)]:
		var h: float = _hf.height_at(p.x, p.y)
		assert_true(is_finite(h), "height is finite at %s (got %s)" % [p, h])
		assert_true(is_finite(_hf.slope_at(p.x, p.y)), "slope is finite at %s" % p)
	var edge: float = _hf.height_at(_hf.size() * 0.5, 0.0)
	assert_true(is_equal_approx(edge, _hf.height_at(_hf.size(), 0.0)), "outside the bounds clamps to the edge")


func test_degenerate_config_does_not_crash() -> void:
	var configs: Array[Dictionary] = [
		{},
		{"size": 0, "noise": {"octaves": 0, "frequency": 0.0}},
		{"size": -100, "pond": {"radius": -5, "falloff": -10, "depth": 3}, "plateaus": [{"radius": -1, "blend": 0, "height": 5}]},
		{"ridge": {"inner_radius": 50, "outer_radius": 10, "height": 20}, "valley": {"waypoints": [[0, 0]], "width": 0, "blend": 0}},
		{"valley": {"waypoints": [[0, 0], [0, 0]], "width": -1, "blend": -1, "flatten": 9}, "spawn": {"step": 0, "direction": [0, 0]}},
	]
	for cfg: Dictionary in configs:
		var hf: Heightfield = Heightfield.from_dict(cfg)
		for p: Vector2 in SAMPLES:
			assert_true(is_finite(hf.height_at(p.x, p.y)), "degenerate config %s gives a finite height" % cfg)
			assert_true(is_finite(hf.normal_at(p.x, p.y).length()), "degenerate config %s gives a finite normal" % cfg)
		var spawn: Vector3 = hf.spawn_point()
		assert_true(is_finite(spawn.x) and is_finite(spawn.y) and is_finite(spawn.z), "degenerate config %s still yields a spawn" % cfg)


func test_spawn_point_is_dry_and_gentle() -> void:
	var spawn: Vector3 = _hf.spawn_point()
	var s: Dictionary = _data["spawn"]
	assert_true(spawn.y >= _hf.water_level() + float(s["clearance"]), "spawn is above water by the clearance")
	assert_true(_hf.slope_at(spawn.x, spawn.z) <= float(s["max_slope"]), "spawn slope within max_slope")
	assert_true(is_equal_approx(spawn.y, _hf.height_at(spawn.x, spawn.z)), "spawn y is the ground height")


func test_terrain_mesh_lods_and_winding() -> void:
	var cells: int = 8
	var grid: PackedFloat32Array = TerrainMesh.sample_grid(_hf, Vector2(100.0, 100.0), cells, 2.0)
	assert_eq(grid.size(), (cells + 3) * (cells + 3), "grid carries a one-cell border")
	var lod0: ArrayMesh = TerrainMesh.build_lod(grid, cells, 1, 2.0, 0.0, Vector2.ZERO, 1.0)
	var lod2: ArrayMesh = TerrainMesh.build_lod(grid, cells, 4, 2.0, 3.0, Vector2.ZERO, 1.0)
	var v0: PackedVector3Array = lod0.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var v2: PackedVector3Array = lod2.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	assert_eq(v0.size(), (cells + 1) * (cells + 1), "LOD0 without skirt has (cells+1)^2 vertices")
	assert_eq(v2.size(), 3 * 3 + 4 * 3, "LOD2 with skirt adds one duplicated row per edge")
	assert_true(TerrainMesh.first_face_normal(lod0).y > 0.0, "LOD0 triangles wind so the face normal points up")
	assert_true(TerrainMesh.first_face_normal(lod2).y > 0.0, "LOD2 triangles wind so the face normal points up")
	assert_true(is_equal_approx(v0[0].y, _hf.height_at(100.0, 100.0)), "corner vertex sits exactly on the heightfield")
	var faces: PackedVector3Array = TerrainMesh.collision_faces(grid, cells, 2.0)
	assert_eq(faces.size(), cells * cells * 6, "collision faces cover every cell with two triangles")
	var n: PackedVector3Array = lod0.surface_get_arrays(0)[Mesh.ARRAY_NORMAL]
	assert_true(is_equal_approx(n[0].length(), 1.0) and n[0].y > 0.0, "vertex normals are unit and upward")
