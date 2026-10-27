extends "res://tests/test_case.gd"
## Houses (W8-H): the house kit pieces, the five archetype layouts in data/structures/houses/ (each intact
## and ruined), their twenty placements in data/sites/vale_houses.json, and the loot they hold. The rules
## every site must obey live in tests/test_site_placement.gd; this file proves what is specific to houses:
## that each one builds, that a player can get in and up to its loft, that its doorstep reaches the ground
## wherever it stands, that every prop rests on something, and that every item in the game has exactly one
## place it comes from. Nothing here says whether a house looks like a house: the runner has no renderer.

const HOUSES_DIR := "res://data/structures/houses/"
const HOUSES_FILE := "vale_houses.json"
const AREA := "vale"
const ITEMS := "res://data/items.json"
const LORE := "res://data/lore.json"
const PLAYER_STEP_UP := 0.4
const PLAYER_RADIUS := 0.35
const PLAYER_HEIGHT := 1.75
const MIN_DOORWAY_WIDTH := 1.0
const MIN_DOORWAY_HEIGHT := 2.2
## Every layout's floor slab is this thick, so its top is the threshold the door opening must clear.
const SLAB_TOP := 0.12
## How far the front stair descends below the floor (docs/WORLD_PLAN.md: the foundation reaches ~2 m, the
## doorstep covers the 1.6 m of ground drop a site may stand on).
const STEP_DOWN := 1.6
const ANCHOR_REACH := 15.0
## The vale's own structure scenes: items given there count as sourced in the shipped game. The greybox
## is a test level, excluded from the export, and deliberately not scanned.
const FIXED_SCENES: Array[String] = ["res://scenes/structures/castle_morrow.tscn",
		"res://scenes/structures/village.tscn", "res://scenes/structures/hearth_chamber.tscn"]
## Items docs/GAME_DESIGN.md puts in the Weeping Wood or the Sunscar Barrens. They are defined so the
## inventory can show their silhouettes and must have NO source in the Vale: placing one would move an
## area that does not exist yet into this one.
const OTHER_AREAS: Array[String] = ["kindling_green", "kindling_red", "sluice_wheel", "storm_lantern", "bell_rope",
		"name_fragment_shrine", "name_fragment_windmill"]
## The lead's anchors (one per house, chosen clear of the road, the spawn, the fixed sites and each other);
## a house may stand within ANCHOR_REACH of its anchor and no further, so the points of interest, placed
## by someone else at the same time, can keep 25 m from them without ever seeing this file.
const ANCHORS: Dictionary = {
	"maren_cottage": ["cottage", 70, 130], "fisher_shack": ["shack", -133, -51], "pond_shrine": ["shrine", -87, 112],
	"road_cottage": ["cottage", -158, 130], "outskirt_cottage_n": ["cottage", -218, 92],
	"outskirt_cottage_s": ["cottage", -127, 198], "village_shack": ["shack", -250, 150],
	"village_barn": ["barn", -111, 158], "farm_barn_w": ["barn", -295, -60], "farm_barn_s": ["barn", -154, -200],
	"farmhouse": ["cottage", -215, -118], "orchard_shack": ["shack", -51, -197], "north_watch": ["watch", -30, -280],
	"shepherd_shack": ["shack", -110, -234], "castle_foot_watch": ["watch", 138, -16],
	"east_road_shrine": ["shrine", 107, -34], "woodcutter_shack": ["shack", 300, -10],
	"east_ridge_watch": ["watch", 326, -51], "hermit_shack": ["shack", 113, 273], "edge_shrine": ["shrine", -258, -245],
}

var _hf: Heightfield
var _layouts: Dictionary = {}
var _houses: Array[Dictionary] = []
var _nodes: Array[Node] = []


func setup() -> void:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/areas/vale.json"))
	_hf = Heightfield.from_dict(data as Dictionary)
	var names: Array[String] = []
	for name: String in DirAccess.get_files_at(HOUSES_DIR):
		if name.ends_with(".json"):
			names.append(name)
	names.sort()
	for name: String in names:
		_layouts[HOUSES_DIR + name] = StructureBuilder.load_layout(HOUSES_DIR + name)
	for site: Dictionary in SiteRegistry.load_area(AREA):
		if str(site.get("_file", "")) == HOUSES_FILE:
			_houses.append(site)


