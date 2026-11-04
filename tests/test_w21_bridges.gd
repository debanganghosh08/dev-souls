extends "res://tests/test_case.gd"
## The crossings and the river sheet (W21). The owner filmed: a bridge deck a few metres UNDER the river;
## a bridge "we cannot get into", with nothing joining its deck to either bank; and a river where "the water
## is not rendering". All three were true, and test_w20_river.gd could not see any of them, because it asks
## where a bridge STANDS and never how high, and asks that a water surface exists and never how wide.
##
## What was wrong, in order: (1) a crossing was floored at terrain max under a footprint that lay entirely
## inside the river cut -- so "max" was the riverbed, and the deck went at the bed; (2) the layouts had piers,
## a deck, parapets and lamps, and no stair, ramp or abutment at either end; (3) the water sheet was only as
## wide as the channel, while the cut's bank is a 28 m slope the ground crosses the surface somewhere out in,
## so 10-20 m of bare bed lay between the sheet's edge and the real waterline on each side; and the Wide
## Water drew a second sheet on exactly the same plane as the first, which z-fights.
##
## Every assertion here is one of those, measured against the real heightfield.

const AREA := "vale"
## Metres of air the deck's underside keeps above the water, everywhere along it.
const CLEARANCE := 1.5
## How far below the deck top a bank may lie before the player needs a stair down to it.
const STEP_DOWN := 0.4
const SAMPLE := 2.0
## Ribbon pairs left out at each end: a river mouth spreads where it leaves the map (W20, by design).
const MOUTH := 4

var _hf: Heightfield
var _area: Dictionary = {}
var _cuts: Array = []
var _crossings: Array[Dictionary] = []
var _nodes: Array[Node] = []


func setup() -> void:
	_area = JSON.parse_string(FileAccess.get_file_as_string("res://data/areas/%s.json" % AREA))
	_hf = Heightfield.from_dict(_area)
	_cuts = _area.get("cuts", [])
	for site: Dictionary in SiteRegistry.load_area(AREA):
		if str(site["layout"]).contains("bridge") and not str(site["id"]).begins_with("hollowmere"):
			_crossings.append(site)
	StructureBuilder.clear_shared()


func teardown() -> void:
	for node: Node in _nodes:
		node.free()
	_nodes.clear()
	StructureBuilder.clear_shared()


func _floor_of(site: Dictionary) -> float:
	return Settlements.ground_height(site, _hf, 1.0)


func _piece(site: Dictionary, name: String) -> Dictionary:
	for raw: Variant in StructureBuilder.load_layout(str(site["layout"])).get("pieces", []):
		if str((raw as Dictionary).get("name", "")) == name:
			return raw
	return {}


func _world(site: Dictionary, floor_y: float, local: Vector3) -> Vector3:
	return SiteRegistry.site_transform(site, floor_y) * local


## The cut this site stands in (its line within the cut's half width), widest first.
func _cut_under(site: Dictionary) -> Dictionary:
	var at: Vector2 = SiteRegistry.at_of(site)
	var best: Dictionary = {}
	for raw: Variant in _cuts:
		var cut: Dictionary = raw
		var points: Array = cut["points"]
		var d: float = INF
		for i: int in points.size() - 1:
			var a := Vector2(float((points[i] as Array)[0]), float((points[i] as Array)[1]))
			var b := Vector2(float((points[i + 1] as Array)[0]), float((points[i + 1] as Array)[1]))
			d = minf(d, at.distance_to(Geometry2D.get_closest_point_to_segment(at, a, b)))
		if d < float(cut["half_width"]) and (best.is_empty() or float(cut["half_width"]) > float(best["half_width"])):
			best = cut
	return best


