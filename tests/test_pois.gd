extends "res://tests/test_case.gd"
## Points of interest (W8-P): the props kit, the small layouts built from it, and where they stand in the
## Vale. Houses (W8-H) and these are placed by two people at once into two files. The one rule that keeps
## them apart is here: every house stands within 15 m of one of HOUSE_ANCHORS, so every point of every POI
## footprint keeps HOUSE_CLEARANCE from every anchor. Seen to fail: docs/reports/W8-P.md quotes the
## negative control. The general rules (dry, inside the ridge, off the road, never crowding another site)
## are test_site_placement.gd's and apply to these sites too.

const AREA := "vale"
const POIS_FILE := "vale_pois.json"
const LAYOUT_DIR := "res://data/structures/pois/"
const VALE_SCENE := "res://scenes/levels/vale.tscn"
const PROBE_FRAME_CAP := "1200"
## From the W8 brief: each house is placed within 15 m of one of these.
const HOUSE_ANCHORS: Array = [[70, 130], [-133, -51], [-87, 112], [-158, 130], [-218, 92], [-127, 198], [-250, 150],
		[-111, 158], [-295, -60], [-154, -200], [-215, -118], [-51, -197], [-30, -280], [-110, -234], [138, -16],
		[107, -34], [300, -10], [326, -51], [113, 273], [-258, -245]]
const HOUSE_CLEARANCE := 25.0
const MIN_SITES := 25
const MIN_LAYOUTS := 12
const KINDS: Array[String] = ["well", "cart", "fence", "haystack", "scarecrow", "cairn", "signpost", "campfire",
		"tent_frame", "weapon_rack", "grave_mound", "trough"]
## Kinds that stand on the ground and so must reach `sink` below it; the cart stands on its wheels at y = 0.
const STANDING: Array[String] = ["well", "fence", "haystack", "scarecrow", "cairn", "signpost", "campfire",
		"tent_frame", "weapon_rack", "grave_mound", "trough"]
## Vertices all the POI placements add together; meshes are shared per layout, so the GPU holds far fewer.
const VERTEX_BUDGET := 120000

var _sites: Array[Dictionary] = []
var _nodes: Array[Node] = []


func setup() -> void:
	for site: Dictionary in SiteRegistry.load_area(AREA):
		if str(site.get("_file", "")) == POIS_FILE:
			_sites.append(site)


func teardown() -> void:
	for node: Node in _nodes:
		node.free()
	_nodes.clear()
	StructureBuilder.clear_shared()


# --- the kit ----------------------------------------------------------------------------------------------

func test_every_prop_kind_builds_geometry_with_collision() -> void:
	for kind: String in KINDS:
		var piece: Dictionary = StructureKitProps.make(kind, {})
		assert_false(piece.is_empty(), "%s is a kind the props kit owns" % kind)
		if piece.is_empty():
			continue
		var mesh: ArrayMesh = piece["mesh"]
		assert_true(mesh.get_surface_count() >= 1, "%s has geometry" % kind)
		assert_true(int(piece["verts"]) > 0, "%s counts its vertices" % kind)
		var shapes: Array = piece["shapes"]
		assert_true(shapes.size() >= 1, "%s has collision a player can walk into" % kind)
		for s: Dictionary in shapes:
			assert_true(s["shape"] is Shape3D, "%s: every collider is a shape" % kind)
		assert_true(StructureKitHouse.make(kind, {}).is_empty(),
				"%s is not also claimed by the house kit, which would win the dispatch" % kind)
		print("POI piece %s verts=%d colliders=%d surfaces=%d" % [kind, int(piece["verts"]), shapes.size(), mesh.get_surface_count()])
	assert_true(StructureKitProps.make("no_such_prop", {}).is_empty(), "an unknown kind is not claimed")


func test_every_standing_piece_reaches_below_the_ground() -> void:
	# Settlements floors a site at the highest ground under it, so the low side of a footprint can be up to
	# MAX_GROUND_DROP lower than y = 0: a piece whose geometry ended at y = 0 would float there.
	for kind: String in STANDING:
		var low: float = _lowest_y(StructureKitProps.make(kind, {"sink": 0.8}))
		assert_true(low <= -0.79, "%s reaches 0.8 m below the ground (lowest vertex %.2f)" % [kind, low])
	var cart_low: float = _lowest_y(StructureKitProps.make("cart", {}))
	assert_true(absf(cart_low) < 0.06, "a cart's wheels rest on the ground (lowest vertex %.2f)" % cart_low)


