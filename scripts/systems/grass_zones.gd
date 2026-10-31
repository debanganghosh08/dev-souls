class_name GrassZones
extends RefCounted
## Where each kind of grass grows and what colour it is, as data (W8-G, docs/WORLD_PLAN.md section 4).
## data/grass/zones_<area>.json lists zones in paint order; each has a shape (a soft region of the map)
## and the channels it sets: density (times the meadow's), blade height, how much tall grass and how many
## wildflowers, and a root/tip palette. sample(x, z) paints them in order, lerping each channel by the
## zone's weight, so zones blend over their feathers instead of meeting at an edge; on top goes a slow
## colour noise across the valley so no two fields are quite the same green. Pure: no nodes, only the
## Heightfield (plateaus, pond, the old road's polyline, ground height), so tests can sample it directly.
## Every number in the data is for the owner to retune by eye; headless proves density and coverage only.

enum Shape { BASE, NOISE, RECT, RING, TOP, SKIRT, HEIGHT, ROAD }

const DEFAULT_ROOT := Color("#2f3a1e")
const DEFAULT_TIP := Color("#9a9a52")
const MIN_FEATHER := 0.01

## Result of the last sample(): read straight after the call. density is a multiplier on the meadow's
## (1.0), height on the blade height, tall and flowers are 0..1 weights for those layers.
var density: float = 1.0
var height: float = 1.0
var tall: float = 0.0
var flowers: float = 0.0
var root: Color = DEFAULT_ROOT
var tip: Color = DEFAULT_TIP

var _hf: Heightfield
var _zones: Array[Dictionary] = []
var _road: PackedVector2Array = PackedVector2Array()
var _road_half: float = 2.5
var _road_feather: float = 4.0
# The box the road fits in, grown by how far its zone reaches. See road_distance.
var _road_box: Rect2 = Rect2()
var _max_density: float = 1.0
var _green: FastNoiseLite
var _light: FastNoiseLite
var _green_amount: float = 0.0
var _light_amount: float = 0.0


static func load_file(path: String, hf: Heightfield) -> GrassZones:
	var data: Dictionary = Terrain.load_data(path)
	return from_dict(data, hf) if not data.is_empty() else null


static func from_dict(data: Dictionary, hf: Heightfield) -> GrassZones:
	var zones := GrassZones.new()
	zones._hf = hf
	var seed_v: int = int(data.get("seed", 20261024))
	var road: Dictionary = data.get("road", {})
	zones._road_half = maxf(0.0, float(road.get("half_width", 2.5)))
	zones._road_feather = maxf(MIN_FEATHER, float(road.get("feather", 4.0)))
	var waypoints: Variant = road.get("waypoints", "valley")
	if waypoints is String and hf != null:
		waypoints = (hf.config().get("valley", {}) as Dictionary).get("waypoints", [])
	if waypoints is Array:
		for wp: Variant in waypoints:
			if wp is Array and (wp as Array).size() >= 2:
				zones._road.append(Vector2(float(wp[0]), float(wp[1])))
	if zones._road.size() >= 2:
		zones._road_box = Rect2(zones._road[0], Vector2.ZERO)
		for q: Vector2 in zones._road:
			zones._road_box = zones._road_box.expand(q)
		zones._road_box = zones._road_box.grow(zones._road_half + zones._road_feather + 1.0)
	var noise: Dictionary = data.get("colour_noise", {})
	zones._green_amount = clampf(float(noise.get("green", 0.0)), 0.0, 1.0)
	zones._light_amount = clampf(float(noise.get("light", 0.0)), 0.0, 1.0)
	zones._green = _noise(seed_v + 17, float(noise.get("frequency", 0.005)))
	zones._light = _noise(seed_v + 29, float(noise.get("frequency", 0.005)) * 0.7)
	var index: int = 0
	for raw: Variant in data.get("zones", []):
		if not raw is Dictionary:
			continue
		var zone: Dictionary = zones._parse_zone(raw, seed_v, index)
		if not zone.is_empty():
			zones._zones.append(zone)
			if zone["has_density"]:
				zones._max_density = maxf(zones._max_density, float(zone["density"]))
		index += 1
	return zones


## The largest density any zone asks for: a layer sizes its candidate pool by this so the densest zone can
## actually reach it (an accept probability cannot exceed 1).
func max_density() -> float:
	return _max_density


func zone_names() -> Array[String]:
	var out: Array[String] = []
	for zone: Dictionary in _zones:
		out.append(str(zone["name"]))
	return out


