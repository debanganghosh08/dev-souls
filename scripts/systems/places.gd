class_name Places
extends RefCounted
## The names of things (W19). The owner asked for every castle, village, river reach and quarter of the map
## to have a name, so that we can both say "the Girdle" instead of trading coordinates. Those names live in
## one file, data/places.json, and nothing else in the project repeats them.
##
## Everything here is static and pure except `load_file`, so the map can draw from it, a test can check it,
## and a banner can announce a region without any of them owning the data.
##
## North is -Z. That is not a choice made here: the site ids chose it weeks ago -- north_watch sits at
## z = -280 and south_ring at z = +350 -- and the compass follows the data rather than the other way round.

const PATH := "res://data/places.json"
## The eight points, in bearing order from north, clockwise. Index = round(bearing / 45) mod 8.
const COMPASS: Array[String] = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
const COMPASS_LONG: Array[String] = ["north", "north-east", "east", "south-east",
		"south", "south-west", "west", "north-west"]


static func load_file(path: String = PATH) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_error("Places: no such file %s" % path)
		return empty()
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not data is Dictionary:
		push_error("Places: %s is not a JSON object" % path)
		return empty()
	return coerce(data as Dictionary)


static func empty() -> Dictionary:
	return {"area": "", "regions": [], "places": [], "waters": []}


## Fills in whatever the file left out, so every caller can index the result without checking first.
static func coerce(raw: Dictionary) -> Dictionary:
	var out: Dictionary = empty()
	out["area"] = str(raw.get("area", ""))
	for key: String in ["regions", "places", "waters"]:
		var rows: Array = []
		for row: Variant in raw.get(key, []):
			if row is Dictionary and str((row as Dictionary).get("name", "")) != "":
				rows.append(row)
		out[key] = rows
	return out


## Bearing of a point from the origin, in degrees clockwise from north. North is -Z, east is +X.
static func bearing_of(at: Vector2) -> float:
	return fposmod(rad_to_deg(atan2(at.x, -at.y)), 360.0)


## Which of the eight points a bearing falls on.
static func compass_of(bearing: float) -> String:
	return COMPASS[_compass_index(bearing)]


static func compass_long(bearing: float) -> String:
	return COMPASS_LONG[_compass_index(bearing)]


static func _compass_index(bearing: float) -> int:
	return int(round(fposmod(bearing, 360.0) / 45.0)) % 8


## The region a point is in: the one whose centre is nearest, among those whose radius reaches it. Regions
## overlap on purpose -- the Vale has no borders drawn on the ground -- so nearest-centre decides, and a
## point outside every region still gets the nearest one rather than nothing.
static func region_at(places: Dictionary, at: Vector2) -> Dictionary:
	var inside: Dictionary = {}
	var inside_d: float = INF
	var nearest: Dictionary = {}
	var nearest_d: float = INF
	for row: Variant in places.get("regions", []):
		var r: Dictionary = row
		var centre: Vector2 = _point(r.get("centre"))
		var d: float = centre.distance_to(at)
		if d < nearest_d:
			nearest_d = d
			nearest = r
		if d <= float(r.get("radius", 0.0)) and d < inside_d:
			inside_d = d
			inside = r
	return inside if not inside.is_empty() else nearest


## The named place nearest a point, and how far away it is: {"name", "kind", "distance", ...}. Empty when
## the file names no places at all.
static func nearest_place(places: Dictionary, at: Vector2) -> Dictionary:
	var best: Dictionary = {}
	var best_d: float = INF
	for row: Variant in places.get("places", []):
		var p: Dictionary = row
		var d: float = _point(p.get("at")).distance_to(at)
		if d < best_d:
			best_d = d
			best = p
	if best.is_empty():
		return {}
	var out: Dictionary = best.duplicate()
	out["distance"] = best_d
	return out


## "Thornhollow, 40 m north-east" -- the one line a banner or a map footer wants. Falls back to the region
## alone when nothing is named near enough to be worth pointing at.
static func describe(places: Dictionary, at: Vector2, reach: float = 90.0) -> String:
	var region: Dictionary = region_at(places, at)
	var region_name: String = str(region.get("name", "")) if not region.is_empty() else ""
	var near: Dictionary = nearest_place(places, at)
	if near.is_empty() or float(near["distance"]) > reach:
		return region_name
	var name: String = str(near["name"])
	var away: float = float(near["distance"])
	if away < 24.0:
		return name
	var heading: String = compass_long(bearing_of(_point(near.get("at")) - at))
	return "%s, %d m %s" % [name, int(round(away)), heading]


## Every place of a kind, in file order. The map colours its dots by kind and this is how it gathers them.
static func of_kind(places: Dictionary, kind: String) -> Array:
	var out: Array = []
	for row: Variant in places.get("places", []):
		if str((row as Dictionary).get("kind", "")) == kind:
			out.append(row)
	return out


static func _point(raw: Variant) -> Vector2:
	if raw is Array and (raw as Array).size() >= 2:
		return Vector2(float((raw as Array)[0]), float((raw as Array)[1]))
	return Vector2.ZERO
