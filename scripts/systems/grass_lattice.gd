class_name GrassLattice
extends RefCounted
## The pure maths behind Grass: where things may grow and which lattice cells a player position needs.
## Scene-free and static (like Heightfield is to Terrain) so tests call it directly and Grass stays a thin
## node around pooled MultiMeshes. SHORE_BAND is how far above the water line growth thins to nothing.

const SHORE_BAND := 1.0
const MAX_CELLS_PER_SIDE := 48

## 0..1 growth factor for the land: full on gentle ground, fading from half the slope limit to nothing at
## it, nothing under water and thinning over SHORE_BAND metres above it. Degenerate input yields 0, not NaN.
static func density_at(slope_deg: float, height: float, water_level: float, max_slope: float) -> float:
	if is_nan(slope_deg) or is_nan(height) or is_nan(water_level) or is_nan(max_slope) or max_slope <= 0.0:
		return 0.0
	if height <= water_level or slope_deg >= max_slope:
		return 0.0
	var shore: float = clampf((height - water_level) / SHORE_BAND, 0.0, 1.0)
	var s: float = clampf(slope_deg / max_slope, 0.0, 1.0)
	return shore * shore * (1.0 - smoothstep(0.5, 1.0, s))


## 0 inside a plateau site's radius, rising over `skirt` of its blend to 1: nothing grows on the paved
## village and castle tops, and the skirt fades in rather than a ring of grass at the edge.
static func site_factor(x: float, z: float, sites: Array[Dictionary], skirt: float = 0.5) -> float:
	var f: float = 1.0
	for site: Dictionary in sites:
		var r: float = float(site.get("radius", 0.0))
		var d: float = Vector2(x, z).distance_to(site.get("centre", Vector2.ZERO))
		f *= smoothstep(r, r + maxf(0.001, float(site.get("blend", 0.0)) * skirt), d)
	return f


static func cell_of(x: float, z: float, size: float) -> Vector2i:
	var s: float = maxf(0.001, size)
	return Vector2i(floori(x / s), floori(z / s))


static func cell_centre(key: Vector2i, size: float) -> Vector2:
	return Vector2((float(key.x) + 0.5) * size, (float(key.y) + 0.5) * size)


## Offsets of every cell whose centre lies within `lattice_radius` of the centre cell's centre. Depends on
## the centre cell only, so jitter inside one cell never changes the set.
static func lattice_offsets(lattice_radius: float, size: float) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var s: float = maxf(0.001, size)
	# Capped so a zero cell size or a kilometre radius cannot ask for millions of cells.
	var n: int = mini(MAX_CELLS_PER_SIDE, maxi(0, ceili(maxf(0.0, lattice_radius) / s)))
	for j: int in range(-n, n + 1):
		for i: int in range(-n, n + 1):
			if Vector2(float(i), float(j)).length() * s <= lattice_radius:
				out.append(Vector2i(i, j))
	return out


static func cells_needed(player: Vector3, lattice_radius: float, size: float) -> Array[Vector2i]:
	var centre: Vector2i = cell_of(player.x, player.z, size)
	var out: Array[Vector2i] = []
	for o: Vector2i in lattice_offsets(lattice_radius, size):
		out.append(centre + o)
	return out


## {drop: cells in `have` (keys) but not wanted, add: wanted cells not in `have`}; kept cells untouched.
static func cell_diff(have: Dictionary, want: Array[Vector2i]) -> Dictionary:
	var drop: Array[Vector2i] = []
	var add: Array[Vector2i] = []
	for key: Vector2i in want:
		if not have.has(key):
			add.append(key)
	for key: Variant in have.keys():
		if not want.has(key):
			drop.append(key)
	return {"drop": drop, "add": add}


## Fraction of a cell's instances to show at `distance`: 1 inside near_radius, down to far_fraction at the edge.
static func thin_factor(distance: float, lattice_radius: float, near_radius: float, far_fraction: float) -> float:
	if distance <= near_radius or lattice_radius <= near_radius:
		return 1.0
	return lerpf(1.0, clampf(far_fraction, 0.0, 1.0), clampf((distance - near_radius) / (lattice_radius - near_radius), 0.0, 1.0))