## Distance to the old road's centre line, INF when the area has no road.
## How far (x, z) is from the old road. Every grass cell asks this for each of the 81 points in its
## height grid, for the road zone, and the road is four segments -- so a box round it answers for
## most of the Vale without any of that, and the answer only has to be exact where the zone can
## actually reach (it fades out at _road_half + _road_feather).
func road_distance(x: float, z: float) -> float:
	if _road.size() < 2:
		return INF
	var p := Vector2(x, z)
	if not _road_box.has_point(p):
		return INF
	var best: float = INF
	for i: int in _road.size() - 1:
		best = minf(best, p.distance_to(Geometry2D.get_closest_point_to_segment(p, _road[i], _road[i + 1])))
	return best


## Each zone's 0..1 weight at (x, z), by name. For tests and tuning; the hot path is sample().
func weights(x: float, z: float) -> Dictionary:
	var out: Dictionary = {}
	var p := Vector2(x, z)
	for zone: Dictionary in _zones:
		out[zone["name"]] = _weight(zone, p)
	return out


func density_at(x: float, z: float) -> float:
	sample(x, z)
	return density


## The tip colour at (x, z) after the zone palettes and the colour noise.
func tint_at(x: float, z: float) -> Color:
	sample(x, z)
	return tip


## Paints every zone in order into the result fields. No allocation: the lattice calls this per grid node.
func sample(x: float, z: float) -> void:
	density = 1.0
	height = 1.0
	tall = 0.0
	flowers = 0.0
	root = DEFAULT_ROOT
	tip = DEFAULT_TIP
	if is_nan(x) or is_nan(z) or is_inf(x) or is_inf(z):
		density = 0.0
		return
	var p := Vector2(x, z)
	for zone: Dictionary in _zones:
		# _weight, inlined: this runs 25 times per lattice cell and a call per zone was a tenth of the cost.
		var w: float = 1.0
		for shape: Dictionary in zone["shapes"]:
			w *= _shape_weight(shape, p)
			if w <= 0.0:
				break
		if w <= 0.0:
			continue
		if zone["has_density"]:
			density = lerpf(density, float(zone["density"]), w)
		if zone["has_height"]:
			height = lerpf(height, float(zone["height"]), w)
		if zone["has_tall"]:
			tall = lerpf(tall, float(zone["tall"]), w)
		if zone["has_flowers"]:
			flowers = lerpf(flowers, float(zone["flowers"]), w)
		if zone["has_palette"]:
			root = root.lerp(zone["root"], w)
			tip = tip.lerp(zone["tip"], w)
	# Slow colour drift: one noise pushes toward green or toward gold, another lightens or darkens, both
	# over hundreds of metres, so a field reads as one colour and the next field as a slightly different one.
	if _green_amount > 0.0 or _light_amount > 0.0:
		var g: float = _green.get_noise_2d(x, z) * _green_amount
		var l: float = 1.0 + _light.get_noise_2d(x, z) * _light_amount
		var m := Color((1.0 - 0.6 * g) * l, (1.0 + 0.5 * g) * l, (1.0 - 0.3 * g) * l, 1.0)
		root = root * m
		tip = tip * m
		root.a = 1.0
		tip.a = 1.0


func _weight(zone: Dictionary, p: Vector2) -> float:
	var w: float = 1.0
	for shape: Dictionary in zone["shapes"]:
		w *= _shape_weight(shape, p)
		if w <= 0.0:
			return 0.0
	return w


func _shape_weight(s: Dictionary, p: Vector2) -> float:
	var f: float = s.get("feather", MIN_FEATHER)
	match int(s["type"]):
		Shape.BASE:
			return 1.0
		Shape.NOISE:
			return smoothstep(float(s["lo"]), float(s["hi"]), (s["noise"] as FastNoiseLite).get_noise_2d(p.x, p.y))
		Shape.RECT:
			var mn: Vector2 = s["min"]
			var mx: Vector2 = s["max"]
			return _inside(mn.x, mx.x, f, p.x) * _inside(mn.y, mx.y, f, p.y)
		Shape.RING:
			var d: float = p.distance_to(s["centre"])
			var w: float = 1.0 - smoothstep(float(s["outer"]), float(s["outer"]) + f, d)
			if float(s["inner"]) > 0.0:
				w *= smoothstep(float(s["inner"]) - f, float(s["inner"]), d)
			return w
		Shape.TOP:
			var d: float = p.distance_to(s["centre"])
			return 1.0 - smoothstep(float(s["radius"]) - f, float(s["radius"]) + f, d)
		Shape.SKIRT:
			# From the plateau's rim down its whole blend: the castle hill the owner climbs.
			var d: float = p.distance_to(s["centre"])
			var r: float = float(s["radius"])
			var foot: float = r + float(s["blend"])
			return smoothstep(r - f, r + f, d) * (1.0 - smoothstep(foot, foot + f, d))
		Shape.HEIGHT:
			if _hf == null:
				return 0.0
			return smoothstep(float(s["lo"]), float(s["hi"]), _hf.height_at(p.x, p.y))
		Shape.ROAD:
			return 1.0 - smoothstep(_road_half, _road_half + _road_feather, road_distance(p.x, p.y))
	return 0.0


