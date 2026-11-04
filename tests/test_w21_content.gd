extends "res://tests/test_case.gd"
## W21-F: content along the river and the roads that are drawn (and not drawn) across the Vale. Two things
## the suite found or the owner asked for. test_world_reach.gd failed: the emptiest walkable spot, (0, -380)
## on the far bank of the Wide Water, was 95 m from anything built, exactly the limit. And the terrain road
## (data/areas/vale.json material.road) is one polyline the shader draws pair by pair, up to
## TerrainMaterial.MAX_ROAD_SEGMENTS of it; two points appended after the castle drew a 499 m track from the
## castle over the pond to Hollowmere's crofts and another back across the village, roads nobody intended.
## The sites here are in data/sites/vale_river.json; the road is read from the area file as the shader reads it.

const AREA := "vale"
const RIVER_FILE := "vale_river.json"
const POIS_DIR := "res://data/structures/pois/"
const EMPTY_SPOT := Vector2(0.0, -380.0)
## test_world_reach.gd allows 95 m; the far-bank sites leave the once-emptiest spot well inside that.
const COMFORTABLE := 60.0
const NEW_SITES: Array[String] = ["far_bank_hearth", "far_bank_cairn", "wide_water_camp", "wide_water_cairn",
		"last_mouth_camp", "last_mouth_fire", "last_mouth_cairn"]
## The sites with a fire that the others gather round.
const CAMPS: Array[String] = ["far_bank_hearth", "wide_water_camp", "last_mouth_camp"]
## A camp "along the river" stands within this of the river's centre line (the bank itself reaches 45 m).
const RIVER_REACH := 90.0
const CLUSTER := 50.0
## Dressing sets whose scatter reaches a camp, so it reads as lived-in and not as a layout on bare grass.
const DRESSED_BY := 3
## A waypoint is a place: within this of a built site's origin or of a place named in data/places.json.
const PLACE_REACH := 20.0
## The Vale's places are 100-150 m apart; a longer segment is a track across the map, not a road between neighbours.
const MAX_SEGMENT := 200.0
## A building beside a track keeps this from its centre line (the old road's lamps stand at 3.4 m).
const BESIDE := 3.0
const CUT_SITE := "road_cut"
const AXIS_TOLERANCE_DEG := 5.0
const SAMPLE := 0.5

var _area: Dictionary = {}
var _hf: Heightfield
var _sites: Array[Dictionary] = []
var _river_sites: Array[Dictionary] = []
var _road: Dictionary = {}
var _places: Array = []


func setup() -> void:
	_area = JSON.parse_string(FileAccess.get_file_as_string("res://data/areas/%s.json" % AREA))
	_hf = Heightfield.from_dict(_area)
	_sites = SiteRegistry.load_area(AREA)
	for site: Dictionary in _sites:
		if str(site.get("_file", "")) == RIVER_FILE:
			_river_sites.append(site)
	_road = (_area.get("material", {}) as Dictionary).get("road", {})
	var places: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/places.json"))
	_places = (places as Dictionary).get("places", []) if places is Dictionary else []


func _site(id: String) -> Dictionary:
	for site: Dictionary in _sites:
		if str(site.get("id", "")) == id:
			return site
	return {}


## Distance from a point to the nearest point of an OBB (0 inside it), as test_pois.gd measures it.
static func _obb_distance(obb: Dictionary, p: Vector2) -> float:
	var d: Vector2 = p - (obb["centre"] as Vector2)
	var ax: float = maxf(0.0, absf(d.dot(obb["ux"])) - float(obb["hx"]))
	var az: float = maxf(0.0, absf(d.dot(obb["uz"])) - float(obb["hz"]))
	return Vector2(ax, az).length()


## Nearest a segment comes to an OBB, sampled along the segment.
static func _segment_to_obb(a: Vector2, b: Vector2, obb: Dictionary) -> float:
	var steps: int = maxi(1, ceili(a.distance_to(b) / SAMPLE))
	var best: float = INF
	for i: int in range(steps + 1):
		best = minf(best, _obb_distance(obb, a.lerp(b, float(i) / float(steps))))
	return best