func teardown() -> void:
	for node: Node in _nodes:
		node.free()
	_nodes.clear()
	StructureBuilder.clear_shared()


# --- the kit --------------------------------------------------------------------------------------------

func test_a_lean_roof_slopes_down_toward_the_front_and_overhangs() -> void:
	var piece: Dictionary = StructureKitHouse.lean_roof(3.0, 4.0, 0.6, 0.1, "roof", 0.3)
	var box: AABB = (piece["mesh"] as ArrayMesh).get_aabb()
	assert_true(is_equal_approx(box.size.x, 3.6), "3 m wide plus 0.3 m overhang each side (got %.2f)" % box.size.x)
	assert_true(box.size.z > 4.5 and box.size.z < 4.8, "runs past both eaves (got %.2f)" % box.size.z)
	assert_true(box.end.y > -0.05 and box.end.y < 0.3, "level with the origin at the high eave (top %.2f)" % box.end.y)
	assert_true(box.position.y < -0.55, "0.6 m lower at the low eave (bottom %.2f)" % box.position.y)
	assert_eq((piece["shapes"] as Array).size(), 1, "one collider, the slab (the eave plate carries none)")
	var high: float = _max_y_where(piece["mesh"], func(v: Vector3) -> bool: return v.z < -1.5)
	var low: float = _max_y_where(piece["mesh"], func(v: Vector3) -> bool: return v.z > 1.5)
	assert_true(high > low + 0.4, "the back edge (%.2f) sits above the front edge (%.2f)" % [high, low])


func test_a_lean_wall_climbs_toward_its_high_end_and_keeps_its_doorway() -> void:
	var plain: Dictionary = StructureKitHouse.lean_wall(4.0, 2.5, 0.6, 0.1, "planks")
	var box: AABB = (plain["mesh"] as ArrayMesh).get_aabb()
	assert_true(is_equal_approx(box.size.x, 4.0) and is_equal_approx(box.size.y, 3.1), "4 m long, 3.1 m at its highest (got %s)" % box.size)
	assert_true(absf(box.size.z - 0.1) < 0.001, "one wall thickness, the wedge included")
	var right: float = _max_y_where(plain["mesh"], func(v: Vector3) -> bool: return v.x > 1.9)
	var left: float = _max_y_where(plain["mesh"], func(v: Vector3) -> bool: return v.x < -1.9)
	assert_true(is_equal_approx(right, 3.1) and is_equal_approx(left, 2.5), "high at +X (%.2f), low at -X (%.2f)" % [right, left])
	assert_eq((plain["shapes"] as Array).size(), 2, "a box and the wedge's slope collider")
	var door: Dictionary = StructureKitHouse.lean_wall(4.0, 2.5, 0.6, 0.1, "planks", {"width": 1.1, "height": 2.4})
	assert_eq((door["shapes"] as Array).size(), 4, "two piers, a lintel and the slope")
	for s: Dictionary in door["shapes"]:
		var shape: BoxShape3D = s["shape"]
		var t: Transform3D = s["transform"]
		if absf(t.basis.y.y - 1.0) > 0.01:
			continue
		var in_gap: bool = t.origin.x + shape.size.x * 0.5 > -0.54 and t.origin.x - shape.size.x * 0.5 < 0.54 \
				and t.origin.y - shape.size.y * 0.5 < 2.39
		assert_false(in_gap, "no upright collider intrudes into the 1.1 x 2.4 doorway")


func test_a_gable_is_a_triangle_on_its_base_line() -> void:
	var piece: Dictionary = StructureKitHouse.gable(5.0, 2.0, 0.5, "stone")
	var box: AABB = (piece["mesh"] as ArrayMesh).get_aabb()
	assert_true(box.position.is_equal_approx(Vector3(-2.5, 0.0, -0.25)) and box.end.is_equal_approx(Vector3(2.5, 2.0, 0.25)),
			"5 m base, 2 m apex, 0.5 m thick (got %s)" % box)
	var apex: float = _max_y_where(piece["mesh"], func(v: Vector3) -> bool: return absf(v.x) < 0.01)
	var corner: float = _max_y_where(piece["mesh"], func(v: Vector3) -> bool: return v.x > 2.4)
	assert_true(is_equal_approx(apex, 2.0) and corner < 0.01, "apex on the centre line, the corners at the base")
	assert_eq((piece["shapes"] as Array).size(), 2, "two slope colliders, one per side")
	assert_true(StructureBuilder.make_piece("gable", {"w": 3.0, "rise": 1.0, "t": 0.4, "mat": "stone"}).has("mesh"),
			"the builder reaches it through the house kit")


