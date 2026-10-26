extends "res://tests/test_case.gd"
## W6-02: the castle read as "cardboard" because every surface tiled its texture once per metre whatever the
## image depicted, and a plain slab has nothing but a sharp top edge. These tests pin the data path
## (materials.json merged over defaults, bad files fall back), the per-material tiling and the per-piece
## UV offset the builder now takes, and the opt-in plinth and string course on walls and blocks: that they
## add geometry with matching collision, break around openings, and stay off by default. Headless has no
## textures and no renderer, so none of this proves the castle now looks like stone -- only the numbers.

const BAD_PATH := "user://structure_materials_bad_test.json"
const PARTIAL_PATH := "user://structure_materials_partial_test.json"
const LAYOUT := "res://data/structures/castle_morrow.json"
const TEXTURED: Array[String] = ["castle_wall", "blocks", "stone", "roof", "planks", "plaster"]
const FIELDS: Array[String] = ["metres_per_tile", "normal_scale", "roughness", "ao_light_affect"]
## The entries the task opted in; every crypt_ piece must stay untouched (its slabs seal a terrain hole).
const TRIMMED: Array[String] = [
	"south_wall_w", "west_wall_s", "north_wall_e1", "north_wall_e2", "east_wall_n",
	"gate_tower_w", "gate_tower_e", "keep_west_n", "keep_west_s",
]


func teardown() -> void:
	for path: String in [BAD_PATH, PARTIAL_PATH]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	StructureMaterials.clear_cache()


func test_materials_file_parses_and_tunes_every_textured_kind() -> void:
	var real: Dictionary = StructureMaterials.load_from()
	for kind: String in TEXTURED:
		assert_true(real.has(kind), "materials.json defines %s" % kind)
		for field: String in FIELDS:
			assert_true(real[kind].has(field), "%s has %s" % [kind, field])
			assert_true(float(real[kind][field]) > 0.0, "%s.%s is positive" % [kind, field])
	assert_true(StructureMaterials.metres_per_tile("castle_wall") > 0.0, "the castle wall tile size is positive")
	assert_eq(StructureMaterials.metres_per_tile("bronze"), 1.0, "an untextured kind keeps one tile per metre")
	assert_eq(StructureMaterials.metres_per_tile("no_such_kind"), 1.0, "an unknown kind keeps one tile per metre")


func test_missing_and_malformed_materials_fall_back_without_crashing() -> void:
	var missing: Dictionary = StructureMaterials.load_from("res://data/structures/does_not_exist.json", false)
	assert_eq(missing, StructureMaterials.DEFAULTS, "a missing file yields the built-in defaults")
	var f: FileAccess = FileAccess.open(BAD_PATH, FileAccess.WRITE)
	f.store_string("{ \"castle_wall\": { nope")
	f.close()
	var bad: Dictionary = StructureMaterials.load_from(BAD_PATH, false)
	assert_eq(bad, StructureMaterials.DEFAULTS, "a malformed file yields the built-in defaults")
	f = FileAccess.open(BAD_PATH, FileAccess.WRITE)
	f.store_string("[1, 2, 3]")
	f.close()
	assert_eq(StructureMaterials.load_from(BAD_PATH, false), StructureMaterials.DEFAULTS, "a non-object file yields the defaults")


func test_partial_entries_merge_field_by_field() -> void:
	var f: FileAccess = FileAccess.open(PARTIAL_PATH, FileAccess.WRITE)
	f.store_string("{\"castle_wall\": {\"metres_per_tile\": 3.0, \"roughness\": \"soft\"}, \"moss\": {\"normal_scale\": 0.2}, \"junk\": 7}")
	f.close()
	var merged: Dictionary = StructureMaterials.load_from(PARTIAL_PATH, false)
	var cw: Dictionary = merged["castle_wall"]
	assert_eq(float(cw["metres_per_tile"]), 3.0, "the file's tile size overrides the default")
	assert_eq(float(cw["normal_scale"]), float(StructureMaterials.DEFAULTS["castle_wall"]["normal_scale"]), "an omitted field keeps its default")
	assert_eq(float(cw["roughness"]), 1.0, "a non-numeric field is skipped, not applied")
	assert_true(merged.has("moss"), "a new kind is accepted")
	assert_eq(float(merged["moss"]["metres_per_tile"]), 1.0, "a new kind starts from BASE for fields it omits")
	assert_false(merged.has("junk"), "a non-object entry is ignored")
	assert_true(merged.has("blocks"), "kinds the file does not mention keep their defaults")


