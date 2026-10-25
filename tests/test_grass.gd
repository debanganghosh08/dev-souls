extends "res://tests/test_case.gd"
## Pure tests for the Grass system: GrassLattice (density from the land, cell recycling maths, distance
## thinning), GrassMesh (blade clump geometry) and GrassLayer.fill determinism on a fake ground. No scene,
## no renderer: fills write into a MultiMesh the dummy renderer discards, so placement is checked from the
## CPU-side positions the layer writes alongside.

const WATER := -5.0
const MAX_SLOPE := 32.0
const CELL := 12.0
const LAYER := {"name": "grass", "kind": "clump", "density": 1.0, "max_per_cell": 120, "max_slope": 32.0,
	"blades": 4, "segments": 3, "height": [0.3, 0.6], "scale": [0.8, 1.2], "patch_min": 1.0}


func test_density_is_full_on_gentle_dry_ground_and_zero_at_the_slope_limit() -> void:
	assert_true(is_equal_approx(GrassLattice.density_at(0.0, 10.0, WATER, MAX_SLOPE), 1.0), "flat dry ground grows fully")
	assert_true(is_equal_approx(GrassLattice.density_at(MAX_SLOPE * 0.5, 10.0, WATER, MAX_SLOPE), 1.0), "half the limit is still full")
	assert_true(is_zero_approx(GrassLattice.density_at(MAX_SLOPE, 10.0, WATER, MAX_SLOPE)), "nothing grows at the limit")
	assert_true(is_zero_approx(GrassLattice.density_at(MAX_SLOPE + 10.0, 10.0, WATER, MAX_SLOPE)), "nothing grows past the limit")
	var just_under: float = GrassLattice.density_at(MAX_SLOPE - 0.5, 10.0, WATER, MAX_SLOPE)
	assert_true(just_under > 0.0 and just_under < 0.1, "just under the limit a trace grows (%s)" % just_under)


func test_density_falls_monotonically_across_the_slope_threshold() -> void:
	var last: float = 2.0
	for i: int in 33:
		var d: float = GrassLattice.density_at(float(i), 10.0, WATER, MAX_SLOPE)
		assert_true(d <= last + 0.000001, "density never rises with slope (at %d deg: %s after %s)" % [i, d, last])
		assert_true(d >= 0.0 and d <= 1.0, "density stays in 0..1")
		last = d
	var mid: float = GrassLattice.density_at(MAX_SLOPE * 0.75, 10.0, WATER, MAX_SLOPE)
	assert_true(mid > 0.3 and mid < 0.7, "three quarters of the limit is about half density (%s)" % mid)


func test_density_is_zero_under_water_and_thins_at_the_shore() -> void:
	assert_true(is_zero_approx(GrassLattice.density_at(0.0, WATER - 2.0, WATER, MAX_SLOPE)), "under water: nothing")
	assert_true(is_zero_approx(GrassLattice.density_at(0.0, WATER, WATER, MAX_SLOPE)), "at the water line: nothing")
	var shore: float = GrassLattice.density_at(0.0, WATER + 0.5, WATER, MAX_SLOPE)
	assert_true(shore > 0.0 and shore < 1.0, "half a metre up the shore grass is thin (%s)" % shore)
	assert_true(is_equal_approx(GrassLattice.density_at(0.0, WATER + GrassLattice.SHORE_BAND, WATER, MAX_SLOPE), 1.0), "above the shore band: full")


func test_density_handles_degenerate_input_without_nan() -> void:
	for v: float in [GrassLattice.density_at(NAN, 1.0, 0.0, 30.0), GrassLattice.density_at(1.0, NAN, 0.0, 30.0),
			GrassLattice.density_at(1.0, 1.0, NAN, 30.0), GrassLattice.density_at(1.0, 1.0, 0.0, NAN),
			GrassLattice.density_at(1.0, 1.0, 0.0, 0.0), GrassLattice.density_at(1.0, 1.0, 0.0, -5.0),
			GrassLattice.density_at(-10.0, INF, 0.0, 30.0), GrassLattice.density_at(INF, 10.0, 0.0, 30.0)]:
		assert_false(is_nan(v), "degenerate input never yields NaN")
		assert_true(v >= 0.0 and v <= 1.0, "degenerate input stays in 0..1 (%s)" % v)
	assert_true(is_equal_approx(GrassLattice.density_at(-10.0, INF, 0.0, 30.0), 1.0), "an infinitely high dry plain grows fully")


