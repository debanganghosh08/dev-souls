class_name GrassCell
extends RefCounted
## Scratch context for filling one Grass lattice cell: a coarse height grid over the cell, the cell's
## hollow factor, the cluster points (trees) within reach and, when the area has GrassZones, the zones
## sampled on the same grid. Allocated once per Grass node and re-prepared per fill, so filling a cell
## costs (GRID + 1)^2 ground samples (plus as many zone samples) and one exact sample per accepted
## instance instead of five samples per candidate; everything else is bilinear maths on the grid. Zones
## blend over feathers of 4 m and more, so the 3 m grid resolves them; the exact function is in GrassZones.

const GRID := 4
const HOLLOW_SCALE := 1.5

var origin: Vector2 = Vector2.ZERO
var size: float = 1.0
var step: float = 1.0
var water_level: float = 0.0
var hollow: float = 0.0
var height_sampler: Callable = Callable()
var heights: PackedFloat32Array = PackedFloat32Array()
var cluster_points: PackedVector2Array = PackedVector2Array()
var cluster_count: int = 0
var zones: GrassZones
## Per grid node: r density as a fraction of the zones' maximum, g blade height, b tall weight, a flowers.
var zone_channels: PackedColorArray = PackedColorArray()
var zone_roots: PackedColorArray = PackedColorArray()
var zone_tips: PackedColorArray = PackedColorArray()
## The largest tall and flower weight on the grid: a layer skips the cell outright when its channel is 0.
var zone_tall_max: float = 0.0
var zone_flowers_max: float = 0.0
## Result of the last zone_at(): read straight after the call. zone_density is 0..1 of the zones' maximum.
var zone_density: float = 1.0
var zone_height: float = 1.0
var zone_tall: float = 0.0
var zone_flowers: float = 0.0
var zone_root: Color = GrassZones.DEFAULT_ROOT
var zone_tip: Color = GrassZones.DEFAULT_TIP

# Grid corner and bilinear weights of the last zone_at(), reused by zone_palette().
var _zone_a: int = 0
var _zone_fu: float = 0.0
var _zone_fv: float = 0.0


func _init() -> void:
	heights.resize((GRID + 1) * (GRID + 1))
	zone_channels.resize(heights.size())
	zone_roots.resize(heights.size())
	zone_tips.resize(heights.size())


## Samples the grid for `key`'s cell and copies the cluster points that can influence it.
func prepare(key: Vector2i, cell_size: float, sampler: Callable, water: float, clusters: PackedVector3Array, reach: float, area_zones: GrassZones = null) -> void:
	size = maxf(0.001, cell_size)
	step = size / float(GRID)
	origin = Vector2(float(key.x) * size, float(key.y) * size)
	water_level = water
	height_sampler = sampler
	zones = area_zones
	zone_tall_max = 0.0
	zone_flowers_max = 0.0
	var inv_max: float = 1.0 / maxf(0.001, zones.max_density()) if zones != null else 1.0
	for j: int in GRID + 1:
		for i: int in GRID + 1:
			var x: float = origin.x + float(i) * step
			var z: float = origin.y + float(j) * step
			var n: int = j * (GRID + 1) + i
			heights[n] = float(sampler.call(x, z))
			if zones != null:
				zones.sample(x, z)
				zone_channels[n] = Color(zones.density * inv_max, zones.height, zones.tall, zones.flowers)
				zone_roots[n] = zones.root
				zone_tips[n] = zones.tip
				zone_tall_max = maxf(zone_tall_max, zones.tall)
				zone_flowers_max = maxf(zone_flowers_max, zones.flowers)
	# Positive when the cell sits below its corners (a hollow), negative on a knoll. Pebbles and leaves
	# gather in hollows, grass thickens there; the lattice never has to ask the heightfield again.
	var corners: float = (heights[0] + heights[GRID] + heights[GRID * (GRID + 1)] + heights[heights.size() - 1]) * 0.25
	var centre: float = height(origin.x + size * 0.5, origin.y + size * 0.5)
	hollow = clampf((corners - centre) / HOLLOW_SCALE, -1.0, 1.0)
	if cluster_points.size() < clusters.size():
		cluster_points.resize(clusters.size())
	cluster_count = 0
	for p: Vector3 in clusters:
		if p.x >= origin.x - reach and p.x <= origin.x + size + reach and p.z >= origin.y - reach and p.z <= origin.y + size + reach:
			cluster_points[cluster_count] = Vector2(p.x, p.z)
			cluster_count += 1


