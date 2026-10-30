extends "res://tests/test_case.gd"
## "Many things are floating in the air" -- the owner, watching his own recording. This is the test that
## was missing. A site is floored at the HIGHEST ground under its footprint (D-022), so on any slope the
## low corner of a building stands over a gap unless its foundation reaches down past the fall. Nothing
## measured that, because every other test asks whether a thing is in a legal PLACE, not whether there is
## ground under all of it.

const AREA := "vale"
## A foundation has to reach at least this far below the worst fall under its own site.
const COVER := 0.3
## Kit kinds that bury their own base by `sink` (StructureKitProps.SINK when the layout names none).
const SINKABLE: Array[String] = ["fence", "garden_bed", "haystack", "scarecrow", "cairn", "well", "trough",
		"signpost", "campfire", "tent_frame", "weapon_rack", "grave_mound", "brazier", "torch_post",
		"hearth_remains", "lamp_stone", "pyre", "beacon"]

var _hf: Heightfield
var _sites: Array[Dictionary] = []


func setup() -> void:
	var area: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/areas/vale.json"))
	_hf = Heightfield.from_dict(area)
	_sites = SiteRegistry.load_area(AREA)


func test_every_building_reaches_the_ground_on_its_low_side() -> void:
	var worst: float = 0.0
	var worst_id: String = ""
	var checked: int = 0
	var floating: Array[String] = []
	for site: Dictionary in _sites:
		if bool(site.get("fixed", false)):
			continue
		var layout: Dictionary = StructureBuilder.load_layout(str(site.get("layout", "")))
		if layout.is_empty():
			continue
		var span: Vector2 = Settlements.ground_span(site, _hf, 1.0)
		if span.x == INF:
			continue
		var floor_y: float = Settlements.ground_height(site, _hf, 1.0)
		var fall: float = floor_y - span.x
		if fall <= 0.05:
			continue
		checked += 1
		# How far down does anything in this layout actually reach?
		var deepest: float = 0.0
		for raw: Variant in layout.get("pieces", []):
			var piece: Dictionary = raw
			var params: Dictionary = piece.get("params", {})
			var kind: String = str(piece.get("kind", ""))
			for t: Transform3D in StructureBuilder.placements_of(piece):
				var bottom: float = t.origin.y
				if kind == "block" or kind == "floor_slab":
					deepest = minf(deepest, bottom)
				elif params.has("sink"):
					deepest = minf(deepest, bottom - float(params["sink"]))
				elif SINKABLE.has(kind):
					# A layout that names no sink gets the kit default, which is most of them.
					deepest = minf(deepest, bottom - StructureKitProps.SINK)
		var reach: float = -deepest
		if fall - reach > worst:
			worst = fall - reach
			worst_id = str(site.get("id", "?"))
		if reach + COVER < fall:
			floating.append("%s (ground falls %.1f m, the building reaches %.1f m)"
					% [site.get("id", "?"), fall, reach])
	print("FLOATING checked=%d worst_shortfall=%.2f m (%s)" % [checked, worst, worst_id])
	assert_true(checked > 40, "there were sloping sites to check (%d)" % checked)
	assert_true(floating.is_empty(), "nothing hangs in the air: %s" % ", ".join(floating.slice(0, 6)))


func test_the_overlook_is_high_and_can_be_walked_up() -> void:
	var top: float = _hf.height_at(-240.0, 8.0)
	assert_true(top > 12.1, "the overlook stands above the valley (%.1f m)" % top)
	# Walkable all the way round: no step the player cannot climb, which is what makes it an overlook
	# rather than a wall. PlayerController tops out near 45 degrees; this stays well under.
	var worst: float = 0.0
	for i: int in range(24):
		var a: float = TAU * float(i) / 24.0
		var last: float = _hf.height_at(-240.0 + cos(a) * 90.0, 8.0 + sin(a) * 90.0)
		for step: int in range(1, 60):
			var r: float = 90.0 - float(step) * 1.5
			var h: float = _hf.height_at(-240.0 + cos(a) * r, 8.0 + sin(a) * r)
			worst = maxf(worst, absf(h - last))
			last = h
	print("FLOATING overlook top=%.1f m worst_step=%.2f m per 1.5 m" % [top, worst])
	assert_true(worst <= 1.26, "the climb has no step over 1.26 m per 1.5 m (worst %.2f)" % worst)
