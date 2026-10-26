extends "res://tests/test_case.gd"
## Structure kit and scene tests. Geometry is checked directly (meshes, UV scale, risers, collision), both
## structure scenes are instanced detached and walked, and a child headless Godot plays structure_test.tscn
## with --probe for the live counts and the bell puzzle through the real nodes. None of this proves the
## ruin reads well or that the player fits through a door in practice; it proves the numbers are inside
## the player's limits (0.4 m step-up, 0.35 m radius, 1.75 m tall) and that nothing walkable lacks collision.

const STRUCTURE_TEST := "res://scenes/levels/structure_test.tscn"
const CASTLE_SCENE := "res://scenes/structures/castle_morrow.tscn"
const VILLAGE_SCENE := "res://scenes/structures/village.tscn"
const LAYOUTS: Array[String] = ["res://data/structures/castle_morrow.json", "res://data/structures/village.json"]
const PROBE_FRAME_CAP := "1200"
const PLAYER_STEP_UP := 0.4
const PLAYER_WIDTH := 0.7
const PLAYER_HEIGHT := 1.75
const MIN_DOORWAY_WIDTH := 1.0
const MIN_DOORWAY_HEIGHT := 2.2

var _nodes: Array[Node] = []


func teardown() -> void:
	for node: Node in _nodes:
		node.free()
	_nodes.clear()


func test_wall_mesh_has_normals_and_world_scaled_uvs() -> void:
	var piece: Dictionary = StructureKit.wall(4.0, 3.0, 0.5, "castle_wall")
	var mesh: ArrayMesh = piece["mesh"]
	assert_eq(mesh.get_surface_count(), 1, "a wall is one surface")
	var arrays: Array = mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	assert_eq(verts.size(), 24, "a plain wall is one box: 6 faces x 4 vertices")
	assert_eq(normals.size(), verts.size(), "every vertex has a normal")
	assert_eq(uvs.size(), verts.size(), "every vertex has a UV")
	for n: Vector3 in normals:
		assert_true(is_equal_approx(n.length(), 1.0), "normals are unit length")
	# Only the upright faces: the top and bottom tile on X/Z instead, so their V is the wall's thickness.
	var u_min: float = INF
	var u_max: float = -INF
	var v_min: float = INF
	var v_max: float = -INF
	for i: int in range(uvs.size()):
		if absf(normals[i].y) > 0.5:
			continue
		u_min = minf(u_min, uvs[i].x)
		u_max = maxf(u_max, uvs[i].x)
		v_min = minf(v_min, uvs[i].y)
		v_max = maxf(v_max, uvs[i].y)
	assert_true(is_equal_approx(u_max - u_min, 4.0), "a 4 m wall spans 4 texture tiles along its length (got %.2f)" % (u_max - u_min))
	assert_true(is_equal_approx(v_max - v_min, 3.0), "a 3 m wall spans 3 tiles up (got %.2f)" % (v_max - v_min))
	assert_eq((piece["shapes"] as Array).size(), 1, "a plain wall has one collision box")


func test_wall_opening_leaves_a_passable_gap() -> void:
	var piece: Dictionary = StructureKit.wall(6.0, 3.0, 0.5, "blocks", {"width": 1.4, "height": 2.4})
	var shapes: Array = piece["shapes"]
	assert_eq(shapes.size(), 3, "a doorway wall is two piers and a lintel")
	for s: Dictionary in shapes:
		var box: BoxShape3D = s["shape"]
		var xform: Transform3D = s["transform"]
		var lo_x: float = xform.origin.x - box.size.x * 0.5
		var hi_x: float = xform.origin.x + box.size.x * 0.5
		var lo_y: float = xform.origin.y - box.size.y * 0.5
		var in_gap: bool = hi_x > -0.7 and lo_x < 0.7 and lo_y < 2.4
		assert_false(in_gap, "no collision box intrudes into the 1.4 x 2.4 doorway")


func test_stairs_risers_stay_under_the_player_step_up() -> void:
	var piece: Dictionary = StructureKit.stairs(1.4, 4.5, "blocks", 0.25, 0.35)
	assert_eq(int(piece["steps"]), 18, "4.5 m at 0.25 m risers is 18 steps")
	assert_true(float(piece["riser"]) <= StructureKit.MAX_RISER, "riser %.3f within the kit limit" % float(piece["riser"]))
	assert_true(StructureKit.MAX_RISER < PLAYER_STEP_UP, "the kit limit (%.2f) sits under the player's 0.4 m step-up" % StructureKit.MAX_RISER)
	var tops: Array[float] = []
	for s: Dictionary in piece["shapes"]:
		var box: BoxShape3D = s["shape"]
		tops.append((s["transform"] as Transform3D).origin.y + box.size.y * 0.5)
	tops.sort()
	for i: int in range(1, tops.size()):
		assert_true(tops[i] - tops[i - 1] <= StructureKit.MAX_RISER + 0.001, "consecutive treads differ by at most the limit")
	assert_true(is_equal_approx(tops[tops.size() - 1], 4.5), "the flight reaches its full rise")
	var greedy: Dictionary = StructureKit.stairs(1.0, 3.0, "blocks", 0.6, 0.35)
	assert_true(float(greedy["riser"]) <= StructureKit.MAX_RISER, "a requested 0.6 m riser is clamped to the limit (got %.3f)" % float(greedy["riser"]))