func _nearest_built(p: Vector2, sites: Array[Dictionary]) -> float:
	var best: float = INF
	for site: Dictionary in sites:
		for obb: Dictionary in SiteRegistry.world_obbs(site):
			best = minf(best, _obb_distance(obb, p))
	return best


func _river_line() -> PackedVector2Array:
	var out := PackedVector2Array()
	for raw: Variant in _area.get("cuts", []):
		var cut: Dictionary = raw
		if str(cut.get("name", "")) != "river":
			continue
		for p: Variant in cut["points"]:
			out.append(Vector2(float((p as Array)[0]), float((p as Array)[1])))
	return out


static func _distance_to_path(p: Vector2, path: PackedVector2Array) -> float:
	var best: float = INF
	for i: int in range(path.size() - 1):
		best = minf(best, p.distance_to(Geometry2D.get_closest_point_to_segment(p, path[i], path[i + 1])))
	return best


func _waypoints() -> PackedVector2Array:
	var out := PackedVector2Array()
	for p: Variant in _road.get("waypoints", []):
		out.append(MapShapes.point(p))
	return out


## Is p a place: within PLACE_REACH of a built site's origin or a named place's point?
func _is_place(p: Vector2) -> bool:
	for site: Dictionary in _sites:
		if SiteRegistry.at_of(site).distance_to(p) <= PLACE_REACH:
			return true
	for raw: Variant in _places:
		if MapShapes.point((raw as Dictionary).get("at", [])).distance_to(p) <= PLACE_REACH:
			return true
	return false


# --- the sites -------------------------------------------------------------------------------------------

func test_the_river_sites_exist_with_what_the_registry_and_settlements_need() -> void:
	# Negative controls: a misspelt layout path, an `at` with one number, a yaw written as a string, a
	# site given `props` (loot and villagers live in the houses and village files), a duplicated id.
	assert_eq(_river_sites.size(), NEW_SITES.size(), "the river file places %d sites" % NEW_SITES.size())
	var seen: Dictionary = {}
	for id: String in NEW_SITES:
		var site: Dictionary = _site(id)
		assert_false(site.is_empty(), "%s is in the registry" % id)
		if site.is_empty():
			continue
		assert_eq(str(site.get("_file", "")), RIVER_FILE, "%s comes from the river file" % id)
		var path: String = str(site.get("layout", ""))
		assert_true(path.begins_with(POIS_DIR), "%s reuses a point-of-interest layout, not a new kit" % id)
		assert_true(FileAccess.file_exists(path), "%s: layout %s exists" % [id, path])
		assert_false(StructureBuilder.load_layout(path).is_empty(), "%s: layout parses" % id)
		var at: Variant = site.get("at", [])
		assert_true(at is Array and (at as Array).size() == 2, "%s has at [x, z]" % id)
		assert_true(site.get("yaw", 0.0) is float or site.get("yaw", 0.0) is int, "%s has a numeric yaw" % id)
		assert_false(site.has("props"), "%s is scenery only" % id)
		assert_false(bool(site.get("fixed", false)), "%s is built by Settlements" % id)
		assert_true(SiteRegistry.world_obbs(site).size() > 0, "%s has a footprint the placement rules can see" % id)
	for site: Dictionary in _sites:
		var id: String = str(site.get("id", ""))
		assert_false(seen.has(id), "site id '%s' is used once" % id)
		seen[id] = true


func test_the_once_emptiest_spot_is_comfortably_within_reach_of_something_built() -> void:
	# Negative control: delete far_bank_hearth and far_bank_cairn and the nearest thing is 95 m again.
	var d: float = _nearest_built(EMPTY_SPOT, _sites)
	assert_true(d <= COMFORTABLE, "(0, -380) is %.0f m from the nearest footprint (want <= %.0f, the suite's limit is 95)" % [d, COMFORTABLE])
	var far_sites: Array[Dictionary] = [_site("far_bank_hearth"), _site("far_bank_cairn")]
	var far: float = _nearest_built(EMPTY_SPOT, far_sites)
	assert_true(far <= 30.0, "it is the far-bank sites that close the gap (%.0f m)" % far)
	for id: String in ["far_bank_hearth", "far_bank_cairn"]:
		var at: Vector2 = SiteRegistry.at_of(_site(id))
		assert_true(at.length() < _hf.ridge_inner_radius() - 25.0, "%s keeps the ridge clearance" % id)
		var span: Vector2 = Settlements.ground_span(_site(id), _hf)
		assert_true(span.x > _hf.water_level() + 0.5, "%s is out of the water (lowest %.2f)" % [id, span.x])
		assert_true(span.y - span.x <= 1.6, "%s stands on ground its footing covers (falls %.2f m)" % [id, span.y - span.x])


