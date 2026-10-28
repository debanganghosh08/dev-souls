extends "res://tests/test_case.gd"
## The tall towers (W9-T): three watchtowers and the pond light tower, each one a stack of storeys the
## player climbs. The rule that matters is headroom: the first cut of these layouts put a floor slab across
## the whole storey, which left 1.2 m over the middle of every flight and would have stopped the climb dead.
## Seen to fail: docs/reports/W9-T.md quotes the negative control.

const DIR := "res://data/structures/towers/"
const AREA := "vale"
const TOWERS_FILE := "vale_towers.json"
## PlayerController's capsule is 1.8 m; a flight has to clear it with something to spare.
const HEADROOM := 1.9
## The owner asked for a 50-60 ft building: four or five storeys.
const MIN_HEAD_HEIGHT := 13.0
const MIN_STOREYS := 4
const PLAYER_WIDTH := 0.9

var _nodes: Array[Node] = []


func teardown() -> void:
	for node: Node in _nodes:
		node.free()
	_nodes.clear()
	StructureBuilder.clear_shared()


func test_every_tower_layout_builds_with_collision_on_every_piece() -> void:
	var files: Array[String] = _layouts()
	assert_true(files.size() >= 3, "at least three tower layouts (%d)" % files.size())
	for path: String in files:
		var builder := StructureBuilder.new()
		builder.layout_path = path
		builder.build()
		_nodes.append(builder)
		var layout: Dictionary = builder.layout()
		var stats: Dictionary = builder.stats()
		assert_eq(int(stats["pieces"]), (layout.get("pieces", []) as Array).size(),
				"%s: every piece kind is known to a kit" % path.get_file())
		assert_true(int(stats["verts"]) > 0, "%s has geometry" % path.get_file())
		for child: Node in builder.get_children():
			var body: StaticBody3D = child.get_node_or_null(^"Body") as StaticBody3D
			assert_true(body != null and body.get_child_count() > 0,
					"%s/%s collides, or the player falls through it" % [path.get_file(), child.name])
		print("TOWER %s pieces=%d verts=%d colliders=%d" % [path.get_file(), stats["pieces"], stats["verts"],
				stats["colliders"]])


func test_every_tower_is_four_or_five_storeys_and_tall_enough_to_see_from() -> void:
	for path: String in _layouts():
		var layout: Dictionary = StructureBuilder.load_layout(path)
		var storeys: int = int(layout.get("storeys", 0))
		assert_true(storeys >= MIN_STOREYS, "%s is at least %d storeys (%d)" % [path.get_file(), MIN_STOREYS, storeys])
		var head: float = float(layout.get("storey_height", 0.0)) * float(storeys)
		assert_true(head >= MIN_HEAD_HEIGHT, "%s stands %.1f m to its head, at least %.0f m (%.0f ft)"
				% [path.get_file(), head, MIN_HEAD_HEIGHT, head * 3.281])
		var beacon: Dictionary = _piece_named(layout, "tower_fire")
		assert_false(beacon.is_empty(), "%s carries a fire at its head" % path.get_file())
		if not beacon.is_empty():
			assert_true(float((beacon["at"] as Array)[1]) >= head - 0.5,
					"%s fire burns at the head, not partway up" % path.get_file())


func test_every_flight_is_climbable_and_has_headroom_the_whole_way() -> void:
	# The headroom check is the point of this file. It walks the real treads of every flight and asks what
	# is over each one, exactly as the player's head does.
	var checked: int = 0
	for path: String in _layouts():
		var layout: Dictionary = StructureBuilder.load_layout(path)
		var slabs: Array = _slabs(layout, path.get_file())
		for entry: Variant in layout.get("pieces", []):
			var piece: Dictionary = entry
			if str(piece.get("kind", "")) != "stairs" or str(piece.get("name", "")) == "doorstep":
				continue
			var p: Dictionary = piece.get("params", {})
			var name: String = "%s/%s" % [path.get_file(), piece.get("name", "?")]
			var riser: float = minf(float(p.get("riser", StructureKit.DEFAULT_RISER)), StructureKit.MAX_RISER)
			assert_true(float(p.get("riser", 1.0)) <= StructureKit.MAX_RISER, "%s riser is climbable" % name)
			assert_true(float(p.get("w", 0.0)) >= PLAYER_WIDTH, "%s is wide enough to walk up" % name)
			var rise: float = float(p.get("rise", 0.0))
			var tread: float = float(p.get("tread", StructureKit.DEFAULT_TREAD))
			var steps: int = maxi(1, ceili(rise / riser - 0.001))
			var placement: Transform3D = StructureBuilder.placements_of(piece)[0]
			for i: int in range(steps):
				var surface: Vector3 = placement * Vector3(0.0, rise / float(steps) * float(i + 1),
						-tread * (float(i) + 0.5))
				checked += 1
				for slab: Dictionary in slabs:
					var rect: Rect2 = slab["rect"]
					if not rect.has_point(Vector2(surface.x, surface.z)):
						continue
					var under: float = float(slab["bottom"]) - surface.y
					if under <= 0.0:
						continue
					assert_true(under >= HEADROOM, "%s: %s hangs %.2f m over the tread at (%.1f, %.1f) -- the climb needs %.1f m"
							% [name, slab["name"], under, surface.x, surface.z, HEADROOM])
			# Somewhere to step off at the top, or the climb ends in a fall down the stairwell.
			var head: Vector3 = placement * Vector3(0.0, rise, -tread * float(steps) - 0.2)
			var landed: bool = false
			for slab: Dictionary in slabs:
				var rect: Rect2 = slab["rect"]
				if rect.has_point(Vector2(head.x, head.z)) and absf(float(slab["top"]) - head.y) < 0.35:
					landed = true
			assert_true(landed, "%s arrives on a floor (nothing to step onto at %.1f, %.1f)" % [name, head.x, head.z])
	assert_true(checked > 100, "the flights were actually walked (%d treads)" % checked)


