extends "res://tests/test_case.gd"
## W10: the three things that made Hollowmere a place rather than a model of one -- a fire you rest at that
## moves the day, a forest band with a road through it, and villagers whose line of dialogue is data on a
## child node. Each is small; each would be silently wrong in a way nobody would notice for weeks.

const VILLAGE := "res://data/sites/vale_village.json"
const STOPS: Array[float] = [6.0, 12.0, 18.0, 0.0]

var _nodes: Array[Node] = []


func teardown() -> void:
	for node: Node in _nodes:
		node.free()
	_nodes.clear()


# --- resting ----------------------------------------------------------------------------------------------

func test_resting_always_moves_the_clock_forward_to_the_next_stop() -> void:
	# Plain cases: from each stop you land on the next one.
	assert_true(is_equal_approx(RestFire.next_stop(6.0, STOPS), 6.0), "dawn rests to noon")
	assert_true(is_equal_approx(RestFire.next_stop(12.0, STOPS), 6.0), "noon rests to dusk")
	assert_true(is_equal_approx(RestFire.next_stop(18.0, STOPS), 6.0), "dusk rests to midnight")
	# The wrap, which is where this kind of arithmetic is always wrong.
	assert_true(is_equal_approx(RestFire.next_stop(0.0, STOPS), 6.0), "midnight rests to dawn, not backwards")
	# Exactly min_jump away still counts: at 23:30 the next stop really is midnight, half an hour off.
	assert_true(is_equal_approx(RestFire.next_stop(23.5, STOPS), 0.5), "23:30 rests the half hour to midnight")
	assert_true(is_equal_approx(RestFire.next_stop(23.8, STOPS), 6.2), "but 23:48 is too close to it, so it waits for dawn")
	assert_true(is_equal_approx(RestFire.next_stop(5.9, STOPS), 6.1), "just before dawn skips it and goes to noon")
	# Never zero, never negative: resting that did nothing would read as a broken fire.
	for hour: float in [0.0, 3.3, 5.99, 6.0, 11.9, 17.5, 22.2]:
		var jump: float = RestFire.next_stop(hour, STOPS)
		assert_true(jump > 0.0 and jump <= 24.0, "resting at %.2f moves somewhere (%.2f h)" % [hour, jump])
	assert_true(is_equal_approx(RestFire.next_stop(9.0, []), 24.0), "a fire with no stops rests a whole day")


func test_a_rest_fire_advances_the_real_clock() -> void:
	var fire := RestFire.new()
	_nodes.append(fire)
	var game := _FakeGame.new()
	_nodes.append(game)
	game.time_of_day = 20.0
	fire._inject_game(game)
	fire.stops = STOPS
	assert_true(is_equal_approx(fire.hours_until_next(), 4.0), "20:00 is four hours short of midnight")
	fire._on_interact(null)
	assert_true(is_equal_approx(game.advanced, 4.0), "and resting asked the clock for exactly that")


# --- the forest band --------------------------------------------------------------------------------------

func test_the_band_crowds_both_sides_of_the_road_and_leaves_it_walkable() -> void:
	var line := PackedVector2Array([Vector2(0.0, 0.0), Vector2(100.0, 0.0)])
	var mix: Dictionary = {"fir": 3.0, "pine": 1.0}
	var band: Dictionary = Forest.plan_band(line, 8.0, 30.0, 200, 11, mix)
	var trees: PackedVector3Array = band["positions"]
	assert_true(trees.size() > 120, "the band is dense (%d trees of 200 asked)" % trees.size())
	var left: int = 0
	var right: int = 0
	for t: Vector3 in trees:
		var off: float = absf(t.z)
		assert_true(off >= 8.0 - 0.01, "no tree stands in the road (%.2f m off the line)" % off)
		assert_true(off <= 30.0 + 0.01, "and none strays past the band (%.2f m)" % off)
		assert_true(t.x >= -1.0 and t.x <= 101.0, "the band follows the line, not the compass")
		if t.z < 0.0:
			left += 1
		else:
			right += 1
	assert_true(left > 20 and right > 20, "trees on BOTH sides (%d / %d)" % [left, right])
	assert_eq((band["archetypes"] as PackedStringArray).size(), trees.size(), "every tree has an archetype")
	assert_eq((band["scales"] as PackedFloat32Array).size(), trees.size(), "every tree has a size")
	# The negative control for the whole feature: no points, no band, and the forest is what it always was.
	assert_true((Forest.plan_band(PackedVector2Array(), 8.0, 30.0, 200, 11, mix)["positions"] as PackedVector3Array).is_empty(),
			"a forest with no band keeps none")
	assert_true((Forest.plan_band(line, 8.0, 30.0, 0, 11, mix)["positions"] as PackedVector3Array).is_empty(),
			"and nor does one that asked for no trees")