## 1 inside lo..hi, feathering to 0 over `f` outside it.
static func _inside(lo: float, hi: float, f: float, v: float) -> float:
	return smoothstep(lo - f, lo, v) * (1.0 - smoothstep(hi, hi + f, v))


func _parse_zone(d: Dictionary, seed_v: int, index: int) -> Dictionary:
	var zone: Dictionary = {"name": str(d.get("name", "zone%d" % index)), "shapes": [] as Array[Dictionary]}
	var raw_shapes: Variant = d.get("shapes", [d.get("shape", {"type": "base"})])
	if raw_shapes is Dictionary:
		raw_shapes = [raw_shapes]
	for raw: Variant in raw_shapes:
		if raw is Dictionary:
			var shape: Dictionary = _parse_shape(raw, seed_v, index)
			if shape.is_empty():
				push_error("GrassZones: zone %s has a bad shape %s" % [zone["name"], raw])
				return {}
			(zone["shapes"] as Array[Dictionary]).append(shape)
	for channel: String in ["density", "height", "tall", "flowers"]:
		zone["has_" + channel] = d.has(channel)
		zone[channel] = maxf(0.0, float(d.get(channel, 0.0)))
	zone["has_palette"] = d.has("root") and d.has("tip")
	zone["root"] = _color(d.get("root"), DEFAULT_ROOT)
	zone["tip"] = _color(d.get("tip"), DEFAULT_TIP)
	return zone


func _parse_shape(d: Dictionary, seed_v: int, index: int) -> Dictionary:
	var out: Dictionary = {"feather": maxf(MIN_FEATHER, float(d.get("feather", MIN_FEATHER)))}
	match str(d.get("type", "base")):
		"base":
			out["type"] = Shape.BASE
		"noise":
			out["type"] = Shape.NOISE
			out["noise"] = _noise(seed_v + 131 * (index + 1), float(d.get("frequency", 0.01)))
			var range_v: Vector2 = _range(d.get("range"), Vector2(0.2, 0.5))
			out["lo"] = range_v.x
			out["hi"] = range_v.y
		"rect":
			out["type"] = Shape.RECT
			out["min"] = _vec2(d.get("min"))
			out["max"] = _vec2(d.get("max"))
		"ring":
			out["type"] = Shape.RING
			out["centre"] = _centre(d.get("centre", [0, 0]))
			out["inner"] = maxf(0.0, float(d.get("inner", 0.0)))
			out["outer"] = maxf(0.0, float(d.get("outer", 0.0)))
		"top", "skirt":
			var plateau: Dictionary = _plateau(str(d.get("plateau", "")))
			if plateau.is_empty():
				return {}
			out["type"] = Shape.TOP if str(d["type"]) == "top" else Shape.SKIRT
			out["centre"] = plateau["centre"]
			out["radius"] = float(plateau["radius"])
			out["blend"] = float(plateau["blend"])
		"height":
			out["type"] = Shape.HEIGHT
			var range_v: Vector2 = _range(d.get("range"), Vector2(0.0, 1.0))
			out["lo"] = range_v.x
			out["hi"] = range_v.y
		"road":
			out["type"] = Shape.ROAD
		_:
			return {}
	return out


## A ring or disc centre: [x, z], "pond", or "plateau:<name>".
func _centre(v: Variant) -> Vector2:
	if v is String:
		if v == "pond" and _hf != null:
			return _hf.pond_centre()
		if (v as String).begins_with("plateau:"):
			var plateau: Dictionary = _plateau((v as String).trim_prefix("plateau:"))
			if not plateau.is_empty():
				return plateau["centre"]
		return Vector2.ZERO
	return _vec2(v)


func _plateau(name: String) -> Dictionary:
	if _hf == null:
		return {}
	for site: Dictionary in _hf.plateaus():
		if str(site.get("name", "")) == name:
			return site
	return {}


static func _noise(seed_v: int, frequency: float) -> FastNoiseLite:
	var n := FastNoiseLite.new()
	n.seed = seed_v
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.fractal_type = FastNoiseLite.FRACTAL_NONE
	n.frequency = maxf(0.0001, frequency)
	return n


static func _vec2(v: Variant) -> Vector2:
	if v is Array and (v as Array).size() >= 2:
		return Vector2(float(v[0]), float(v[1]))
	return Vector2.ZERO


static func _range(v: Variant, fallback: Vector2) -> Vector2:
	if v is Array and (v as Array).size() >= 2:
		return Vector2(float(v[0]), float(v[1]))
	return fallback


static func _color(v: Variant, fallback: Color) -> Color:
	if v is String and Color.html_is_valid(v):
		return Color.html(v)
	return fallback
