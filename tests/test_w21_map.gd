extends "res://tests/test_case.gd"
## The map as a map (W21-C). The owner used the map to point at places during his recording and then held
## up Elden Ring's map as what a map should look like. The claims here are the ones a test can make:
## the land on the map is sampled from the Heightfield the terrain is built from (not a second set of
## blobs), it is built once and shared, the projection is exact at every span, every name in
## data/places.json lands on the map, the water and roads are real shapes from the area file, names are
## never written over each other, and the corner map -- which redraws while playing -- does no relief work.

const FULL := Rect2(Vector2(0.0, 0.0), Vector2(1840.0, 960.0))
const MINI := Rect2(Vector2(0.0, 0.0), Vector2(168.0, 168.0))
## A small relief for the raster checks: the real one is 256 px and would cost the suite seconds.
const SMALL_PX := 64
const POINTS: Array[Vector2] = [Vector2.ZERO, Vector2(200.0, -160.0), Vector2(-350.0, -168.0), Vector2(37.0, 239.0)]

var _world: Dictionary = {}
var _relief: MapRelief


func setup() -> void:
	_world = MapPanel.gather("vale")
	_relief = MapRelief.create(_world["area"], "vale", SMALL_PX, 1100.0)
	_relief.build_all()


func test_the_relief_is_one_object_built_once_and_shared_by_both_views() -> void:
	var before: int = MapRelief.builds
	var panel := MapPanel.new()
	panel._build()
	panel.load_world("vale")
	var first: MapRelief = panel.relief()
	assert_not_null(first, "loading the world makes a relief")
	assert_false(first.is_ready(), "but does not build it there and then: that is sliced over frames")
	# bind_level loads the world a second time, for the grove. Same area, same relief.
	panel.load_world("vale")
	assert_true(panel.relief() == first, "loading the same area again keeps the same relief")
	assert_true(panel._mini.relief == first and panel._full.relief == first, "both views draw the one picture")
	assert_eq(MapRelief.builds, before, "and nothing was built in the process")
	first.step(0)
	assert_true(is_equal_approx(first.progress(), 1.0 / float(2 * first.px)),
			"a zero budget still does exactly one row, no more (%.4f)" % first.progress())
	panel.free()
	var done: int = MapRelief.builds
	_relief.build_all()
	_relief.step(1000)
	assert_eq(MapRelief.builds, done, "building a built relief again does nothing")


func test_the_relief_is_the_heightfield_and_not_a_drawing_of_its_own() -> void:
	assert_true(_relief.is_ready() and _relief.texture != null, "a built relief has a texture")
	assert_eq(_relief.image.get_width(), SMALL_PX, "of the size asked for")
	var area: Dictionary = _world["area"]
	var hf: Heightfield = Heightfield.from_dict(area)
	var pond: Color = _relief.colour_at(hf.pond_centre())
	assert_true(pond.b > pond.r, "the pond centre is painted as water (%s)" % pond)
	assert_true(pond.a > 0.99, "and solid: it is inside the Vale")
	# The same pixel with the pond taken out of the data is land: the raster follows the Heightfield.
	var dry: Dictionary = area.duplicate(true)
	dry.erase("pond")
	var no_pond: MapRelief = MapRelief.create(dry, "dry", SMALL_PX, 1100.0)
	no_pond.build_all()
	var dry_c: Color = no_pond.colour_at(hf.pond_centre())
	assert_true(dry_c.r >= dry_c.b, "take the pond out of the area and the map has no pond (%s)" % dry_c)
	# The ridge is high ground in the Heightfield, so it is pale on the map; the valley floor is dark.
	var ridge_lum: float = 0.0
	for k: int in 8:
		ridge_lum += _relief.colour_at(Vector2.from_angle(float(k) * TAU / 8.0) * 515.0).get_luminance() / 8.0
	var floor_lum: float = 0.0
	var floor_pts: Array[Vector2] = [Vector2(-90.0, 70.0), Vector2(105.0, -80.0), Vector2(-150.0, 105.0)]
	for p: Vector2 in floor_pts:
		floor_lum += _relief.colour_at(p).get_luminance() / float(floor_pts.size())
		assert_true(hf.height_at(515.0, 0.0) > hf.height_at(p.x, p.y) + 30.0, "the ridge stands over the road at %s" % p)
	assert_true(ridge_lum > floor_lum + 0.03, "and is paler on the map (%.2f vs %.2f)" % [ridge_lum, floor_lum])
	# The fade is a function of the pixel centre's distance from the origin, so at 64 px (17 m per pixel)
	# the pixel under (0, -549) is centred only 21 m past the ridge and is half faded; the corner is 245 m
	# past it and all the way down. Both are asserted: the order, and the floor it reaches.
	var rim: Color = _relief.colour_at(Vector2(0.0, -549.0))
	var corner: Color = _relief.colour_at(Vector2(549.0, -549.0))
	assert_true(corner.a < MapRelief.FADE_TO + 0.02, "far past the ridge the land is faded to the floor (a %.2f)" % corner.a)
	assert_true(corner.a < rim.a and rim.a < pond.a, "and the fade runs with distance (%.2f < %.2f < %.2f)" % [corner.a, rim.a, pond.a])


