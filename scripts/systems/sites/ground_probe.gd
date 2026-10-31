class_name GroundProbe
extends RefCounted
## Answers "can a building stand here?" against the real heightfield, in one place, for everyone who needs
## to ask (W10). Until now the answer came from a throwaway `--script` run written fresh each time, which is
## fine for the lead and impossible for anyone who is not allowed to write GDScript -- and the owner's rule
## for outside agents is content only, no code. `tools/ground_report.gd` is a thin command-line wrapper over
## this, so laying out a village becomes "run the tool, read the table" instead of "write a program".
##
## The rules are tests/test_site_placement.gd's, restated here as a query rather than an assertion. They
## are deliberately a little stricter than the test (a bigger default footprint, a wider road margin), so a
## spot this calls legal still passes the suite with room to spare.

## Metres of ground a default structure needs to sit on, square.
const FOOTPRINT := 9.0
## Rules, matching tests/test_site_placement.gd with a margin.
const MAX_DROP := 1.2
## Clear of the water by this much. The suite only asks for "above the water line"; this keeps a margin,
## but a small one, because the wayside lamps along the pond's west shore legitimately stand 0.5 m above it
## and a tool that called the existing map illegal would be no use for adding to it. A bigger building
## wants a bigger `footprint`, which is the parameter that actually scales with the thing being placed.
const DRY_MARGIN := 0.5
## What `find` aims for, as opposed to what `report` accepts. A spot that only just clears the water by
## the suite's own threshold is a spot that fails the moment the site standing on it is wider than the
## probe that measured it -- which is how two sites ended up 7 cm under the line after the river went in.
const FIND_MARGIN := 1.1
const ROAD_CLEAR := 4.0
const SITE_CLEAR := 8.0
## Kept clear of the ridge wall, matching tests/test_site_placement.gd. The limit itself is not a constant:
## it is the area's own ridge radius less this, because a hard-coded 360 called four graves on the Vale's
## western rim illegal when the suite is perfectly happy with them.
const RIDGE_CLEARANCE := 25.0
## Samples per side of the footprint when measuring the fall across it.
const GRID := 5


## Everything worth knowing about one spot. `legal` is the conjunction of the rest, which is the only field
## most callers need.
static func report(hf: Heightfield, road: PackedVector2Array, taken: Array, at: Vector2,
		footprint: float = FOOTPRINT, ridge: float = INF) -> Dictionary:
	var low: float = INF
	var high: float = -INF
	var half: float = maxf(0.5, footprint) * 0.5
	for i: int in range(GRID):
		for j: int in range(GRID):
			var p := Vector2(
				at.x + lerpf(-half, half, float(i) / float(GRID - 1)),
				at.y + lerpf(-half, half, float(j) / float(GRID - 1)))
			var h: float = hf.height_at(p.x, p.y)
			low = minf(low, h)
			high = maxf(high, h)
	var water: float = hf.water_level()
	var road_distance: float = distance_to_path(at, road)
	var nearest: float = INF
	var nearest_id: String = ""
	for entry: Variant in taken:
		if not entry is Dictionary:
			continue
		var site: Dictionary = entry
		var d: float = at.distance_to(SiteRegistry.at_of(site))
		if d < nearest:
			nearest = d
			nearest_id = str(site.get("id", "?"))
	var dry: bool = low >= water + DRY_MARGIN
	var flat: bool = high - low <= MAX_DROP
	var off_road: bool = road_distance >= ROAD_CLEAR
	var clear: bool = nearest >= SITE_CLEAR
	var inside: bool = at.length() <= ridge
	return {
		"at": at,
		"height": hf.height_at(at.x, at.y),
		"lowest": low,
		"highest": high,
		"drop": high - low,
		"water": water,
		"road_distance": road_distance,
		"nearest_site": nearest,
		"nearest_id": nearest_id,
		"dry": dry,
		"flat": flat,
		"off_road": off_road,
		"clear": clear,
		"inside_ridge": inside,
		"legal": dry and flat and off_road and clear and inside,
	}


## The nearest legal spot to `want`, searched in rings. Vector2.INF when there is none inside `reach`.
## This is what turns "put a smithy about here" into a placement that passes the suite.
static func find(hf: Heightfield, road: PackedVector2Array, taken: Array, want: Vector2,
		footprint: float = FOOTPRINT, reach: float = 40.0, steps: int = 8, ridge: float = INF) -> Vector2:
	if _good_enough(report(hf, road, taken, want, footprint, ridge)):
		return want
	var ring: float = reach / float(maxi(1, steps))
	for step: int in range(1, steps + 1):
		var radius: float = ring * float(step)
		var points: int = maxi(8, int(TAU * radius / 6.0))
		for i: int in range(points):
			var a: float = TAU * float(i) / float(points)
			var spot := Vector2(want.x + cos(a) * radius, want.y + sin(a) * radius)
			if _good_enough(report(hf, road, taken, spot, footprint, ridge)):
				return spot
	return Vector2.INF


## Legal, and clear of the water by FIND_MARGIN rather than by the bare minimum.
static func _good_enough(row: Dictionary) -> bool:
	return bool(row["legal"]) and float(row["lowest"]) >= float(row["water"]) + FIND_MARGIN


## Shortest distance from a point to a polyline, INF when the line has fewer than two points.
static func distance_to_path(p: Vector2, path: PackedVector2Array) -> float:
	if path.size() < 2:
		return INF
	var best: float = INF
	for i: int in range(path.size() - 1):
		best = minf(best, p.distance_to(Geometry2D.get_closest_point_to_segment(p, path[i], path[i + 1])))
	return best


## How far from the centre an area allows building: its ridge's inner radius less RIDGE_CLEARANCE. An
## area with no ridge has no limit.
static func ridge_limit(area: Dictionary) -> float:
	var ridge: Variant = area.get("ridge", {})
	if not ridge is Dictionary:
		return INF
	var inner: float = float((ridge as Dictionary).get("inner_radius", 0.0))
	return inner - RIDGE_CLEARANCE if inner > 0.0 else INF


## The old road of an area, as the polyline every other system reads: the valley channel's waypoints.
static func road_of(area: Dictionary) -> PackedVector2Array:
	var out := PackedVector2Array()
	var valley: Variant = area.get("valley", {})
	if not valley is Dictionary:
		return out
	for raw: Variant in (valley as Dictionary).get("waypoints", []):
		if raw is Array and (raw as Array).size() >= 2:
			var p: Array = raw
			out.append(Vector2(float(p[0]), float(p[1])))
	return out


## One line of the tool's table. Kept here so the report and its wording stay together.
static func line(row: Dictionary) -> String:
	var at: Vector2 = row["at"]
	var flags: String = ""
	for key: String in ["dry", "flat", "off_road", "clear", "inside_ridge"]:
		if not bool(row[key]):
			flags += " NOT_" + key.to_upper()
	return "%8.1f %8.1f  ground=%7.2f drop=%5.2f road=%6.1f nearest=%6.1f (%s)  %s%s" % [
		at.x, at.y, row["height"], row["drop"], row["road_distance"], row["nearest_site"],
		row["nearest_id"], "LEGAL" if bool(row["legal"]) else "ILLEGAL", flags,
	]