func test_every_crossing_is_floored_by_the_water_and_never_under_its_bank() -> void:
	# Negative control: the W20 data (ground absent, so "max") under the W20 footprint (32 m, all riverbed)
	# floors every crossing at the bed, 2-3 m under the surface, and the clearance assertion fails.
	assert_eq(_crossings.size(), 4, "four crossings")
	for site: Dictionary in _crossings:
		assert_eq(str(site.get("ground", "")), "water", "%s is floored by the water, not by the ground" % site["id"])
		var at: Vector2 = SiteRegistry.at_of(site)
		var surface: Vector2 = _hf.surface_at(at.x, at.y)
		assert_true(surface.x > -INF, "%s has a river under it" % site["id"])
		var floor_y: float = _floor_of(site)
		assert_true(floor_y >= surface.x + Settlements.WATER_CLEARANCE - 0.001,
				"%s's floor is %.2f m over the water (surface %.2f, floor %.2f)" % [site["id"], Settlements.WATER_CLEARANCE, surface.x, floor_y])
		var span: Vector2 = Settlements.ground_span(site, _hf, 1.0)
		assert_true(floor_y >= span.y - 0.001, "%s's floor is never below its bank (bank %.2f, floor %.2f)" % [site["id"], span.y, floor_y])


func test_the_deck_underside_clears_the_water_along_its_whole_length() -> void:
	# Negative control: a deck piece placed at y = -3 in either layout, or CLEARANCE in Settlements cut to
	# 1.0, puts the underside within 1.5 m of (or under) the surface somewhere along the span.
	for site: Dictionary in _crossings:
		var deck: Dictionary = _piece(site, "deck")
		assert_false(deck.is_empty(), "%s has a deck" % site["id"])
		var floor_y: float = _floor_of(site)
		var dy: float = float((deck["at"] as Array)[1])
		var half_d: float = float((deck["params"] as Dictionary)["d"]) * 0.5
		var wet: int = 0
		var lowest: float = INF
		var z: float = -half_d
		while z <= half_d + 0.001:
			var p: Vector3 = _world(site, floor_y, Vector3(0.0, dy, z))
			var surface: Vector2 = _hf.surface_at(p.x, p.z)
			if surface.y <= _hf.reach_of_cuts():
				wet += 1
				lowest = minf(lowest, p.y - surface.x)
			z += SAMPLE
		assert_true(wet >= 10, "%s was sampled over the river (%d wet samples)" % [site["id"], wet])
		assert_true(lowest >= CLEARANCE, "%s's deck underside clears the water all along it (closest %.2f m)" % [site["id"], lowest])


func test_every_crossing_spans_its_cut_and_lands_ashore_at_both_ends() -> void:
	# Negative control: the W20 river_bridge (30 m deck, 32 m keep-out) ends 15 m from the line, inside a
	# channel whose bed is 2.4 m under the surface; both assertions fail for all three stone bridges.
	for site: Dictionary in _crossings:
		var cut: Dictionary = _cut_under(site)
		assert_false(cut.is_empty(), "%s stands in a cut" % site["id"])
		var reach: float = float(cut["half_width"]) + float(cut["bank"])
		var layout: Dictionary = StructureBuilder.load_layout(str(site["layout"]))
		var keep: Array = (layout["keep_out"] as Array)[0]
		var half_len: float = float(keep[3]) * 0.5
		assert_true(half_len >= reach - 0.01, "%s is as long as its cut is wide (%.0f m against %.0f m)" % [site["id"], half_len * 2.0, reach * 2.0])
		var deck: Dictionary = _piece(site, "deck")
		var floor_y: float = _floor_of(site)
		var half_d: float = float((deck["params"] as Dictionary)["d"]) * 0.5
		for way: float in [-1.0, 1.0]:
			var p: Vector3 = _world(site, floor_y, Vector3(0.0, 0.0, way * half_d))
			var ground: float = _hf.height_at(p.x, p.z)
			var surface: Vector2 = _hf.surface_at(p.x, p.z)
			assert_true(surface.x == -INF or ground >= surface.x - 0.3,
					"%s's %s end lands ashore (ground %.2f, water %.2f)" % [site["id"], "far" if way > 0.0 else "near", ground, surface.x])