func test_the_landmark_tree_is_the_biggest_thing_in_the_wood() -> void:
	var line := PackedVector2Array([Vector2(0.0, 0.0), Vector2(100.0, 0.0)])
	var mix: Dictionary = {"fir": 1.0}
	var band: Dictionary = Forest.plan_band(line, 8.0, 30.0, 80, 5, mix, 0.5, 3.4)
	var scales: PackedFloat32Array = band["scales"]
	var biggest: float = 0.0
	for s: float in scales:
		biggest = maxf(biggest, s)
	assert_true(is_equal_approx(biggest, 3.4), "the landmark stands at the scale it was given (%.2f)" % biggest)
	var ordinary: int = 0
	for s: float in scales:
		if s < 2.0:
			ordinary += 1
	assert_eq(ordinary, scales.size() - 1, "exactly one tree is the landmark; the rest are trees")
	var plain: Dictionary = Forest.plan_band(line, 8.0, 30.0, 80, 5, mix, 0.5, 0.0)
	assert_eq((plain["positions"] as PackedVector3Array).size(), (band["positions"] as PackedVector3Array).size() - 1,
			"scale 0 leaves the landmark out entirely")


func test_a_point_on_the_line_is_measured_by_distance_not_by_corner() -> void:
	# Two segments, one 10 m and one 90 m: halfway along is deep in the second, not at the join.
	var bent := PackedVector2Array([Vector2(0.0, 0.0), Vector2(10.0, 0.0), Vector2(100.0, 0.0)])
	assert_true(Forest.point_on(bent, 0.5).x > 40.0, "halfway by length, not halfway by segment (%.1f)"
			% Forest.point_on(bent, 0.5).x)
	assert_true(Forest.point_on(bent, 0.0).is_equal_approx(Vector2.ZERO), "t=0 is the start")
	assert_true(Forest.point_on(bent, 1.0).is_equal_approx(Vector2(100.0, 0.0)), "t=1 is the end")


func test_the_vale_actually_carries_a_forest_band() -> void:
	# A .tscn drops a property whose name does not match an export, silently. Without this, the band could
	# work perfectly in plan_band and never appear in the game, and nothing would say so.
	var scene: String = FileAccess.get_file_as_string("res://scenes/levels/vale.tscn")
	assert_true("band_points = PackedVector2Array(" in scene, "the Vale's forest is given a band to plant")
	assert_true("band_count = " in scene and not "band_count = 0" in scene, "and trees to plant in it")
	assert_true("landmark_scale = " in scene and not "landmark_scale = 0.0" in scene,
			"and the one big tree the owner asked for")
	for name: String in ["band_points", "band_gap", "band_half", "band_count", "landmark_at", "landmark_scale"]:
		assert_true(("@export var %s" % name) in FileAccess.get_file_as_string("res://scripts/systems/forest.gd")
				or ("@export_range(0.0, 1.0) var %s" % name) in FileAccess.get_file_as_string("res://scripts/systems/forest.gd"),
				"%s is a real export, so the scene value is not thrown away" % name)


# --- the people -------------------------------------------------------------------------------------------

func test_a_prop_can_set_a_property_on_a_child_so_a_villager_carries_its_own_line() -> void:
	var root := Node3D.new()
	_nodes.append(root)
	var talk := LoreStone.new()
	talk.name = "Talk"
	root.add_child(talk)
	Settlements.set_coerced(root, "Talk/lore_key", "villager_smith")
	assert_eq(talk.lore_key, "villager_smith", "the child took the line")
	# Unchanged for everything that is not a path, which is every prop placed before today.
	Settlements.set_coerced(talk, "lore_key", "villager_miller")
	assert_eq(talk.lore_key, "villager_miller", "a plain key still sets the node itself")