func test_every_river_site_stands_along_the_river_on_dry_ground_near_its_camp() -> void:
	# Negative controls: a site at the pond (300 m from the river) fails the reach; one on the bed fails
	# in_river; the Last Mouth camp at its first spot (-160, -272) was 31 m further from its fire than this.
	var line: PackedVector2Array = _river_line()
	assert_true(line.size() >= 2, "the vale has a river to build along")
	var camps: Array[Vector2] = []
	for id: String in CAMPS:
		camps.append(SiteRegistry.at_of(_site(id)))
	for site: Dictionary in _river_sites:
		var at: Vector2 = SiteRegistry.at_of(site)
		assert_true(_distance_to_path(at, line) <= RIVER_REACH, "%s is along the river (%.0f m from its line)" % [site["id"], _distance_to_path(at, line)])
		assert_false(_hf.in_river(at.x, at.y, 1.0), "%s is on the bank, not in the river" % site["id"])
		var surface: Vector2 = _hf.surface_at(at.x, at.y)
		assert_true(surface.x == -INF or _hf.height_at(at.x, at.y) > surface.x + 0.5, "%s stands above the water surface" % site["id"])
		var nearest: float = INF
		for c: Vector2 in camps:
			nearest = minf(nearest, at.distance_to(c))
		assert_true(nearest <= CLUSTER, "%s belongs to a camp (%.0f m from the nearest fire)" % [site["id"], nearest])


func test_the_camps_are_dressed_as_lived_in() -> void:
	# Negative control: remove the W21-F scatter entries from data/dressing/vale.json and no set reaches
	# the camps; a dressing keep_out drawn over a camp fences the scatter off it.
	var dressing: Dictionary = LevelDressing.load_data("res://data/dressing/vale.json")
	var sets: Array = dressing.get("sets", [])
	assert_true(sets.size() > 5, "the vale's dressing has sets (%d)" % sets.size())
	for id: String in CAMPS:
		var at: Vector3 = Vector3(SiteRegistry.at_of(_site(id)).x, 0.0, SiteRegistry.at_of(_site(id)).y)
		var reaching: int = 0
		for raw: Variant in sets:
			var set: Dictionary = raw
			for zone: Variant in set.get("scatter", []):
				var rect: Dictionary = (zone as Dictionary).get("zone", {})
				if LevelDressing.in_rect(at, rect):
					reaching += 1
					break
		assert_true(reaching >= DRESSED_BY, "%s is reached by %d dressing sets (want %d)" % [id, reaching, DRESSED_BY])
		for raw: Variant in dressing.get("keep_out", []):
			var fence: Dictionary = raw
			assert_false(LevelDressing.in_rect(at, fence), "%s is not fenced off by the dressing keep-out '%s'" % [id, fence.get("name", "?")])


# --- the roads -------------------------------------------------------------------------------------------

func test_the_road_fits_the_shader_and_carries_the_old_road_verbatim() -> void:
	# Negative controls: a tenth waypoint (the shader draws eight segments and the map nine, two roads that
	# drift apart); the valley's second point left out, so the terrain wears a line the grass zones and
	# the placement rules do not know.
	var points: PackedVector2Array = _waypoints()
	assert_true(points.size() >= 2, "the vale defines a road")
	assert_true(points.size() - 1 <= TerrainMaterial.MAX_ROAD_SEGMENTS,
			"%d segments fit the shader's %d" % [points.size() - 1, TerrainMaterial.MAX_ROAD_SEGMENTS])
	var spine: PackedVector2Array = MapShapes.roads(_area)["spine"]
	assert_true(spine.size() >= 2, "the valley polyline is the old road")
	var start: int = -1
	for i: int in range(points.size() - spine.size() + 1):
		if points[i].distance_to(spine[0]) >= 0.5:
			continue
		var ok: bool = true
		for k: int in range(spine.size()):
			ok = ok and points[i + k].distance_to(spine[k]) < 0.5
		if ok:
			start = i
	assert_true(start >= 0, "the old road appears whole and in order among the waypoints")
	assert_true(float(_road.get("half_width", 0.0)) > 0.0 and float(_road.get("feather", 0.0)) > 0.0, "the road has a width and a feather")