func test_each_end_has_a_walkable_way_down_onto_the_bank() -> void:
	# Negative controls: `reach` removed from the approach entry (or a builder given no ground_at) builds no
	# flight, and the deck end then hangs more than a step above the bank; a fixed `rise` instead of `reach`
	# lands the foot in the air or inside the hill, which the foot assertions catch.
	for site: Dictionary in _crossings:
		var floor_y: float = _floor_of(site)
		var builder: StructureBuilder = Settlements.builder_for(site, _hf, floor_y)
		_nodes.append(builder)
		var entry: Dictionary = _piece(site, "approach")
		assert_eq(str(entry.get("reach", "")), "ground", "%s's approaches reach for the ground" % site["id"])
		var tops: Array[Transform3D] = StructureBuilder.placements_of(entry)
		assert_eq(tops.size(), 2, "%s has an approach at each end" % site["id"])
		var deck: Dictionary = _piece(site, "deck")
		var deck_top: float = float((deck["at"] as Array)[1]) + float((deck["params"] as Dictionary)["t"])
		var half_d: float = float((deck["params"] as Dictionary)["d"]) * 0.5
		var flights: Array[Node3D] = []
		for child: Node in builder.get_children():
			if child.has_meta(&"flight"):
				flights.append(child)
		for top: Transform3D in tops:
			assert_true(absf(top.origin.y - deck_top) <= STEP_DOWN, "%s's approach starts at deck height" % site["id"])
			assert_true(absf(top.origin.z) >= half_d - 0.01 and absf(top.origin.z) <= half_d + 3.0,
					"%s's approach starts at the deck end (z %.2f)" % [site["id"], top.origin.z])
			var flight: Node3D = null
			for f: Node3D in flights:
				var meta: Dictionary = f.get_meta(&"flight")
				var back: Vector3 = f.transform * Vector3(0.0, float(meta["rise"]), -float(meta["run"]))
				if back.distance_to(top.origin) < 0.01:
					flight = f
			var end: Vector3 = _world(site, floor_y, top.origin)
			if flight == null:
				# No stair was needed only if the bank is already there to step onto.
				assert_true(_hf.height_at(end.x, end.z) >= top.origin.y + floor_y - STEP_DOWN,
						"%s: the bank meets the deck end at z %.0f, so no stair (ground %.2f, deck %.2f)"
						% [site["id"], top.origin.z, _hf.height_at(end.x, end.z), top.origin.y + floor_y])
				continue
			var meta: Dictionary = flight.get_meta(&"flight")
			var steps: int = int(meta["steps"])
			var riser: float = float(meta["rise"]) / float(steps)
			var tread: float = float(meta["run"]) / float(steps)
			assert_true(riser <= StructureKit.MAX_RISER + 0.001, "%s's flight is climbable (riser %.3f)" % [site["id"], riser])
			# The foot: the ground at it is below it by less than a riser, and it is on the bank, not in the river.
			var foot: Vector3 = _world(site, floor_y, flight.transform.origin)
			var at_foot: float = _hf.height_at(foot.x, foot.z)
			var beyond: Vector3 = _world(site, floor_y, flight.transform * Vector3(0.0, 0.0, tread))
			var past_foot: float = _hf.height_at(beyond.x, beyond.z)
			assert_true(at_foot <= foot.y + 0.001, "%s's flight is not buried at its foot (ground %.2f, foot %.2f)" % [site["id"], at_foot, foot.y])
			assert_true(past_foot >= foot.y - riser - 0.001, "%s's flight reaches the bank, not the air (ground %.2f one tread on, foot %.2f)" % [site["id"], past_foot, foot.y])
			var surface: Vector2 = _hf.surface_at(foot.x, foot.z)
			assert_true(surface.x == -INF or at_foot >= surface.x - 0.3, "%s's flight lands ashore (ground %.2f, water %.2f)" % [site["id"], at_foot, surface.x])
			# Nothing pokes up through a tread by more than a step: every tread's far edge is over ground.
			var blocked: int = 0
			for k: int in range(1, steps + 1):
				var edge: Vector3 = _world(site, floor_y, top * Vector3(0.0, 0.0, tread * float(k)))
				if _hf.height_at(edge.x, edge.z) > top.origin.y + floor_y - riser * float(k) + STEP_DOWN:
					blocked += 1
			assert_eq(blocked, 0, "%s's flight is clear of the hill on every tread" % site["id"])


