extends "res://tests/test_case.gd"
## The site layer (D-022): where things are built, the ground they occupy, and the spawner that puts houses
## and points of interest on the terrain. Everything that scatters -- grass, trees, props -- now asks the
## keep-out mask instead of avoiding whole plateaus, so a wrong footprint here means grass through a floor or
## a bare ring round every house, and a wrong ground height means a house floating over a slope.

const AREA := "vale"
const VALE_SCENE := "res://scenes/levels/vale.tscn"
const FIXTURE := "res://tests/fixtures/slab_4x6.json"
const CASTLE_AT := Vector2(200.0, -160.0)

var _hf: Heightfield


func setup() -> void:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/areas/vale.json"))
	_hf = Heightfield.from_dict(data as Dictionary)


# --- the registry -----------------------------------------------------------------------------------------

func test_the_vale_registry_loads_its_three_fixed_sites_first() -> void:
	var files: Array[String] = SiteRegistry.files_for(AREA)
	assert_true(files.size() >= 1 and files[0].ends_with("/vale.json"), "the area's own file loads first")
	var fixed: Array[String] = []
	for site: Dictionary in SiteRegistry.load_area(AREA):
		if bool(site.get("fixed", false)):
			fixed.append(str(site["id"]))
	assert_eq(fixed, ["castle_morrow", "broken_village", "hearth_chamber"] as Array[String], "the three built places")


func test_every_site_id_and_every_interactable_id_is_unique_in_the_area() -> void:
	# Interactables persist through once-flags derived from their id: two chests sharing one would open
	# together and save as one.
	var sites: Dictionary = {}
	var props: Dictionary = {}
	for site: Dictionary in SiteRegistry.load_area(AREA):
		var id: String = str(site.get("id", ""))
		assert_ne(id, "", "every site has an id (%s)" % str(site.get("_file", "")))
		assert_false(sites.has(id), "site id '%s' is used once" % id)
		sites[id] = true
		for raw: Variant in site.get("props", []):
			var pid: String = str((raw as Dictionary).get("set", {}).get("id", "")) if raw is Dictionary else ""
			if pid == "":
				continue
			assert_false(props.has(pid), "interactable id '%s' is used once" % pid)
			props[pid] = true


func test_every_site_layout_exists_and_parses() -> void:
	for site: Dictionary in SiteRegistry.load_area(AREA):
		var path: String = str(site.get("layout", ""))
		assert_true(FileAccess.file_exists(path), "%s: layout %s exists" % [site.get("id", "?"), path])
		assert_false(StructureBuilder.load_layout(path).is_empty(), "%s: layout parses" % site.get("id", "?"))


func test_fixed_sites_agree_with_the_level_scene() -> void:
	# The scene places them; the registry only describes them. If the two ever disagree, grass grows through
	# one castle and stops short of another that is not there.
	var vale: Node = (load(VALE_SCENE) as PackedScene).instantiate()
	var placed: Dictionary = {}
	for child: Node in vale.get_children():
		var builder: Node = child.get_node_or_null(^"Builder")
		if child is Node3D and builder != null and builder.get(&"layout_path") != null:
			placed[str(builder.get(&"layout_path"))] = (child as Node3D).transform
	for site: Dictionary in SiteRegistry.load_area(AREA):
		if not bool(site.get("fixed", false)):
			continue
		var layout: String = str(site["layout"])
		assert_true(placed.has(layout), "%s is instanced in vale.tscn" % site["id"])
		if not placed.has(layout):
			continue
		var t: Transform3D = placed[layout]
		var at: Vector2 = SiteRegistry.at_of(site)
		assert_true(t.origin.is_equal_approx(Vector3(at.x, float(site["y"]), at.y)),
				"%s sits where the registry says (%s)" % [site["id"], t.origin])
	vale.free()


# --- footprints -------------------------------------------------------------------------------------------

func test_ground_pieces_count_and_raised_or_buried_ones_do_not() -> void:
	var castle: Dictionary = StructureBuilder.load_layout("res://data/structures/castle_morrow.json")
	var obbs: Array[Dictionary] = Footprint.layout_obbs(castle)
	assert_true(obbs.size() > 20, "the castle has many ground pieces (%d)" % obbs.size())
	assert_false(_any_has(obbs, -17.8, 24.1), "the wall-walk landing at 4.1 m is not ground")
	assert_true(_any_has(obbs, -16.125, 26.0), "the south curtain wall is ground")
	# Buried slabs are not ground pieces: under terrain they are invisible, and in a hole the hole is masked.
	# Points chosen clear of the castle's other walls: the north curtain runs over the crypt at z -26, and the
	# bell tower's west wall stands on the east apron.
	assert_false(_any_has(obbs, 10.5, -23.0), "the crypt's ceiling, 0.3 m under the graveyard, is not ground")
	assert_false(_any_has(obbs, 8.5, -18.0), "nor is the apron sunk into the crypt mouth's hole")


