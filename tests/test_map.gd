extends "res://tests/test_case.gd"
## The map (W19). The owner asked for a small map in the corner, M for the whole thing, the eight bearings
## marked, and -- the part worth testing -- for it to show the world "exactly", so that anything added to
## the Vale appears on it without being listed twice. That is the claim here: the map's content comes from
## the same files the world is built from, and the arithmetic puts north up.

const RECT := Rect2(Vector2(0.0, 0.0), Vector2(400.0, 400.0))

var _world: Dictionary = {}


func setup() -> void:
	_world = MapPanel.gather("vale")


func test_the_map_is_drawn_from_the_world_and_not_from_a_list_of_its_own() -> void:
	var sites: Array = _world["sites"]
	assert_eq(sites.size(), SiteRegistry.load_area("vale").size(),
			"every site on the map is a site in the level (%d)" % sites.size())
	assert_true((_world["area"] as Dictionary).has("ridge"), "the ridge comes from the area file")
	assert_true((_world["area"] as Dictionary).has("crests"), "and so does the river bed")
	assert_true(not (_world["places"] as Dictionary).is_empty(), "and the names from data/places.json")
	# The three places built this week are on the map because they are sites, not because anyone added them
	# to the map. This is the whole point of reading the registry.
	var ids: Dictionary = {}
	for site: Dictionary in sites:
		ids[str(site["id"])] = true
	for id: String in ["thornhollow_pyre", "wyrms_rest", "sunken_wheel", "girdle"]:
		assert_true(ids.has(id), "%s is on the map without the map being told about it" % id)


func test_north_is_up_and_east_is_right() -> void:
	var mid: Vector2 = RECT.position + RECT.size * 0.5
	var north: Vector2 = MapDraw.to_panel(Vector2(0.0, -100.0), Vector2.ZERO, 400.0, RECT)
	var east: Vector2 = MapDraw.to_panel(Vector2(100.0, 0.0), Vector2.ZERO, 400.0, RECT)
	assert_true(north.y < mid.y, "a point north of the middle is drawn above it")
	assert_true(is_equal_approx(north.x, mid.x), "and directly above it")
	assert_true(east.x > mid.x, "a point east of the middle is drawn to the right")
	assert_true(is_equal_approx(east.y, mid.y), "and level with it")


func test_the_scale_is_the_span_asked_for_and_reverses_exactly() -> void:
	# A 400 px box showing 400 m is one pixel per metre, whatever the centre.
	assert_true(is_equal_approx(MapDraw.scale_for(400.0, RECT), 1.0), "400 m across 400 px is 1 px/m")
	assert_true(is_equal_approx(MapDraw.scale_for(800.0, RECT), 0.5), "and 800 m is half that")
	var world := Vector2(-137.0, 268.0)
	var there: Vector2 = MapDraw.to_panel(world, Vector2(40.0, -20.0), 1100.0, RECT)
	var back: Vector2 = MapDraw.to_world(there, Vector2(40.0, -20.0), 1100.0, RECT)
	assert_true(back.distance_to(world) < 0.01, "panel -> world -> panel comes back to the same metre")


func test_eight_bearings_are_marked_with_north_at_the_top() -> void:
	var marks: Array[Dictionary] = MapDraw.compass_marks(RECT, 10.0)
	assert_eq(marks.size(), 8, "all eight points the owner asked for")
	var mid: Vector2 = RECT.position + RECT.size * 0.5
	var by_name: Dictionary = {}
	for m: Dictionary in marks:
		by_name[str(m["text"])] = m["at"] as Vector2
	assert_true((by_name["N"] as Vector2).y < mid.y, "N is above the middle")
	assert_true((by_name["S"] as Vector2).y > mid.y, "S below it")
	assert_true((by_name["E"] as Vector2).x > mid.x, "E to the right")
	assert_true((by_name["W"] as Vector2).x < mid.x, "W to the left")
	# The diagonals go into the corners, where there is room for them, rather than onto a circle inside.
	var ne: Vector2 = by_name["NE"]
	assert_true(ne.x > mid.x and ne.y < mid.y, "NE in the top-right corner")
	for m: Dictionary in marks:
		assert_true(RECT.grow(1.0).has_point(m["at"] as Vector2), "%s is inside the box" % m["text"])