func test_a_broken_fence_loses_rails_and_only_whole_bays_block() -> void:
	var whole: Dictionary = StructureKitProps.make("fence", {"length": 8.0, "spacing": 2.0})
	var broken: Dictionary = StructureKitProps.make("fence", {"length": 8.0, "spacing": 2.0, "broken": true, "seed": 4})
	assert_eq((whole["shapes"] as Array).size(), 1, "an intact run is one collider")
	var bays: int = (broken["shapes"] as Array).size()
	assert_true(bays >= 1 and bays < 4, "a broken run blocks only its whole bays (%d of 4)" % bays)
	assert_eq(int(whole["verts"]), int(broken["verts"]), "breaking moves rails; it adds and removes none")


func test_a_tilted_placement_lays_a_piece_on_its_side() -> void:
	# Carts and a tent frame are placed tipped with the layout's `tilt`, not with a kit variant.
	var t: Transform3D = StructureBuilder.placement([0, 0.35, 0, 20, 75])
	assert_true(t.basis.y.y < 0.3, "at 75 degrees of tilt the piece's up axis is nearly flat (%.2f)" % t.basis.y.y)


# --- the layouts ------------------------------------------------------------------------------------------

func test_every_poi_layout_builds_every_piece_and_declares_its_ground() -> void:
	var files: Array[String] = _layout_files()
	assert_true(files.size() >= MIN_LAYOUTS, "at least %d layouts (%d)" % [MIN_LAYOUTS, files.size()])
	for path: String in files:
		var builder := StructureBuilder.new()
		builder.layout_path = path
		builder.build()
		_nodes.append(builder)
		var layout: Dictionary = builder.layout()
		var entries: int = (layout.get("pieces", []) as Array).size()
		var stats: Dictionary = builder.stats()
		assert_eq(int(stats["pieces"]), entries, "%s: every piece kind is known to a kit" % path.get_file())
		assert_true(int(stats["verts"]) > 0, "%s has geometry" % path.get_file())
		assert_true(int(stats["colliders"]) > 0, "%s has collision" % path.get_file())
		assert_true(Footprint.layout_obbs(layout).size() > 0,
				"%s declares ground (keep_out or ground kinds), so grass stops at it and the placement rules see it" % path.get_file())
		print("POI layout %s pieces=%d instances=%d verts=%d colliders=%d" % [path.get_file(), stats["pieces"],
				stats["instances"], stats["verts"], stats["colliders"]])


func test_every_keep_out_rect_holds_a_piece() -> void:
	# A rect nobody stands in is a typo: a bare patch in the grass for nothing.
	for path: String in _layout_files():
		var layout: Dictionary = StructureBuilder.load_layout(path)
		var origins: Array[Vector2] = []
		for raw: Variant in layout.get("pieces", []):
			if raw is Dictionary:
				for t: Transform3D in StructureBuilder.placements_of(raw):
					origins.append(Vector2(t.origin.x, t.origin.z))
		for raw: Variant in layout.get("keep_out", []):
			var r: Array = raw
			var rect := Rect2(float(r[0]), float(r[1]), float(r[2]), float(r[3])).abs().grow(0.3)
			var held: bool = false
			for o: Vector2 in origins:
				held = held or rect.has_point(o)
			assert_true(held, "%s: keep_out %s holds a piece" % [path.get_file(), str(raw)])
	assert_true(_layout_files().size() > 0, "there are layouts to check")


# --- the placements ---------------------------------------------------------------------------------------

func test_every_poi_keeps_clear_of_every_house_anchor() -> void:
	assert_eq(HOUSE_ANCHORS.size(), 20, "the twenty house anchors of the brief")
	assert_true(_sites.size() >= MIN_SITES, "at least %d points of interest are placed (%d)" % [MIN_SITES, _sites.size()])
	for site: Dictionary in _sites:
		var obbs: Array[Dictionary] = SiteRegistry.world_obbs(site)
		assert_true(obbs.size() > 0, "%s has a footprint to measure" % site["id"])
		for obb: Dictionary in obbs:
			for a: Array in HOUSE_ANCHORS:
				var d: float = _obb_distance(obb, Vector2(float(a[0]), float(a[1])))
				assert_true(d >= HOUSE_CLEARANCE, "%s keeps %.0f m from the house anchor %s (%.1f m)"
						% [site["id"], HOUSE_CLEARANCE, str(a), d])


