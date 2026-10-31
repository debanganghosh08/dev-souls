extends "res://tests/test_case.gd"
## The naming layer (W19). The owner asked for every castle, village, river reach and quarter of the map to
## have a name so that we can both say "the Girdle" instead of trading coordinates. The risk with a names
## file is that it drifts: a name points at a site that was moved or deleted, and the map then labels bare
## ground. So this checks the names against the real site list, not only against themselves.

var _places: Dictionary = {}
var _ids: Dictionary = {}


func setup() -> void:
	_places = Places.load_file()
	for site: Dictionary in SiteRegistry.load_area("vale"):
		_ids[str(site.get("id", ""))] = true


func test_the_file_names_the_area_its_quarters_its_places_and_its_waters() -> void:
	assert_eq(str(_places["area"]), "The Ashen Vale", "the area has the name it has always had")
	assert_true((_places["regions"] as Array).size() >= 9, "nine quarters, so every bearing has a name")
	assert_true((_places["places"] as Array).size() >= 20, "at least twenty named places")
	assert_true((_places["waters"] as Array).size() >= 4, "the river is named in reaches, not as one thing")


func test_every_name_is_used_once() -> void:
	var seen: Dictionary = {}
	for key: String in ["regions", "places", "waters"]:
		for row: Variant in _places[key]:
			var name: String = str((row as Dictionary)["name"])
			assert_true(not seen.has(name), "'%s' is used once (second use in %s)" % [name, key])
			seen[name] = true


func test_every_named_place_that_claims_a_site_claims_a_site_that_exists() -> void:
	var claimed: int = 0
	for row: Variant in _places["places"]:
		var p: Dictionary = row
		var site: String = str(p.get("site", ""))
		if site == "":
			continue
		claimed += 1
		assert_true(_ids.has(site), "%s points at site '%s', which is on the map" % [p["name"], site])
	assert_true(claimed >= 18, "most named places are anchored to a real site (%d of them)" % claimed)


func test_every_quarter_names_a_compass_point_and_sits_where_that_point_is() -> void:
	for row: Variant in _places["regions"]:
		var r: Dictionary = row
		var point: String = str(r.get("compass", ""))
		if point == "the centre":
			continue
		assert_true(Places.COMPASS.has(point), "'%s' is one of the eight points" % point)
		var centre := Vector2(float((r["centre"] as Array)[0]), float((r["centre"] as Array)[1]))
		assert_eq(Places.compass_of(Places.bearing_of(centre)), point,
				"%s is actually %s of the middle" % [r["name"], point])


# North is -Z in this project. That was not decided here: north_watch has sat at z = -280 and south_ring at
# z = +350 for weeks, and the compass follows the data. If this ever flips, every site id lies.
func test_north_is_negative_z() -> void:
	assert_eq(Places.compass_of(Places.bearing_of(Vector2(0.0, -100.0))), "N", "-Z is north")
	assert_eq(Places.compass_of(Places.bearing_of(Vector2(100.0, 0.0))), "E", "+X is east")
	assert_eq(Places.compass_of(Places.bearing_of(Vector2(0.0, 100.0))), "S", "+Z is south")
	assert_eq(Places.compass_of(Places.bearing_of(Vector2(-100.0, 0.0))), "W", "-X is west")
	assert_eq(Places.compass_of(Places.bearing_of(Vector2(70.0, -70.0))), "NE", "and the diagonals follow")
	assert_eq(Places.compass_long(315.0), "north-west", "the long form reads as a sentence")


func test_the_quarter_a_point_falls_in() -> void:
	assert_eq(str(Places.region_at(_places, Vector2(0.0, 0.0))["name"]), "Mournhearth",
			"the spawn bowl is Mournhearth")
	assert_eq(str(Places.region_at(_places, Vector2(200.0, -160.0))["name"]), "Morrowfield",
			"the castle stands in Morrowfield")
	assert_eq(str(Places.region_at(_places, Vector2(-120.0, 250.0))["name"]), "Hollowmere Downs",
			"and Hollowmere in its own downs")
	# A point outside every circle still gets an answer: the Vale has no borders drawn on the ground, and a
	# map footer that goes blank at the rim is worse than one that names the nearest quarter.
	assert_true(not Places.region_at(_places, Vector2(600.0, 600.0)).is_empty(),
			"a point past the rim still gets the nearest quarter")


func test_the_nearest_named_place_and_the_line_that_describes_it() -> void:
	var at := Vector2(-208.0, -202.0)
	var near: Dictionary = Places.nearest_place(_places, at)
	assert_eq(str(near["name"]), "Thornhollow", "standing in the hidden village, that is the nearest place")
	assert_true(float(near["distance"]) < 1.0, "and it is under a metre away")
	assert_eq(Places.describe(_places, at), "Thornhollow", "close enough that no bearing is needed")
	# Far enough off that the bearing is the useful part of the answer.
	# 58 m north-east of the village, where nothing else named is nearer: the Edge Shrine is 100 m west of
	# here and Ashfarm 127 m south, so Thornhollow is what this point should be told about.
	var line: String = Places.describe(_places, Vector2(-158.0, -232.0))
	assert_true(line.contains("Thornhollow") and line.contains("south-west"),
			"from 58 m north-east of it: '%s'" % line)
	assert_eq(Places.describe(_places, Vector2(-158.0, -232.0), 10.0), "The Fallow Marches",
			"and with nothing named within reach, the quarter alone")


func test_a_missing_or_broken_file_names_nothing_rather_than_crashing() -> void:
	var gone: Dictionary = Places.load_file("res://data/places_does_not_exist.json")
	assert_eq((gone["places"] as Array).size(), 0, "a missing file names no places")
	assert_eq(str(gone["area"]), "", "and no area")
	var junk: Dictionary = Places.coerce({"places": [{"no_name": 1}, "not a row"]})
	assert_eq((junk["places"] as Array).size(), 0, "a row with no name is not a place")
	assert_true(Places.nearest_place(junk, Vector2.ZERO).is_empty(), "and nothing is near nothing")
