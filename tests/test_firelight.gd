extends "res://tests/test_case.gd"
## The lit kit (W9-F): the seven fire pieces, the FireLight nodes they hang on a placement, and where the
## fires stand in the Vale. The property the whole pass exists for is the last test here: walking the old
## road at night, there is always something lit within sight, so the player is never left in the dark with
## no direction. Seen to fail: docs/reports/W9-F.md quotes the negative control.

const LIT_KINDS: Array[String] = ["brazier", "torch_post", "wall_torch", "hearth_remains", "lamp_stone",
		"pyre", "beacon"]
## Kinds that stand on the ground, so their base must reach `sink` below it. A wall torch is mounted.
const STANDING: Array[String] = ["brazier", "torch_post", "hearth_remains", "lamp_stone", "pyre", "beacon"]
const HOUSES_DIR := "res://data/structures/houses/"
const POIS_DIR := "res://data/structures/pois/"
const AREA := "vale"
const LIGHTS_FILE := "vale_lights.json"
const ROAD: Array = [[-200, 140], [-90, 70], [0, 0], [105, -80], [200, -160]]
## The pond basin: the road crosses water there, so no fire can stand on that stretch.
const POND_RADIUS := 90.0
const ROAD_STEP := 8.0
## How far the next lit thing may be from any walkable point of the road. 60 m would be no guard at all:
## with data/sites/vale_lights.json held back, the houses and camps alone leave the worst stretch at 57.7 m,
## and this test passed. 40 m is a limit the wayside lights have to earn (they bring it to 24.8 m).
const ROAD_SIGHT := 40.0
## The most fires that may ever fall inside one 60 m cull sphere, anywhere in the valley. They are the
## lights that can all be on at once, so this is the number to watch when more fires are added; the castle
## alone holds twenty-one. The vale probe prints the same figure from the live scene (PROBE fires).
## Raised 45 -> 55 (W12) -> 70 (W17). Hollowmere holds 59 inside one sphere now that every house has a
## fire indoors, which is the change that answered "the interiors are black holes". The judgement, so it
## can be overturned with evidence rather than feel: these are OMNI lights with NO shadows and a distance
## fade, which is the cheap end of what a clustered renderer does, and the interior ones cull at 48 m so
## most of them are not drawing at any given moment. What would prove this wrong is the owner's laptop
## dropping frames in that village -- and the vale probe prints `drawing` every run, which is the number
## to look at when it does.
const CROWD_LIMIT := 70

var _nodes: Array[Node] = []


func teardown() -> void:
	for node: Node in _nodes:
		node.free()
	_nodes.clear()
	StructureBuilder.clear_shared()
	FireLight.clear_shared()


# --- the kit ----------------------------------------------------------------------------------------------

func test_every_lit_kind_builds_geometry_a_light_and_a_flame() -> void:
	for kind: String in LIT_KINDS:
		var piece: Dictionary = StructureBuilder.make_piece(kind, {"seed": 3}, kind)
		assert_false(piece.is_empty(), "%s is a kind the builder knows" % kind)
		if piece.is_empty():
			continue
		assert_true(int(piece["verts"]) > 0, "%s has geometry" % kind)
		assert_true((piece["shapes"] as Array).size() > 0, "%s collides" % kind)
		var lights: Array = piece.get("lights", [])
		assert_true(lights.size() >= 1, "%s carries at least one light" % kind)
		for spec: Variant in lights:
			var light: Dictionary = spec
			assert_true(float(light["energy"]) > 0.0, "%s light has energy" % kind)
			assert_true(float(light["range"]) > 1.0, "%s light reaches past its own stones" % kind)
			assert_true(float(light["flame"]) > 0.0, "%s shows a flame, not just a glow" % kind)
			assert_true(float(light["at"][1]) > 0.0, "%s light sits above its base" % kind)