func test_layout_stairs_and_doorways_fit_the_player() -> void:
	for path: String in LAYOUTS:
		var layout: Dictionary = StructureBuilder.load_layout(path)
		assert_true(not layout.is_empty(), "%s loads" % path)
		var flights: int = 0
		for entry: Variant in layout.get("pieces", []):
			var p: Dictionary = entry.get("params", {})
			match str(entry.get("kind", "")):
				"stairs":
					flights += 1
					var built: Dictionary = StructureBuilder.make_piece("stairs", p)
					assert_true(float(built["riser"]) <= StructureKit.MAX_RISER, "%s riser %.3f climbable" % [entry.get("name"), float(built["riser"])])
					assert_true(float(p.get("w", 0.0)) >= PLAYER_WIDTH + 0.3, "%s wide enough for the capsule" % entry.get("name"))
				"wall":
					var o: Dictionary = p.get("opening", {})
					if not o.is_empty() and float(o.get("sill", 0.0)) <= 0.0 and float(o.get("height", 0.0)) >= 2.0:
						assert_true(float(o["width"]) >= MIN_DOORWAY_WIDTH, "%s doorway width %.2f >= %.2f" % [entry.get("name"), float(o["width"]), MIN_DOORWAY_WIDTH])
						assert_true(float(o["height"]) >= MIN_DOORWAY_HEIGHT, "%s doorway height %.2f >= %.2f" % [entry.get("name"), float(o["height"]), MIN_DOORWAY_HEIGHT])
				"arch":
					assert_true(float(p.get("ow", 0.0)) >= MIN_DOORWAY_WIDTH, "%s arch opening wide enough" % entry.get("name"))
					assert_true(float(p.get("oh", 0.0)) >= MIN_DOORWAY_HEIGHT + 0.2, "%s arch crown high enough" % entry.get("name"))
		assert_true(flights >= 1 or path.ends_with("village.json"), "%s has at least one staircase" % path)


func test_layouts_build_with_collision_on_every_piece_and_fit_their_plateaus() -> void:
	for path: String in LAYOUTS:
		var builder := StructureBuilder.new()
		_nodes.append(builder)
		builder.layout_path = path
		builder.build()
		var stats: Dictionary = builder.stats()
		var layout: Dictionary = builder.layout()
		assert_eq(int(stats["pieces"]), (layout["pieces"] as Array).size(), "%s: every layout entry became a piece" % path)
		assert_true(int(stats["verts"]) > 0, "%s has geometry" % path)
		for child: Node in builder.get_children():
			var has_mesh: bool = child.get_node_or_null(^"Mesh") != null or child.get_node_or_null(^"Multi") != null
			var body: StaticBody3D = child.get_node_or_null(^"Body") as StaticBody3D
			assert_true(has_mesh, "%s draws something" % child.name)
			assert_not_null(body, "%s has a collision body" % child.name)
			if body != null:
				assert_eq(body.collision_layer, 1, "%s collides on the world layer" % child.name)
				assert_true(body.get_child_count() > 0, "%s body carries at least one shape" % child.name)
		var plateau: float = _plateau_radius(str(layout.get("plateau", "")))
		assert_true(plateau > 0.0, "%s names a plateau in data/areas/vale.json" % path)
		assert_true(builder.footprint_radius() <= plateau, "%s footprint %.1f m fits inside the %.0f m plateau" % [path, builder.footprint_radius(), plateau])


