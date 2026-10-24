extends "res://tests/test_case.gd"
## Pure TreeGen / TreeParams / TreeMaterials tests: no scene tree, no autoloads, meshes built directly.

const BAD_JSON_PATH := "user://treegen_bad_test.json"
const MISSING_PATH := "res://data/does_not_exist_trees.json"
const HEIGHT_TOLERANCE := 0.001


func setup() -> void:
	TreeParams.reset()
	TreeMaterials.clear_cache()


func teardown() -> void:
	if FileAccess.file_exists(BAD_JSON_PATH):
		DirAccess.remove_absolute(BAD_JSON_PATH)
	TreeParams.reset()
	TreeMaterials.clear_cache()


func test_same_seed_is_byte_identical() -> void:
	for archetype: String in TreeGen.archetypes():
		var p: Dictionary = TreeGen.params_for(archetype)
		var a: Dictionary = TreeGen.build(p, 4242)
		var b: Dictionary = TreeGen.build(p, 4242)
		var va: PackedVector3Array = _verts(a["trunk"])
		var vb: PackedVector3Array = _verts(b["trunk"])
		assert_eq(va.size(), vb.size(), "%s: same seed gives the same trunk vertex count" % archetype)
		assert_true(va.size() > 0, "%s: trunk has vertices" % archetype)
		assert_eq(va[0], vb[0], "%s: first trunk vertex identical" % archetype)
		assert_eq(va[va.size() - 1], vb[vb.size() - 1], "%s: last trunk vertex identical" % archetype)
		assert_true(_arrays(a["trunk"]) == _arrays(b["trunk"]), "%s: every trunk array identical" % archetype)
		assert_true(_arrays(a["cards"]) == _arrays(b["cards"]), "%s: every card array identical" % archetype)
		assert_eq(a["height"], b["height"], "%s: same height" % archetype)


func test_different_seeds_differ() -> void:
	var p: Dictionary = TreeGen.params_for("fir")
	var a: Dictionary = TreeGen.build(p, 1)
	var b: Dictionary = TreeGen.build(p, 2)
	var va: PackedVector3Array = _verts(a["trunk"])
	var vb: PackedVector3Array = _verts(b["trunk"])
	assert_ne(va[va.size() - 1], vb[vb.size() - 1], "different seeds move the trunk tip")
	assert_true(_verts(a["cards"]) != _verts(b["cards"]), "different seeds give different cards")


func test_every_archetype_builds_in_range() -> void:
	var names: PackedStringArray = TreeGen.archetypes()
	assert_eq(names.size(), 4, "four archetypes are defined")
	for archetype: String in names:
		var p: Dictionary = TreeGen.params_for(archetype)
		var tree: Dictionary = TreeGen.build(p, 99)
		assert_true(_verts(tree["trunk"]).size() > 0, "%s: trunk has vertices" % archetype)
		var lo: float = float(p["height"][0]) - HEIGHT_TOLERANCE
		var hi: float = float(p["height"][1]) + HEIGHT_TOLERANCE
		var h: float = float(tree["height"])
		assert_true(h >= lo and h <= hi, "%s: height %.2f within [%s, %s]" % [archetype, h, p["height"][0], p["height"][1]])
		assert_true(float(tree["collider_radius"]) > 0.0, "%s: collider radius positive" % archetype)
		var tip_y: float = _verts(tree["trunk"])[_verts(tree["trunk"]).size() - 1].y
		assert_true(tip_y >= h, "%s: trunk apex reaches the configured height" % archetype)
		if archetype == "dead":
			assert_eq((tree["cards"] as ArrayMesh).get_surface_count(), 0, "dead trees have no cards")
		else:
			assert_true(_verts(tree["cards"]).size() > 0, "%s: has cards" % archetype)
			assert_true(float(tree["radius"]) > float(tree["collider_radius"]), "%s: crown wider than trunk" % archetype)


func test_card_count_matches_whorls_times_branches() -> void:
	# One quad per branch, single winding: double-sidedness comes from the material's cull_disabled.
	for archetype: String in ["fir", "pine", "ancient"]:
		var p: Dictionary = TreeGen.params_for(archetype)
		var tree: Dictionary = TreeGen.build(p, 5)
		var cards: int = int(p["whorls"]) * int(p["branches_per_whorl"])
		assert_eq(_verts(tree["cards"]).size(), cards * 4, "%s: 4 vertices per card" % archetype)
		assert_eq((_arrays(tree["cards"])[Mesh.ARRAY_INDEX] as PackedInt32Array).size(), cards * 6, "%s: 6 indices per card" % archetype)


func test_trunk_topology() -> void:
	var p: Dictionary = TreeGen.params_for("fir")
	var tree: Dictionary = TreeGen.build(p, 3)
	var expected: int = (int(p["segments"]) + 1) * (int(p["rings"]) + 1) + 1
	assert_eq(_verts(tree["trunk"]).size(), expected, "trunk is (segments+1) x (rings+1) ring vertices plus an apex")
	var arrays: Array = _arrays(tree["trunk"])
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	assert_true(is_equal_approx(uvs[0].x, 0.0) and is_equal_approx(uvs[int(p["segments"])].x, 1.0), "trunk UV u wraps exactly once around a ring")
	assert_true(uvs[uvs.size() - 1].y > 1.0, "trunk UV v tiles up the height (more than one tile over the trunk)")
	for n: Vector3 in (arrays[Mesh.ARRAY_NORMAL] as PackedVector3Array):
		if not is_equal_approx(n.length(), 1.0):
			_fail("trunk normal not unit length: %s" % n)
			break