# --- the archetypes -------------------------------------------------------------------------------------

func test_five_archetypes_each_intact_and_ruined_build_with_collision_on_every_piece() -> void:
	var seen: Dictionary = {}
	for path: String in _layouts:
		var layout: Dictionary = _layouts[path]
		assert_false(layout.is_empty(), "%s parses" % path.get_file())
		if layout.is_empty():
			continue
		var key: String = "%s/%s" % [layout.get("archetype", "?"), layout.get("variant", "?")]
		seen[key] = true
		var builder: StructureBuilder = _build(path)
		var stats: Dictionary = builder.stats()
		assert_eq(int(stats["pieces"]), (layout["pieces"] as Array).size(), "%s: every entry became a piece" % path.get_file())
		assert_true(int(stats["verts"]) > 0, "%s has geometry" % path.get_file())
		for child: Node in builder.get_children():
			var has_mesh: bool = child.get_node_or_null(^"Mesh") != null or child.get_node_or_null(^"Multi") != null
			var body: StaticBody3D = child.get_node_or_null(^"Body") as StaticBody3D
			assert_true(has_mesh, "%s/%s draws something" % [path.get_file(), child.name])
			assert_true(body != null and body.collision_layer == 1 and body.get_child_count() > 0,
					"%s/%s collides on the world layer" % [path.get_file(), child.name])
		print("COST layout=%s verts=%d colliders=%d instances=%d meshes=%d multimeshes=%d" % [path.get_file(),
				stats["verts"], stats["colliders"], stats["instances"], stats["meshes"], stats["multimeshes"]])
	for archetype: String in ["shack", "cottage", "barn", "watch", "shrine"]:
		for variant: String in ["intact", "ruined"]:
			assert_true(seen.has("%s/%s" % [archetype, variant]), "a %s %s layout exists" % [variant, archetype])
	# What the twenty placements add, summed over the layouts they use (shared meshes are still drawn once
	# per placement, so draw instances and colliders scale with sites; unique vertex data does not).
	var total := {"instances": 0, "colliders": 0, "verts": 0}
	for site: Dictionary in _houses:
		var stats: Dictionary = _build(str(site["layout"])).stats()
		for k: String in total:
			total[k] += int(stats[k])
	print("COST houses sites=%d draw_instances=%d colliders=%d drawn_verts=%d" % [_houses.size(), total["instances"], total["colliders"], total["verts"]])
	assert_true(total["instances"] > 0, "the placements add draw instances")