func test_world_to_panel_round_trips_at_every_span_and_the_relief_agrees() -> void:
	for span: float in [MapDraw.MINI_SPAN, 600.0, 1100.0, 2048.0]:
		for rect: Rect2 in [MINI, FULL]:
			for p: Vector2 in POINTS:
				for c: Vector2 in [Vector2.ZERO, Vector2(-120.0, 250.0)]:
					var back: Vector2 = MapDraw.to_world(MapDraw.to_panel(p, c, span, rect), c, span, rect)
					assert_true(back.distance_to(p) < 0.01, "%s comes back at span %.0f in %s" % [p, span, rect.size])
	# The relief's pixel grid is the same projection: a point lands in the pixel to_panel puts it in.
	var grid := Rect2(Vector2.ZERO, Vector2(SMALL_PX, SMALL_PX))
	for p: Vector2 in POINTS:
		var at: Vector2 = MapDraw.to_panel(p, _relief.centre, _relief.span, grid)
		assert_eq(_relief.pixel_of(p), Vector2i(floori(at.x), floori(at.y)), "%s falls in the same pixel" % p)
	var north: Vector2i = _relief.pixel_of(Vector2(0.0, -400.0))
	assert_true(north.y < _relief.pixel_of(Vector2.ZERO).y, "north is the top row of the image")


func test_every_name_in_places_json_lands_on_the_full_map() -> void:
	var places: Dictionary = _world["places"]
	var expected: int = (places["regions"] as Array).size() + (places["places"] as Array).size() \
			+ (places["waters"] as Array).size()
	var named: Array[Dictionary] = []
	for row: Variant in places["regions"]:
		named.append({"name": (row as Dictionary)["name"], "at": MapShapes.point((row as Dictionary)["centre"])})
	for row: Variant in places["places"]:
		named.append({"name": (row as Dictionary)["name"], "at": MapShapes.point((row as Dictionary)["at"])})
	for row: Variant in places["waters"]:
		var pts: Array = (row as Dictionary)["points"]
		named.append({"name": (row as Dictionary)["name"], "at": MapShapes.point(pts[pts.size() >> 1])})
	assert_eq(named.size(), expected, "every region, place and reach is a name on the map (%d)" % expected)
	for n: Dictionary in named:
		var at: Vector2 = MapDraw.to_panel(n["at"], Vector2.ZERO, 1100.0, FULL)
		assert_true(FULL.has_point(at), "'%s' is inside the full map at %s" % [n["name"], at])
		assert_true(_relief.colour_at(n["at"]).a > 0.5, "'%s' is on the land, not in the faded void" % n["name"])


func test_water_and_roads_are_shapes_from_the_area_file() -> void:
	var area: Dictionary = _world["area"]
	var fill: Dictionary = MapShapes.river_pieces(area)
	var quads: Array = fill["quads"]
	var joints: PackedVector3Array = fill["joints"]
	assert_true(quads.size() >= 2 and joints.size() == quads.size() + 1,
			"the river is a chain of quads with a disc at every joint (%d quads)" % quads.size())
	for q: PackedVector2Array in quads:
		assert_eq(q.size(), 4, "each piece is a quad")
	var widest: float = 0.0
	var narrowest: float = INF
	for i: int in range(1, joints.size() - 1):
		widest = maxf(widest, joints[i].z)
		narrowest = minf(narrowest, joints[i].z)
	assert_true(widest > narrowest + 1.0, "the river widens at the Wide Water (%.1f vs %.1f m)" % [widest, narrowest])
	assert_true(joints[0].z < joints[1].z, "and tapers where it leaves the Vale")
	var rim: Dictionary = MapShapes.river_pieces(area, 2.0)
	assert_true(is_equal_approx((rim["joints"] as PackedVector3Array)[1].z, joints[1].z + 2.0),
			"the shore is the same chain, two metres wider")
	assert_true(float(MapShapes.pond(area)["radius"]) > 0.0, "the pond is a disc with a radius")
	var roads: Dictionary = MapShapes.roads(area)
	var spine: PackedVector2Array = roads["spine"]
	assert_eq(spine.size(), ((area["valley"] as Dictionary)["waypoints"] as Array).size(),
			"the old road is the valley's own waypoints")
	var tracks: Array = roads["tracks"]
	assert_true(not tracks.is_empty(), "the worn tracks beyond the old road are drawn too")
	for t: PackedVector2Array in tracks:
		assert_false(MapShapes._on_spine(spine, t[0], t[1]), "and no track repeats a piece of the road")
	# Negative controls: no waters, no river; one point, no ribbon.
	var dry: Dictionary = area.duplicate(true)
	dry["waters"] = []
	assert_true((MapShapes.river_pieces(dry)["quads"] as Array).is_empty(), "an area with no waters draws no river")
	var stub: Dictionary = MapShapes.ribbon_pieces(PackedVector2Array([Vector2.ZERO]), PackedFloat32Array([5.0]))
	assert_true((stub["quads"] as Array).is_empty(), "one point is not a river")