func test_builder_default_still_tiles_once_per_metre() -> void:
	var b := StructureMeshBuilder.new()
	b.add_box(Transform3D(Basis.IDENTITY, Vector3(0.0, 1.5, 0.0)), Vector3(4.0, 3.0, 0.5))
	var span: Vector2 = _upright_uv_span(b.commit(null))
	assert_true(is_equal_approx(span.x, 4.0), "no tiling given: a 4 m wall spans 4 tiles along (got %.2f)" % span.x)
	assert_true(is_equal_approx(span.y, 3.0), "no tiling given: a 3 m wall spans 3 tiles up (got %.2f)" % span.y)
	assert_eq(b.uv_offset, Vector2.ZERO, "no offset given: UVs are unshifted")


func test_builder_tiling_and_offset_change_the_uvs() -> void:
	var plain := StructureMeshBuilder.new()
	plain.add_box(Transform3D(Basis.IDENTITY, Vector3(0.0, 1.5, 0.0)), Vector3(4.0, 3.0, 0.5))
	var scaled := StructureMeshBuilder.new(2.0)
	scaled.add_box(Transform3D(Basis.IDENTITY, Vector3(0.0, 1.5, 0.0)), Vector3(4.0, 3.0, 0.5))
	var span: Vector2 = _upright_uv_span(scaled.commit(null))
	assert_true(is_equal_approx(span.x, 2.0), "2 m per tile: a 4 m wall spans 2 tiles along (got %.2f)" % span.x)
	assert_true(is_equal_approx(span.y, 1.5), "2 m per tile: a 3 m wall spans 1.5 tiles up (got %.2f)" % span.y)
	var offset := Vector2(0.25, 0.5)
	var shifted := StructureMeshBuilder.new(1.0, offset)
	shifted.add_box(Transform3D(Basis.IDENTITY, Vector3(0.0, 1.5, 0.0)), Vector3(4.0, 3.0, 0.5))
	var a: PackedVector2Array = plain.commit(null).surface_get_arrays(0)[Mesh.ARRAY_TEX_UV]
	var c: PackedVector2Array = shifted.commit(null).surface_get_arrays(0)[Mesh.ARRAY_TEX_UV]
	assert_eq(a.size(), c.size(), "the offset changes no vertex count")
	for i: int in range(a.size()):
		assert_true((c[i] - a[i]).is_equal_approx(offset), "every UV moved by the offset")
	var guarded := StructureMeshBuilder.new(0.0)
	assert_eq(guarded.metres_per_tile, 1.0, "a zero tile size is refused, not divided by")


func test_uv_offset_is_fixed_per_name_and_differs_between_names() -> void:
	var a: Vector2 = StructureMeshBuilder.uv_offset_for("south_wall_w")
	assert_eq(a, StructureMeshBuilder.uv_offset_for("south_wall_w"), "the same name always gives the same offset")
	assert_ne(a, StructureMeshBuilder.uv_offset_for("west_wall_s"), "two different walls get different offsets")
	assert_ne(StructureMeshBuilder.uv_offset_for("keep_west_n"), StructureMeshBuilder.uv_offset_for("keep_west_s"), "near-identical names still differ")
	assert_eq(StructureMeshBuilder.uv_offset_for(""), Vector2.ZERO, "no name, no shift")
	for name: String in TRIMMED:
		var o: Vector2 = StructureMeshBuilder.uv_offset_for(name)
		assert_true(o.x >= 0.0 and o.x < 1.0 and o.y >= 0.0 and o.y < 1.0, "%s offset stays inside one tile" % name)


