extends "res://tests/test_case.gd"
## The hidden wood (W19). The owner asked for a forest of thousands with a ring of rock inside it and a
## village inside the ring, hidden well enough that you find it by walking into it. Four things have to be
## true for that to work, and none of them is visible in a screenshot of the clearing:
##
##   1. the wood is actually thousands of trees, not a hundred spread thin;
##   2. it leaves a clearing, or there is nowhere to put the village;
##   3. the ring is broken in exactly one place, or there is no way in;
##   4. the trees in it are solid, because a wall of wood you can walk through hides nothing.
##
## The fourth is the one that would have shipped broken: colliders went to the trees nearest the origin,
## and this wood is 305 m from the origin.

const MIX := {"fir": 3.0, "pine": 2.0, "dead": 5.0}
const CENTRE := Vector2(-208.0, -202.0)

var _sites: Array[Dictionary] = []
var _grove: Dictionary = {}


func setup() -> void:
	_sites = SiteRegistry.load_area("vale")
	_grove = Forest.plan_grove(CENTRE, 95.0, 36.0, 5200, 104729, MIX)


func test_the_wood_is_thousands_of_trees() -> void:
	var trees: PackedVector3Array = _grove["positions"]
	# Candidates land on top of each other and are dropped, so 2,400 asked for is fewer placed. "Thousands"
	# is the claim the owner made and the number that has to survive the spacing rule.
	# 5,200 asked for and about 2,340 planted: by the end the rim is full and the spacing rule refuses the
	# rest. Asking for what we want to plant would plant half of it.
	assert_true(trees.size() > 2000, "a wood of thousands (%d trees placed of 5,200 asked)" % trees.size())
	assert_eq((_grove["archetypes"] as PackedStringArray).size(), trees.size(), "every tree has a kind")
	assert_eq((_grove["yaws"] as PackedFloat32Array).size(), trees.size(), "and a facing")
	assert_eq((_grove["scales"] as PackedFloat32Array).size(), trees.size(), "and a size")
	var kinds: Dictionary = {}
	for k: String in _grove["archetypes"] as PackedStringArray:
		kinds[k] = true
	assert_true(kinds.size() >= 2, "and the wood is mixed, not one tree repeated")


func test_it_leaves_a_clearing_and_fills_the_edge() -> void:
	var trees: PackedVector3Array = _grove["positions"]
	var inside: int = 0
	var outer_half: int = 0
	for t: Vector3 in trees:
		var d: float = Vector2(t.x, t.z).distance_to(CENTRE)
		if d < 35.0:
			inside += 1
		if d > 72.0:
			outer_half += 1
		assert_true(d <= 95.1, "no tree is outside the wood (%.1f m)" % d)
	assert_eq(inside, 0, "the clearing is clear, so the village has somewhere to stand")
	# Density rises outward on purpose: that is what makes it a wall from outside and a room from within.
	# Half the wood's area lies beyond 72 m, so an even scatter would put half the trees there and no more.
	assert_true(outer_half > trees.size() * 0.55,
			"the wood crowds its outer edge (%d of %d trees past 72 m)" % [outer_half, trees.size()])


func test_an_unasked_for_grove_plants_nothing() -> void:
	assert_eq((Forest.plan_grove(CENTRE, 0.0, 36.0, 5200, 1, MIX)["positions"] as PackedVector3Array).size(), 0,
			"no radius, no wood")
	assert_eq((Forest.plan_grove(CENTRE, 95.0, 36.0, 0, 1, MIX)["positions"] as PackedVector3Array).size(), 0,
			"and no count, no wood")
	assert_eq((Forest.plan_grove(CENTRE, 95.0, 36.0, 50, 1, {})["positions"] as PackedVector3Array).size(), 0,
			"and nothing to plant, nothing planted")


func test_the_colliders_follow_the_anchors_rather_than_the_origin() -> void:
	var here := Vector3(2.0, 0.0, 3.0)
	var far := Vector3(CENTRE.x, 0.0, CENTRE.y)
	var none := PackedVector2Array()
	assert_true(Forest.anchor_distance(here, none) < Forest.anchor_distance(far, none),
			"with no anchors, the origin decides and the far tree loses")
	var anchored := PackedVector2Array([CENTRE])
	assert_true(Forest.anchor_distance(far, anchored) < Forest.anchor_distance(here, anchored),
			"with the wood anchored, the tree in the wood wins instead")
	assert_true(is_equal_approx(Forest.anchor_distance(far, anchored), 0.0), "a tree on the anchor is at zero")
	# The origin stays an anchor whatever else is listed, so the trees round the spawn never go soft.
	assert_true(Forest.anchor_distance(here, anchored) < 4.0, "and the spawn is still an anchor")
	var scene: String = FileAccess.get_file_as_string("res://scenes/levels/vale.tscn")
	assert_true(scene.contains("collider_anchors = PackedVector2Array(-208, -202)"),
			"the level anchors colliders in the wood")
	assert_true(scene.contains("collider_count = 220"), "and pays for enough of them to be felt")


