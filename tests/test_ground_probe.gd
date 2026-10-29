extends "res://tests/test_case.gd"
## The placement checker (W10). It exists so content work can be done without writing programs, which means
## its answers have to agree with tests/test_site_placement.gd -- the suite is what actually guards the map,
## and a tool that disagreed with it would send someone confidently to a spot that fails.

const AREA := "vale"

var _hf: Heightfield
var _road: PackedVector2Array
var _sites: Array[Dictionary] = []
var _ridge: float = INF


func setup() -> void:
	var area: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/areas/vale.json"))
	_hf = Heightfield.from_dict(area)
	_road = GroundProbe.road_of(area)
	_sites = SiteRegistry.load_area(AREA)
	_ridge = GroundProbe.ridge_limit(area)


func test_the_road_is_the_same_line_every_other_system_reads() -> void:
	assert_true(_road.size() >= 2, "the vale's road has segments (%d points)" % _road.size())
	var area: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/areas/vale.json"))
	var waypoints: Array = (area["valley"] as Dictionary)["waypoints"]
	assert_eq(_road.size(), waypoints.size(), "every valley waypoint is a road point")
	assert_true(GroundProbe.distance_to_path(_road[0], _road) < 0.001, "a point on the line is on the line")
	assert_true(GroundProbe.distance_to_path(_road[0] + Vector2(0.0, 500.0), _road) > 100.0,
			"and a point far off it is far off it")


func test_it_refuses_the_places_the_suite_refuses() -> void:
	# The pond: under water, which is the rule no building in this valley may break.
	var pond: Dictionary = GroundProbe.report(_hf, _road, _sites, Vector2.ZERO, GroundProbe.FOOTPRINT, _ridge)
	assert_false(bool(pond["dry"]), "the middle of the pond is not dry (lowest %.2f, water %.2f)"
			% [pond["lowest"], pond["water"]])
	assert_false(bool(pond["legal"]), "so nothing may be built there")
	# The old road itself.
	var on_road: Dictionary = GroundProbe.report(_hf, _road, _sites, _road[1], GroundProbe.FOOTPRINT, _ridge)
	assert_false(bool(on_road["off_road"]), "a waypoint is on the road (%.1f m from it)" % on_road["road_distance"])
	assert_false(bool(on_road["legal"]), "and nothing is built on the old road")
	# Outside the ridge.
	var far: Dictionary = GroundProbe.report(_hf, _road, _sites, Vector2(0.0, 480.0), GroundProbe.FOOTPRINT, _ridge)
	assert_false(bool(far["inside_ridge"]), "480 m out is past the ridge")
	# On top of something that is already there.
	var crowded: Dictionary = GroundProbe.report(_hf, _road, _sites, SiteRegistry.at_of(_sites[0]), GroundProbe.FOOTPRINT, _ridge)
	assert_false(bool(crowded["clear"]), "a site's own spot is not clear of that site")


func test_it_agrees_with_the_suite_about_every_site_already_built() -> void:
	# The strong claim: every building the owner already has stands on ground this tool calls dry, flat
	# enough and inside the ridge. If the tool were stricter than the map, it would be useless for adding
	# to the map. (Road and crowding are left out here: a site is never clear of itself, and the fixed
	# sites -- the castle, the village, the pond chamber -- are bigger than one footprint.)
	var checked: int = 0
	for site: Dictionary in _sites:
		if bool(site.get("fixed", false)):
			continue
		var at: Vector2 = SiteRegistry.at_of(site)
		var row: Dictionary = GroundProbe.report(_hf, _road, _sites, at, 7.0, _ridge)
		checked += 1
		assert_true(bool(row["dry"]), "%s stands on dry ground (lowest %.2f, water %.2f)"
				% [site["id"], row["lowest"], row["water"]])
		assert_true(bool(row["inside_ridge"]), "%s is inside the ridge" % site["id"])
	assert_true(checked > 60, "every placed site was checked (%d)" % checked)


func test_find_turns_a_rough_wish_into_a_legal_spot() -> void:
	# "Put something about here" is how content work actually arrives, and here is usually in the pond.
	var want := Vector2(30.0, 30.0)
	assert_false(bool(GroundProbe.report(_hf, _road, _sites, want, GroundProbe.FOOTPRINT, _ridge)["legal"]), "the wished-for spot is not legal")
	var spot: Vector2 = GroundProbe.find(_hf, _road, _sites, want, 9.0, 120.0, 12, _ridge)
	assert_true(spot != Vector2.INF, "a legal spot was found near it")
	if spot == Vector2.INF:
		return
	var row: Dictionary = GroundProbe.report(_hf, _road, _sites, spot, GroundProbe.FOOTPRINT, _ridge)
	assert_true(bool(row["legal"]), "and what it returned is legal: %s" % GroundProbe.line(row))
	assert_true(bool(row["dry"]) and bool(row["flat"]) and bool(row["off_road"]) and bool(row["clear"]),
			"every rule holds at the spot it chose")
	print("PROBE find wanted=(30, 30) got=(%.1f, %.1f) moved=%.1f m" % [spot.x, spot.y, spot.distance_to(want)])


func test_a_report_reads_as_a_line_somebody_can_act_on() -> void:
	var row: Dictionary = GroundProbe.report(_hf, _road, _sites, Vector2.ZERO, GroundProbe.FOOTPRINT, _ridge)
	var text: String = GroundProbe.line(row)
	assert_true("ILLEGAL" in text, "an illegal spot says so")
	assert_true("NOT_DRY" in text, "and says which rule it broke: %s" % text)