func test_card_uvs_inside_atlas() -> void:
	for archetype: String in ["fir", "pine"]:
		var tree: Dictionary = TreeGen.build(TreeGen.params_for(archetype), 11)
		var uvs: PackedVector2Array = _arrays(tree["cards"])[Mesh.ARRAY_TEX_UV]
		var bad: int = 0
		for uv: Vector2 in uvs:
			if uv.x < 0.0 or uv.x > 1.0 or uv.y < 0.0 or uv.y > 1.0:
				bad += 1
		assert_eq(bad, 0, "%s: all card UVs inside the atlas" % archetype)


func test_missing_json_falls_back() -> void:
	var data: Dictionary = TreeParams.load_file(MISSING_PATH)
	assert_eq(data.size(), 4, "missing file yields the four built-in archetypes")
	assert_true(data.has("fir") and data.has("dead"), "fallback contains fir and dead")
	var tree: Dictionary = TreeGen.build(data["fir"], 1)
	assert_true(_verts(tree["trunk"]).size() > 0, "fallback params still build a tree")


func test_malformed_json_falls_back() -> void:
	var f: FileAccess = FileAccess.open(BAD_JSON_PATH, FileAccess.WRITE)
	f.store_string("{ \"fir\": { nope")
	f.close()
	var data: Dictionary = TreeParams.load_file(BAD_JSON_PATH)
	assert_eq(data.size(), 4, "malformed file yields the built-in archetypes")
	assert_true((data["pine"] as Dictionary).has("atlas_cells"), "fallback archetypes carry every BASE key")


func test_degenerate_params_do_not_crash_or_nan() -> void:
	var cases: Array[Dictionary] = [
		{"whorls": 0}, {"segments": 1}, {"height": [0.0, 0.0]}, {"base_radius": [-1.0, -1.0]},
		{"rings": 0}, {"branches_per_whorl": 0}, {"atlas_cells": [], "atlas_grid": [0, 0]},
		{"card_length": 0.0, "tip_scale": 0.0}, {"lean_deg": 400.0, "bend": 5.0, "gnarl": 3.0},
	]
	for c: Dictionary in cases:
		var p: Dictionary = TreeGen.params_for("fir")
		for key: String in c.keys():
			p[key] = c[key]
		var tree: Dictionary = TreeGen.build(p, 8)
		assert_true(_verts(tree["trunk"]).size() > 0, "%s: trunk still built" % str(c))
		assert_false(_has_nan(tree["trunk"]) or _has_nan(tree["cards"]), "%s: no NaN in vertex arrays" % str(c))
		assert_false(is_nan(float(tree["height"])) or is_nan(float(tree["radius"])), "%s: height/radius finite" % str(c))


func test_lod_params_reduce_cards() -> void:
	var p: Dictionary = TreeGen.params_for("fir")
	var lod1: Dictionary = TreeGen.lod_params(p, 1)
	assert_true(int(lod1["whorls"]) < int(p["whorls"]), "lod1 has fewer whorls")
	assert_true(float(lod1["card_length"]) > float(p["card_length"]), "lod1 cards are larger to keep the mass")
	var full: int = _verts(TreeGen.build(p, 1)["cards"]).size()
	var reduced: int = _verts(TreeGen.build(lod1, 1)["cards"]).size()
	assert_true(reduced > 0 and reduced < full, "lod1 card mesh is smaller (%d < %d)" % [reduced, full])


func test_materials_are_cached_per_archetype() -> void:
	var a: Material = TreeMaterials.cards_for("fir")
	var b: Material = TreeMaterials.cards_for("fir")
	assert_true(is_same(a, b), "asking twice for fir cards returns the same material object")
	assert_true(is_same(TreeMaterials.bark_for("pine"), TreeMaterials.bark_for("pine")), "bark is cached too")
	assert_false(is_same(TreeMaterials.bark_for("pine"), TreeMaterials.bark_for("fir")), "different archetypes get different bark")
	TreeMaterials.clear_cache()
	assert_false(is_same(a, TreeMaterials.cards_for("fir")), "clear_cache drops the cached material")


func _verts(mesh: ArrayMesh) -> PackedVector3Array:
	if mesh.get_surface_count() == 0:
		return PackedVector3Array()
	return mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]


func _arrays(mesh: ArrayMesh) -> Array:
	return mesh.surface_get_arrays(0) if mesh.get_surface_count() > 0 else []


func _has_nan(mesh: ArrayMesh) -> bool:
	if mesh.get_surface_count() == 0:
		return false
	var arrays: Array = mesh.surface_get_arrays(0)
	for v: Vector3 in (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array):
		if is_nan(v.x) or is_nan(v.y) or is_nan(v.z):
			return true
	for n: Vector3 in (arrays[Mesh.ARRAY_NORMAL] as PackedVector3Array):
		if is_nan(n.x) or is_nan(n.y) or is_nan(n.z):
			return true
	for uv: Vector2 in (arrays[Mesh.ARRAY_TEX_UV] as PackedVector2Array):
		if is_nan(uv.x) or is_nan(uv.y):
			return true
	return false
