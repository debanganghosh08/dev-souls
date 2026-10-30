class_name Heightfield
extends RefCounted
## The authoritative shape of an area's ground. Pure maths: no nodes, no singletons, no global RNG, so the
## same data/areas/*.json always yields the same land and tests can sample it without a scene. Everything
## that needs the ground (terrain meshes, collision, scatter, spawn, trees) samples this; nothing else may
## invent a height.
##
## Layers, in the order they compose (see height_at):
##   1. noise    fractal FastNoiseLite -> rolling hills, the only non-analytic term
##   2. valley   a channel along a waypoint polyline that calms and lowers the NOISE: the natural route.
##               It acts on the noise alone so it cannot lift the pond floor back up (it did, once).
##   3. basin    radial bowl pulling the ground down to the Mirror Pond floor (pond floor flattened)
##   4. ridge    boundary ring rising steeply past the player's 45 deg floor limit, a wall without a wall
##   5. plateaus village and castle sites lerped to a level height with a smoothstep skirt
## Plateaus are a blend toward a target, not additive, so they come last: a site stays level whatever
## lies beneath it and its skirt blends into the ridge foot instead of being lifted by it.

const NORMAL_EPS := 0.5
const DEFAULT_SIZE := 1024.0

var _config: Dictionary = {}
var _half: float = DEFAULT_SIZE * 0.5
var _noise: FastNoiseLite
var _wobble: FastNoiseLite
var _amplitude: float = 0.0
var _water: float = 0.0
var _pond_centre := Vector2.ZERO
var _pond_radius: float = 0.0
var _pond_falloff: float = 0.0
var _pond_depth: float = 0.0
var _pond_flatten: float = 0.75
var _valley: PackedVector2Array = PackedVector2Array()
var _valley_width: float = 0.0
var _valley_blend: float = 0.0
var _valley_depth: float = 0.0
var _valley_flatten: float = 0.0
var _plateaus: Array[Dictionary] = []
## Lines of raised ground (W12). Each is {points, height, half_width, blend}: within half_width of the
## polyline the ground stands `height` above whatever was there, falling to nothing over `blend`. A closed
## ring walls in a valley; a gap left in the ring is the only way into it. Applied BEFORE plateaus, so the
## village and castle sites still flatten whatever a crest did underneath them.
var _crests: Array[Dictionary] = []
# World-space rectangles where the terrain is omitted entirely — mesh and collision — so built structures can
# descend below the surface (the castle crypt, later the Wood's drowned shrine and the Barrens' caves).
# Whatever is built there must enclose the opening itself; the terrain simply stops.
var _holes: Array[Rect2] = []
var _ridge_inner: float = 0.0
var _ridge_outer: float = 0.0
var _ridge_height: float = 0.0
var _ridge_wobble: float = 0.0


