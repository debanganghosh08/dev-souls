extends "res://tests/test_case.gd"
## The castle crypt is the only place in the game where the terrain is deliberately absent, and the first
## owner play-test walked straight off the graveyard into the 4.6 m shaft. The cause was not the hole itself
## but its SIZE: the terrain drops a cell when the cell's CENTRE falls in the authored rect, so a 6 x 9 m
## rect becomes a 6 x 8 m gap snapped outwards onto the 2 m terrain grid -- wider than the crypt house on
## three sides. Anything inside that gap which is not the stair opening has to be floored by the structure.
##
## These tests re-derive the snapped gap from the real data and prove the castle covers all of it. They are
## pure arithmetic on the two JSON files, so they catch the mistake if anyone moves the hole, the crypt
## house, the stairs or the apron -- which a probe walking one path would not.

const AREA := "res://data/areas/vale.json"
const LAYOUT := "res://data/structures/castle_morrow.json"
## Terrain.lod0_spacing's default. Collision cells are this wide, so this is the grid the hole snaps to.
const LOD0_SPACING := 2.0
const SAMPLE := 0.2
## Local y of the apron tops: just under the plateau, so the slabs cannot z-fight the terrain they overhang
## into, and well inside PlayerController.max_step_height (0.4) so the lip is free to walk over.
const APRON_TOP := -0.05
const MAX_STEP_HEIGHT := 0.4
## The pieces that are allowed to be the floor of the crypt mouth.
const MOUTH_PIECES: Array[String] = [
	"crypt_mouth_apron_w", "crypt_mouth_apron_e", "crypt_mouth_apron_n", "crypt_mouth_landing",
	"crypt_stairs",
]

var _area: Dictionary = {}
var _layout: Dictionary = {}
var _centre := Vector2.ZERO
var _plateau_radius: float = 0.0
var _entries: Dictionary = {}


func setup() -> void:
	_area = _read(AREA)
	_layout = _read(LAYOUT)
	for raw: Variant in _area.get("plateaus", []):
		if raw is Dictionary and str((raw as Dictionary).get("name", "")) == "castle":
			var c: Array = (raw as Dictionary).get("centre", [0, 0])
			_centre = Vector2(float(c[0]), float(c[1]))
			_plateau_radius = float((raw as Dictionary).get("radius", 0.0))
	for raw: Variant in _layout.get("pieces", []):
		if raw is Dictionary:
			_entries[str((raw as Dictionary).get("name", ""))] = raw


func _read(path: String) -> Dictionary:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return data as Dictionary if data is Dictionary else {}


# --- the gap the terrain actually leaves ------------------------------------------------------------------

## Cells die when their centre is inside `rect`, so the real gap is the union of those cells: the authored
## rect grown outwards to the nearest cell edges. Never smaller than what was authored.
static func snap_to_cells(rect: Rect2, world_size: float, spacing: float) -> Rect2:
	var half: float = world_size * 0.5
	var lo := Vector2(_first_edge(rect.position.x, half, spacing), _first_edge(rect.position.y, half, spacing))
	var hi := Vector2(_last_edge(rect.end.x, half, spacing), _last_edge(rect.end.y, half, spacing))
	return Rect2(lo, hi - lo)


static func _first_edge(v: float, half: float, spacing: float) -> float:
	return -half + float(ceili((v - spacing * 0.5 + half) / spacing)) * spacing


static func _last_edge(v: float, half: float, spacing: float) -> float:
	return -half + float(floori((v - spacing * 0.5 + half) / spacing) + 1) * spacing


## Every authored hole on the castle plateau, snapped and moved into the castle's local frame. The vale has
## a second hole under the Mirror Pond (tests/test_hearth_mouth.gd owns that one), so holes are picked by
## site rather than assumed to all be the castle's.
func _local_gaps() -> Array[Rect2]:
	var out: Array[Rect2] = []
	var size: float = float(_area.get("size", 1024.0))
	for raw: Variant in _area.get("holes", []):
		if not raw is Array or (raw as Array).size() < 4:
			continue
		var r: Array = raw
		var world := Rect2(float(r[0]), float(r[1]), float(r[2]), float(r[3])).abs()
		if world.get_center().distance_to(_centre) > _plateau_radius:
			continue
		var snapped: Rect2 = snap_to_cells(world, size, LOD0_SPACING)
		out.append(Rect2(snapped.position - _centre, snapped.size))
	return out