func test_plateau_sites_block_growth_and_fade_in_over_the_skirt() -> void:
	var sites: Array[Dictionary] = [{"centre": Vector2(100.0, 0.0), "radius": 50.0, "blend": 40.0, "height": 3.0}]
	assert_true(is_zero_approx(GrassLattice.site_factor(100.0, 0.0, sites)), "nothing at the plateau centre")
	assert_true(is_zero_approx(GrassLattice.site_factor(140.0, 0.0, sites)), "nothing just inside the radius")
	var skirt: float = GrassLattice.site_factor(160.0, 0.0, sites)
	assert_true(skirt > 0.0 and skirt < 1.0, "the skirt fades in (%s)" % skirt)
	assert_true(is_equal_approx(GrassLattice.site_factor(200.0, 0.0, sites), 1.0), "full growth beyond the skirt")
	assert_true(is_equal_approx(GrassLattice.site_factor(0.0, 0.0, [] as Array[Dictionary]), 1.0), "no sites: full growth")


func test_lattice_offsets_cover_a_disc_and_survive_degenerate_sizes() -> void:
	var offsets: Array[Vector2i] = GrassLattice.lattice_offsets(70.0, CELL)
	assert_true(offsets.has(Vector2i.ZERO), "the centre cell is included")
	var expected: float = PI * 70.0 * 70.0 / (CELL * CELL)
	assert_true(absf(float(offsets.size()) - expected) < expected * 0.15, "about pi r^2 / c^2 cells (%d vs %.0f)" % [offsets.size(), expected])
	for o: Vector2i in offsets:
		assert_true(Vector2(o).length() * CELL <= 70.0, "offset %s lies within the radius" % o)
		assert_true(offsets.has(-o), "the disc is symmetric (%s)" % o)
	assert_eq(GrassLattice.lattice_offsets(0.0, CELL).size(), 1, "zero radius keeps only the centre cell")
	assert_eq(GrassLattice.lattice_offsets(-5.0, CELL).size(), 0, "a negative radius wants nothing")
	var tiny: Array[Vector2i] = GrassLattice.lattice_offsets(70.0, 0.0)
	assert_true(tiny.size() <= (2 * GrassLattice.MAX_CELLS_PER_SIDE + 1) * (2 * GrassLattice.MAX_CELLS_PER_SIDE + 1), "a zero cell size is capped, not a hang")


func test_cells_needed_ignore_jitter_inside_a_cell_and_shift_by_one_column_per_cell_crossed() -> void:
	var a: Array[Vector2i] = GrassLattice.cells_needed(Vector3(3.0, 0.0, 3.0), 40.0, CELL)
	var b: Array[Vector2i] = GrassLattice.cells_needed(Vector3(11.9, 7.0, 0.1), 40.0, CELL)
	assert_eq(a, b, "two positions inside the same cell need the same set")
	var have: Dictionary = {}
	for key: Vector2i in a:
		have[key] = 0
	assert_true(GrassLattice.cell_diff(have, b)["add"].is_empty() and GrassLattice.cell_diff(have, b)["drop"].is_empty(), "jitter inside a cell recycles nothing")
	var c: Array[Vector2i] = GrassLattice.cells_needed(Vector3(12.5, 0.0, 3.0), 40.0, CELL)
	var diff: Dictionary = GrassLattice.cell_diff(have, c)
	var drop: Array[Vector2i] = diff["drop"]
	var add: Array[Vector2i] = diff["add"]
	assert_true(add.size() > 0 and add.size() == drop.size(), "one cell east: as many cells enter as leave (%d / %d)" % [add.size(), drop.size()])
	assert_true(add.size() < a.size() / 3, "only the leading ring is refilled, not the lattice (%d of %d)" % [add.size(), a.size()])
	for key: Vector2i in drop:
		assert_false(c.has(key), "dropped cell %s is not wanted any more" % key)
		assert_true(have.has(key), "dropped cell %s was held" % key)
	for key: Vector2i in add:
		assert_false(have.has(key), "added cell %s was not already held" % key)
		assert_true(c.has(key), "added cell %s is wanted" % key)
	assert_eq(GrassLattice.cell_of(-0.1, 12.0, CELL), Vector2i(-1, 1), "cells floor, so -0.1 is cell -1 and 12.0 is cell 1")


func test_thin_factor_is_full_near_and_reaches_far_fraction_at_the_edge() -> void:
	assert_true(is_equal_approx(GrassLattice.thin_factor(10.0, 70.0, 30.0, 0.25), 1.0), "inside the near radius everything shows")
	assert_true(is_equal_approx(GrassLattice.thin_factor(70.0, 70.0, 30.0, 0.25), 0.25), "at the edge the far fraction shows")
	assert_true(is_equal_approx(GrassLattice.thin_factor(500.0, 70.0, 30.0, 0.25), 0.25), "beyond the edge it clamps")
	assert_true(is_equal_approx(GrassLattice.thin_factor(50.0, 70.0, 30.0, 0.0), 0.5), "halfway thins halfway")
	assert_true(is_equal_approx(GrassLattice.thin_factor(50.0, 20.0, 30.0, 0.25), 1.0), "a radius inside the near radius never thins")