func test_kit_wall_uses_the_material_tiling_and_the_name_offset() -> void:
	var tile: float = StructureMaterials.metres_per_tile("castle_wall")
	var named: Dictionary = StructureKit.wall(4.0, 3.0, 0.5, "castle_wall", {}, {}, {}, "south_wall_w")
	var span: Vector2 = _upright_uv_span(named["mesh"])
	assert_true(is_equal_approx(span.x, 4.0 / tile), "a kit wall tiles at its material's metres_per_tile (got %.2f)" % span.x)
	var anon: Dictionary = StructureKit.wall(4.0, 3.0, 0.5, "castle_wall")
	var a: PackedVector2Array = (anon["mesh"] as ArrayMesh).surface_get_arrays(0)[Mesh.ARRAY_TEX_UV]
	var n: PackedVector2Array = (named["mesh"] as ArrayMesh).surface_get_arrays(0)[Mesh.ARRAY_TEX_UV]
	var expected: Vector2 = StructureMeshBuilder.uv_offset_for("south_wall_w")
	assert_true((n[0] - a[0]).is_equal_approx(expected), "the named wall's UVs are the anonymous wall's plus its offset")
	var via_builder: Dictionary = StructureBuilder.make_piece("wall", {"w": 4.0, "h": 3.0, "t": 0.5, "mat": "castle_wall"}, "south_wall_w")
	var v: PackedVector2Array = (via_builder["mesh"] as ArrayMesh).surface_get_arrays(0)[Mesh.ARRAY_TEX_UV]
	assert_eq(v, n, "StructureBuilder.make_piece passes the entry name through")


func test_plain_wall_and_block_are_still_one_box() -> void:
	var wall: Dictionary = StructureKit.wall(4.0, 3.0, 0.5, "castle_wall", {}, {}, {}, "any")
	assert_eq(_verts(wall).size(), 24, "a plain wall is one box: 6 faces x 4 vertices")
	assert_eq((wall["shapes"] as Array).size(), 1, "a plain wall has one collision box")
	var block: Dictionary = StructureBuilder.make_piece("block", {"w": 1.0, "h": 1.0, "d": 1.0, "mat": "castle_wall"})
	assert_eq(_verts(block).size(), 24, "a plain block is one box")
	var junk: Dictionary = StructureBuilder.make_piece("wall", {"w": 4.0, "h": 3.0, "t": 0.5, "plinth": true, "course": "yes"})
	assert_eq(_verts(junk).size(), 24, "non-object plinth/course params are ignored, not crashed on")


func test_plinth_adds_a_wider_base_with_matching_collision() -> void:
	var piece: Dictionary = StructureKit.wall(4.0, 3.0, 0.5, "castle_wall", {}, {"h": 0.4, "out": 0.12})
	assert_eq(_verts(piece).size(), 48, "a plinth is one more box")
	var shapes: Array = piece["shapes"]
	assert_eq(shapes.size(), 2, "the plinth carries its own collision box")
	var box: BoxShape3D = shapes[1]["shape"]
	assert_true(box.size.is_equal_approx(Vector3(4.0, 0.4, 0.74)), "plinth collider is wall width, 0.4 high, 0.12 proud each side (got %s)" % box.size)
	assert_true(is_equal_approx((shapes[1]["transform"] as Transform3D).origin.y, 0.2), "plinth collider sits on the ground")
	assert_true(_proud_verts_within(piece, 0.25, 0.0, 0.4), "every vertex outside the wall faces belongs to the 0..0.4 m plinth")
	assert_eq(_proud_count(piece, 0.25), 24, "every vertex of the plinth box stands proud of the wall faces, and nothing else does")