func test_a_stair_footprint_runs_back_from_its_foot() -> void:
	var r: Rect2 = Footprint.local_rect("stairs", {"w": 2.0, "rise": 1.0, "riser": 0.25, "tread": 0.35})
	assert_eq(r, Rect2(-1.0, -1.4, 2.0, 1.4), "four treads of 0.35 m climbing toward -Z")


func test_a_quarter_turn_swaps_the_axes() -> void:
	var obb: Dictionary = Footprint.transform_obb(
			{"centre": Vector2.ZERO, "ux": Vector2.RIGHT, "uz": Vector2(0.0, 1.0), "hx": 2.0, "hz": 1.0},
			Vector2.ZERO, 90.0)
	assert_true(Footprint.has_point(obb, 0.0, 1.9), "the long axis now runs along Z")
	assert_false(Footprint.has_point(obb, 1.9, 0.0), "and no longer along X")


# --- the mask ---------------------------------------------------------------------------------------------

func test_the_mask_blocks_inside_a_footprint_and_its_margin_only() -> void:
	var mask := KeepOutMask.new()
	mask.add_obb({"centre": Vector2(10.0, 10.0), "ux": Vector2.RIGHT, "uz": Vector2(0.0, 1.0), "hx": 2.0, "hz": 1.0}, 0.5)
	assert_true(mask.blocks(10.0, 10.0), "the centre is built on")
	assert_true(mask.blocks(12.3, 10.0), "the margin is kept clear")
	assert_false(mask.blocks(13.5, 10.0), "beyond the margin is free")
	# The last blocked cell's centre is at x = 12.25 (the 0.5 m cell holding the margin's edge at 12.5).
	assert_true(mask.blocks_near(14.0, 10.0, 2.0), "1.75 m away is near enough to matter for a tree")
	assert_false(mask.blocks_near(17.0, 10.0, 2.0), "far enough not to")


func test_a_diagonal_footprint_is_masked_on_the_diagonal_not_as_a_box() -> void:
	var mask := KeepOutMask.new()
	var obb: Dictionary = Footprint.transform_obb(
			{"centre": Vector2.ZERO, "ux": Vector2.RIGHT, "uz": Vector2(0.0, 1.0), "hx": 4.0, "hz": 0.5},
			Vector2.ZERO, 45.0)
	mask.add_obb(obb)
	# A thin 8 m wall turned 45 degrees has a bounding box about 6 m square; a box test would block all of it.
	var along: Vector2 = Vector2(obb["ux"]) * 3.0
	var across: Vector2 = Vector2(obb["uz"]) * 3.0
	assert_true(mask.blocks(along.x, along.y), "a point along the rotated wall is blocked")
	assert_true(Footprint.bounds(obb).has_point(across), "a point across it is inside the bounding box")
	assert_false(mask.blocks(across.x, across.y), "and yet free, because the wall is not a box")


func test_on_the_real_castle_walls_block_and_the_courtyard_and_hill_do_not() -> void:
	var mask: KeepOutMask = SiteRegistry.keep_out(AREA, 0.3)
	assert_true(mask.blocks(CASTLE_AT.x - 16.125, CASTLE_AT.y + 26.0), "the south curtain wall")
	assert_false(mask.blocks(CASTLE_AT.x, CASTLE_AT.y + 10.0), "the open courtyard grows grass")
	assert_false(mask.blocks(CASTLE_AT.x, CASTLE_AT.y + 100.0), "the hill up to the castle grows grass")
	assert_true(mask.blocks(CASTLE_AT.x + 8.5, CASTLE_AT.y - 18.0), "the crypt mouth, masked as a hole")
	assert_false(mask.blocks(CASTLE_AT.x + 10.5, CASTLE_AT.y - 23.0), "the graveyard over the buried crypt grows grass")
	assert_true(mask.blocks(0.0, 0.0), "the hole under the Mirror Pond")


# --- ground height ----------------------------------------------------------------------------------------