# The wall is ONE layout rather than a ring of rock sites, because the suite makes every pair of sites keep
# 1.5 m between their real footprints and a crag's footprint is 13 m wide: a ring tight enough to read as a
# wall is a ring of sites that overlap. So the ring is checked piece by piece inside its layout.
func test_the_ring_of_stone_has_exactly_one_way_in() -> void:
	var layout: Dictionary = JSON.parse_string(
			FileAccess.get_file_as_string("res://data/structures/rocks/girdle.json"))
	var bearings: Array[float] = []
	var fires: int = 0
	for row: Variant in layout["pieces"]:
		var piece: Dictionary = row
		var at: Array = piece["at"]
		var flat := Vector2(float(at[0]), float(at[2]))
		if str(piece["kind"]) == "brazier":
			fires += 1
			continue
		assert_true(["crag", "boulders", "standing_stones"].has(str(piece["kind"])),
				"the wall is built of rock (%s)" % piece["kind"])
		assert_true(absf(flat.length() - 28.0) <= 2.3,
				"%s stands on the ring (%.1f m out)" % [piece["name"], flat.length()])
		bearings.append(Places.bearing_of(flat))
	assert_true(bearings.size() >= 20, "the wall is twenty-odd groups of rock (%d)" % bearings.size())
	assert_eq(fires, 2, "with a fire either side of the gap, to see who comes through")
	bearings.sort()
	var gaps: int = 0
	var widest: float = 0.0
	for i: int in bearings.size():
		var step: float = fposmod(bearings[(i + 1) % bearings.size()] - bearings[i], 360.0)
		widest = maxf(widest, step)
		if step > 30.0:
			gaps += 1
	assert_eq(gaps, 1, "one gap, so one way in")
	assert_true(widest > 60.0 and widest < 110.0, "wide enough to walk through (%.0f degrees)" % widest)
	# A single site, so the clearing inside it stays free for the village.
	var ids: Dictionary = {}
	for site: Dictionary in _sites:
		ids[str(site["id"])] = true
	assert_true(ids.has("girdle"), "and the whole wall is one site on the map")


func test_the_village_stands_on_the_flat_ground_made_for_it() -> void:
	var area: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/areas/vale.json"))
	var plateau: Dictionary = {}
	for row: Variant in area["plateaus"]:
		if str((row as Dictionary)["name"]) == "fellwood":
			plateau = row
	assert_true(not plateau.is_empty(), "the hidden wood has a plateau under it")
	var hf: Heightfield = Heightfield.from_dict(area)
	var houses: int = 0
	for site: Dictionary in _sites:
		if not str(site["id"]).begins_with("thornhollow_"):
			continue
		houses += 1
		var at := Vector2(float((site["at"] as Array)[0]), float((site["at"] as Array)[1]))
		assert_true(at.distance_to(CENTRE) < 15.0, "%s is inside the ring" % site["id"])
		# Flat is the whole reason the plateau is there: the south-east of the Vale drops 4 to 6 m across
		# any footprint, and that is what made this ground unbuildable before.
		var low: float = INF
		var high: float = -INF
		for dx: float in [-4.0, 0.0, 4.0]:
			for dz: float in [-4.0, 0.0, 4.0]:
				var h: float = hf.height_at(at.x + dx, at.y + dz)
				low = minf(low, h)
				high = maxf(high, h)
		assert_true(high - low < 1.0, "%s stands on flat ground (%.2f m of drop)" % [site["id"], high - low])
	# Seven, not eleven: the clearing inside the wall is 56 m across and a cottage's footprint is 12 m of
	# it, so seven is what fits. Saying so is better than claiming a town.
	assert_true(houses >= 7, "seven buildings in the clearing (%d)" % houses)


func test_the_two_set_pieces_are_where_they_were_put() -> void:
	var by_id: Dictionary = {}
	for site: Dictionary in _sites:
		by_id[str(site["id"])] = site
	assert_true(by_id.has("wyrms_rest"), "the dead dragon is placed")
	assert_true(by_id.has("sunken_wheel"), "and the fallen hoop of stone")
	var dragon: Dictionary = JSON.parse_string(
			FileAccess.get_file_as_string("res://data/structures/rocks/dead_dragon.json"))
	var kinds: Dictionary = {}
	for piece: Variant in dragon["pieces"]:
		kinds[str((piece as Dictionary)["kind"])] = true
	assert_true(kinds.has("fence"), "the owner asked for it fenced off, and it is")
	assert_true(kinds.has("hearth_remains") or kinds.has("brazier"), "with a fire at the fence")
	var ring: Dictionary = JSON.parse_string(
			FileAccess.get_file_as_string("res://data/structures/rocks/fallen_ring.json"))
	var high: int = 0
	for piece: Variant in ring["pieces"]:
		var p: Dictionary = piece
		if p.has("at") and float((p["at"] as Array)[1]) > 2.0:
			high += 1
	assert_true(high >= 4, "the hoop stands up out of the ground rather than lying flat (%d pieces high)" % high)