func test_the_village_is_peopled_and_every_line_they_speak_exists() -> void:
	var sites: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(VILLAGE))
	var lore: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/lore.json"))
	var villagers: int = 0
	var animals: int = 0
	var fires: int = 0
	var ids: Dictionary = {}
	for raw: Variant in sites.get("sites", []):
		var site: Dictionary = raw
		for entry: Variant in site.get("props", []):
			var prop: Dictionary = entry
			var scene: String = str(prop.get("scene", ""))
			assert_true(ResourceLoader.exists(scene), "%s exists" % scene)
			var values: Dictionary = prop.get("set", {})
			for key: Variant in values:
				if str(key).ends_with("id"):
					var id: String = str(values[key])
					assert_false(ids.has(id), "prop id '%s' is used once" % id)
					ids[id] = true
				if str(key).ends_with("lore_key"):
					assert_true(lore.has(str(values[key])), "%s is a line that exists" % str(values[key]))
			if scene.contains("villager"):
				villagers += 1
				assert_true(values.has("Talk/lore_key"), "a villager has something to say")
			elif scene.contains("creatures/"):
				animals += 1
			elif scene.contains("rest_fire"):
				fires += 1
	print("W10 village: %d villagers, %d animals, %d rest fires" % [villagers, animals, fires])
	assert_true(villagers >= 6, "people live here (%d)" % villagers)
	assert_true(animals >= 4, "and animals (%d)" % animals)
	assert_true(fires >= 2, "and somewhere to rest (%d)" % fires)


class _FakeGame:
	extends Node
	var time_of_day: float = 8.0
	var advanced: float = 0.0

	func advance_time(hours: float) -> void:
		advanced = hours
		time_of_day = fposmod(time_of_day + hours, 24.0)


# --- water (W14-W15) ---------------------------------------------------------------------------------------

func test_the_vale_holds_water_and_the_pond_can_be_emptied() -> void:
	var area: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/areas/vale.json"))
	var waters: Array = area.get("waters", [])
	# The Mirror Pond is a plane the level places on the basin (vale.gd._place_water), because it was
	# there before this system was; `waters` is the rivers.
	assert_true(waters.size() >= 1, "the vale has a river (%d entries)" % waters.size())
	var river: Dictionary = {}
	for raw: Variant in waters:
		if str((raw as Dictionary).get("name", "")) == "river":
			river = raw
	assert_false(river.is_empty(), "the river runs")
	assert_eq(str(river.get("drains_with", "")), "", "and it is not going anywhere")
	# A channel is carved for the river, and it is gentle enough that the banks are not cliffs.
	var channel: Dictionary = {}
	for raw: Variant in area.get("crests", []):
		if str((raw as Dictionary).get("name", "")) == "river_channel":
			channel = raw
	assert_false(channel.is_empty(), "the river runs in a channel, not across the grass")
	assert_true(float(channel.get("height", 0.0)) < 0.0, "a channel is carved, so its height is negative")
	var slope: float = absf(float(channel["height"])) / maxf(1.0, float(channel.get("blend", 1.0)))
	assert_true(slope < 0.25, "its banks are walkable rather than a gorge (%.2f m per m)" % slope)


func test_water_builds_a_surface_and_something_to_drown_in() -> void:
	var water := Water.new()
	_nodes.append(water)
	water.rebuild([
		{"name": "test_river", "points": [[0, 0], [40, 0], [80, 20]], "level": -1.0, "half_width": 6.0, "depth": 5.0},
		{"name": "test_pool", "points": [[200, 200]], "radius": 30.0, "level": -2.0, "depth": 6.0,
			"drains_with": "test_flag"},
	])
	var stats: Dictionary = water.stats()
	assert_eq(int(stats["surfaces"]), 2, "a surface for each")
	assert_eq(int(stats["volumes"]), 2, "and a volume under each")
	var ribbon: ArrayMesh = Water.ribbon(Water.walk(PackedVector2Array([Vector2.ZERO, Vector2(40, 0)]), 6.0), 6.0, -1.0)
	var verts: PackedVector3Array = ribbon.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	assert_true(verts.size() >= 8, "the ribbon follows its line (%d vertices)" % verts.size())
	for v: Vector3 in verts:
		assert_true(is_equal_approx(v.y, -1.0), "water is level")
		assert_true(absf(v.z) <= 6.01, "and no wider than it was asked to be")
	var pool: ArrayMesh = Water.disc(Vector2(200, 200), 30.0, -2.0)
	var pond_verts: PackedVector3Array = pool.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	assert_true(pond_verts.size() > 40, "the pool is round, not a square")
	for v: Vector3 in pond_verts:
		assert_true(Vector2(v.x - 200.0, v.z - 200.0).length() <= 30.01, "and stays inside its radius")
	# Draining takes the water away and the drowning with it; everything else stays.
	assert_eq(water.drain(&"test_flag"), 2, "the pool's surface and its volume both went")
	assert_eq(water.drain(&"nothing_named_this"), 0, "and nothing else did")
