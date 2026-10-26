extends "res://tests/test_case.gd"
## The stairwell down to the Hearth is the second place where the terrain is deliberately absent, and it
## is worse than the crypt: the Mirror Pond's water is a bare mesh with no collision, so the player can
## walk down into the basin and onto this hole long before the pond is drained. The same D-014 rule holds
## (the terrain drops a cell when its CENTRE is in the authored rect, so [-4,-5,8,10] becomes an 8 x 12 m
## gap on the 2 m grid) with one more piece: the stair opening itself must be capped by the pond seal until
## `pond_drained` is set, and open afterwards.
##
## These tests re-derive the snapped gap from the real data and prove the apron plus the seal floor all of
## it, and that the apron alone leaves exactly the stair opening. They are pure arithmetic on the JSON (the
## helpers are the crypt test's, so there is one snapping rule to drift), plus a detached instance of the
## scene for the seal's state. None of it says what the chamber looks like.

const CryptMouth := preload("res://tests/test_crypt_mouth.gd")

const AREA := "res://data/areas/vale.json"
const LAYOUT := "res://data/structures/hearth_chamber.json"
const SCENE := "res://scenes/structures/hearth_chamber.tscn"
const LEVEL := "res://scenes/levels/vale.tscn"
const FlagsScript := preload("res://scripts/autoloads/flags.gd")
const LOD0_SPACING := 2.0
const SAMPLE := 0.2
## World y of the basin floor at the pond centre, measured from the heightfield when the chamber was laid
## out. The scene is placed here; if the seed or noise ever moves the basin, this fails instead of leaving
## the chamber floating or buried.
const BASIN_FLOOR := -11.375
const BASIN_TOLERANCE := 0.03
const APRON_TOP := -0.05
const MAX_STEP_HEIGHT := 0.4
const APRON_PIECES: Array[String] = ["pond_apron_w", "pond_apron_e", "pond_apron_n", "pond_landing"]
const STAIRS := "hearth_stairs"
const SEAL := "pond_seal"
## Pieces allowed to stand above the basin floor: the lips of the open stairwell, its kerb, the posts
## that mark the descent, and the seal itself. Everything else is buried.
const PROUD_PIECES: Array[String] = ["shaft_w", "shaft_e", "stair_kerb_n", "gate_posts", SEAL]
## How tall each kind stands over its placement y, for the buried check.
const HEIGHT_KEY: Dictionary = {
	"wall": "h", "broken_wall": "h", "pillar": "h", "block": "h", "buttress": "h",
	"floor_slab": "t", "stairs": "rise",
}
const RUBBLE_PROUD := 0.5

var _area: Dictionary = {}
var _layout: Dictionary = {}
var _hf: Heightfield
var _centre := Vector2.ZERO
var _radius: float = 0.0
var _entries: Dictionary = {}
var _nodes: Array[Node] = []


func setup() -> void:
	_area = _read(AREA)
	_layout = _read(LAYOUT)
	_hf = Heightfield.from_dict(_area)
	var pond: Dictionary = _area.get("pond", {})
	var c: Array = pond.get("centre", [0, 0])
	_centre = Vector2(float(c[0]), float(c[1]))
	_radius = float(pond.get("radius", 0.0))
	for raw: Variant in _layout.get("pieces", []):
		if raw is Dictionary:
			_entries[str((raw as Dictionary).get("name", ""))] = raw


func teardown() -> void:
	for node: Node in _nodes:
		node.free()
	_nodes.clear()


func _read(path: String) -> Dictionary:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return data as Dictionary if data is Dictionary else {}


## The authored holes that lie in the pond, snapped and moved into the chamber's local frame (the scene
## sits at the pond centre, so local XZ is world XZ minus that).
func _local_gaps() -> Array[Rect2]:
	var out: Array[Rect2] = []
	var size: float = float(_area.get("size", 1024.0))
	for raw: Variant in _area.get("holes", []):
		if not raw is Array or (raw as Array).size() < 4:
			continue
		var r: Array = raw
		var world := Rect2(float(r[0]), float(r[1]), float(r[2]), float(r[3])).abs()
		if world.get_center().distance_to(_centre) > _radius:
			continue
		var snapped: Rect2 = CryptMouth.snap_to_cells(world, size, LOD0_SPACING)
		out.append(Rect2(snapped.position - _centre, snapped.size))
	return out


