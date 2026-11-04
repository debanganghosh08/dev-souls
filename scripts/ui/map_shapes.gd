class_name MapShapes
extends RefCounted
## World-space geometry for the map's water and roads (W21-C), built once when a world is handed to a
## MapView and drawn every frame under a transform, so the per-frame cost is draw calls and nothing else.
##
## The river is a chain of quads with a disc at every joint rather than one polygon: a long bendy polygon
## can fold over itself at a sharp turn and then triangulates to nothing, while a quad is always convex
## and a disc is always round. The width comes from data/areas/vale.json's `waters`, which are the same
## numbers the water surface is built from, so the river on the map is the river in the world.

## The Vale's river as {"quads": Array[PackedVector2Array], "joints": PackedVector3Array (x, z, radius)}
## grown by `grow` metres all round, so the same chain drawn twice gives a shore line and a fill.
static func river_pieces(area: Dictionary, grow: float = 0.0) -> Dictionary:
	var spine: PackedVector2Array = river_spine(area)
	var widths: PackedFloat32Array = river_half_widths(area, spine)
	return ribbon_pieces(spine, widths, grow)


## The longest water in the area, point by point. The wide reach shares its points with it, so the spine
## is the whole river and the reach only changes how wide it is.
static func river_spine(area: Dictionary) -> PackedVector2Array:
	var best: Array = []
	for row: Variant in area.get("waters", []):
		if row is Dictionary and ((row as Dictionary).get("points", []) as Array).size() > best.size():
			best = (row as Dictionary).get("points", [])
	var out := PackedVector2Array()
	for p: Variant in best:
		out.append(point(p))
	return out


## Half width at every spine point: the widest water that has a point there.
static func river_half_widths(area: Dictionary, spine: PackedVector2Array) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for at: Vector2 in spine:
		var w: float = 0.0
		for row: Variant in area.get("waters", []):
			if not row is Dictionary:
				continue
			var water: Dictionary = row
			for p: Variant in water.get("points", []):
				if point(p).distance_to(at) < 1.0:
					w = maxf(w, float(water.get("half_width", 0.0)))
					break
		out.append(w)
	return out


## Quads and joint discs along `points`, each point `half_widths[i] + grow` wide, the two ends narrowed
## by `taper` so the river leaves the map as a river and not as a cut-off block.
static func ribbon_pieces(points: PackedVector2Array, half_widths: PackedFloat32Array, grow: float = 0.0,
		taper: float = 0.6) -> Dictionary:
	var quads: Array[PackedVector2Array] = []
	var joints := PackedVector3Array()
	var n: int = points.size()
	if n < 2 or half_widths.size() < n:
		return {"quads": quads, "joints": joints}
	for i: int in n:
		var w: float = half_widths[i] + grow
		if i == 0 or i == n - 1:
			w *= taper
		joints.append(Vector3(points[i].x, points[i].y, w))
	for i: int in n - 1:
		var a: Vector2 = points[i]
		var b: Vector2 = points[i + 1]
		var dir: Vector2 = (b - a).normalized()
		var side := Vector2(-dir.y, dir.x)
		var wa: float = joints[i].z
		var wb: float = joints[i + 1].z
		quads.append(PackedVector2Array([a + side * wa, b + side * wb, b - side * wb, a - side * wa]))
	return {"quads": quads, "joints": joints}


## The pond as {"centre": Vector2, "radius": float}; radius 0 when there is none.
static func pond(area: Dictionary) -> Dictionary:
	var p: Dictionary = area.get("pond", {})
	return {"centre": point(p.get("centre", [0.0, 0.0])), "radius": maxf(0.0, float(p.get("radius", 0.0)))}


## The roads as {"spine": PackedVector2Array, "tracks": Array[PackedVector2Array]}. The spine is the old
## road the valley itself was carved along; the tracks are every other segment the terrain wears bare
## (data/areas/vale.json material.road), drawn exactly as the terrain shader draws them, consecutive
## waypoint to consecutive waypoint, so the map shows the ground the player sees.
static func roads(area: Dictionary) -> Dictionary:
	var spine := PackedVector2Array()
	for q: Variant in (area.get("valley", {}) as Dictionary).get("waypoints", []):
		spine.append(point(q))
	var tracks: Array[PackedVector2Array] = []
	var road: Variant = (area.get("material", {}) as Dictionary).get("road", {})
	var worn: Array = (road as Dictionary).get("waypoints", []) if road is Dictionary else []
	for i: int in maxi(0, worn.size() - 1):
		var a: Vector2 = point(worn[i])
		var b: Vector2 = point(worn[i + 1])
		if not _on_spine(spine, a, b):
			tracks.append(PackedVector2Array([a, b]))
	return {"spine": spine, "tracks": tracks}


static func _on_spine(spine: PackedVector2Array, a: Vector2, b: Vector2) -> bool:
	for i: int in maxi(0, spine.size() - 1):
		if spine[i].distance_to(a) < 0.5 and spine[i + 1].distance_to(b) < 0.5:
			return true
	return false


static func point(raw: Variant) -> Vector2:
	if raw is Array and (raw as Array).size() >= 2:
		return Vector2(float((raw as Array)[0]), float((raw as Array)[1]))
	if raw is Vector2:
		return raw
	return Vector2.ZERO
