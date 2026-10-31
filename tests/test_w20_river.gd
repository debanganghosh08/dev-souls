extends "res://tests/test_case.gd"
## The river (W20). The owner spent ten minutes in the game and came back with: the river is not properly
## cut out, there is no proper water, and of the bridges he found one, with nothing under it.
##
## All three were true and none of them was caught by anything, because the suite checked that a water
## surface existed and that it would drown you -- never that there was any water under your feet, and
## never that a bridge went over the water rather than past it. Every assertion here is one of the things
## the recording showed:
##
##   1. the bed is below the water for the river's whole length, not just where the land happens to be low;
##   2. the water only ever runs downhill;
##   3. the banks are above the water, so you cannot walk underneath the surface;
##   4. every bridge is ON the river and turned ACROSS it;
##   5. nothing grows in the water.

const AREA := "vale"
## How far apart the samples are when walking the river.
const STEP := 16.0

var _hf: Heightfield
var _cuts: Array = []
var _waters: Array = []
var _sites: Array[Dictionary] = []


func setup() -> void:
	var area: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/areas/%s.json" % AREA))
	_hf = Heightfield.from_dict(area)
	_cuts = area.get("cuts", [])
	_waters = area.get("waters", [])
	_sites = SiteRegistry.load_area(AREA)


func test_the_river_has_water_in_it_from_one_rim_to_the_other() -> void:
	assert_true(_cuts.size() >= 1, "the Vale cuts a bed for its river")
	var walked: int = 0
	var dry: int = 0
	var shallowest: float = INF
	for raw: Variant in _cuts:
		var cut: Dictionary = raw
		var points := PackedVector2Array()
		var levels := PackedFloat32Array()
		for q: Variant in cut["points"]:
			var p: Array = q
			points.append(Vector2(float(p[0]), float(p[1])))
			levels.append(float(p[2]))
		var line: PackedVector2Array = Water.walk(points, STEP)
		var surface: PackedFloat32Array = Water._levels_along(points, levels, line, 0.0)
		for i: int in line.size():
			var depth: float = surface[i] - _hf.height_at(line[i].x, line[i].y)
			walked += 1
			shallowest = minf(shallowest, depth)
			if depth <= 0.0:
				dry += 1
	# Before W20 this was 22 of 31 steps dry, with the bed standing up to 13 m ABOVE the water, because
	# the bed was cut a fixed depth below whatever the ground did and the ground rises to +13 m.
	assert_eq(dry, 0, "no step of the river is dry (%d of %d walked)" % [dry, walked])
	assert_true(shallowest > 1.5, "and the shallowest reach is still a river (%.2f m)" % shallowest)
	assert_true(walked > 40, "the whole length was walked (%d steps)" % walked)


func test_the_water_only_ever_runs_downhill() -> void:
	for raw: Variant in _cuts:
		var cut: Dictionary = raw
		var last: float = INF
		for q: Variant in cut["points"]:
			var p: Array = q
			assert_true(float(p[2]) <= last + 0.001,
					"%s falls from source to mouth (%.2f after %.2f)" % [cut["name"], float(p[2]), last])
			last = float(p[2])


func test_the_banks_stand_above_the_water_so_you_cannot_walk_under_it() -> void:
	# The owner filmed a black plane across the whole horizon. It was the UNDERSIDE of the river: the
	# surface sat at a fixed height over ground that had sunk below it, so the bank was lower than the
	# water and you could walk in under the sheet. A real cut cannot do that.
	var cut: Dictionary = _cuts[0]
	var reach: float = float(cut["half_width"]) + float(cut["bank"]) + 3.0
	var spilling: Array[String] = []
	var points: Array = cut["points"]
	for i: int in range(1, points.size() - 1):
		var a: Array = points[i]
		var at := Vector2(float(a[0]), float(a[1]))
		var ahead: Array = points[i + 1]
		var dir: Vector2 = (Vector2(float(ahead[0]), float(ahead[1])) - at).normalized()
		var side := Vector2(-dir.y, dir.x)
		for way: Vector2 in [side, -side]:
			var bank: float = _hf.height_at(at.x + way.x * reach, at.y + way.y * reach)
			if bank < float(a[2]):
				spilling.append("%s at (%.0f, %.0f): bank %.2f under a surface of %.2f"
						% [cut["name"], at.x, at.y, bank, float(a[2])])
	# The two rim ends are left out of the loop above on purpose: a river reaching the edge of the world
	# spreads out, and that is what a mouth does.
	assert_true(spilling.is_empty(), "the water is held by its banks (%s)" % ", ".join(spilling))