func _footprints(names: Array) -> Array[Rect2]:
	var out: Array[Rect2] = []
	for name: String in names:
		if _entries.has(name):
			out.append(CryptMouth.placed_footprint(_entries[name]))
	return out


# Rect2.has_point excludes the far edges, so butted slabs would leave hairline false gaps; grow by half a
# sample instead, exactly as the crypt test does.
static func _covered(cover: Array[Rect2], x: float, z: float) -> bool:
	for r: Rect2 in cover:
		if r.grow(SAMPLE * 0.5).has_point(Vector2(x, z)):
			return true
	return false


## Walks the gap on a SAMPLE grid; returns {open, first, inside_open, inside_first} where `open` counts
## samples outside `opening` that `cover` misses, and `inside_open` counts samples inside `opening` that
## `cover` wrongly fills. The grid lands exactly on the opening's edges (they sit on 0.1 m multiples), so
## the edge itself is neither demanded nor forbidden: a sample has to be half a sample clear of the edge
## to count as inside for the intrusion check, and half a sample clear to count as outside for coverage.
func _walk(gap: Rect2, cover: Array[Rect2], opening: Rect2) -> Dictionary:
	var out: Dictionary = {"open": 0, "first": Vector2.ZERO, "inside_open": 0, "inside_first": Vector2.ZERO}
	var has_opening: bool = opening.has_area()
	var x: float = gap.position.x + SAMPLE * 0.5
	while x < gap.end.x:
		var z: float = gap.position.y + SAMPLE * 0.5
		while z < gap.end.y:
			var near_opening: bool = has_opening and opening.grow(SAMPLE * 0.5).has_point(Vector2(x, z))
			var well_inside: bool = has_opening and opening.grow(-SAMPLE * 0.5).has_point(Vector2(x, z))
			var covered: bool = _covered(cover, x, z)
			if not near_opening and not covered:
				if out["open"] == 0:
					out["first"] = Vector2(x, z)
				out["open"] += 1
			if well_inside and covered:
				if out["inside_open"] == 0:
					out["inside_first"] = Vector2(x, z)
				out["inside_open"] += 1
			z += SAMPLE
		x += SAMPLE
	return out


# --- the gap the terrain actually leaves ------------------------------------------------------------------

func test_the_data_describes_one_hole_under_the_pond() -> void:
	assert_true(_radius > 0.0, "the vale defines a Mirror Pond to measure against")
	var gaps: Array[Rect2] = _local_gaps()
	assert_eq(gaps.size(), 1, "exactly one terrain hole in the pond, the stairwell")
	for name: String in APRON_PIECES + [STAIRS, SEAL]:
		assert_true(_entries.has(name), "the chamber layout still has piece '%s'" % name)


func test_the_hole_snaps_outwards_to_eight_by_twelve() -> void:
	var authored := Rect2(-4.0, -5.0, 8.0, 10.0)
	var snapped: Rect2 = CryptMouth.snap_to_cells(authored, 1024.0, LOD0_SPACING)
	assert_eq(snapped, Rect2(-4.0, -6.0, 8.0, 12.0), "the 8 x 10 rect becomes an 8 x 12 gap on the cell grid")
	var gaps: Array[Rect2] = _local_gaps()
	if gaps.is_empty():
		return
	assert_eq(gaps[0], Rect2(-4.0, -6.0, 8.0, 12.0), "in chamber-local metres the gap is x -4..4, z -6..6")


func test_every_covering_piece_is_a_quarter_turn() -> void:
	for name: String in APRON_PIECES + [STAIRS, SEAL]:
		if _entries.has(name):
			assert_true(CryptMouth.is_quarter_turn(_entries[name]), "piece '%s' is placed on a quarter turn" % name)