func test_every_track_runs_between_places_and_beside_buildings_not_through_them() -> void:
	# Negative controls, all from the data this replaced: (200, -160) -> (-150, 196) was 499 m long and ran
	# through village_barn and the pond lighthouse; (-150, 196) -> (-96, 244) ran through Hollowmere's
	# market stalls and sitting area; (-168, 126) -> (-240, -18) ended 26 m from anything, on the Overlook's skirt.
	var tracks: Array = MapShapes.roads(_area)["tracks"]
	assert_true(tracks.size() >= 2, "there are tracks beyond the old road (%d)" % tracks.size())
	for t: PackedVector2Array in tracks:
		var a: Vector2 = t[0]
		var b: Vector2 = t[1]
		assert_true(a.distance_to(b) <= MAX_SEGMENT, "%s -> %s is a road between neighbours (%.0f m)" % [a, b, a.distance_to(b)])
		assert_true(_is_place(a) and _is_place(b), "%s -> %s joins two places" % [a, b])
		for site: Dictionary in _sites:
			var at: Vector2 = SiteRegistry.at_of(site)
			if at.distance_to(a) <= PLACE_REACH or at.distance_to(b) <= PLACE_REACH:
				continue
			for obb: Dictionary in SiteRegistry.world_obbs(site):
				var d: float = _segment_to_obb(a, b, obb)
				assert_true(d >= BESIDE, "%s stands beside the track %s -> %s, not under it (%.1f m)" % [site["id"], a, b, d])


func test_the_track_through_the_cutting_runs_on_its_axis_between_the_faces() -> void:
	# Negative controls: a track through the cut turned 30 degrees off its axis; a road half_width of 6,
	# whose worn gravel reaches into the rock faces; the cut with no track at all.
	var cut: Dictionary = _site(CUT_SITE)
	assert_false(cut.is_empty(), "the Cutting is a site")
	var at: Vector2 = SiteRegistry.at_of(cut)
	var through: Array[PackedVector2Array] = []
	for t: PackedVector2Array in MapShapes.roads(_area)["tracks"]:
		if t[0].distance_to(at) <= PLACE_REACH and t[1].distance_to(at) <= PLACE_REACH:
			through.append(t)
	assert_true(through.size() >= 1, "a track runs through the Cutting: it is where the road was cut through rock")
	var basis := Basis(Vector3.UP, deg_to_rad(SiteRegistry.yaw_of(cut)))
	var axis3: Vector3 = basis * Vector3.RIGHT
	var axis := Vector2(axis3.x, axis3.z).normalized()
	var faces: Array[Dictionary] = SiteRegistry.world_obbs(cut)
	assert_eq(faces.size(), 2, "the cut has two faces")
	for t: PackedVector2Array in through:
		var dir: Vector2 = (t[1] - t[0]).normalized()
		var off: float = rad_to_deg(acos(clampf(absf(dir.dot(axis)), 0.0, 1.0)))
		assert_true(off <= AXIS_TOLERANCE_DEG, "the track runs on the cut's axis (%.1f degrees off)" % off)
		var mid: Vector2 = (t[0] + t[1]) * 0.5
		assert_true(mid.distance_to(at) <= 2.0, "and passes through its middle (%.1f m off)" % mid.distance_to(at))
		for face: Dictionary in faces:
			var d: float = _segment_to_obb(t[0], t[1], face)
			assert_true(d >= float(_road.get("half_width", 0.0)), "the worn gravel stops short of the rock face (%.1f m, half width %.1f)" % [d, float(_road.get("half_width", 0.0))])
