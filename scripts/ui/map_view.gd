class_name MapView
extends Control
## One drawing of the Vale (W19). The same control draws the little map in the corner and the full-screen
## one; they differ only in `span`, `centre` and whether names are written on them.
##
## Nothing here is a list of what is in the world. The ridge, the pond, the river and the plateaus come out
## of the area file, the buildings come out of SiteRegistry and the names come out of data/places.json, so
## the owner's rule holds: anything added to the Vale is on the map without this file changing.

## Whole-world drawing data, set once by MapPanel: {"area", "sites", "places", "grove"}.
var world: Dictionary = {}
## The world point drawn at the middle of this control.
var centre: Vector2 = Vector2.ZERO
## How many metres fit across the shorter side.
var span: float = MapDraw.MINI_SPAN
var player: Vector2 = Vector2.ZERO
## Where the player is looking, in degrees clockwise from north, for the arrow.
var player_bearing: float = 0.0
var dot_size: float = MapDraw.MINI_DOT
var show_names: bool = false
var show_compass: bool = true

const GROUND := Color(0.16, 0.17, 0.14, 0.92)
const RIDGE := Color(0.26, 0.24, 0.21, 0.95)
const WATER := Color(0.20, 0.34, 0.40, 0.95)
const ROAD := Color(0.42, 0.36, 0.27, 0.95)
const FLAT := Color(0.24, 0.25, 0.20, 1.0)
const WOOD := Color(0.17, 0.26, 0.17, 1.0)
const INK := Color(0.80, 0.76, 0.66)
const DIM := Color(0.62, 0.58, 0.50)
const PLAYER := Color(0.96, 0.88, 0.58)


func refresh(at: Vector2, bearing: float) -> void:
	player = at
	player_bearing = bearing
	queue_redraw()


func _draw() -> void:
	if world.is_empty():
		return
	var rect := Rect2(Vector2.ZERO, size)
	var area: Dictionary = world.get("area", {})
	_draw_ground(rect, area)
	_draw_water(rect, area)
	_draw_road(rect, area)
	_draw_sites(rect)
	if show_names:
		_draw_names(rect)
	if show_compass:
		_draw_compass(rect)
	_draw_player(rect)


## The valley floor, the ridge wall round it, the flat ground of each plateau, and the hidden wood.
func _draw_ground(rect: Rect2, area: Dictionary) -> void:
	var ridge: Dictionary = area.get("ridge", {})
	var outer: float = float(ridge.get("outer_radius", 520.0))
	var inner: float = float(ridge.get("inner_radius", 410.0))
	_fill_circle(rect, Vector2.ZERO, outer, RIDGE)
	_fill_circle(rect, Vector2.ZERO, inner, GROUND)
	var grove: Dictionary = world.get("grove", {})
	if float(grove.get("radius", 0.0)) > 0.0:
		_fill_circle(rect, _point(grove.get("centre")), float(grove["radius"]), WOOD)
	for row: Variant in area.get("plateaus", []):
		var p: Dictionary = row
		_fill_circle(rect, _point(p.get("centre")), float(p.get("radius", 0.0)), FLAT)


func _draw_water(rect: Rect2, area: Dictionary) -> void:
	var pond: Dictionary = area.get("pond", {})
	if float(pond.get("radius", 0.0)) > 0.0:
		_fill_circle(rect, _point(pond.get("centre")), float(pond["radius"]), WATER)
	# The river is drawn from the same crests that carve its bed, so the line on the map is the line in
	# the ground. A negative crest is a channel; a positive one is a hill and is not water.
	for row: Variant in area.get("crests", []):
		var c: Dictionary = row
		if float(c.get("height", 0.0)) >= 0.0:
			continue
		var pts := PackedVector2Array()
		for q: Variant in c.get("points", []):
			pts.append(_point(q))
		if pts.size() < 2:
			continue
		var width: float = maxf(1.5, float(c.get("half_width", 7.0)) * 2.0 * MapDraw.scale_for(span, rect))
		draw_polyline(MapDraw.panel_line(pts, centre, span, rect), WATER, width, true)