# --- coverage -------------------------------------------------------------------------------------------

func test_the_apron_and_the_seal_floor_the_whole_hole() -> void:
	# The pond is full, the seal is in place: there must be no open ground anywhere in the gap.
	var gaps: Array[Rect2] = _local_gaps()
	if gaps.is_empty():
		return
	var cover: Array[Rect2] = _footprints(APRON_PIECES + [SEAL])
	var r: Dictionary = _walk(gaps[0], cover, Rect2())
	assert_eq(int(r["open"]), 0, "no open ground in the sealed pond mouth (%d samples, first at %s)" % [r["open"], r["first"]])


func test_the_apron_alone_leaves_exactly_the_stair_opening() -> void:
	# The pond is drained, the seal is gone: the only open ground is the stair flight, and all of it.
	var gaps: Array[Rect2] = _local_gaps()
	if gaps.is_empty() or not _entries.has(STAIRS):
		return
	var opening: Rect2 = CryptMouth.placed_footprint(_entries[STAIRS])
	var r: Dictionary = _walk(gaps[0], _footprints(APRON_PIECES), opening)
	assert_eq(int(r["open"]), 0, "outside the stair opening the apron covers everything (%d samples, first at %s)" % [r["open"], r["first"]])
	assert_eq(int(r["inside_open"]), 0, "the apron does not intrude into the stair opening (%d samples, first at %s)" % [r["inside_open"], r["inside_first"]])
	assert_true(gaps[0].encloses(opening), "the stair opening lies inside the hole, not through solid terrain")


func test_the_seal_covers_the_opening_and_stands_within_a_step() -> void:
	if not _entries.has(STAIRS) or not _entries.has(SEAL):
		return
	var opening: Rect2 = CryptMouth.placed_footprint(_entries[STAIRS])
	var lid: Rect2 = CryptMouth.placed_footprint(_entries[SEAL])
	assert_true(lid.grow(0.001).encloses(opening), "the seal covers the whole stair opening (%s over %s)" % [lid, opening])
	var e: Dictionary = _entries[SEAL]
	var top: float = float(e["at"][1]) + float(e["params"]["t"])
	assert_true(top > APRON_TOP, "the seal stands above the apron, not inside it")
	assert_true(top < MAX_STEP_HEIGHT, "the seal is inside the player's step-up (top %.2f)" % top)
	var stair_top: float = float(_entries[STAIRS]["at"][1]) + float(_entries[STAIRS]["params"]["rise"])
	assert_true(float(e["at"][1]) <= stair_top + 0.001, "the seal rests on the top tread, leaving no slot under it")


func test_the_stair_flight_is_as_wide_as_the_shaft() -> void:
	var west: Dictionary = _entries.get("shaft_w", {})
	var east: Dictionary = _entries.get("shaft_e", {})
	var stairs: Dictionary = _entries.get(STAIRS, {})
	if west.is_empty() or east.is_empty() or stairs.is_empty():
		assert_true(false, "the shaft walls and stairs are all present")
		return
	var inner: float = absf(float(east["at"][0]) - float(west["at"][0])) \
			- (float(east["params"]["t"]) + float(west["params"]["t"])) * 0.5
	assert_true(float(stairs["params"]["w"]) >= inner - 0.001,
			"the flight spans the shaft wall to wall (%.2f >= %.2f)" % [float(stairs["params"]["w"]), inner])
	var built: Dictionary = StructureBuilder.make_piece("stairs", stairs["params"])
	assert_true(float(built["riser"]) <= StructureKit.MAX_RISER, "the riser %.3f is climbable" % float(built["riser"]))
	var top: float = float(stairs["at"][1]) + float(stairs["params"]["rise"])
	assert_true(is_equal_approx(top, APRON_TOP), "the flight tops out flush with the apron (%.3f)" % top)