## Bilinear ground height from the grid at world (x, z).
func height(x: float, z: float) -> float:
	var u: float = clampf((x - origin.x) / step, 0.0, float(GRID) - 0.0001)
	var v: float = clampf((z - origin.y) / step, 0.0, float(GRID) - 0.0001)
	var i: int = int(u)
	var j: int = int(v)
	var fu: float = u - float(i)
	var fv: float = v - float(j)
	var row: int = GRID + 1
	var h00: float = heights[j * row + i]
	var h10: float = heights[j * row + i + 1]
	var h01: float = heights[(j + 1) * row + i]
	var h11: float = heights[(j + 1) * row + i + 1]
	return lerpf(lerpf(h00, h10, fu), lerpf(h01, h11, fu), fv)


## Normal of the bilinear patch under (x, z); y is always positive.
func normal(x: float, z: float) -> Vector3:
	var u: float = clampf((x - origin.x) / step, 0.0, float(GRID) - 0.0001)
	var v: float = clampf((z - origin.y) / step, 0.0, float(GRID) - 0.0001)
	var i: int = int(u)
	var j: int = int(v)
	var fu: float = u - float(i)
	var fv: float = v - float(j)
	var row: int = GRID + 1
	var h00: float = heights[j * row + i]
	var h10: float = heights[j * row + i + 1]
	var h01: float = heights[(j + 1) * row + i]
	var h11: float = heights[(j + 1) * row + i + 1]
	var dx: float = lerpf(h10 - h00, h11 - h01, fv) / step
	var dz: float = lerpf(h01 - h00, h11 - h10, fu) / step
	return Vector3(-dx, 1.0, -dz).normalized()


## Bilinear zone channels at world (x, z), into zone_density/height/tall/flowers. Without zones the
## fields stay at their defaults: full density, no tall grass, no flowers. The palette is a separate call
## (zone_palette) because most candidates are rejected on the roll and never need a colour.
func zone_at(x: float, z: float) -> void:
	if zones == null:
		return
	var u: float = clampf((x - origin.x) / step, 0.0, float(GRID) - 0.0001)
	var v: float = clampf((z - origin.y) / step, 0.0, float(GRID) - 0.0001)
	var i: int = int(u)
	var j: int = int(v)
	_zone_fu = u - float(i)
	_zone_fv = v - float(j)
	_zone_a = j * (GRID + 1) + i
	var c: Color = zone_channels[_zone_a].lerp(zone_channels[_zone_a + 1], _zone_fu).lerp(zone_channels[_zone_a + GRID + 1].lerp(zone_channels[_zone_a + GRID + 2], _zone_fu), _zone_fv)
	zone_density = c.r
	zone_height = c.g
	zone_tall = c.b
	zone_flowers = c.a


## The root and tip colours at the point of the last zone_at(), into zone_root and zone_tip.
func zone_palette() -> void:
	if zones == null:
		return
	var a: int = _zone_a
	var b: int = _zone_a + GRID + 1
	zone_root = zone_roots[a].lerp(zone_roots[a + 1], _zone_fu).lerp(zone_roots[b].lerp(zone_roots[b + 1], _zone_fu), _zone_fv)
	zone_tip = zone_tips[a].lerp(zone_tips[a + 1], _zone_fu).lerp(zone_tips[b].lerp(zone_tips[b + 1], _zone_fu), _zone_fv)


static func slope_deg(n: Vector3) -> float:
	return rad_to_deg(acos(clampf(n.y, -1.0, 1.0)))


## Distance to the nearest cluster point within reach, or INF when none is near.
func nearest_cluster(x: float, z: float) -> float:
	var best: float = INF
	for k: int in cluster_count:
		var p: Vector2 = cluster_points[k]
		var dx: float = p.x - x
		var dz: float = p.y - z
		best = minf(best, dx * dx + dz * dz)
	return sqrt(best) if best < INF else INF