func test_scenes_have_unique_ids_three_bells_and_a_wired_puzzle() -> void:
	var ids: Dictionary = {}
	var bells: Array[int] = []
	for scene_path: String in [CASTLE_SCENE, VILLAGE_SCENE]:
		var root: Node = (load(scene_path) as PackedScene).instantiate()
		_nodes.append(root)
		var stack: Array[Node] = [root]
		while not stack.is_empty():
			var node: Node = stack.pop_back()
			stack.append_array(node.get_children())
			if node is Interactable:
				var id: StringName = (node as Interactable).id
				assert_ne(id, &"", "%s/%s has an id" % [scene_path.get_file(), node.name])
				assert_false(ids.has(id), "interactable id '%s' is unique" % id)
				ids[id] = true
			if node is Bell:
				bells.append((node as Bell).index)
	bells.sort()
	assert_eq(bells, [0, 1, 2], "the castle has exactly three ringable bells indexed 0, 1, 2")
	var castle: Node = _nodes[_nodes.size() - 2]
	var puzzle: BellPuzzle = castle.get_node_or_null(^"BellPuzzle") as BellPuzzle
	assert_not_null(puzzle, "the castle carries a BellPuzzle")
	if puzzle != null:
		assert_not_null(puzzle.get_node_or_null(puzzle.bells_root), "puzzle bells_root resolves")
		assert_true(puzzle.get_node_or_null(puzzle.chapel_bell) is ChapelBell, "puzzle chapel_bell resolves to a ChapelBell")
		var prize: Node = puzzle.get_node_or_null(puzzle.reward)
		assert_true(prize is Chest, "puzzle reward is a Chest")
		if prize is Chest:
			assert_false((prize as Chest).visible, "the kindling chest starts hidden in the bell-bed")
			assert_eq((prize as Chest).contents, {"kindling_grey": 1}, "the chest holds the Grey Kindling")
	var door: Door = castle.get_node_or_null(^"GateDoor") as Door
	assert_not_null(door, "the gatehouse has the castle door")
	if door != null:
		assert_eq(door.required_item, &"castle_key", "the gate needs the castle key")
	# The sluice socket is the pond's only gate, and the Sluice Wheel that opens it is in the Barrens, an
	# area that does not exist yet (docs/GAME_DESIGN.md). So it is deliberately a lock the player meets long
	# before its key: it must refuse, and refuse by naming what is missing, rather than be absent or free.
	var socket: WheelSocket = castle.get_node_or_null(^"SluiceWheelSocket") as WheelSocket
	assert_not_null(socket, "the sluice house has a wheel socket")
	if socket != null:
		assert_eq(socket.required_item, &"sluice_wheel", "the socket wants the Sluice Wheel")
		assert_true(socket.consumes_item, "fitting the wheel spends it")
		assert_eq(socket.sets_flag, &"pond_drained", "fitting it drains the pond")
		assert_false(socket.can_interact(), "with no wheel carried, the socket refuses")
		# Interactable fills need_item_text with the item's in-world name, so without a placeholder the
		# player would be refused without being told what for. (No inventory exists in this runner, so the
		# refusal here falls back to refusal_text; the %s is what makes the named version possible.)
		assert_true("%s" in socket.need_item_text, "the refusal has somewhere to name the missing wheel")
		assert_ne(socket.refusal_reason(), "", "a refusal always says something")
		assert_false(socket.is_fitted(), "the axle starts bare")
	var village: Node = _nodes[_nodes.size() - 1]
	assert_true(village.get_node(^"NPCHooks").get_child_count() >= 3, "the village leaves NPC hook markers")


func test_headless_probe_counts_and_bell_puzzle() -> void:
	var output: Array = []
	var args: PackedStringArray = [
		"--headless", "--path", ProjectSettings.globalize_path("res://"),
		STRUCTURE_TEST, "--quit-after", PROBE_FRAME_CAP, "--", "--probe",
	]
	var code: int = OS.execute(OS.get_executable_path(), args, output, true)
	var text: String = "\n".join(PackedStringArray(output))
	assert_eq(code, 0, "child headless run of structure_test exits cleanly")
	assert_false("SCRIPT ERROR" in text, "child run printed no script errors")
	var castle: Dictionary = _probe_line(text, "PROBE castle")
	assert_true(not castle.is_empty(), "probe printed the castle line")
	if not castle.is_empty():
		assert_eq(castle["bells"], "3", "castle has three bells")
		assert_true(int(castle["interactables"]) >= 11, "castle has door, bells, chest, pickup and lore stones (got %s)" % castle["interactables"])
		assert_true(int(castle["colliders"]) > 100, "castle pieces carry collision")
		assert_true(int(castle["multimeshes"]) >= 5, "repeated castle pieces are instanced")
	var village: Dictionary = _probe_line(text, "PROBE village")
	assert_true(not village.is_empty(), "probe printed the village line")
	if not village.is_empty():
		assert_eq(village["shacks"], "7", "seven shacks")
		assert_eq(village["props"], "11", "eleven real props placed")
		assert_eq(village["interactables"], "2", "a chest and a lore stone")
	var fit: Dictionary = _probe_line(text, "PROBE fit")
	assert_eq(fit.get("fits", ""), "true", "both structures fit their plateaus")
	var puzzle: Dictionary = _probe_line(text, "PROBE bellpuzzle")
	assert_true(not puzzle.is_empty(), "probe printed the bell puzzle line")
	if not puzzle.is_empty():
		assert_eq(puzzle["configured"], "true", "puzzle read its order from data")
		assert_eq(puzzle["wrong_first"], "true", "a wrong first ring reset with nothing credited")
		assert_eq(puzzle["solved"], "true", "ringing the data order through real Bells solved it")
		assert_eq(puzzle["resets"], "1", "exactly the one deliberate reset")
		assert_eq(puzzle["kindling_revealed"], "true", "the kindling chest was revealed")
		assert_eq(puzzle["bell_fallen"], "true", "the chapel bell fell")
		assert_eq(puzzle["repeat_changed"], "false", "repeating the order after solving changed nothing")


func _plateau_radius(name: String) -> float:
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string("res://data/areas/vale.json")) != OK:
		return 0.0
	for p: Variant in (json.data as Dictionary).get("plateaus", []):
		if p is Dictionary and str(p.get("name", "")) == name:
			return float(p.get("radius", 0.0))
	return 0.0


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