func test_a_site_is_coloured_by_what_it_is_and_what_it_is_comes_from_its_layout() -> void:
	assert_eq(MapDraw.kind_of_site({"layout": "res://data/structures/village/mill.json"}), "village",
			"anything in the village folder is a village dot")
	assert_eq(MapDraw.kind_of_site({"layout": "res://data/structures/houses/cottage_intact.json"}), "house", "a house is a house")
	assert_eq(MapDraw.kind_of_site({"layout": "res://data/structures/rocks/crag.json"}), "rock", "and a crag is rock")
	# The file name wins where it says more than the folder does: these all live under rocks/.
	assert_eq(MapDraw.kind_of_site({"layout": "res://data/structures/rocks/dead_dragon.json"}), "ruin",
			"the dead dragon is a ruin, not a rock")
	assert_eq(MapDraw.kind_of_site({"layout": "res://data/structures/rocks/graveyard.json"}), "graves", "a graveyard is graves")
	assert_eq(MapDraw.kind_of_site({"layout": "res://data/structures/rocks/hanging_bridge.json"}), "crossing", "a bridge is a crossing")
	assert_eq(MapDraw.kind_of_site({"layout": "res://data/structures/towers/watchtower.json"}), "tower", "and a watchtower is a tower")
	assert_eq(MapDraw.kind_of_site({"layout": ""}), "prop", "and something unrecognised is still drawn")
	assert_true(MapDraw.colour_of("castle") != MapDraw.colour_of("water"), "kinds read apart by colour")
	assert_eq(MapDraw.colour_of("no_such_kind"), MapDraw.UNKNOWN_COLOUR, "an unknown kind has a colour too")


func test_only_what_is_in_view_is_drawn() -> void:
	# The corner map shows 320 m. Standing at the spawn, the castle 256 m away is off it; the pond is not.
	assert_true(MapDraw.in_view(Vector2(0.0, 0.0), Vector2.ZERO, MapDraw.MINI_SPAN, RECT),
			"the ground underfoot is in view")
	assert_true(not MapDraw.in_view(Vector2(0.0, -900.0), Vector2.ZERO, MapDraw.MINI_SPAN, RECT),
			"and the far rim is not")


func test_circle_points_close_the_ring() -> void:
	var ring: PackedVector2Array = MapDraw.circle_points(Vector2(10.0, -4.0), 25.0, 24)
	assert_eq(ring.size(), 25, "24 sides and a closing point")
	assert_true(ring[0].distance_to(ring[ring.size() - 1]) < 0.001, "the last point is the first")
	for p: Vector2 in ring:
		assert_true(absf(p.distance_to(Vector2(10.0, -4.0)) - 25.0) < 0.001, "every point is on the circle")


func test_the_map_knows_where_the_hidden_wood_is_because_the_forest_told_it() -> void:
	var scene: String = FileAccess.get_file_as_string("res://scenes/levels/vale.tscn")
	assert_true(scene.contains("grove_radius = 95.0"), "the level plants a 95 m wood")
	assert_true(scene.contains("grove_centre = Vector2(-208, -202)"), "round the hidden village")
	# The panel reads those two exports off the live Forest rather than repeating them, which is what keeps
	# the wood on the map if it is ever moved.
	var source: String = FileAccess.get_file_as_string("res://scripts/ui/map_panel.gd")
	assert_true(source.contains('forest.get("grove_centre")') and source.contains('forest.get("grove_radius")'),
			"and the map asks the Forest where it is, instead of being told twice")


func test_m_opens_it() -> void:
	assert_true(InputMap.has_action(&"map"), "there is a map action")
	var keys: Array[InputEvent] = InputMap.action_get_events(&"map")
	assert_true(keys.size() >= 1, "with a key on it")
	assert_eq((keys[0] as InputEventKey).physical_keycode, KEY_M, "and the key is M")
