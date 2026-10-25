class_name GrassCell
extends RefCounted
## Scratch context for filling one Grass lattice cell: a coarse height grid over the cell, the cell's
## hollow factor and the cluster points (trees) within reach. Allocated once per Grass node and re-prepared
## per fill, so filling a cell costs (GRID + 1)^2 ground samples plus one exact sample per accepted
## instance instead of five samples per candidate; everything else is bilinear maths on the grid.

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


func _init() -> void:
	heights.resize((GRID + 1) * (GRID + 1))


## Samples the grid for `key`'s cell and copies the cluster points that can influence it.
func prepare(key: Vector2i, cell_size: float, sampler: Callable, water: float, clusters: PackedVector3Array, reach: float) -> void:
	size = maxf(0.001, cell_size)
	step = size / float(GRID)
	origin = Vector2(float(key.x) * size, float(key.y) * size)
	water_level = water
	height_sampler = sampler
	for j: int in GRID + 1:
		for i: int in GRID + 1:
			heights[j * (GRID + 1) + i] = float(sampler.call(origin.x + float(i) * step, origin.y + float(j) * step))
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