func test_course_adds_a_string_course_with_matching_collision() -> void:
	var piece: Dictionary = StructureKit.wall(4.0, 6.5, 1.3, "castle_wall", {}, {}, {"y": 4.2, "h": 0.25, "out": 0.1})
	assert_eq(_verts(piece).size(), 48, "a course is one more box")
	var shapes: Array = piece["shapes"]
	assert_eq(shapes.size(), 2, "the course carries its own collision box")
	var box: BoxShape3D = shapes[1]["shape"]
	assert_true(box.size.is_equal_approx(Vector3(4.0, 0.25, 1.5)), "course collider is wall width, 0.25 high, 0.1 proud each side (got %s)" % box.size)
	assert_true(is_equal_approx((shapes[1]["transform"] as Transform3D).origin.y, 4.325), "course collider is centred on its band")
	assert_true(_proud_verts_within(piece, 0.65, 4.2, 4.45), "every vertex outside the wall faces lies in the 4.2..4.45 m course")
	var capped: Dictionary = StructureKit.wall(4.0, 3.0, 0.5, "castle_wall", {}, {}, {"y": 2.9, "h": 0.25, "out": 0.1})
	var cap_box: BoxShape3D = (capped["shapes"] as Array)[1]["shape"]
	assert_true(is_equal_approx(cap_box.size.y, 0.1), "a course that would poke above the wall is clipped to its top")
	var above: Dictionary = StructureKit.wall(4.0, 3.0, 0.5, "castle_wall", {}, {}, {"y": 3.5, "h": 0.25, "out": 0.1})
	assert_eq(_verts(above).size(), 24, "a course entirely above the wall adds nothing")


func test_plinth_and_course_do_not_cross_an_opening() -> void:
	var door := {"width": 1.4, "height": 2.4}
	var piece: Dictionary = StructureKit.wall(6.0, 3.0, 0.5, "blocks", door, {"h": 0.4, "out": 0.12})
	var shapes: Array = piece["shapes"]
	assert_eq(shapes.size(), 5, "two piers, a lintel and a plinth segment either side of the door")
	for s: Dictionary in shapes:
		var box: BoxShape3D = s["shape"]
		var xform: Transform3D = s["transform"]
		var lo_x: float = xform.origin.x - box.size.x * 0.5
		var hi_x: float = xform.origin.x + box.size.x * 0.5
		var lo_y: float = xform.origin.y - box.size.y * 0.5
		assert_false(hi_x > -0.7 + 0.001 and lo_x < 0.7 - 0.001 and lo_y < 2.4, "no collision box intrudes into the doorway")
	for v: Vector3 in _verts(piece):
		if absf(v.z) > 0.25 + 0.001:
			assert_false(v.x > -0.7 + 0.001 and v.x < 0.7 - 0.001, "no plinth vertex inside the doorway (x=%.2f)" % v.x)
	var window := {"width": 1.0, "height": 2.0, "sill": 1.6}
	var under: Dictionary = StructureKit.wall(8.0, 6.0, 0.7, "blocks", window, {"h": 0.4, "out": 0.12})
	var under_shapes: Array = under["shapes"]
	assert_eq(under_shapes.size(), 5, "a plinth below a window sill runs the full width (4 wall boxes + 1 plinth)")
	assert_true(is_equal_approx((under_shapes[4]["shape"] as BoxShape3D).size.x, 8.0), "the unbroken plinth is wall width")
	var through: Dictionary = StructureKit.wall(8.0, 6.0, 0.7, "blocks", window, {}, {"y": 2.0, "h": 0.25, "out": 0.1})
	assert_eq((through["shapes"] as Array).size(), 6, "a course level with the window is split either side of it")
	for s: Dictionary in through["shapes"]:
		var box: BoxShape3D = s["shape"]
		var xform: Transform3D = s["transform"]
		if box.size.z > 0.7 + 0.001:
			assert_true(xform.origin.x + box.size.x * 0.5 <= -0.5 + 0.001 or xform.origin.x - box.size.x * 0.5 >= 0.5 - 0.001, "course segments stop at the jambs")
	var offset_door := {"width": 1.4, "height": 2.4, "offset": 2.0}
	var side: Dictionary = StructureKit.wall(6.0, 3.0, 0.5, "blocks", offset_door, {"h": 0.4, "out": 0.12})
	for v: Vector3 in _verts(side):
		if absf(v.z) > 0.25 + 0.001:
			assert_false(v.x > 1.3 + 0.001 and v.x < 2.7 - 0.001, "an off-centre doorway is respected too (x=%.2f)" % v.x)