func test_doorways_stairs_and_lofts_fit_the_player_in_every_layout() -> void:
	for path: String in _layouts:
		var layout: Dictionary = _layouts[path]
		var name: String = path.get_file()
		var door: Dictionary = layout.get("door", {})
		assert_true(not door.is_empty(), "%s names its door" % name)
		if door.is_empty():
			continue
		assert_true(float(door["width"]) >= MIN_DOORWAY_WIDTH, "%s door %.2f m wide" % [name, door["width"]])
		assert_true(float(door["height"]) >= MIN_DOORWAY_HEIGHT + SLAB_TOP, "%s door %.2f m clears the slab top plus the player" % [name, door["height"]])
		var dx: float = float(door["at"][0])
		var dz: float = float(door["at"][1])
		assert_true(_opening_at(layout, dx, dz, float(door["width"]), float(door["height"])),
				"%s has a wall or arch opening of that size where its door says" % name)
		var step: Dictionary = _piece(layout, str(door.get("stair", "")))
		assert_true(not step.is_empty() and str(step.get("kind", "")) == "stairs", "%s has a doorstep stair" % name)
		if not step.is_empty():
			var built: Dictionary = StructureBuilder.make_piece("stairs", step["params"])
			var at: Array = step["at"]
			assert_true(is_equal_approx(float(at[1]), -STEP_DOWN), "%s doorstep starts %.1f m below the floor" % [name, STEP_DOWN])
			assert_true(is_equal_approx(float(at[1]) + float(step["params"]["rise"]), SLAB_TOP), "%s doorstep tops out at the slab top" % name)
			assert_true(is_equal_approx(float(at[0]), dx) and is_equal_approx(float(at[2]) - float(built["run"]), dz),
					"%s doorstep climbs from %.2f out to the door face" % [name, float(built["run"])])
			assert_true(float(step["params"]["w"]) >= float(door["width"]), "%s doorstep is at least the door's width" % name)
			var covered: bool = false
			for raw: Variant in layout.get("keep_out", []):
				var r: Array = raw
				var rect := Rect2(float(r[0]), float(r[1]), float(r[2]), float(r[3])).abs()
				covered = covered or (rect.has_point(Vector2(dx, dz + 0.05)) and rect.has_point(Vector2(dx, float(at[2]) - 0.05)))
			assert_true(covered, "%s keep_out covers the doorstep's ground (it is buried, so Footprint cannot see it)" % name)
		for entry: Variant in layout.get("pieces", []):
			if str((entry as Dictionary).get("kind", "")) != "stairs":
				continue
			var p: Dictionary = entry.get("params", {})
			var built: Dictionary = StructureBuilder.make_piece("stairs", p)
			assert_true(float(built["riser"]) <= StructureKit.MAX_RISER, "%s/%s riser %.3f climbable" % [name, entry.get("name"), float(built["riser"])])
			assert_true(float(p.get("w", 0.0)) >= PLAYER_RADIUS * 2.0 + 0.3, "%s/%s wide enough for the capsule" % [name, entry.get("name")])
		for loft: Variant in layout.get("lofts", []):
			var stairs: Dictionary = _piece(layout, str(loft["stairs"]))
			var slab: Dictionary = _piece(layout, str(loft["slab"]))
			assert_true(not stairs.is_empty() and not slab.is_empty(), "%s loft names real pieces" % name)
			if stairs.is_empty() or slab.is_empty():
				continue
			var head_y: float = float(stairs["at"][1]) + float(stairs["params"]["rise"])
			var top_y: float = float(slab["at"][1]) + float(slab["params"].get("t", 0.3))
			assert_true(absf(head_y - top_y) <= StructureKit.MAX_RISER, "%s loft stairs land within a riser of the loft (%.2f vs %.2f)" % [name, head_y, top_y])
			var run: float = float(StructureBuilder.make_piece("stairs", stairs["params"])["run"])
			var head: Vector3 = StructureBuilder.placements_of(stairs)[0] * Vector3(0.0, 0.0, -run + 0.1)
			var rect: Rect2 = Footprint.local_rect("floor_slab", slab["params"])
			rect = rect.grow(PLAYER_RADIUS + 0.3)
			var local: Vector3 = StructureBuilder.placements_of(slab)[0].affine_inverse() * Vector3(head.x, 0.0, head.z)
			assert_true(rect.has_point(Vector2(local.x, local.z)), "%s loft stairs head (%.1f, %.1f) is at the loft's edge" % [name, head.x, head.z])