static func from_dict(data: Dictionary) -> Heightfield:
	var hf := Heightfield.new()
	hf._config = data.duplicate(true)
	hf._half = maxf(0.5, float(data.get("size", DEFAULT_SIZE)) * 0.5)
	var seed_v: int = int(data.get("seed", 1))
	var noise: Dictionary = data.get("noise", {})
	hf._noise = FastNoiseLite.new()
	hf._noise.seed = seed_v
	hf._noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	hf._noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	hf._noise.fractal_octaves = clampi(int(noise.get("octaves", 4)), 1, 9)
	hf._noise.frequency = maxf(0.0, float(noise.get("frequency", 0.003)))
	hf._noise.fractal_lacunarity = float(noise.get("lacunarity", 2.0))
	hf._noise.fractal_gain = float(noise.get("gain", 0.5))
	hf._amplitude = float(noise.get("amplitude", 10.0)) if int(noise.get("octaves", 4)) > 0 else 0.0
	for raw: Variant in data.get("holes", []):
		if raw is Array and (raw as Array).size() == 4:
			var r: Array = raw
			var w: float = absf(float(r[2]))
			var h: float = absf(float(r[3]))
			if w > 0.0 and h > 0.0:
				hf._holes.append(Rect2(float(r[0]), float(r[1]), w, h))
	hf._water = float(data.get("water_level", 0.0))
	var pond: Dictionary = data.get("pond", {})
	hf._pond_centre = _vec2(pond.get("centre", [0, 0]))
	hf._pond_radius = maxf(0.0, float(pond.get("radius", 0.0)))
	hf._pond_falloff = maxf(hf._pond_radius, float(pond.get("falloff", 0.0)))
	hf._pond_depth = float(pond.get("depth", 0.0))
	var valley: Dictionary = data.get("valley", {})
	for wp: Variant in valley.get("waypoints", []):
		hf._valley.append(_vec2(wp))
	hf._valley_width = maxf(0.0, float(valley.get("width", 0.0)))
	hf._valley_blend = maxf(0.0, float(valley.get("blend", 0.0)))
	hf._valley_depth = float(valley.get("depth", 0.0))
	hf._valley_flatten = clampf(float(valley.get("flatten", 0.0)), 0.0, 1.0)
	for raw: Variant in data.get("crests", []):
		if not raw is Dictionary:
			continue
		var crest: Dictionary = raw
		var pts := PackedVector2Array()
		for point: Variant in crest.get("points", []):
			pts.append(_vec2(point))
		if pts.size() >= 2:
			hf._crests.append({"name": str(crest.get("name", "")), "points": pts,
				"height": float(crest.get("height", 0.0)),
				"half_width": maxf(0.5, float(crest.get("half_width", 8.0))),
				"blend": maxf(1.0, float(crest.get("blend", 30.0)))})
	for p: Variant in data.get("plateaus", []):
		if p is Dictionary:
			hf._plateaus.append({"centre": _vec2(p.get("centre", [0, 0])), "radius": maxf(0.0, float(p.get("radius", 0.0))),
				"height": float(p.get("height", 0.0)), "blend": maxf(0.0, float(p.get("blend", 0.0))), "name": str(p.get("name", ""))})
	var ridge: Dictionary = data.get("ridge", {})
	hf._ridge_inner = maxf(0.0, float(ridge.get("inner_radius", 0.0)))
	hf._ridge_outer = maxf(hf._ridge_inner, float(ridge.get("outer_radius", 0.0)))
	hf._ridge_height = float(ridge.get("height", 0.0))
	hf._ridge_wobble = float(ridge.get("wobble", 0.0))
	hf._wobble = FastNoiseLite.new()
	hf._wobble.seed = seed_v + 1
	hf._wobble.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	hf._wobble.frequency = maxf(0.0, float(ridge.get("wobble_frequency", 0.004)))
	return hf


static func _vec2(v: Variant) -> Vector2:
	if v is Array and (v as Array).size() >= 2:
		return Vector2(float(v[0]), float(v[1]))
	return Vector2.ZERO