func test_a_standing_fire_reaches_below_the_ground_and_a_wall_torch_does_not() -> void:
	for kind: String in STANDING:
		var piece: Dictionary = StructureBuilder.make_piece(kind, {"sink": 0.8, "seed": 5}, kind)
		var lowest: float = INF
		for v: Vector3 in _verts(piece):
			lowest = minf(lowest, v.y)
		assert_true(lowest <= -0.75, "%s reaches 0.8 m under the ground it stands on (got %.2f)" % [kind, lowest])
	var mounted: Dictionary = StructureBuilder.make_piece("wall_torch", {}, "wall_torch")
	var under: float = INF
	for v: Vector3 in _verts(mounted):
		under = minf(under, v.y)
	assert_true(under > -0.6, "a wall torch hangs where it is put; it does not sink (lowest %.2f)" % under)


func test_a_lit_piece_hangs_one_fire_on_every_placement() -> void:
	var piece: Dictionary = StructureBuilder.make_piece("brazier", {"h": 1.0}, "brazier")
	var single: Node3D = StructureKit.make_node(piece, "one")
	_nodes.append(single)
	assert_eq(_fires(single).size(), 1, "a lone brazier gets one fire")
	var spots: Array[Transform3D] = [
		Transform3D(Basis.IDENTITY, Vector3(5.0, 0.0, 0.0)),
		Transform3D(Basis.IDENTITY, Vector3(-5.0, 0.0, 2.0)),
		Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(0.0, 1.0, -3.0)),
	]
	var many: Node3D = StructureKit.make_multi(piece, spots, "three")
	_nodes.append(many)
	var fires: Array[FireLight] = _fires(many)
	assert_eq(fires.size(), 3, "three instanced braziers get three fires, not one")
	var lift: float = float((piece["lights"][0] as Dictionary)["at"][1])
	for i: int in range(mini(fires.size(), spots.size())):
		var want: Vector3 = spots[i].origin + Vector3(0.0, lift, 0.0)
		assert_true(fires[i].position.is_equal_approx(want),
				"fire %d stands on its own instance (%s, wanted %s)" % [i, str(fires[i].position), str(want)])


func test_an_unlit_piece_gets_no_fire() -> void:
	# The negative control for the plumbing: if make_node lit everything, this would fail.
	for kind: String in ["wall", "cairn", "haystack", "floor_slab"]:
		var piece: Dictionary = StructureBuilder.make_piece(kind, {"w": 2.0, "h": 2.0, "d": 2.0, "t": 0.4}, kind)
		assert_false(piece.has("lights"), "%s describes no lights" % kind)
		var node: Node3D = StructureKit.make_node(piece, kind)
		_nodes.append(node)
		assert_eq(_fires(node).size(), 0, "%s hangs no fire" % kind)


func test_a_fire_casts_no_shadow_fades_with_distance_and_carries_a_flame() -> void:
	var parent := Node3D.new()
	_nodes.append(parent)
	var light: FireLight = FireLight.attach(parent, {"at": [0, 1, 0], "energy": 2.0, "range": 9.0,
			"flame": 0.5, "cull": 48.0})
	light._ready()
	assert_false(light.shadow_enabled, "a fire never casts a shadow: it is the one thing that makes it cheap")
	assert_true(light.distance_fade_enabled and light.distance_fade_begin < light.cull_distance,
			"the engine fades it out before the cull distance")
	assert_true(is_equal_approx(light.omni_range, 9.0), "the spec's range reached the light")
	assert_true(light.light_energy > 0.0, "it is burning")
	assert_true(light.is_in_group(FireLight.GROUP), "it joins the fires group the probe counts")
	var flame: MeshInstance3D = light.get_node_or_null(^"Flame") as MeshInstance3D
	assert_not_null(flame, "it has a flame to see")
	if flame != null:
		assert_eq(flame.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "the flame casts nothing")
		assert_true(is_equal_approx(flame.visibility_range_end, 48.0), "the flame stops drawing at the cull distance")
		assert_true(flame.position.y > 0.0, "the flame stands on its base, not through it")
	var dark := Node3D.new()
	_nodes.append(dark)
	var glow: FireLight = FireLight.attach(dark, {"at": [0, 1, 0], "flame": 0.0})
	glow._ready()
	assert_null(glow.get_node_or_null(^"Flame"), "flame 0 is a bare glow with nothing to draw")