func test_the_towers_stand_where_the_map_says_and_the_light_tower_is_on_its_islet() -> void:
	var sites: Array[Dictionary] = []
	for site: Dictionary in SiteRegistry.load_area(AREA):
		if str(site.get("_file", "")) == TOWERS_FILE:
			sites.append(site)
	assert_true(sites.size() >= 3, "at least three towers stand in the Vale (%d)" % sites.size())
	var area: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/areas/vale.json"))
	var hf: Heightfield = Heightfield.from_dict(area)
	var lighthouse: bool = false
	for site: Dictionary in sites:
		assert_true(str(site.get("layout", "")).begins_with(DIR), "%s uses a tower layout" % site["id"])
		assert_false(site.has("props"), "%s carries no interactables" % site["id"])
		var at: Vector2 = SiteRegistry.at_of(site)
		assert_true(hf.height_at(at.x, at.y) > hf.water_level() + 1.0,
				"%s stands out of the water" % site["id"])
		if str(site["id"]) == "pond_lighthouse":
			lighthouse = true
			assert_true(at.length() < 42.0, "the light tower stands inside the pond, on its islet (%.0f m out)"
					% at.length())
			# The islet is a plateau: its top is flat, and the water is well below it.
			assert_true(hf.height_at(at.x, at.y) - hf.water_level() > 2.5,
					"the islet stands %.1f m clear of the water" % (hf.height_at(at.x, at.y) - hf.water_level()))
	assert_true(lighthouse, "the pond carries the light tower")


func test_the_light_tower_has_a_terrace_to_walk_round_and_a_lantern_above_it() -> void:
	var layout: Dictionary = StructureBuilder.load_layout(DIR + "lighthouse.json")
	var terrace: Dictionary = _piece_named(layout, "terrace")
	assert_false(terrace.is_empty(), "the light tower has a terrace")
	var rail: Dictionary = _piece_named(layout, "terrace_rail")
	assert_false(rail.is_empty(), "the terrace has a railing, so walking round it is not a death")
	if not rail.is_empty():
		assert_true((rail.get("repeat", []) as Array).size() >= 3, "the railing runs along three sides")
		assert_true(float((rail["params"] as Dictionary).get("h", 0.0)) >= 0.9, "the railing is waist high")
	var gap: Dictionary = _piece_named(layout, "terrace_rail_gap")
	assert_true((gap.get("params", {}) as Dictionary).has("opening"), "the fourth side has a gap to step through")
	if not terrace.is_empty():
		# The deck's full span, not the slab's width: the slab is trimmed where the last flight comes up.
		var deck: float = float(layout.get("deck", 0.0))
		var walls: Dictionary = _piece_named(layout, "lantern_0")
		assert_false(walls.is_empty(), "there is a lantern room over the terrace")
		if not walls.is_empty():
			assert_true(float((walls["params"] as Dictionary).get("w", 99.0)) < deck,
					"the lantern room is narrower than the deck, so there is deck to walk on")


# --- helpers ----------------------------------------------------------------------------------------------

func _layouts() -> Array[String]:
	var out: Array[String] = []
	for name: String in DirAccess.get_files_at(DIR):
		if name.ends_with(".json"):
			out.append(DIR + name)
	out.sort()
	return out


func _piece_named(layout: Dictionary, name: String) -> Dictionary:
	for entry: Variant in layout.get("pieces", []):
		if entry is Dictionary and str((entry as Dictionary).get("name", "")) == name:
			return entry
	return {}


## Every horizontal surface in the layout, as a plan rectangle plus the heights of its underside and top.
## Floor slabs in these layouts are all placed square (yaw 0), which the first assertion pins, so a plain
## Rect2 is the honest shape; a rotated slab would need an oriented box and this would quietly lie.
func _slabs(layout: Dictionary, file: String) -> Array:
	var out: Array = []
	for entry: Variant in layout.get("pieces", []):
		var piece: Dictionary = entry
		if str(piece.get("kind", "")) != "floor_slab":
			continue
		assert_true(absf(fposmod(float(piece.get("yaw", 0.0)), 180.0)) < 0.01,
				"%s/%s is square to the tower" % [file, piece.get("name", "?")])
		var p: Dictionary = piece.get("params", {})
		var at: Array = piece.get("at", [0, 0, 0])
		var w: float = float(p.get("w", 0.0))
		var d: float = float(p.get("d", 0.0))
		out.append({
			"name": str(piece.get("name", "?")),
			"rect": Rect2(float(at[0]) - w * 0.5, float(at[2]) - d * 0.5, w, d),
			"bottom": float(at[1]),
			"top": float(at[1]) + float(p.get("t", 0.0)),
		})
	return out