func test_a_site_floor_is_never_below_any_corner_of_its_footprint() -> void:
	# The default is the highest ground under the footprint, so nothing hangs over a gap on the low side.
	var site: Dictionary = {"id": "t", "layout": FIXTURE, "at": [120.0, 60.0], "yaw": 30.0}
	var span: Vector2 = Settlements.ground_span(site, _hf, 0.5)
	assert_true(span.y >= span.x, "the span is ordered")
	var floor_y: float = Settlements.ground_height(site, _hf, 0.5)
	assert_true(is_equal_approx(floor_y, span.y), "default ground is the highest point")
	for obb: Dictionary in SiteRegistry.world_obbs(site):
		for sx: float in [-1.0, 1.0]:
			for sz: float in [-1.0, 1.0]:
				var p: Vector2 = Vector2(obb["centre"]) + Vector2(obb["ux"]) * float(obb["hx"]) * sx \
						+ Vector2(obb["uz"]) * float(obb["hz"]) * sz
				assert_true(floor_y >= _hf.height_at(p.x, p.y) - 0.001, "corner %s is under the floor" % p)


func test_ground_can_be_the_lowest_point_absolute_or_lifted() -> void:
	var base: Dictionary = {"id": "t", "layout": FIXTURE, "at": [120.0, 60.0], "yaw": 0.0}
	var span: Vector2 = Settlements.ground_span(base, _hf, 0.5)
	var low: Dictionary = base.duplicate()
	low["ground"] = "min"
	assert_true(is_equal_approx(Settlements.ground_height(low, _hf, 0.5), span.x), "min is the lowest point")
	var fixed: Dictionary = base.duplicate()
	fixed["ground"] = 7.5
	assert_true(is_equal_approx(Settlements.ground_height(fixed, _hf), 7.5), "a number is absolute")
	var lifted: Dictionary = base.duplicate()
	lifted["lift"] = 0.4
	assert_true(is_equal_approx(Settlements.ground_height(lifted, _hf, 0.5), span.y + 0.4), "lift adds")


# --- spawning ---------------------------------------------------------------------------------------------

func test_a_prop_entry_sets_typed_properties_from_json() -> void:
	# JSON has no StringName: an id assigned as a String would never match a flag lookup.
	var chest: Node = Settlements.spawn_prop({
		"scene": "res://scenes/props/chest.tscn", "at": [1.0, 0.0, -2.0], "yaw": 90.0,
		"set": {"id": "test_chest", "contents": {"sword": 1}, "prompt": "Open it"},
	})
	assert_not_null(chest, "the chest scene instanced")
	if chest == null:
		return
	assert_eq(typeof(chest.get(&"id")), TYPE_STRING_NAME, "id arrived as a StringName")
	assert_eq(chest.get(&"id"), &"test_chest", "with the right value")
	assert_eq((chest.get(&"contents") as Dictionary).size(), 1, "contents came through")
	assert_true((chest as Node3D).position.is_equal_approx(Vector3(1.0, 0.0, -2.0)), "placed site-locally")
	chest.free()


func test_coercion_follows_the_type_the_property_already_has() -> void:
	var n := Node3D.new()
	Settlements.set_coerced(n, "visible", 0)
	assert_false(n.visible, "an int into a bool")
	Settlements.set_coerced(n, "rotation_order", 2.0)
	assert_eq(n.rotation_order, 2, "a JSON float into an int")
	n.free()


func test_one_layout_placed_twice_shares_its_meshes_when_asked() -> void:
	StructureBuilder.clear_shared()
	var a := StructureBuilder.new()
	var b := StructureBuilder.new()
	var c := StructureBuilder.new()
	for builder: StructureBuilder in [a, b, c]:
		builder.layout_path = FIXTURE
	a.share_pieces = true
	b.share_pieces = true
	for builder: StructureBuilder in [a, b, c]:
		builder.build()
	var mesh_a: Mesh = (a.get_child(0).get_node(^"Mesh") as MeshInstance3D).mesh
	var mesh_b: Mesh = (b.get_child(0).get_node(^"Mesh") as MeshInstance3D).mesh
	var mesh_c: Mesh = (c.get_child(0).get_node(^"Mesh") as MeshInstance3D).mesh
	assert_true(mesh_a == mesh_b, "two sharing placements draw the same mesh")
	assert_false(mesh_a == mesh_c, "a builder that did not ask builds its own")
	for builder: StructureBuilder in [a, b, c]:
		builder.free()
	StructureBuilder.clear_shared()


func test_an_unknown_piece_kind_falls_through_both_extension_kits_to_nothing() -> void:
	assert_true(StructureKitHouse.make("no_such_piece", {}).is_empty(), "the house kit does not claim it")
	assert_true(StructureKitProps.make("no_such_piece", {}).is_empty(), "nor the props kit")


func _any_has(obbs: Array[Dictionary], x: float, z: float) -> bool:
	for obb: Dictionary in obbs:
		if Footprint.has_point(obb, x, z):
			return true
	return false