func test_darkness_follows_the_sun() -> void:
	assert_true(is_equal_approx(FireLight.darkness_at(0.0), 1.0), "midnight is full dark")
	assert_true(is_equal_approx(FireLight.darkness_at(12.0), 0.0), "noon is none")
	assert_true(is_equal_approx(FireLight.darkness_at(3.0), 1.0), "the small hours are full dark")
	assert_true(is_equal_approx(FireLight.darkness_at(22.0), 1.0), "an hour after dusk is full dark")
	var dusk: float = FireLight.darkness_at(17.0)
	assert_true(dusk > 0.5 and dusk < 1.0, "the fires are already carrying by dusk (%.2f)" % dusk)
	assert_true(FireLight.darkness_at(7.0) > FireLight.darkness_at(9.0), "it keeps lightening after sunrise")


func test_the_flame_texture_is_a_teardrop() -> void:
	var tex: ImageTexture = FireLight.flame_texture()
	var img: Image = tex.get_image()
	var size: int = img.get_width()
	var base: Color = img.get_pixel(size / 2, size - 2)
	var top_edge: Color = img.get_pixel(2, 2)
	var tip: Color = img.get_pixel(size / 2, 0)
	assert_true(base.a > 0.5, "the core at the base is bright (%.2f)" % base.a)
	assert_true(top_edge.a < 0.05, "the top corners are empty (%.2f)" % top_edge.a)
	assert_true(tip.a < base.a, "it narrows to a tip (%.2f vs %.2f)" % [tip.a, base.a])
	assert_true(base.r > base.b, "a flame is warm, not grey")


# --- where the fires stand --------------------------------------------------------------------------------

func test_every_house_archetype_is_lit() -> void:
	var by_archetype: Dictionary = {}
	for name: String in DirAccess.get_files_at(HOUSES_DIR):
		if not name.ends_with(".json"):
			continue
		var layout: Dictionary = StructureBuilder.load_layout(HOUSES_DIR + name)
		var kinds: Array[String] = _lit_kinds_of(layout)
		assert_true(kinds.size() >= 1, "%s carries a fire somebody could walk towards" % name)
		var archetype: String = str(layout.get("archetype", "?"))
		by_archetype[archetype] = true
		# A fire inside a house is no use for finding the house, so every layout has one outdoors too.
		var outdoors: bool = false
		for kind: String in kinds:
			outdoors = outdoors or kind != "wall_torch"
		assert_true(outdoors, "%s has a fire outside it, not only on a wall indoors" % name)
	for archetype: String in ["shack", "cottage", "barn", "watch", "shrine"]:
		assert_true(by_archetype.has(archetype), "the %s archetype is lit" % archetype)


func test_the_watch_huts_carry_their_fire_on_the_lookout() -> void:
	for name: String in ["watch_intact.json", "watch_ruined.json"]:
		var layout: Dictionary = StructureBuilder.load_layout(HOUSES_DIR + name)
		var found: bool = false
		for raw: Variant in layout.get("pieces", []):
			var entry: Dictionary = raw
			if str(entry.get("kind", "")) != "beacon":
				continue
			found = true
			var at: Array = entry.get("at", [0, 0, 0])
			assert_true(float(at[1]) > 2.5, "%s beacon stands on the lookout floor, not the ground" % name)
			var params: Dictionary = entry.get("params", {})
			assert_true(float(params.get("range", 0.0)) >= 24.0,
					"%s beacon carries further than a yard fire" % name)
		assert_true(found, "%s has a beacon" % name)