func test_the_gorge_is_deep_where_the_land_is_high() -> void:
	# The owner asked for cut hills with the river between them. An absolute cut gives that for free: it
	# takes the ground down to the same water wherever it starts from, so high land becomes a gorge.
	var deepest: float = 0.0
	var cut: Dictionary = _cuts[0]
	var reach: float = float(cut["half_width"]) + float(cut["bank"]) + 3.0
	for raw: Variant in cut["points"]:
		var p: Array = raw
		var at := Vector2(float(p[0]), float(p[1]))
		var rim: float = maxf(_hf.height_at(at.x + reach, at.y), _hf.height_at(at.x, at.y + reach))
		var bed: float = _hf.height_at(at.x, at.y)
		# The CUT has to be what put the bed there, not a hollow that happened to be lying about:
		# without this the test passes on natural ground that merely slopes, which is how a control
		# that switched the cut off entirely went unnoticed here.
		# At or below where this cut asks for it, never above: the Wide Water is a second cut over the
		# same middle reach and it digs 0.8 m deeper, so the bed there is the deeper of the two.
		assert_true(bed <= float(p[2]) - float(cut["depth"]) + 0.35,
			"the bed at (%.0f, %.0f) is where a cut put it (%.2f against %.2f)"
			% [at.x, at.y, bed, float(p[2]) - float(cut["depth"])])
		deepest = maxf(deepest, rim - bed)
	assert_true(deepest > 8.0, "somewhere the river runs in a real gorge (%.1f m)" % deepest)


func test_every_bridge_stands_on_the_river_and_crosses_it() -> void:
	# This is the one the owner found by walking: four bridges were placed 15 m to the SIDE of the water
	# and a river_bridge is 36 m long, so not one of them reached the river. Nothing checked.
	var bridges: Array[Dictionary] = []
	for site: Dictionary in _sites:
		if str(site["layout"]).contains("bridge") and not str(site["id"]).begins_with("hollowmere"):
			bridges.append(site)
	assert_true(bridges.size() >= 3, "the river has crossings (%d)" % bridges.size())
	var cut: Dictionary = _cuts[0]
	var points: Array = cut["points"]
	for site: Dictionary in bridges:
		var at: Vector2 = SiteRegistry.at_of(site)
		# Nearest point on the river, and the river's heading there.
		var best: float = INF
		var heading: float = 0.0
		for i: int in points.size() - 1:
			var a := Vector2(float((points[i] as Array)[0]), float((points[i] as Array)[1]))
			var b := Vector2(float((points[i + 1] as Array)[0]), float((points[i + 1] as Array)[1]))
			var on: Vector2 = Geometry2D.get_closest_point_to_segment(at, a, b)
			if at.distance_to(on) < best:
				best = at.distance_to(on)
				heading = rad_to_deg(atan2(b.x - a.x, -(b.y - a.y)))
		assert_true(best < float(cut["half_width"]),
				"%s stands over the water, not beside it (%.1f m off the line)" % [site["id"], best])
		# And turned across the flow: the layouts run along their own Z, so a crossing is the river's
		# heading plus a right angle, give or take.
		var want: float = fposmod(heading + 90.0, 180.0)
		var got: float = fposmod(SiteRegistry.yaw_of(site), 180.0)
		var off: float = absf(fposmod(got - want + 90.0, 180.0) - 90.0)
		assert_true(off < 25.0, "%s is turned across the river, not along it (%.0f deg out)" % [site["id"], off])
		# And there is water under it. A bridge over dry ground is a folly.
		var level: Vector2 = _hf.surface_at(at.x, at.y)
		assert_true(level.x - _hf.height_at(at.x, at.y) > 1.0,
				"%s has water under it (%.2f m of it)" % [site["id"], level.x - _hf.height_at(at.x, at.y)])


