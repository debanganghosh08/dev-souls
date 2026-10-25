extends "res://tests/test_case.gd"
## Terrain holes let built structures go underground (the castle crypt; later the Wood's drowned shrine and
## the Barrens' caves). The rule that matters: the visible mesh and the collision must agree exactly, or the
## player walks on air over a hole — or falls through solid-looking ground.

const HeightfieldScript := preload("res://scripts/systems/heightfield.gd")
const TerrainMeshScript := preload("res://scripts/systems/terrain_mesh.gd")

const CELLS := 16
const SPACING := 2.0

var _hf: Heightfield
var _origin := Vector2(0.0, 0.0)
var _grid: PackedFloat32Array


func setup() -> void:
	# A deliberately plain field: the hole behaviour must not depend on the landform.
	_hf = HeightfieldScript.from_dict({
		"size": 256.0,
		"seed": 7,
		"noise": {"octaves": 2, "frequency": 0.01, "amplitude": 4.0},
		"water_level": -5.0,
		"holes": [[8.0, 8.0, 6.0, 6.0]],
	})
	_grid = TerrainMeshScript.sample_grid(_hf, _origin, CELLS, SPACING)


func _no_holes() -> Array[Rect2]:
	return [] as Array[Rect2]


func test_holes_parse_from_data_and_reject_degenerate_rects() -> void:
	assert_eq(_hf.holes().size(), 1, "one hole parsed from the data")
	assert_eq(_hf.holes()[0], Rect2(8.0, 8.0, 6.0, 6.0), "hole matches the configured rect")
	var junk: Heightfield = HeightfieldScript.from_dict({
		"size": 256.0,
		"holes": [[1.0, 1.0, 0.0, 5.0], [1.0, 1.0, 5.0, 0.0], [1.0, 2.0], "nonsense", [1.0, 1.0, -4.0, -4.0]],
	})
	assert_eq(junk.holes().size(), 1, "zero-sized and malformed rects are dropped; a negative one is absolute")


func test_a_point_inside_the_hole_is_detected_and_outside_is_not() -> void:
	var holes: Array[Rect2] = _hf.holes()
	assert_true(HeightfieldScript.point_in_holes(holes, 10.0, 10.0), "centre of the hole is inside")
	assert_false(HeightfieldScript.point_in_holes(holes, 1.0, 1.0), "a point well outside is not")
	assert_false(HeightfieldScript.point_in_holes(holes, 20.0, 10.0), "a point past the far edge is not")
	assert_false(HeightfieldScript.point_in_holes(_no_holes(), 10.0, 10.0), "no holes means nothing is inside")


func test_mesh_and_collision_remove_exactly_the_same_cells() -> void:
	# This is the whole point: a mismatch means invisible floor or invisible holes.
	var holes: Array[Rect2] = _hf.holes()
	var with_mesh: int = _indices(holes)
	var without_mesh: int = _indices(_no_holes())
	var with_col: int = TerrainMeshScript.collision_faces(_grid, CELLS, SPACING, _origin, holes).size()
	var without_col: int = TerrainMeshScript.collision_faces(_grid, CELLS, SPACING, _origin, _no_holes()).size()
	assert_true(with_mesh < without_mesh, "the hole removed mesh triangles (%d < %d)" % [with_mesh, without_mesh])
	assert_true(with_col < without_col, "the hole removed collision triangles (%d < %d)" % [with_col, without_col])
	assert_eq(without_mesh - with_mesh, without_col - with_col, "mesh and collision lost the same count")


func test_a_chunk_away_from_any_hole_is_untouched() -> void:
	var far := Vector2(64.0, 64.0)
	var grid: PackedFloat32Array = TerrainMeshScript.sample_grid(_hf, far, CELLS, SPACING)
	var cut: int = TerrainMeshScript.collision_faces(grid, CELLS, SPACING, far, _hf.holes()).size()
	var whole: int = TerrainMeshScript.collision_faces(grid, CELLS, SPACING, far, _no_holes()).size()
	assert_eq(cut, whole, "a chunk nowhere near a hole keeps every face")


func test_holes_apply_at_every_lod_step() -> void:
	# Coarser LODs cover more ground per quad, so a hole must still register there or the distant mesh
	# visibly fills in the gap the near mesh leaves open.
	for step: int in [1, 2, 4]:
		var cut: int = _indices(_hf.holes(), step)
		var whole: int = _indices(_no_holes(), step)
		assert_true(cut < whole, "LOD step %d drops quads over the hole (%d < %d)" % [step, cut, whole])


func test_the_real_vale_hole_sits_inside_the_castle_plateau() -> void:
	# A hole outside the castle footprint would open a pit in open ground the player could fall into.
	var text: String = FileAccess.get_file_as_string("res://data/areas/vale.json")
	var data: Variant = JSON.parse_string(text)
	assert_true(data is Dictionary, "vale.json parses")
	if not data is Dictionary:
		return
	var vale: Heightfield = HeightfieldScript.from_dict(data)
	var holes: Array[Rect2] = vale.holes()
	assert_true(holes.size() >= 1, "the vale defines at least the crypt hole")
	var castle: Dictionary = {}
	for raw: Variant in (data as Dictionary).get("plateaus", []):
		if raw is Dictionary and str((raw as Dictionary).get("name", "")) == "castle":
			castle = raw
	assert_false(castle.is_empty(), "the vale has a castle plateau")
	if castle.is_empty():
		return
	var centre := Vector2(float(castle["centre"][0]), float(castle["centre"][1]))
	var radius: float = float(castle["radius"])
	for r: Rect2 in holes:
		for corner: Vector2 in [r.position, r.end, Vector2(r.position.x, r.end.y), Vector2(r.end.x, r.position.y)]:
			assert_true(corner.distance_to(centre) < radius,
					"hole corner %s is inside the castle plateau (r=%.0f)" % [corner, radius])


func _indices(holes: Array[Rect2], step: int = 1) -> int:
	var mesh: ArrayMesh = TerrainMeshScript.build_lod(_grid, CELLS, step, SPACING, 0.0, Vector2.ZERO, 1.0,
			_origin, holes)
	if mesh.get_surface_count() == 0:
		return 0
	return (mesh.surface_get_arrays(0)[Mesh.ARRAY_INDEX] as PackedInt32Array).size()