func test_the_apron_sits_a_hair_under_the_basin_floor() -> void:
	for name: String in APRON_PIECES:
		if not _entries.has(name):
			continue
		var e: Dictionary = _entries[name]
		var top: float = float(e["at"][1]) + float(e["params"]["t"])
		assert_true(is_equal_approx(top, APRON_TOP), "%s tops out at %.3f, not %.3f" % [name, top, APRON_TOP])
		assert_true(top < 0.0, "%s is not coplanar with the basin floor" % name)
	# Against the real ground, not the nominal one: the lip from the terrain at the hole edge down onto the
	# apron must be inside the step-up, so the player can walk in and out of the mouth.
	var gaps: Array[Rect2] = _local_gaps()
	if gaps.is_empty():
		return
	var gap: Rect2 = gaps[0]
	var worst: float = 0.0
	for corner: Vector2 in [gap.position, gap.end, Vector2(gap.position.x, gap.end.y), Vector2(gap.end.x, gap.position.y),
			Vector2(gap.get_center().x, gap.position.y), Vector2(gap.get_center().x, gap.end.y)]:
		var h: float = _hf.height_at(_centre.x + corner.x, _centre.y + corner.y) - BASIN_FLOOR
		worst = maxf(worst, absf(h - APRON_TOP))
	assert_true(worst < MAX_STEP_HEIGHT, "the hole edge is within a step of the apron (worst %.3f)" % worst)


# --- the basin and the scene ----------------------------------------------------------------------------

func test_the_basin_floor_is_still_where_the_chamber_was_laid_out() -> void:
	var h: float = _hf.height_at(_centre.x, _centre.y)
	assert_true(absf(h - BASIN_FLOOR) <= BASIN_TOLERANCE,
			"the pond centre is at %.4f, expected %.3f within %.2f: the chamber would float or be buried" % [h, BASIN_FLOOR, BASIN_TOLERANCE])
	assert_true(_hf.slope_at(_centre.x, _centre.y) < 1.0, "the basin floor reads as level at the centre")


func test_the_level_places_the_chamber_at_the_basin_floor() -> void:
	# The tscn is read as text: instancing the whole vale would build terrain, forest and grass.
	var text: String = FileAccess.get_file_as_string(LEVEL)
	var at: int = text.find('[node name="HearthChamber"')
	assert_true(at >= 0, "vale.tscn instances the HearthChamber")
	if at < 0:
		return
	var line_end: int = text.find("\n", text.find("transform = Transform3D(", at))
	var line: String = text.substr(at, line_end - at)
	var open: int = line.find("Transform3D(")
	var parts: PackedStringArray = line.substr(open + 12, line.find(")", open) - open - 12).split(",")
	assert_eq(parts.size(), 12, "the chamber transform is a full Transform3D")
	if parts.size() != 12:
		return
	var origin := Vector3(float(parts[9]), float(parts[10]), float(parts[11]))
	assert_true(is_equal_approx(origin.x, _centre.x) and is_equal_approx(origin.z, _centre.y),
			"the chamber sits on the pond centre (%s)" % origin)
	assert_true(absf(origin.y - BASIN_FLOOR) <= BASIN_TOLERANCE, "the chamber sits at the basin floor (y %.3f)" % origin.y)
	var builder: Dictionary = {}
	for raw: Variant in _layout.get("pieces", []):
		builder[str(raw.get("name", ""))] = true
	assert_true(builder.has(SEAL), "the layout the scene builds carries the seal")