func test_the_widest_reach_has_a_span_with_nothing_holding_it_up() -> void:
	var hanging: Array[Dictionary] = []
	for site: Dictionary in _sites:
		if str(site["layout"]).contains("hanging_bridge"):
			hanging.append(site)
	assert_eq(hanging.size(), 1, "there is one hanging bridge, which the owner asked for by name")
	var wide: Dictionary = {}
	for raw: Variant in _cuts:
		if str((raw as Dictionary)["name"]) == "river_wide":
			wide = raw
	assert_false(wide.is_empty(), "and a widest reach for it to hang over")
	var at: Vector2 = SiteRegistry.at_of(hanging[0])
	var points: Array = wide["points"]
	var best: float = INF
	for i: int in points.size() - 1:
		var a := Vector2(float((points[i] as Array)[0]), float((points[i] as Array)[1]))
		var b := Vector2(float((points[i + 1] as Array)[0]), float((points[i + 1] as Array)[1]))
		best = minf(best, at.distance_to(Geometry2D.get_closest_point_to_segment(at, a, b)))
	assert_true(best < float(wide["half_width"]), "the span hangs over the Wide Water (%.1f m off it)" % best)


func test_nothing_grows_in_the_water() -> void:
	# Trees stood in the river in the recording, dead trunks rising out of it, because every scatter
	# filter knew only the pond's water level (-5.0) and the rivers run on their own surfaces from -4.2
	# down to -7.5. A level that asks the pond about a river gets the wrong answer every time.
	var level: String = FileAccess.get_file_as_string("res://scenes/levels/vale.gd")
	assert_true(level.contains("if hf.in_river(x, z, TREE_SHORE_CLEARANCE):"), "no tree grows in a river")
	assert_true(level.contains("if _is_wet(x, z):"), "no grass grows in a river")
	assert_true(level.contains("if hf.in_river(x, z, TREE_SHORE_CLEARANCE * 0.5):"), "and no prop sits in one")
	# And the rule itself works: the middle of the river is wet and the bank thirty metres off is not.
	var cut: Dictionary = _cuts[0]
	var mid: Array = cut["points"][cut["points"].size() / 2]
	var at := Vector2(float(mid[0]), float(mid[1]))
	assert_true(_hf.in_river(at.x, at.y), "the middle of the river is in the river")
	var reach: float = float(cut["half_width"]) + float(cut["bank"]) + 40.0
	assert_false(_hf.in_river(at.x + reach, at.y + reach), "and the field beyond the bank is not")


func test_a_site_in_the_riverbed_is_refused_by_the_placement_checker() -> void:
	# GroundProbe is what content work is laid out with (W10). It only knew the pond's water level too,
	# which is how a well house came to stand 4 m from the centre line of a river.
	var area: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/areas/%s.json" % AREA))
	var road: PackedVector2Array = GroundProbe.road_of(area)
	var cut: Dictionary = _cuts[0]
	var mid: Array = cut["points"][cut["points"].size() / 2]
	var row: Dictionary = GroundProbe.report(_hf, road, [], Vector2(float(mid[0]), float(mid[1])), 9.0)
	assert_false(bool(row["ashore"]), "the middle of the river is not ashore")
	assert_false(bool(row["legal"]), "so nothing may be built there")