## The old road, which is the valley's own spine.
func _draw_road(rect: Rect2, area: Dictionary) -> void:
	var valley: Dictionary = area.get("valley", {})
	var pts := PackedVector2Array()
	for q: Variant in valley.get("waypoints", []):
		pts.append(_point(q))
	if pts.size() < 2:
		return
	var width: float = maxf(1.0, float(valley.get("width", 36.0)) * 0.3 * MapDraw.scale_for(span, rect))
	draw_polyline(MapDraw.panel_line(pts, centre, span, rect), ROAD, width, true)


func _draw_sites(rect: Rect2) -> void:
	for row: Variant in world.get("sites", []):
		var site: Dictionary = row
		var at: Vector2 = _point(site.get("at"))
		if not MapDraw.in_view(at, centre, span, rect):
			continue
		draw_circle(MapDraw.to_panel(at, centre, span, rect), dot_size,
				MapDraw.colour_of(MapDraw.kind_of_site(site)))


func _draw_names(rect: Rect2) -> void:
	var font: Font = get_theme_default_font()
	if font == null:
		return
	var places: Dictionary = world.get("places", {})
	for row: Variant in places.get("regions", []):
		var r: Dictionary = row
		var at: Vector2 = MapDraw.to_panel(_point(r.get("centre")), centre, span, rect)
		draw_string(font, at + Vector2(0.0, -6.0), str(r.get("name", "")), HORIZONTAL_ALIGNMENT_CENTER,
				-1.0, 13, Color(DIM, 0.75))
	for row: Variant in places.get("places", []):
		var p: Dictionary = row
		var at: Vector2 = _point(p.get("at"))
		if not MapDraw.in_view(at, centre, span, rect, 60.0):
			continue
		var panel: Vector2 = MapDraw.to_panel(at, centre, span, rect)
		var colour: Color = MapDraw.colour_of(str(p.get("kind", "")))
		draw_circle(panel, dot_size * 1.7, colour)
		draw_circle(panel, dot_size * 1.7, Color(0.0, 0.0, 0.0, 0.6), false, 1.0)
		draw_string(font, panel + Vector2(dot_size * 2.4, 4.0), str(p.get("name", "")),
				HORIZONTAL_ALIGNMENT_LEFT, -1.0, 14, INK)
	for row: Variant in places.get("waters", []):
		var w: Dictionary = row
		var pts: Array = w.get("points", [])
		if pts.is_empty():
			continue
		var mid: Vector2 = _point(pts[pts.size() / 2])
		draw_string(font, MapDraw.to_panel(mid, centre, span, rect) + Vector2(4.0, -4.0),
				str(w.get("name", "")), HORIZONTAL_ALIGNMENT_LEFT, -1.0, 12, Color(0.58, 0.76, 0.82))


func _draw_compass(rect: Rect2) -> void:
	var font: Font = get_theme_default_font()
	if font == null:
		return
	for mark: Dictionary in MapDraw.compass_marks(rect, 11.0 if show_names else 7.0):
		var text: String = str(mark["text"])
		var em: int = 15 if show_names else 11
		var at: Vector2 = mark["at"]
		var w: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, em).x
		draw_string(font, at - Vector2(w * 0.5, -em * 0.35), text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, em,
				INK if text == "N" else DIM)


func _draw_player(rect: Rect2) -> void:
	var at: Vector2 = MapDraw.to_panel(player, centre, span, rect)
	var head: float = deg_to_rad(player_bearing)
	var dir := Vector2(sin(head), -cos(head))
	var side := Vector2(-dir.y, dir.x)
	var r: float = dot_size * 3.0
	draw_colored_polygon(PackedVector2Array([at + dir * r, at - dir * r * 0.5 + side * r * 0.62,
			at - dir * r * 0.5 - side * r * 0.62]), PLAYER)


func _fill_circle(rect: Rect2, at: Vector2, radius: float, colour: Color) -> void:
	if radius <= 0.0:
		return
	draw_colored_polygon(MapDraw.panel_line(MapDraw.circle_points(at, radius), centre, span, rect), colour)


func _point(raw: Variant) -> Vector2:
	if raw is Array and (raw as Array).size() >= 2:
		return Vector2(float((raw as Array)[0]), float((raw as Array)[1]))
	if raw is Vector2:
		return raw
	return Vector2.ZERO