func test_the_castle_the_village_and_the_camps_are_lit() -> void:
	var castle: Array[String] = _lit_kinds_of(StructureBuilder.load_layout("res://data/structures/castle_morrow.json"))
	assert_true(castle.size() >= 8, "the castle is lit in several places (%d lit pieces)" % castle.size())
	assert_true(castle.has("wall_torch") and castle.has("brazier") and castle.has("pyre"),
			"the gate, the chapel and the courtyard each got their own kind of fire")
	var crypt: bool = false
	for raw: Variant in StructureBuilder.load_layout("res://data/structures/castle_morrow.json").get("pieces", []):
		var entry: Dictionary = raw
		if LIT_KINDS.has(str(entry.get("kind", ""))) and str(entry.get("group", "")) == "crypt":
			crypt = true
	assert_true(crypt, "the crypt is lit: it is the one room with no sky at all")
	var village: Array[String] = _lit_kinds_of(StructureBuilder.load_layout("res://data/structures/village.json"))
	assert_true(village.size() >= 4, "the broken village is lit (%d lit pieces)" % village.size())
	assert_true(village.has("beacon"), "the village carries a beacon, so it reads from across the valley")
	for name: String in ["campsite.json", "crossroads.json", "picket.json", "shore_fire.json", "siege_camp.json"]:
		var layout: Dictionary = StructureBuilder.load_layout(POIS_DIR + name)
		assert_true(_lit_kinds_of(layout).size() >= 1, "%s: the camp fire is burning, not cold" % name)


func test_the_road_lights_are_placed_along_the_road() -> void:
	var sites: Array[Dictionary] = _sites_in(LIGHTS_FILE)
	assert_true(sites.size() >= 15, "the lights file places at least 15 sites (%d)" % sites.size())
	var lamps: int = 0
	for site: Dictionary in sites:
		var layout: Dictionary = StructureBuilder.load_layout(str(site.get("layout", "")))
		assert_true(_lit_kinds_of(layout).size() >= 1, "%s is a lit layout" % site["id"])
		assert_false(site.has("props"), "%s carries no interactables" % site["id"])
		var at: Vector2 = SiteRegistry.at_of(site)
		assert_true(at.length() > POND_RADIUS - 2.0, "%s stands out of the pond basin" % site["id"])
		if str(site["id"]).begins_with("way_lamp") or str(site["id"]).begins_with("road_brazier"):
			lamps += 1
			assert_true(_road_distance(at) < 12.0, "%s stands on the verge of the road (%.1f m off)"
					% [site["id"], _road_distance(at)])
	assert_true(lamps >= 10, "at least ten lights stand along the road itself (%d)" % lamps)


func test_no_cull_sphere_ever_holds_too_many_fires() -> void:
	var counts: Array = _fire_counts()
	var total: int = 0
	for row: Array in counts:
		total += int(row[1])
	assert_true(total >= 60, "the valley is lit in a lot of places (%d fires)" % total)
	var worst: int = 0
	var worst_at := Vector2.ZERO
	for row: Array in counts:
		var near: int = 0
		for other: Array in counts:
			if (row[0] as Vector2).distance_to(other[0]) < 60.0:
				near += int(other[1])
		if near > worst:
			worst = near
			worst_at = row[0]
	print("FIRES total=%d lit_sites=%d worst_crowd_60m=%d at=%s" % [total, counts.size(), worst, str(worst_at)])
	assert_true(worst <= CROWD_LIMIT, "at most %d fires fall in one 60 m cull sphere (%d at %s)"
			% [CROWD_LIMIT, worst, str(worst_at)])