func test_every_interior_can_be_entered_stood_in_and_its_loot_reached() -> void:
	# From the built collision, not the data: a column the player's capsule occupies must meet no collider
	# above step height. Checked just inside the door, over most of the floor (ruins keep rubble, which is
	# under step height), and beside every prop any site puts in the layout.
	for path: String in _layouts:
		var layout: Dictionary = _layouts[path]
		var name: String = path.get_file()
		var boxes: Array[Dictionary] = _boxes(_build(path))
		var door: Dictionary = layout.get("door", {})
		if door.is_empty():
			continue
		var inside := Vector2(float(door["at"][0]), float(door["at"][1]) - 0.7)
		assert_true(_column_clear(boxes, inside, SLAB_TOP), "%s: the capsule fits just inside the door" % name)
		var outside := Vector2(float(door["at"][0]), float(door["at"][1]) + 0.3)
		assert_true(_column_clear(boxes, outside, SLAB_TOP), "%s: the capsule fits on the top doorstep tread" % name)
		var floor_rect: Rect2 = Footprint.local_rect("floor_slab", _piece(layout, "floor").get("params", {})).grow(-0.8)
		var clear: int = 0
		var total: int = 0
		var x: float = floor_rect.position.x
		while x <= floor_rect.end.x:
			var z: float = floor_rect.position.y
			while z <= floor_rect.end.y:
				total += 1
				if _column_clear(boxes, Vector2(x, z), SLAB_TOP):
					clear += 1
				z += 0.5
			x += 0.5
		assert_true(clear >= total * 0.5, "%s: at least half the floor is standing room (%d of %d columns)" % [name, clear, total])
		var obbs: Array[Dictionary] = Footprint.layout_obbs(layout)
		for site: Dictionary in _houses:
			if str(site.get("layout", "")) != path:
				continue
			for raw: Variant in site.get("props", []):
				var prop: Dictionary = raw
				var a: Array = prop.get("at", [0, 0, 0])
				var at := Vector3(float(a[0]), float(a[1]), float(a[2]))
				assert_false(_blocked(boxes, at + Vector3(0.0, 0.3, 0.0)), "%s/%s: the prop itself is not inside a piece" % [site["id"], prop["set"].get("id", "?")])
				var on_built: bool = false
				for obb: Dictionary in obbs:
					on_built = on_built or Footprint.has_point(obb, at.x, at.z)
				if not on_built:
					# Outside the footprint the player stands on the terrain, which is not in the builder;
					# test_every_prop_rests_on_a_floor_or_on_the_ground checks that prop against the heightfield.
					continue
				# Somewhere within arm's reach of the prop, on the floor it rests on or beside, the capsule fits.
				var reachable: bool = false
				for k: int in range(8):
					var stand: Vector2 = Vector2(at.x, at.z) + Vector2.RIGHT.rotated(TAU * float(k) / 8.0) * 0.7
					var base: float = _top_under(boxes, stand, at.y + 0.05)
					if base > -INF and base >= at.y - 1.2 and _column_clear(boxes, stand, base):
						reachable = true
						break
				assert_true(reachable, "%s/%s: the capsule fits somewhere beside the prop" % [site["id"], prop["set"].get("id", "?")])


# --- the placements -------------------------------------------------------------------------------------

func test_twenty_houses_stand_near_their_anchors_in_the_planned_mix() -> void:
	assert_eq(_houses.size(), 20, "twenty houses in %s" % HOUSES_FILE)
	var per_archetype: Dictionary = {}
	var variants: Dictionary = {}
	var yaws: Dictionary = {}
	for site: Dictionary in _houses:
		var id: String = str(site["id"])
		assert_true(ANCHORS.has(id), "%s is one of the planned houses" % id)
		var layout: Dictionary = _layouts.get(str(site.get("layout", "")), {})
		assert_true(str(site.get("layout", "")).begins_with(HOUSES_DIR) and not layout.is_empty(), "%s uses a house layout" % id)
		if not ANCHORS.has(id) or layout.is_empty():
			continue
		var plan: Array = ANCHORS[id]
		var archetype: String = str(layout.get("archetype", ""))
		assert_eq(archetype, str(plan[0]), "%s is the planned archetype" % id)
		var anchor := Vector2(float(plan[1]), float(plan[2]))
		var d: float = SiteRegistry.at_of(site).distance_to(anchor)
		assert_true(d <= ANCHOR_REACH, "%s stands within %.0f m of its anchor (%.1f)" % [id, ANCHOR_REACH, d])
		per_archetype[archetype] = int(per_archetype.get(archetype, 0)) + 1
		variants["%s/%s" % [archetype, layout.get("variant", "")]] = true
		var key: String = "%s@%.0f" % [site["layout"], SiteRegistry.yaw_of(site)]
		assert_false(yaws.has(key), "%s does not repeat another site's layout at the same yaw" % id)
		yaws[key] = true
	assert_eq(per_archetype, {"shack": 6, "cottage": 5, "barn": 3, "watch": 3, "shrine": 3}, "the mix docs/WORLD_PLAN.md section 2 plans")
	for archetype: String in ["shack", "cottage", "barn", "watch", "shrine"]:
		assert_true(variants.has(archetype + "/intact") and variants.has(archetype + "/ruined"),
				"%s is placed both intact and ruined" % archetype)