func test_piers_and_abutments_stand_in_the_ground_and_carry_the_deck() -> void:
	# Negative control: the W20 piers (y -13, h 13) under a floor that is now the bank top stop short of the
	# bed where the bank is high; a pier whose top is under the deck (h < -y) fails everywhere.
	var checked: int = 0
	for site: Dictionary in _crossings:
		var floor_y: float = _floor_of(site)
		var deck_y: float = float((_piece(site, "deck")["at"] as Array)[1])
		for name: String in ["piers", "abutments", "anchors"]:
			var entry: Dictionary = _piece(site, name)
			if entry.is_empty():
				continue
			var p: Dictionary = entry["params"]
			for t: Transform3D in StructureBuilder.placements_of(entry):
				checked += 1
				assert_true(t.origin.y + float(p["h"]) >= deck_y - 0.01, "%s's %s reach the deck's underside" % [site["id"], name])
				var shortfall: float = -INF
				var z: float = -float(p["d"]) * 0.5
				while z <= float(p["d"]) * 0.5 + 0.001:
					var w: Vector3 = _world(site, floor_y, t * Vector3(0.0, 0.0, z))
					shortfall = maxf(shortfall, (floor_y + t.origin.y) - (_hf.height_at(w.x, w.z) - 0.5))
					z += 1.0
				assert_true(shortfall <= 0.0, "%s's %s at z %.0f stand in the ground all along (%.2f m short)" % [site["id"], name, t.origin.z, shortfall])
				if name == "piers":
					var w: Vector3 = _world(site, floor_y, t.origin)
					assert_true(_hf.in_river(w.x, w.z), "%s's pier at z %.0f stands in the water" % [site["id"], t.origin.z])
	assert_true(checked >= 12, "piers, abutments and anchors were checked (%d)" % checked)