# --- ground footprints of the pieces that do the covering -------------------------------------------------

## The piece's ground footprint in its own space, before placement. Walls are as deep as they are thick; a
## flight of stairs runs from its origin toward local -Z, so its footprint is not centred on the origin.
static func local_footprint(kind: String, p: Dictionary) -> Rect2:
	var w: float = float(p.get("w", 0.0))
	match kind:
		"floor_slab", "block":
			var d: float = float(p.get("d", 0.0))
			return Rect2(-w * 0.5, -d * 0.5, w, d)
		"wall", "broken_wall":
			var t: float = float(p.get("t", 0.0))
			return Rect2(-w * 0.5, -t * 0.5, w, t)
		"stairs":
			return Rect2(-w * 0.5, -stair_run(p), w, stair_run(p))
	return Rect2()


## Must mirror StructureKit.stairs: the riser is capped, then rounded up to a whole number of steps.
static func stair_run(p: Dictionary) -> float:
	var capped: float = minf(float(p.get("riser", StructureKit.DEFAULT_RISER)), StructureKit.MAX_RISER)
	var steps: int = maxi(1, ceili(float(p.get("rise", 0.0)) / capped - 0.001))
	return float(p.get("tread", StructureKit.DEFAULT_TREAD)) * float(steps)


## Footprint placed into structure-local space. Only quarter-turn yaws keep this exact (a diagonal piece
## would need its real outline, and a bounding box would claim ground it does not cover), so callers assert
## the yaw first with is_quarter_turn.
static func placed_footprint(entry: Dictionary) -> Rect2:
	var local: Rect2 = local_footprint(str(entry.get("kind", "")), entry.get("params", {}))
	var t: Transform3D = StructureBuilder.placements_of(entry)[0]
	var a: Vector3 = t * Vector3(local.position.x, 0.0, local.position.y)
	var b: Vector3 = t * Vector3(local.end.x, 0.0, local.end.y)
	return Rect2(Vector2(minf(a.x, b.x), minf(a.z, b.z)), Vector2(absf(b.x - a.x), absf(b.z - a.z)))


static func is_quarter_turn(entry: Dictionary) -> bool:
	return absf(fposmod(float(entry.get("yaw", 0.0)), 90.0)) < 0.001


func _mouth_cover() -> Array[Rect2]:
	var out: Array[Rect2] = []
	for name: String in MOUTH_PIECES:
		if _entries.has(name):
			out.append(placed_footprint(_entries[name]))
	return out


# A point is floored when some covering footprint contains it. Rect2.has_point excludes the far edges, so
# butted slabs would leave hairline false gaps; grow each rect by half a sample instead.
static func _covered(cover: Array[Rect2], x: float, z: float) -> bool:
	for r: Rect2 in cover:
		if r.grow(SAMPLE * 0.5).has_point(Vector2(x, z)):
			return true
	return false


# --- tests ------------------------------------------------------------------------------------------------

func test_the_data_still_describes_one_hole_under_the_castle() -> void:
	assert_ne(_centre, Vector2.ZERO, "the vale defines a castle plateau to measure against")
	var gaps: Array[Rect2] = _local_gaps()
	assert_eq(gaps.size(), 1, "exactly one terrain hole on the castle plateau, the crypt")
	for name: String in MOUTH_PIECES:
		assert_true(_entries.has(name), "the castle layout still has piece '%s'" % name)


func test_the_hole_snaps_outwards_and_is_bigger_than_it_looks() -> void:
	# The whole bug in one assertion: what you author is not what the ground loses.
	var authored := Rect2(207.5, -182.5, 6.0, 9.0)
	var snapped: Rect2 = snap_to_cells(authored, 1024.0, LOD0_SPACING)
	assert_eq(snapped, Rect2(208.0, -182.0, 6.0, 8.0), "the authored rect snaps to whole terrain cells")
	assert_true(snapped.encloses(authored.grow(-0.5)), "snapping never shrinks below the authored rect")
	var gaps: Array[Rect2] = _local_gaps()
	if gaps.is_empty():
		return
	assert_eq(gaps[0], Rect2(8.0, -22.0, 6.0, 8.0), "in castle-local metres the gap is x 8..14, z -22..-14")