func test_every_doorstep_reaches_the_ground_wherever_its_house_stands() -> void:
	# The floor sits at the highest ground under the footprint; the stair descends STEP_DOWN from it. The
	# ground at the stair's foot, and a metre beyond, must be no further below the foot than the player
	# can step up, or the lowest tread hangs in the air. A threshold higher than the stair's whole rise
	# above the ground would mean the footprint rule in test_site_placement.gd had been loosened.
	for site: Dictionary in _houses:
		var layout: Dictionary = _layouts.get(str(site.get("layout", "")), {})
		var door: Dictionary = layout.get("door", {})
		var step: Dictionary = _piece(layout, str(door.get("stair", "")))
		assert_true(not step.is_empty(), "%s has a doorstep" % site["id"])
		if step.is_empty():
			continue
		var floor_y: float = Settlements.ground_height(site, _hf, 0.5)
		var xform: Transform3D = SiteRegistry.site_transform(site, floor_y)
		var foot_local := Vector3(float(step["at"][0]), 0.0, float(step["at"][2]))
		var foot_y: float = floor_y - STEP_DOWN
		var worst: float = -INF
		for beyond: float in [0.0, 0.5, 1.0]:
			var p: Vector3 = xform * (foot_local + Vector3(0.0, 0.0, beyond))
			worst = maxf(worst, foot_y - _hf.height_at(p.x, p.z))
		assert_true(worst <= PLAYER_STEP_UP, "%s: the doorstep's foot is buried or within a step of the ground (hangs %.2f m)" % [site["id"], worst])
		var face: Vector3 = xform * Vector3(float(door["at"][0]), 0.0, float(door["at"][1]) + 0.2)
		var drop: float = floor_y - _hf.height_at(face.x, face.z)
		assert_true(drop >= -0.001 and drop <= STEP_DOWN + 0.001, "%s: the threshold stands 0..%.1f m over the ground at the door (%.2f)" % [site["id"], STEP_DOWN, drop])


func test_every_prop_rests_on_a_floor_or_on_the_ground() -> void:
	for site: Dictionary in _houses:
		var path: String = str(site.get("layout", ""))
		var layout: Dictionary = _layouts.get(path, {})
		var boxes: Array[Dictionary] = _boxes(_build(path))
		var obbs: Array[Dictionary] = Footprint.layout_obbs(layout)
		var floor_y: float = Settlements.ground_height(site, _hf, 0.5)
		var xform: Transform3D = SiteRegistry.site_transform(site, floor_y)
		for raw: Variant in site.get("props", []):
			var prop: Dictionary = raw
			var a: Array = prop.get("at", [0, 0, 0])
			var at := Vector3(float(a[0]), float(a[1]), float(a[2]))
			var pid: String = str(prop.get("set", {}).get("id", "?"))
			var on_built: bool = false
			for obb: Dictionary in obbs:
				on_built = on_built or Footprint.has_point(obb, at.x, at.z)
			if on_built:
				var top: float = _top_under(boxes, Vector2(at.x, at.z), at.y + 0.05)
				assert_true(absf(top - at.y) <= 0.05, "%s/%s sits on a piece's top (%.2f vs %.2f)" % [site["id"], pid, at.y, top])
			else:
				var w: Vector3 = xform * at
				var ground: float = _hf.height_at(w.x, w.z)
				assert_true(absf(w.y - ground) <= 0.35, "%s/%s outside the footprint rests on the terrain (%.2f off)" % [site["id"], pid, w.y - ground])


# --- the loot -------------------------------------------------------------------------------------------