## Division-free smoothstep: a degenerate edge pair becomes a hard step, never NaN.
static func _smooth(edge0: float, edge1: float, x: float) -> float:
	if edge1 - edge0 <= 0.000001:
		return 0.0 if x < edge1 else 1.0
	var t: float = clampf((x - edge0) / (edge1 - edge0), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


func config() -> Dictionary:
	return _config


func size() -> float:
	return _half * 2.0


func water_level() -> float:
	return _water


func pond_centre() -> Vector2:
	return _pond_centre


func pond_falloff() -> float:
	return _pond_falloff


func plateaus() -> Array[Dictionary]:
	return _plateaus


func ridge_inner_radius() -> float:
	return _ridge_inner


func height_at(x: float, z: float) -> float:
	var px: float = clampf(x, -_half, _half)
	var pz: float = clampf(z, -_half, _half)
	var h: float = _channel(px, pz, _noise.get_noise_2d(px, pz) * _amplitude)
	h = _basin(px, pz, h)
	h += _ridge(px, pz)
	h = _crest(px, pz, h)
	h = _plateau(px, pz, h)
	return 0.0 if is_nan(h) or is_inf(h) else h


func _basin(px: float, pz: float, h: float) -> float:
	var d: float = Vector2(px, pz).distance_to(_pond_centre)
	var t: float = 1.0 - _smooth(_pond_radius, _pond_falloff, d)
	return lerpf(h, h * (1.0 - _pond_flatten) - _pond_depth, t)


func _ridge(px: float, pz: float) -> float:
	var d: float = Vector2(px, pz).length() + _wobble.get_noise_2d(px, pz) * _ridge_wobble
	return _smooth(_ridge_inner, _ridge_outer, d) * _ridge_height


func _channel(px: float, pz: float, h: float) -> float:
	if _valley.size() < 2:
		return h
	var p := Vector2(px, pz)
	var best: float = INF
	for i: int in _valley.size() - 1:
		best = minf(best, p.distance_to(Geometry2D.get_closest_point_to_segment(p, _valley[i], _valley[i + 1])))
	var w: float = 1.0 - _smooth(_valley_width, _valley_width + _valley_blend, best)
	return lerpf(h, h * (1.0 - _valley_flatten) - _valley_depth, w)


## The tallest crest wins rather than the sum of them: two ridges crossing should make a saddle, not a
## tower twice the height of either.
func _crest(px: float, pz: float, h: float) -> float:
	if _crests.is_empty():
		return h
	var p := Vector2(px, pz)
	var raise_by: float = 0.0
	for crest: Dictionary in _crests:
		var line: PackedVector2Array = crest["points"]
		var d: float = INF
		for i: int in line.size() - 1:
			d = minf(d, p.distance_to(Geometry2D.get_closest_point_to_segment(p, line[i], line[i + 1])))
		var half: float = crest["half_width"]
		var t: float = 1.0 - _smooth(half, half + float(crest["blend"]), d)
		raise_by = maxf(raise_by, float(crest["height"]) * t)
	return h + raise_by


func crests() -> Array[Dictionary]:
	return _crests


func _plateau(px: float, pz: float, h: float) -> float:
	var p := Vector2(px, pz)
	for site: Dictionary in _plateaus:
		var d: float = p.distance_to(site["centre"])
		var r: float = site["radius"]
		var w: float = 1.0 - _smooth(r, r + float(site["blend"]), d)
		h = lerpf(h, float(site["height"]), w)
	return h


## Finite-difference normal; y is always > 0 so the result can never be degenerate.
func normal_at(x: float, z: float) -> Vector3:
	var dx: float = height_at(x + NORMAL_EPS, z) - height_at(x - NORMAL_EPS, z)
	var dz: float = height_at(x, z + NORMAL_EPS) - height_at(x, z - NORMAL_EPS)
	return Vector3(-dx, 2.0 * NORMAL_EPS, -dz).normalized()


func slope_at(x: float, z: float) -> float:
	return rad_to_deg(acos(clampf(normal_at(x, z).y, -1.0, 1.0)))


func is_underwater(x: float, z: float) -> bool:
	return height_at(x, z) < _water


func sample_walkable(x: float, z: float, max_slope_deg: float) -> bool:
	return not is_underwater(x, z) and slope_at(x, z) <= max_slope_deg


## Walks outward from `from` along `direction` and returns the first point that is dry by `clearance`
## and gentler than `max_slope`; the farthest candidate if none qualifies, so a spawn always exists.
func find_walkable(from: Vector2, direction: Vector2, min_distance: float, max_distance: float, step: float,
		max_slope: float, clearance: float) -> Vector3:
	var dir: Vector2 = direction.normalized() if direction.length_squared() > 0.0 else Vector2.RIGHT
	var stride: float = maxf(0.1, step)
	var d: float = maxf(0.0, min_distance)
	var last := Vector3.ZERO
	while d <= maxf(min_distance, max_distance):
		var p: Vector2 = from + dir * d
		var h: float = height_at(p.x, p.y)
		last = Vector3(p.x, h, p.y)
		if h >= _water + clearance and slope_at(p.x, p.y) <= max_slope:
			return last
		d += stride
	return last


## Spawn point described by the data file's "spawn" block.
func spawn_point() -> Vector3:
	var s: Dictionary = _config.get("spawn", {})
	return find_walkable(_vec2(s.get("from", [0, 0])), _vec2(s.get("direction", [1, 0])),
		float(s.get("min_distance", 0.0)), float(s.get("max_distance", 100.0)), float(s.get("step", 2.0)),
		float(s.get("max_slope", 25.0)), float(s.get("clearance", 1.0)))


func holes() -> Array[Rect2]:
	return _holes.duplicate()


## True when a world XZ point falls in a hole. Static so the mesh builder can use it without a Heightfield.
static func point_in_holes(hole_list: Array[Rect2], x: float, z: float) -> bool:
	for r: Rect2 in hole_list:
		if r.has_point(Vector2(x, z)):
			return true
	return false
