extends "res://tests/test_case.gd"
## The rule the whole of docs/WORLD_PLAN.md was built on, as a number: from anywhere a player can walk in the
## Vale, something built -- a house, a shrine, a cairn, a camp -- should be close enough to walk to. The owner's
## complaint was "the game feels too empty", and emptiness is distance to the nearest thing worth reaching.
##
## Walkable here means inside the ridge, out of the water and gentler than 35 degrees, sampled every 10 m.
## Distance is to the nearest point of any built footprint, not to a site's centre, so a long wall counts along
## its length. The thresholds sit a little under what the map measured when they were set (2026-10-27), so
## moving or deleting a handful of sites fails this, and the failure names the emptiest spot.

const STEP := 10.0
const RIDGE_MARGIN := 30.0
const MAX_SLOPE := 35.0
## Measured on 2026-10-27 after W8-H, W8-P and eleven rim fillers: 99.9 % within 80 m, 100 % within 120 m,
## the emptiest spot 83 m from anything (docs/DECISIONS.md D-023). Before the fillers: 90.3 % and 137 m.
const WITHIN_80M := 0.99
const WITHIN_120M := 0.999
const WORST_ALLOWED := 95.0

var _hf: Heightfield
var _obbs: Array[Dictionary] = []


func setup() -> void:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/areas/vale.json"))
	_hf = Heightfield.from_dict(data as Dictionary)
	for site: Dictionary in SiteRegistry.load_area("vale"):
		_obbs.append_array(SiteRegistry.world_obbs(site))


## Distance from p to the nearest point of any footprint. Public so the measurement can be reproduced.
static func nearest_built(p: Vector2, obbs: Array[Dictionary]) -> float:
	var best: float = INF
	for obb: Dictionary in obbs:
		var d: Vector2 = p - Vector2(obb["centre"])
		var a: float = maxf(absf(d.dot(obb["ux"])) - float(obb["hx"]), 0.0)
		var b: float = maxf(absf(d.dot(obb["uz"])) - float(obb["hz"]), 0.0)
		best = minf(best, sqrt(a * a + b * b))
	return best


func _walkable_distances() -> Dictionary:
	var dists: Array[float] = []
	var worst := Vector2.ZERO
	var worst_d: float = 0.0
	var limit: float = _hf.ridge_inner_radius() - RIDGE_MARGIN
	var x: float = -limit
	while x <= limit:
		var z: float = -limit
		while z <= limit:
			var p := Vector2(x, z)
			z += STEP
			if p.length() > limit or _hf.height_at(p.x, p.y) < _hf.water_level() + 0.3 \
					or _hf.slope_at(p.x, p.y) > MAX_SLOPE:
				continue
			var d: float = nearest_built(p, _obbs)
			dists.append(d)
			if d > worst_d:
				worst_d = d
				worst = p
		x += STEP
	return {"dists": dists, "worst": worst, "worst_d": worst_d}


static func fraction_within(dists: Array[float], r: float) -> float:
	if dists.is_empty():
		return 0.0
	var n: int = 0
	for d: float in dists:
		if d <= r:
			n += 1
	return float(n) / float(dists.size())


func test_almost_everywhere_has_something_built_within_walking_reach() -> void:
	var m: Dictionary = _walkable_distances()
	var dists: Array[float] = m["dists"]
	assert_true(dists.size() > 3000, "the Vale has walkable ground to measure (%d points)" % dists.size())
	var w80: float = fraction_within(dists, 80.0)
	var w120: float = fraction_within(dists, 120.0)
	assert_true(w80 >= WITHIN_80M, "%.1f%% of walkable ground is within 80 m of something built (need %.1f%%)"
			% [w80 * 100.0, WITHIN_80M * 100.0])
	assert_true(w120 >= WITHIN_120M, "%.1f%% within 120 m (need %.1f%%)" % [w120 * 100.0, WITHIN_120M * 100.0])
	assert_true(float(m["worst_d"]) <= WORST_ALLOWED, "the emptiest walkable spot, %s, is %.0f m from anything (limit %.0f)"
			% [m["worst"], m["worst_d"], WORST_ALLOWED])


func test_the_measure_is_distance_to_the_nearest_wall_not_to_a_centre() -> void:
	var wall: Array[Dictionary] = [{"centre": Vector2.ZERO, "ux": Vector2.RIGHT, "uz": Vector2(0.0, 1.0), "hx": 20.0, "hz": 0.5}]
	assert_true(is_equal_approx(nearest_built(Vector2(15.0, 10.5), wall), 10.0), "beside a long wall, its face is near")
	assert_true(is_equal_approx(nearest_built(Vector2(0.0, 0.0), wall), 0.0), "inside a footprint is distance zero")
	var none: Array[float] = []
	assert_eq(fraction_within(none, 80.0), 0.0, "nothing measured is not full coverage")