func test_the_old_road_is_never_dark_for_long() -> void:
	# The point of the whole pass: at night, every step of the road has something lit in sight.
	var spots: Array[Vector2] = _lit_sites()
	var worst: float = 0.0
	var worst_at := Vector2.ZERO
	var samples: int = 0
	for i: int in range(ROAD.size() - 1):
		var a := Vector2(float(ROAD[i][0]), float(ROAD[i][1]))
		var b := Vector2(float(ROAD[i + 1][0]), float(ROAD[i + 1][1]))
		var steps: int = maxi(1, int(a.distance_to(b) / ROAD_STEP))
		for s: int in range(steps + 1):
			var p: Vector2 = a.lerp(b, float(s) / float(steps))
			if p.length() < POND_RADIUS:
				continue
			samples += 1
			var best: float = INF
			for spot: Vector2 in spots:
				best = minf(best, p.distance_to(spot))
			if best > worst:
				worst = best
				worst_at = p
	print("FIRES road_samples=%d worst_dark_stretch=%.1f at=%s" % [samples, worst, str(worst_at)])
	assert_true(samples > 20, "the road was sampled outside the pond basin (%d points)" % samples)
	assert_true(worst <= ROAD_SIGHT, "the darkest point of the road, %s, is %.0f m from the nearest fire (limit %.0f)"
			% [str(worst_at), worst, ROAD_SIGHT])


# --- helpers ----------------------------------------------------------------------------------------------

func _fires(node: Node) -> Array[FireLight]:
	var out: Array[FireLight] = []
	for child: Node in node.get_children():
		if child is FireLight:
			out.append(child)
	return out


func _verts(piece: Dictionary) -> PackedVector3Array:
	var out := PackedVector3Array()
	var mesh: ArrayMesh = piece["mesh"]
	for surface: int in range(mesh.get_surface_count()):
		out.append_array(mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX])
	return out


func _lit_kinds_of(layout: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for raw: Variant in layout.get("pieces", []):
		if raw is Dictionary and LIT_KINDS.has(str((raw as Dictionary).get("kind", ""))):
			out.append(str((raw as Dictionary)["kind"]))
	return out


func _sites_in(file: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for site: Dictionary in SiteRegistry.load_area(AREA):
		if str(site.get("_file", "")) == file:
			out.append(site)
	return out


## Every site in the area whose layout carries a fire, as its world position. The fixed sites count too:
## the castle and the village are the two biggest lit places in the Vale.
func _lit_sites() -> Array[Vector2]:
	var out: Array[Vector2] = []
	var cache: Dictionary = {}
	for site: Dictionary in SiteRegistry.load_area(AREA):
		var path: String = str(site.get("layout", ""))
		if not cache.has(path):
			cache[path] = _lit_kinds_of(StructureBuilder.load_layout(path)).size() > 0
		if bool(cache[path]):
			out.append(SiteRegistry.at_of(site))
	return out


## [position, fires] per lit site, counting a `repeat` list once per placement: the castle is one site and
## twenty-one fires. Close enough for a crowd count, since no site is wider than a cull sphere.
func _fire_counts() -> Array:
	var out: Array = []
	var cache: Dictionary = {}
	for site: Dictionary in SiteRegistry.load_area(AREA):
		var path: String = str(site.get("layout", ""))
		if not cache.has(path):
			var fires: int = 0
			for raw: Variant in StructureBuilder.load_layout(path).get("pieces", []):
				var entry: Dictionary = raw
				if LIT_KINDS.has(str(entry.get("kind", ""))):
					fires += StructureBuilder.placements_of(entry).size()
			cache[path] = fires
		if int(cache[path]) > 0:
			out.append([SiteRegistry.at_of(site), int(cache[path])])
	return out


func _road_distance(p: Vector2) -> float:
	var best: float = INF
	for i: int in range(ROAD.size() - 1):
		var a := Vector2(float(ROAD[i][0]), float(ROAD[i][1]))
		var b := Vector2(float(ROAD[i + 1][0]), float(ROAD[i + 1][1]))
		best = minf(best, p.distance_to(Geometry2D.get_closest_point_to_segment(p, a, b)))
	return best