func test_every_item_has_exactly_one_source_in_the_shipped_vale() -> void:
	var items: Dictionary = _json(ITEMS)
	var sources: Dictionary = {}
	for scene: String in FIXED_SCENES:
		var root: Node = (load(scene) as PackedScene).instantiate()
		_nodes.append(root)
		var stack: Array[Node] = [root]
		while not stack.is_empty():
			var node: Node = stack.pop_back()
			stack.append_array(node.get_children())
			if node is Chest:
				for item: Variant in (node as Chest).contents:
					_source(sources, str(item), "%s/%s" % [scene.get_file(), node.name])
			elif node is Pickup:
				_source(sources, String((node as Pickup).item), "%s/%s" % [scene.get_file(), node.name])
	var site_count: int = 0
	for site: Dictionary in SiteRegistry.load_area(AREA):
		if bool(site.get("fixed", false)):
			continue
		site_count += 1
		for raw: Variant in site.get("props", []):
			var values: Dictionary = (raw as Dictionary).get("set", {})
			var where: String = "%s/%s" % [site["id"], values.get("id", "?")]
			for item: Variant in values.get("contents", {}):
				_source(sources, str(item), where)
			if values.has("item"):
				_source(sources, str(values["item"]), where)
	assert_true(site_count >= 20, "the registry has the houses to scan (%d sites)" % site_count)
	var defined: int = 0
	for id: String in items:
		if not items[id] is Dictionary:
			continue
		defined += 1
		var found: Array = sources.get(id, [])
		if OTHER_AREAS.has(id):
			assert_eq(found.size(), 0, "%s belongs to another area and has no source in the Vale (found %s)" % [id, found])
		else:
			assert_eq(found.size(), 1, "%s has exactly one source (found %s)" % [id, found])
	assert_eq(defined, 33, "33 items audited")
	for id: String in sources:
		assert_true(items.has(id) and items[id] is Dictionary, "sourced item '%s' is defined in items.json (from %s)" % [id, sources[id]])
	for id: String in OTHER_AREAS:
		assert_true(items.has(id), "%s, kept for another area, is still defined" % id)


func test_locks_are_opened_by_keys_found_somewhere_else() -> void:
	var items: Dictionary = _json(ITEMS)
	var locks: int = 0
	for site: Dictionary in _houses:
		var held: Dictionary = {}
		for raw: Variant in site.get("props", []):
			var values: Dictionary = (raw as Dictionary).get("set", {})
			for item: Variant in values.get("contents", {}):
				held[str(item)] = str(values.get("id", "?"))
			if values.has("item"):
				held[str(values["item"])] = str(values.get("id", "?"))
		for raw: Variant in site.get("props", []):
			var values: Dictionary = (raw as Dictionary).get("set", {})
			var key: String = str(values.get("required_item", ""))
			if key == "":
				continue
			locks += 1
			assert_true(items.has(key) and str((items[key] as Dictionary).get("kind", "")) == "key", "%s/%s is locked with a key item (%s)" % [site["id"], values.get("id"), key])
			assert_false(held.has(key), "%s/%s: its key is not kept in the same house (%s)" % [site["id"], values.get("id"), held.get(key, "")])
	assert_eq(locks, 2, "two small puzzles: a locked cottage and a locked watch-hut chest")
	# The castle gate's key (scenes/structures/castle_morrow.tscn) must come from the houses now: no fixed
	# scene gives it, and the greybox does not ship.
	var castle: Node = (load(FIXED_SCENES[0]) as PackedScene).instantiate()
	_nodes.append(castle)
	var gate: Door = castle.get_node_or_null(^"GateDoor") as Door
	assert_true(gate != null and gate.required_item == &"castle_key", "the castle gate still wants the castle key")


func test_every_house_holds_something_and_every_inscription_exists() -> void:
	var lore: Dictionary = _json(LORE)
	var scenes: Dictionary = {}
	for site: Dictionary in _houses:
		var props: Array = site.get("props", [])
		assert_true(props.size() >= 1, "%s holds something" % site["id"])
		for raw: Variant in props:
			var prop: Dictionary = raw
			scenes[str(prop.get("scene", "")).get_file()] = true
			var values: Dictionary = prop.get("set", {})
			assert_true(values.has("id") and str(values["id"]) != "", "%s: every prop has an id for its once-flag" % site["id"])
			if values.has("lore_key"):
				var key: String = str(values["lore_key"])
				assert_true(lore.has(key) and lore[key] is Dictionary and str(lore[key].get("body", "")).length() > 20,
						"%s reads a real inscription (%s)" % [site["id"], key])
				assert_ne(key, LoreStone.MISSING_KEY, "no house reads the worn-stone fallback on purpose")
	assert_true(scenes.has("chest.tscn") and scenes.has("pickup.tscn") and scenes.has("lore_stone.tscn") and scenes.has("door.tscn"),
			"the houses use every interactable kind (%s)" % [scenes.keys()])
	var verse: String = str((lore.get("pond_shrine_verse", {}) as Dictionary).get("body", ""))
	var capitals: String = ""
	for i: int in range(2, verse.length()):
		var c: String = verse[i]
		if c == c.to_upper() and c != c.to_lower() and verse[i - 1] != "." and verse[i - 2] != ".":
			capitals += c
	assert_true(capitals.length() >= 2 and capitals.length() <= 4, "the pond shrine's verse hides a short syllable in its capitals (%s)" % capitals)