func test_poi_sites_are_scenery_only_and_use_poi_layouts() -> void:
	assert_true(_sites.size() > 0, "the POI file has sites")
	for site: Dictionary in _sites:
		assert_true(str(site.get("layout", "")).begins_with(LAYOUT_DIR), "%s uses a POI layout" % site["id"])
		assert_false(site.has("props"), "%s carries no interactables: loot lives in the houses file" % site["id"])
		assert_false(bool(site.get("fixed", false)), "%s is built by Settlements" % site["id"])


func test_the_poi_sites_cost_stays_inside_the_budget() -> void:
	var per_layout: Dictionary = {}
	var verts: int = 0
	var colliders: int = 0
	var instances: int = 0
	for site: Dictionary in _sites:
		var path: String = str(site.get("layout", ""))
		if not per_layout.has(path):
			var builder := StructureBuilder.new()
			builder.layout_path = path
			builder.build()
			_nodes.append(builder)
			per_layout[path] = builder.stats()
		var s: Dictionary = per_layout[path]
		verts += int(s["verts"])
		colliders += int(s["colliders"])
		instances += int(s["instances"])
	print("POI sites=%d layouts=%d piece_instances=%d verts=%d colliders=%d" % [_sites.size(), per_layout.size(),
			instances, verts, colliders])
	assert_true(verts > 0 and verts <= VERTEX_BUDGET, "all placements together add %d vertices (budget %d)" % [verts, VERTEX_BUDGET])
	assert_true(per_layout.size() < _sites.size(), "layouts are reused: %d layouts for %d sites" % [per_layout.size(), _sites.size()])


func test_the_vale_probe_spawns_every_poi_site() -> void:
	var output: Array = []
	var args: PackedStringArray = ["--headless", "--path", ProjectSettings.globalize_path("res://"), VALE_SCENE,
			"--quit-after", PROBE_FRAME_CAP, "--", "--probe"]
	var code: int = OS.execute(OS.get_executable_path(), args, output, true)
	var text: String = "\n".join(PackedStringArray(output))
	assert_eq(code, 0, "the child headless run of the vale exits cleanly")
	assert_false("SCRIPT ERROR" in text, "building the points of interest printed no script errors")
	var line: Dictionary = _probe_line(text, "PROBE sites ")
	assert_true(not line.is_empty(), "the probe printed its sites line")
	if line.is_empty():
		return
	var spawned: int = int(line.get("spawned", "0"))
	assert_true(spawned >= _sites.size(), "the vale spawned every point of interest (%d spawned, %d placed here)"
			% [spawned, _sites.size()])
	var own_obbs: int = 0
	for site: Dictionary in _sites:
		own_obbs += SiteRegistry.world_obbs(site).size()
	assert_true(int(line.get("keepout_obbs", "0")) >= own_obbs, "the keep-out mask holds every POI footprint (%s >= %d)"
			% [line.get("keepout_obbs", "?"), own_obbs])


# --- helpers ----------------------------------------------------------------------------------------------

func _layout_files() -> Array[String]:
	var out: Array[String] = []
	for name: String in DirAccess.get_files_at(LAYOUT_DIR):
		if name.ends_with(".json"):
			out.append(LAYOUT_DIR + name)
	out.sort()
	return out


func _lowest_y(piece: Dictionary) -> float:
	var low: float = INF
	var mesh: ArrayMesh = piece["mesh"]
	for s: int in range(mesh.get_surface_count()):
		for v: Vector3 in (mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX] as PackedVector3Array):
			low = minf(low, v.y)
	return low


## Distance from a point to the nearest point of an OBB (0 inside it).
func _obb_distance(obb: Dictionary, p: Vector2) -> float:
	var d: Vector2 = p - (obb["centre"] as Vector2)
	var ax: float = maxf(0.0, absf(d.dot(obb["ux"])) - float(obb["hx"]))
	var az: float = maxf(0.0, absf(d.dot(obb["uz"])) - float(obb["hz"]))
	return Vector2(ax, az).length()


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