func test_block_trim_wraps_all_four_sides() -> void:
	var piece: Dictionary = StructureBuilder.make_piece("block", {"w": 4.5, "h": 10.0, "d": 5.0, "mat": "castle_wall",
		"plinth": {"h": 0.4, "out": 0.12}, "course": {"y": 4.2, "h": 0.25, "out": 0.1}})
	assert_eq(_verts(piece).size(), 72, "block plus plinth plus course is three boxes")
	var shapes: Array = piece["shapes"]
	assert_eq(shapes.size(), 3, "each band has a collider")
	assert_true((shapes[1]["shape"] as BoxShape3D).size.is_equal_approx(Vector3(4.74, 0.4, 5.24)), "the plinth grows the block on X and Z")
	assert_true((shapes[2]["shape"] as BoxShape3D).size.is_equal_approx(Vector3(4.7, 0.25, 5.2)), "the course grows the block on X and Z")
	assert_true(is_equal_approx((shapes[2]["transform"] as Transform3D).origin.y, 4.325), "the course sits at its y")


func test_castle_opts_the_big_walls_in_and_leaves_the_crypt_alone() -> void:
	var layout: Dictionary = StructureBuilder.load_layout(LAYOUT)
	var seen: Dictionary = {}
	for entry: Variant in layout.get("pieces", []):
		var name: String = str(entry.get("name", ""))
		var p: Dictionary = entry.get("params", {})
		seen[name] = true
		if name.begins_with("crypt_"):
			assert_false(p.has("plinth") or p.has("course"), "%s is untouched" % name)
		if name in TRIMMED:
			assert_true(p.has("plinth") and p.has("course"), "%s has both plinth and course" % name)
			assert_true(float(p["plinth"].get("out", 1.0)) <= 0.2 and float(p["plinth"].get("h", 1.0)) <= 0.5, "%s plinth is modest" % name)
			assert_true(float(p["course"].get("out", 1.0)) <= 0.2 and float(p["course"].get("h", 1.0)) <= 0.3, "%s course is modest" % name)
			var built: Dictionary = StructureBuilder.make_piece(str(entry["kind"]), p, name)
			assert_true((built["shapes"] as Array).size() >= 3, "%s builds with trim collision" % name)
	for name: String in TRIMMED:
		assert_true(seen.has(name), "layout still has %s" % name)


func _verts(piece: Dictionary) -> PackedVector3Array:
	return (piece["mesh"] as ArrayMesh).surface_get_arrays(0)[Mesh.ARRAY_VERTEX]


## U and V extent over the upright faces only (the top and bottom tile on X/Z instead).
func _upright_uv_span(mesh: ArrayMesh) -> Vector2:
	var arrays: Array = mesh.surface_get_arrays(0)
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for i: int in range(uvs.size()):
		if absf(normals[i].y) > 0.5:
			continue
		lo = lo.min(uvs[i])
		hi = hi.max(uvs[i])
	return hi - lo


func _proud_verts_within(piece: Dictionary, half_t: float, y0: float, y1: float) -> bool:
	for v: Vector3 in _verts(piece):
		if absf(v.z) > half_t + 0.001 and (v.y < y0 - 0.001 or v.y > y1 + 0.001):
			return false
	return true


func _proud_count(piece: Dictionary, half_t: float) -> int:
	var n: int = 0
	for v: Vector3 in _verts(piece):
		if absf(v.z) > half_t + 0.001:
			n += 1
	return n