func test_every_covering_piece_is_a_quarter_turn() -> void:
	# placed_footprint is only exact for quarter turns; a diagonal piece would silently over-claim ground.
	for name: String in MOUTH_PIECES:
		if _entries.has(name):
			assert_true(is_quarter_turn(_entries[name]), "piece '%s' is placed on a quarter turn" % name)


func test_the_crypt_mouth_is_floored_everywhere_except_the_stair_opening() -> void:
	# The regression. Walk a 0.2 m grid over the real gap; every sample must stand on something.
	var gaps: Array[Rect2] = _local_gaps()
	if gaps.is_empty():
		return
	var gap: Rect2 = gaps[0]
	var cover: Array[Rect2] = _mouth_cover()
	var open: int = 0
	var first := Vector2.ZERO
	var x: float = gap.position.x + SAMPLE * 0.5
	while x < gap.end.x:
		var z: float = gap.position.y + SAMPLE * 0.5
		while z < gap.end.y:
			if not _covered(cover, x, z):
				if open == 0:
					first = Vector2(x, z)
				open += 1
			z += SAMPLE
		x += SAMPLE
	assert_eq(open, 0, "no open ground in the crypt mouth (%d samples, first at %s)" % [open, first])


func test_the_stair_flight_is_as_wide_as_the_shaft() -> void:
	# At 1.6 m wide a 0.45 m slot was left down each side of the flight, open to the crypt floor 4.6 m below.
	var west: Dictionary = _entries.get("crypt_shaft_w", {})
	var east: Dictionary = _entries.get("crypt_shaft_e", {})
	var stairs: Dictionary = _entries.get("crypt_stairs", {})
	if west.is_empty() or east.is_empty() or stairs.is_empty():
		assert_true(false, "the crypt shaft walls and stairs are all present")
		return
	var inner: float = absf(float(east["at"][0]) - float(west["at"][0])) \
			- (float(east["params"]["t"]) + float(west["params"]["t"])) * 0.5
	assert_true(float(stairs["params"]["w"]) >= inner - 0.001,
			"the flight spans the shaft wall to wall (%.2f >= %.2f)" % [float(stairs["params"]["w"]), inner])


func test_the_doorway_opens_onto_the_landing_and_not_the_shaft() -> void:
	# Stepping through the crypt house door used to mean a 0.75 m stride over nothing before the top tread.
	var door: Dictionary = _entries.get("crypt_house_s", {})
	var stairs: Dictionary = _entries.get("crypt_stairs", {})
	if door.is_empty() or stairs.is_empty():
		assert_true(false, "the crypt house doorway and stairs are both present")
		return
	var opening: Dictionary = door["params"].get("opening", {})
	var half_w: float = float(opening.get("width", 0.0)) * 0.5
	var mid_x: float = float(door["at"][0]) + float(opening.get("offset", 0.0))
	# Inner face of the doorway through to the top tread, which sits `run` from the flight's origin.
	var inner_z: float = float(door["at"][2]) - float(door["params"]["t"]) * 0.5
	var tread_z: float = float(stairs["at"][2]) + stair_run(stairs["params"])
	var cover: Array[Rect2] = _mouth_cover()
	var gap_samples: int = 0
	var x: float = mid_x - half_w + SAMPLE * 0.5
	while x < mid_x + half_w:
		var z: float = tread_z
		while z < inner_z:
			if not _covered(cover, x, z):
				gap_samples += 1
			z += SAMPLE
		x += SAMPLE
	assert_true(tread_z < inner_z, "the top tread stops short of the doorway, so a landing is needed")
	assert_eq(gap_samples, 0, "the doorway threshold is solid all the way to the top tread")


func test_the_apron_sits_a_step_below_the_plateau_without_touching_it() -> void:
	# Flush with the plateau would z-fight where the slabs overhang onto real terrain; too far down would be
	# a drop the player has to climb back out of.
	for name: String in ["crypt_mouth_apron_w", "crypt_mouth_apron_e", "crypt_mouth_apron_n",
			"crypt_mouth_landing"]:
		if not _entries.has(name):
			continue
		var e: Dictionary = _entries[name]
		var top: float = float(e["at"][1]) + float(e["params"]["t"])
		assert_true(is_equal_approx(top, APRON_TOP), "%s tops out at %.3f, not %.3f" % [name, top, APRON_TOP])
		assert_true(absf(top) < MAX_STEP_HEIGHT, "%s is within one step of the plateau" % name)
		assert_true(top < 0.0, "%s is not coplanar with the plateau" % name)