func test_clump_mesh_has_the_expected_blades_and_a_root_to_tip_gradient() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var mesh: ArrayMesh = GrassMesh.clump(4, 3, 0.05, Color(0.1, 0.12, 0.08), Color(0.6, 0.58, 0.45), rng)
	var arrays: Array = mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	assert_eq(verts.size(), 4 * (3 + 1) * 2, "4 blades x 4 rows x 2 verts")
	assert_eq((arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).size(), 4 * 3 * 6, "two triangles per segment")
	assert_eq(GrassMesh.vertex_count(mesh), verts.size(), "vertex_count matches the arrays")
	assert_true(is_zero_approx(uvs[0].y) and is_equal_approx(uvs[7].y, 1.0), "UV.y runs 0 at the root to 1 at the tip")
	assert_true(is_zero_approx(verts[0].y) and is_equal_approx(verts[7].y, 1.0), "blades are unit height")
	assert_true(colors[7].get_luminance() > colors[0].get_luminance() * 2.0, "the tip is far paler than the root")
	rng.seed = 7
	var twin: ArrayMesh = GrassMesh.clump(4, 3, 0.05, Color(0.1, 0.12, 0.08), Color(0.6, 0.58, 0.45), rng)
	assert_eq(twin.surface_get_arrays(0)[Mesh.ARRAY_VERTEX], verts, "the same seed builds the same clump")
	assert_true(GrassMesh.vertex_count(GrassMesh.pebble(Color.GRAY, rng)) > 8, "a pebble is a small lump")
	assert_eq(GrassMesh.vertex_count(GrassMesh.patch_quad()), 4, "a patch is one quad")


func test_fill_is_deterministic_per_cell_and_respects_water_and_slope() -> void:
	var layer: GrassLayer = GrassLayer.from_dict(LAYER, 20261024, 0)
	assert_true(layer.usable(), "the clump layer builds without a scene")
	var mmi: MultiMeshInstance3D = layer.make_instance(0)
	var cell := GrassCell.new()
	var out := PackedVector3Array()
	out.resize(layer.max_per_cell)
	var flat: Callable = func(_x: float, _z: float) -> float: return 2.0
	cell.prepare(Vector2i(3, -2), CELL, flat, WATER, PackedVector3Array(), 0.0)
	var n: int = layer.fill(Vector2i(3, -2), 0, 20261024, cell, mmi, out, Callable(), Callable())
	assert_true(n > CELL * CELL * 0.5, "flat dry ground fills densely (%d)" % n)
	var first: PackedVector3Array = out.slice(0, n)
	for p: Vector3 in first:
		assert_true(p.x >= 36.0 and p.x <= 48.0 and p.z >= -24.0 and p.z <= -12.0, "%s lies inside cell (3, -2)" % p)
		assert_true(absf(p.y - 2.0) < 0.05, "%s sits on the ground" % p)
	cell.prepare(Vector2i(3, -2), CELL, flat, WATER, PackedVector3Array(), 0.0)
	var again: int = layer.fill(Vector2i(3, -2), 0, 20261024, cell, mmi, out, Callable(), Callable())
	assert_eq(again, n, "refilling the same cell places the same count")
	assert_eq(out.slice(0, again), first, "refilling the same cell places the same positions")
	cell.prepare(Vector2i(4, -2), CELL, flat, WATER, PackedVector3Array(), 0.0)
	layer.fill(Vector2i(4, -2), 0, 20261024, cell, mmi, out, Callable(), Callable())
	assert_ne(out.slice(0, n), first, "a neighbouring cell grows differently")
	var half_drowned: Callable = func(x: float, _z: float) -> float: return WATER - 2.0 if x < 42.0 else WATER + 3.0
	cell.prepare(Vector2i(3, -2), CELL, half_drowned, WATER, PackedVector3Array(), 0.0)
	var dry: int = layer.fill(Vector2i(3, -2), 0, 20261024, cell, mmi, out, Callable(), Callable())
	assert_true(dry > 0 and dry < n, "a half-drowned cell grows on the dry half only (%d of %d)" % [dry, n])
	for k: int in dry:
		assert_true(out[k].x >= 42.0 - 0.001, "%s is on the dry side" % out[k])
	var cliff: Callable = func(x: float, _z: float) -> float: return x * 1.2
	cell.prepare(Vector2i(3, -2), CELL, cliff, WATER, PackedVector3Array(), 0.0)
	assert_eq(layer.fill(Vector2i(3, -2), 0, 20261024, cell, mmi, out, Callable(), Callable()), 0, "a 50 degree bank grows nothing")
	var fenced: Callable = func(_x: float, _z: float) -> float: return 0.0
	cell.prepare(Vector2i(3, -2), CELL, flat, WATER, PackedVector3Array(), 0.0)
	assert_eq(layer.fill(Vector2i(3, -2), 0, 20261024, cell, mmi, out, fenced, Callable()), 0, "a zero density filter grows nothing")
	mmi.free()