# --- helpers --------------------------------------------------------------------------------------------

func _build(path: String) -> StructureBuilder:
	var builder := StructureBuilder.new()
	_nodes.append(builder)
	builder.layout_path = path
	builder.share_pieces = true
	builder.build()
	return builder


func _piece(layout: Dictionary, name: String) -> Dictionary:
	for entry: Variant in layout.get("pieces", []):
		if entry is Dictionary and str((entry as Dictionary).get("name", "")) == name:
			return entry
	return {}


## True when a wall or arch piece carries a floor-level opening of at least the given size whose centre
## sits at (x, z) in layout space, allowing the wall's own half thickness.
func _opening_at(layout: Dictionary, x: float, z: float, width: float, height: float) -> bool:
	for entry: Variant in layout.get("pieces", []):
		var e: Dictionary = entry
		var p: Dictionary = e.get("params", {})
		var kind: String = str(e.get("kind", ""))
		var ow: float = 0.0
		var oh: float = 0.0
		var offset: float = 0.0
		if kind == "wall" or kind == "lean_wall":
			var o: Dictionary = p.get("opening", {})
			if o.is_empty() or float(o.get("sill", 0.0)) > 0.0:
				continue
			ow = float(o.get("width", 0.0))
			oh = float(o.get("height", 0.0))
			offset = float(o.get("offset", 0.0))
		elif kind == "arch":
			ow = float(p.get("ow", 0.0))
			oh = float(p.get("oh", 0.0))
		else:
			continue
		var t: Transform3D = StructureBuilder.placements_of(e)[0]
		var centre: Vector3 = t * Vector3(offset, 0.0, 0.0)
		var thick: float = float(p.get("t", 0.5)) * 0.5 + 0.01
		if absf(centre.x - x) < 0.01 and absf(centre.z - z) <= thick and ow >= width - 0.001 and oh >= height - 0.001:
			return true
	return false


## Every collision box of a built layout, as {xform, half} in the builder's space.
func _boxes(builder: StructureBuilder) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for child: Node in builder.get_children():
		var body: Node = child.get_node_or_null(^"Body")
		if body == null:
			continue
		for cs: Node in body.get_children():
			if cs is CollisionShape3D and (cs as CollisionShape3D).shape is BoxShape3D:
				out.append({"xform": (child as Node3D).transform * (cs as CollisionShape3D).transform,
						"half": ((cs as CollisionShape3D).shape as BoxShape3D).size * 0.5})
	return out


func _blocked(boxes: Array[Dictionary], p: Vector3) -> bool:
	for b: Dictionary in boxes:
		var local: Vector3 = (b["xform"] as Transform3D).affine_inverse() * p
		var h: Vector3 = b["half"]
		if absf(local.x) <= h.x + 0.001 and absf(local.y) <= h.y + 0.001 and absf(local.z) <= h.z + 0.001:
			return true
	return false


## A standing column over `floor_y`: from step height to the player's height, nothing may be in the way.
func _column_clear(boxes: Array[Dictionary], at: Vector2, floor_y: float) -> bool:
	var y: float = floor_y + PLAYER_STEP_UP + 0.01
	while y <= floor_y + PLAYER_HEIGHT:
		if _blocked(boxes, Vector3(at.x, y, at.y)):
			return false
		y += 0.15
	return true


## The highest collider surface under (x, z) at or below `from`, found by walking down; -INF when none.
func _top_under(boxes: Array[Dictionary], at: Vector2, from: float) -> float:
	var y: float = from
	while y >= from - 4.0:
		if _blocked(boxes, Vector3(at.x, y, at.y)):
			return y
		y -= 0.02
	return -INF


func _max_y_where(mesh: ArrayMesh, keep: Callable) -> float:
	var best: float = -INF
	for v: Vector3 in mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
		if keep.call(v):
			best = maxf(best, v.y)
	return best


func _source(sources: Dictionary, item: String, where: String) -> void:
	if not sources.has(item):
		sources[item] = []
	(sources[item] as Array).append(where)


func _json(path: String) -> Dictionary:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return data if data is Dictionary else {}