func test_the_river_is_one_sheet_that_runs_from_bank_to_bank() -> void:
	# Negative controls: `spread` 0 on the river leaves the sheet's edge over bed 2.4 m under the surface
	# (the W20 look); giving the Wide Water a point of its own un-folds it into a second sheet on the same
	# plane; the old nearest-POINT level blend puts the sheet off the cut's surface by more than 5 cm.
	# The sheet reaches exactly the rim of the cut it lies in: half_width + spread is the cut's half_width +
	# bank, water by water. A spread of 20 leaves bare bed at the edge; 40 lets the sheet stand proud of any
	# dip beyond the rim. Both fail here, and the edge-vertex check below catches whichever is visible.
	var waters: Array = Water.waters_of("res://data/areas/%s.json" % AREA)
	var pinned: int = 0
	for raw: Variant in waters:
		var entry: Dictionary = raw
		for cut_raw: Variant in _cuts:
			var cut: Dictionary = cut_raw
			if str(cut["name"]) == str(entry.get("name", "")):
				pinned += 1
				assert_true(is_equal_approx(Water.sheet_half(entry), float(cut["half_width"]) + float(cut["bank"])),
						"%s's sheet reaches its cut's rim (%.1f against %.1f)" % [cut["name"], Water.sheet_half(entry), float(cut["half_width"]) + float(cut["bank"])])
	assert_eq(pinned, 2, "both waters lie in a cut of the same name")
	var water := Water.new()
	_nodes.append(water)
	water.rebuild(waters)
	var stats: Dictionary = water.stats()
	assert_eq(int(stats["surfaces"]), 1, "the river is one sheet: the Wide Water folds into it instead of fighting it")
	assert_eq(int(stats["volumes"]), 1, "and one body of water")
	var mesh: ArrayMesh = (water.get_node("Water_river") as MeshInstance3D).mesh
	var verts: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_INDEX]
	var pairs: int = verts.size() / 2
	assert_true(pairs > 100, "the ribbon was walked (%d pairs)" % pairs)
	assert_eq(indices.size(), (pairs - 1) * 6, "every pair of points is joined to the next: no gap in the ribbon")
	var widest_jump: float = 0.0
	var off_surface: float = 0.0
	var bare: Array[String] = []
	var shallowest: float = INF
	for i: int in pairs:
		var left: Vector3 = verts[i * 2]
		var right: Vector3 = verts[i * 2 + 1]
		var centre: Vector3 = (left + right) * 0.5
		if i > 0:
			var before: Vector3 = (verts[i * 2 - 2] + verts[i * 2 - 1]) * 0.5
			widest_jump = maxf(widest_jump, Vector2(centre.x - before.x, centre.z - before.z).length())
		off_surface = maxf(off_surface, absf(centre.y - _hf.surface_at(centre.x, centre.z).x))
		shallowest = minf(shallowest, centre.y - _hf.height_at(centre.x, centre.z))
		if i < MOUTH or i >= pairs - MOUTH:
			continue
		for edge: Vector3 in [left, right]:
			var ground: float = _hf.height_at(edge.x, edge.z)
			if ground < edge.y - 0.3:
				bare.append("(%.0f, %.0f) bank %.2f under a sheet at %.2f" % [edge.x, edge.z, ground, edge.y])
	assert_true(widest_jump <= water.segment * 1.5, "the walked points are evenly spaced (widest %.1f m)" % widest_jump)
	assert_true(off_surface < 0.05, "the sheet IS the cut's surface, point for point (off by %.3f m)" % off_surface)
	assert_true(shallowest > 1.5, "the channel under the sheet is still a river (%.2f m)" % shallowest)
	assert_true(bare.is_empty(), "the sheet's edges are in the banks, not over bare bed: %s" % ", ".join(bare.slice(0, 6)))


func test_the_water_takes_you_at_the_knee_not_on_the_bank() -> void:
	# Negative control: the W20 box top at surface + 0.4 drowned you standing on a bank an ankle above the
	# water once the sheet (and so the box) reached over the shallows; a depth of 2 leaves the bed outside.
	var water := Water.new()
	_nodes.append(water)
	water.rebuild(Water.waters_of("res://data/areas/%s.json" % AREA))
	var body: Area3D = water.get_node("Drown_river") as Area3D
	assert_not_null(body, "the river drowns")
	var boxes: int = 0
	var highest_top: float = -INF
	var lowest_top: float = INF
	var bed_outside: int = 0
	var narrowest: float = INF
	for child: Node in body.get_children():
		var shape: CollisionShape3D = child as CollisionShape3D
		if shape == null or not shape.shape is BoxShape3D:
			continue
		boxes += 1
		var size: Vector3 = (shape.shape as BoxShape3D).size
		var at: Vector3 = shape.transform.origin
		var surface: float = _hf.surface_at(at.x, at.z).x
		var top: float = at.y + size.y * 0.5 - surface
		highest_top = maxf(highest_top, top)
		lowest_top = minf(lowest_top, top)
		if at.y - size.y * 0.5 > _hf.height_at(at.x, at.z):
			bed_outside += 1
		narrowest = minf(narrowest, size.x)
	assert_true(boxes > 100, "the river is boxed step by step (%d)" % boxes)
	assert_true(highest_top <= -Water.WADE_DEPTH + 0.15, "no box reaches nearer the surface than the wade depth (%.2f)" % highest_top)
	assert_true(lowest_top >= -Water.WADE_DEPTH - 0.15, "and none starts deeper than it (%.2f)" % lowest_top)
	assert_eq(bed_outside, 0, "the bed is inside every box")
	var cut: Dictionary = _cuts[0]
	assert_true(narrowest >= 2.0 * (float(cut["half_width"]) + float(cut["bank"])) - 0.01,
			"the water takes you wherever the sheet is, not just mid-channel (narrowest %.0f m)" % narrowest)