func test_the_chamber_stays_buried_and_inside_the_pond() -> void:
	var ceiling: Dictionary = _entries.get("chamber_ceiling", {})
	assert_false(ceiling.is_empty(), "the chamber has a ceiling")
	for name: String in _entries:
		var e: Dictionary = _entries[name]
		var kind: String = str(e.get("kind", ""))
		var p: Dictionary = e.get("params", {})
		var rise: float = float(p.get(HEIGHT_KEY.get(kind, ""), RUBBLE_PROUD if kind == "rubble" else 0.0))
		var reach: float = maxf(maxf(float(p.get("w", 0.0)), float(p.get("d", 0.0))), 2.0 * float(p.get("radius", 0.0))) * 0.5
		for t: Transform3D in StructureBuilder.placements_of(e):
			var top: float = t.origin.y + rise
			if top > 0.001:
				assert_true(PROUD_PIECES.has(name), "%s pokes %.2f m above the basin floor without being deliberate" % [name, top])
			assert_true(Vector2(t.origin.x, t.origin.z).length() + reach < _radius,
					"%s stays inside the pond's %.0f m radius" % [name, _radius])
	# The real ground over the ceiling must be above it everywhere, or the room breaks the basin floor.
	if ceiling.is_empty():
		return
	var rect: Rect2 = CryptMouth.placed_footprint(ceiling)
	var top: float = float(ceiling["at"][1]) + float(ceiling["params"]["t"])
	var lowest: float = INF
	var x: float = rect.position.x
	while x <= rect.end.x:
		var z: float = rect.position.y
		while z <= rect.end.y:
			lowest = minf(lowest, _hf.height_at(_centre.x + x, _centre.y + z) - BASIN_FLOOR)
			z += 1.0
		x += 1.0
	assert_true(lowest > top, "the ground over the chamber (lowest %.3f) stays above the ceiling top (%.2f)" % [lowest, top])


func test_the_layout_builds_with_collision_on_every_piece() -> void:
	var builder := StructureBuilder.new()
	_nodes.append(builder)
	builder.layout_path = LAYOUT
	builder.build()
	var stats: Dictionary = builder.stats()
	assert_eq(int(stats["pieces"]), (_layout["pieces"] as Array).size(), "every layout entry became a piece")
	for child: Node in builder.get_children():
		var has_mesh: bool = child.get_node_or_null(^"Mesh") != null or child.get_node_or_null(^"Multi") != null
		var body: StaticBody3D = child.get_node_or_null(^"Body") as StaticBody3D
		assert_true(has_mesh, "%s draws something" % child.name)
		assert_not_null(body, "%s has a collision body" % child.name)
		if body != null:
			assert_eq(body.collision_layer, StructureKit.WORLD_LAYER, "%s collides on the world layer" % child.name)
			assert_eq(body.collision_mask, 0, "%s collides with nothing itself" % child.name)
	assert_true(builder.footprint_radius() <= _radius, "footprint %.1f m fits the %.0f m pond" % [builder.footprint_radius(), _radius])


# --- the seal's state -------------------------------------------------------------------------------------

func _chamber() -> HearthChamber:
	var root: HearthChamber = (load(SCENE) as PackedScene).instantiate() as HearthChamber
	_nodes.append(root)
	return root


func test_the_seal_stands_until_the_pond_drains_then_goes_for_good() -> void:
	var flags: Node = FlagsScript.new()
	_nodes.append(flags)
	var chamber: HearthChamber = _chamber()
	chamber._inject(flags)
	chamber.bind()
	assert_eq(chamber.drained_flag(), &"pond_drained", "the lid is keyed to the Hearth's own gate flag")
	assert_true(chamber.is_sealed(), "with the pond full the seal is in place")
	var seal: Node = chamber.seal_node()
	assert_not_null(seal.get_node_or_null(^"Body"), "the seal carries collision")
	flags.set_flag(&"some_other_flag")
	assert_true(chamber.is_sealed(), "an unrelated flag changes nothing")
	flags.set_flag(&"pond_drained")
	assert_false(chamber.is_sealed(), "the live flag removes the seal")
	assert_null(chamber.seal_node(), "and it is gone, not hidden")


func test_a_drained_save_comes_back_with_no_seal_from_the_start() -> void:
	var flags: Node = FlagsScript.new()
	_nodes.append(flags)
	flags.restore([&"pond_drained"])
	var chamber: HearthChamber = _chamber()
	chamber._inject(flags)
	chamber.bind()
	assert_false(chamber.is_sealed(), "the water left before this session: no lid, nothing to watch")


func test_with_no_flags_at_all_the_seal_stays() -> void:
	var chamber: HearthChamber = _chamber()
	chamber.bind()
	assert_true(chamber.is_sealed(), "no Flags autoload means the safe state, sealed")
	assert_not_null(chamber.get_node_or_null(^"Hearth"), "the chamber carries the Hearth")