func test_names_never_cover_each_other_and_the_crowd_is_thinned_by_rank() -> void:
	var rect := Rect2(Vector2.ZERO, Vector2(400.0, 400.0))
	var crowd: Array[Dictionary] = []
	for i: int in 6:
		crowd.append({"text": "crowd %d" % i, "at": Vector2(200.0, 200.0), "size": Vector2(80.0, 16.0),
				"rank": 1 if i == 0 else 4, "centred": false, "solid": true})
	var placed: Array[Dictionary] = MapLabels.layout(crowd, rect)
	assert_false(MapLabels.overlaps(placed), "no two written names overlap")
	var count: int = 0
	for item: Dictionary in placed:
		if bool(item["placed"]):
			count += 1
	assert_eq(count, 4, "six names on one point: four sides, so four written and two left off")
	assert_eq(str(placed[0]["text"]), "crowd 0", "the rank-1 name is placed first")
	assert_true((placed[0]["pos"] as Vector2).x > 200.0, "and gets the preferred slot, to the right")
	# A name at the edge is moved to the side that fits, never cut off.
	var rim: Array[Dictionary] = [{"text": "rim", "at": Vector2(395.0, 200.0), "size": Vector2(80.0, 16.0),
			"rank": 1, "centred": false, "solid": true}]
	var edge: Array[Dictionary] = MapLabels.layout(rim, rect)
	assert_true(bool(edge[0]["placed"]), "a name at the right edge is still written")
	assert_true(rect.encloses(Rect2(edge[0]["pos"], edge[0]["size"])), "inside the map, on its left")
	# Region names are a background layer: written, but they block nobody.
	var layered: Array[Dictionary] = [
		{"text": "REGION", "at": Vector2(200.0, 200.0), "size": Vector2(200.0, 20.0), "rank": 0, "centred": true, "solid": false},
		{"text": "place", "at": Vector2(200.0, 200.0), "size": Vector2(60.0, 14.0), "rank": 1, "centred": false, "solid": true},
	]
	var both: Array[Dictionary] = MapLabels.layout(layered, rect)
	assert_true(bool(both[0]["placed"]) and bool(both[1]["placed"]), "a place can sit over its region's name")
	assert_true(Rect2(both[0]["pos"], both[0]["size"]).intersects(Rect2(both[1]["pos"], both[1]["size"])),
			"and does, which is the point: the region name is faint and behind")
	assert_true(MapLabels.em_of("castle") > MapLabels.em_of("tower") and MapLabels.em_of("tower") > MapLabels.em_of("house"),
			"castles are written larger than towers, towers larger than crofts")
	assert_true(MapLabels.rank_of("village") < MapLabels.rank_of("house"), "and a village is placed before a croft")


func test_the_corner_map_does_no_relief_work() -> void:
	# Code lines only: the header comment is allowed to say where the picture comes from.
	var code: String = ""
	for line: String in FileAccess.get_file_as_string("res://scripts/ui/map_view.gd").split("\n"):
		if not line.strip_edges().begins_with("#"):
			code += line + "\n"
	assert_false(code.contains("Heightfield") or code.contains(".step(") or code.contains("build_all("),
			"the view never samples or builds; it draws the texture it is handed")
	var panel_src: String = FileAccess.get_file_as_string("res://scripts/ui/map_panel.gd")
	assert_true(panel_src.contains("step(RELIEF_BUDGET_USEC)"), "the panel slices the build per frame, on a budget")
	var before: int = MapRelief.builds
	var view := MapView.new()
	view.span = MapDraw.MINI_SPAN
	view.dot_size = MapDraw.MINI_DOT
	view.world = _world
	view.relief = MapRelief.create(_world["area"], "vale", SMALL_PX, 1100.0)
	for i: int in 3:
		view.refresh(Vector2(float(i), 0.0), 45.0)
	assert_eq(MapRelief.builds, before, "handing a corner map a world and moving the player builds nothing")
	assert_false(view.relief.is_ready(), "and its relief is untouched until the panel steps it")
	view.free()


func test_the_arrow_points_where_the_player_looks() -> void:
	assert_true(MapDraw.heading(0.0).distance_to(Vector2(0.0, -1.0)) < 0.001, "bearing 0 is up: north")
	assert_true(MapDraw.heading(90.0).distance_to(Vector2(1.0, 0.0)) < 0.001, "bearing 90 is right: east")
	assert_true(MapDraw.heading(180.0).distance_to(Vector2(0.0, 1.0)) < 0.001, "bearing 180 is down: south")
