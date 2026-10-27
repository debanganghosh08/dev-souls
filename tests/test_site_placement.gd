extends "res://tests/test_case.gd"
## Rules every built site in the Vale must obey, whoever placed it. Houses (W8-H) and points of interest
## (W8-P) are added by two people at once into two files, so the rules live here, apply to both, and are the
## only thing either side has to satisfy about the other. With no sites they pass vacuously; each one added
## must keep them passing. Every test also asserts something about the fixed sites or its own inputs, so none
## is vacuous while the map is still empty (the runner fails a test that reaches no assertion).

const AREA := "vale"
## A site's foundation reaches about 2 m down (docs/WORLD_PLAN.md), so the ground under one may not fall more
## than this from its highest point to its lowest.
const MAX_GROUND_DROP := 1.6
const RIDGE_CLEARANCE := 25.0
## The old road is the valley channel's waypoints; nothing is built within this of its centre line.
const ROAD_HALF_WIDTH := 3.0
## Clear ground kept between any two sites, so two buildings never share a wall by accident.
const SITE_CLEARANCE := 1.5
const SPAWN_CLEARANCE := 10.0
## A prop placed further than this outside its site's footprint is almost certainly a typo in `at`.
const PROP_REACH := 4.0

var _hf: Heightfield
var _area: Dictionary = {}
var _sites: Array[Dictionary] = []


func setup() -> void:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/areas/vale.json"))
	_area = data as Dictionary
	_hf = Heightfield.from_dict(_area)
	_sites = SiteRegistry.load_area(AREA)


func _built() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for site: Dictionary in _sites:
		if not bool(site.get("fixed", false)):
			out.append(site)
	return out


func _road() -> PackedVector2Array:
	var out := PackedVector2Array()
	for p: Variant in (_area.get("valley", {}) as Dictionary).get("waypoints", []):
		out.append(Vector2(float(p[0]), float(p[1])))
	return out


func _corners(obb: Dictionary) -> Array[Vector2]:
	var out: Array[Vector2] = [obb["centre"]]
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			out.append(Vector2(obb["centre"]) + Vector2(obb["ux"]) * float(obb["hx"]) * sx
					+ Vector2(obb["uz"]) * float(obb["hz"]) * sz)
	return out


func test_every_site_stands_on_dry_ground_inside_the_ridge() -> void:
	assert_true(_sites.size() >= 3, "the registry loads (%d sites)" % _sites.size())
	for site: Dictionary in _built():
		var span: Vector2 = Settlements.ground_span(site, _hf)
		assert_true(span.x > _hf.water_level() + 0.5, "%s is out of the water (lowest %.2f)" % [site["id"], span.x])
		var at: Vector2 = SiteRegistry.at_of(site)
		assert_true(at.length() < _hf.ridge_inner_radius() - RIDGE_CLEARANCE, "%s is inside the ridge" % site["id"])


func test_every_site_stands_on_ground_its_foundation_can_cover() -> void:
	# The fixed sites stand on plateaus the terrain flattens for them; if that ever stops being true this
	# rule is measuring the wrong thing.
	for site: Dictionary in _sites:
		if bool(site.get("fixed", false)) and str(site["id"]) != "hearth_chamber":
			var flat: Vector2 = Settlements.ground_span({"layout": "res://tests/fixtures/slab_4x6.json",
					"at": site["at"]}, _hf)
			assert_true(flat.y - flat.x < 0.1, "%s's plateau is flat at its centre" % site["id"])
	for site: Dictionary in _built():
		var span: Vector2 = Settlements.ground_span(site, _hf)
		assert_true(span.y - span.x <= MAX_GROUND_DROP,
				"%s: ground falls %.2f m under it (limit %.1f)" % [site["id"], span.y - span.x, MAX_GROUND_DROP])


func test_nothing_is_built_on_the_old_road() -> void:
	var road: PackedVector2Array = _road()
	assert_true(road.size() >= 2, "the vale defines the old road")
	for site: Dictionary in _built():
		for obb: Dictionary in SiteRegistry.world_obbs(site):
			for p: Vector2 in _corners(obb):
				var d: float = INF
				for i: int in range(road.size() - 1):
					d = minf(d, p.distance_to(Geometry2D.get_closest_point_to_segment(p, road[i], road[i + 1])))
				assert_true(d >= ROAD_HALF_WIDTH, "%s is off the road (%.1f m from it)" % [site["id"], d])


func test_no_two_sites_overlap_or_crowd_each_other() -> void:
	var masks: Array[KeepOutMask] = []
	for site: Dictionary in _sites:
		var mask := KeepOutMask.new()
		for obb: Dictionary in SiteRegistry.world_obbs(site):
			mask.add_obb(obb, SITE_CLEARANCE * 0.5)
		masks.append(mask)
	for i: int in range(_sites.size()):
		for j: int in range(i + 1, _sites.size()):
			assert_false(masks[i].overlaps(masks[j]),
					"%s and %s keep %.1f m apart" % [_sites[i]["id"], _sites[j]["id"], SITE_CLEARANCE])


func test_the_spawn_point_is_left_clear() -> void:
	var spawn: Vector3 = _hf.spawn_point()
	for site: Dictionary in _sites:
		for obb: Dictionary in SiteRegistry.world_obbs(site):
			assert_false(Footprint.has_point(obb, spawn.x, spawn.z, SPAWN_CLEARANCE),
					"%s keeps clear of where the player wakes" % site["id"])


func test_every_prop_exists_and_sits_at_its_site() -> void:
	for scene: String in ["res://scenes/props/chest.tscn", "res://scenes/props/pickup.tscn",
			"res://scenes/props/lore_stone.tscn", "res://scenes/props/door.tscn"]:
		assert_true(ResourceLoader.exists(scene), "the interactable %s exists to be placed" % scene.get_file())
	for site: Dictionary in _built():
		var layout: Dictionary = StructureBuilder.load_layout(str(site.get("layout", "")))
		var local: Array[Dictionary] = Footprint.layout_obbs(layout)
		for raw: Variant in site.get("props", []):
			if not raw is Dictionary:
				continue
			var prop: Dictionary = raw
			assert_true(ResourceLoader.exists(str(prop.get("scene", ""))), "%s: prop scene %s exists"
					% [site["id"], prop.get("scene", "")])
			var a: Array = prop.get("at", [0, 0, 0])
			var near: bool = local.is_empty()
			for obb: Dictionary in local:
				near = near or Footprint.has_point(obb, float(a[0]), float(a[2]), PROP_REACH)
			assert_true(near, "%s: prop at %s is within %.0f m of the building" % [site["id"], a, PROP_REACH])
