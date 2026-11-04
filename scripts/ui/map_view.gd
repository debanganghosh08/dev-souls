class_name MapView
extends Control
## One drawing of the Vale (W19, redrawn as a map in W21-C). The same control draws the little map in the
## corner and the full-screen one; they differ only in `span`, `centre` and whether names are written.
##
## Layers, bottom to top: the relief (MapRelief, one cached texture sampled from the Heightfield), the
## hidden wood, the water as filled shapes, the roads, the buildings as ink specks, then in screen space
## the names, the compass and the player. Everything in world metres is drawn under one transform, so
## nothing is converted point by point per frame; the shapes are built once when `world` is set.
##
## Nothing here is a list of what is in the world. The ground comes from the area file through the
## Heightfield, the water and roads from the same file, the buildings from SiteRegistry and the names from
## data/places.json, so anything added to the Vale is on the map without this file changing.

## Whole-world drawing data, set once by MapPanel: {"area", "sites", "places", "grove"}.
var world: Dictionary = {}: set = set_world
## The cached land picture, shared by both views. May be null or still building; the map draws without it.
var relief: MapRelief
## The world point drawn at the middle of this control.
var centre: Vector2 = Vector2.ZERO
## How many metres fit across the shorter side.
var span: float = MapDraw.MINI_SPAN
var player: Vector2 = Vector2.ZERO
## Where the player is looking, in degrees clockwise from north.
var player_bearing: float = 0.0
var dot_size: float = MapDraw.MINI_DOT
var show_names: bool = false
var show_compass: bool = true

const VOID := Color(0.07, 0.07, 0.065, 1.0)
const GROUND := Color(0.21, 0.22, 0.19, 1.0)
const RIDGE := Color(0.32, 0.30, 0.27, 1.0)
const FLAT := Color(0.26, 0.26, 0.22, 1.0)
const WATER := Color(0.17, 0.29, 0.36, 1.0)
const SHORE := Color(0.46, 0.60, 0.64, 0.85)
const ROAD := Color(0.66, 0.55, 0.38, 1.0)
const ROAD_EDGE := Color(0.08, 0.06, 0.04, 0.9)
const TRACK := Color(0.56, 0.48, 0.35, 0.85)
const WOOD := Color(0.13, 0.23, 0.14, 0.55)
const WOOD_EDGE := Color(0.32, 0.46, 0.30, 0.9)
const INK := Color(0.88, 0.84, 0.74)
const DIM := Color(0.62, 0.58, 0.50)
const HALO := Color(0.04, 0.04, 0.03, 0.9)
const REGION := Color(0.74, 0.68, 0.55, 0.40)
const WATER_INK := Color(0.62, 0.80, 0.86)
const PLAYER := Color(0.98, 0.90, 0.60)
const PLAYER_EDGE := Color(0.08, 0.06, 0.03)
const CONE := Color(0.98, 0.90, 0.60, 0.16)
const CONE_DEG := 70.0
const CONE_STEPS := 12
## Shore line thickness and the road's drawn width, in metres.
const SHORE_M := 2.0
const ROAD_M := 7.6

var _water_fill: Dictionary = {}
var _water_rim: Dictionary = {}
var _pond: Dictionary = {}
var _roads: Dictionary = {}
var _site_at := PackedVector2Array()
var _site_colour := PackedColorArray()
var _labels: Array[Dictionary] = []
var _marks: Array[Dictionary] = []
var _arrow := PackedVector2Array([Vector2.ZERO, Vector2.ZERO, Vector2.ZERO])
var _cone := PackedVector2Array()


func _init() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_cone.resize(CONE_STEPS + 2)


func set_world(value: Dictionary) -> void:
	world = value
	var area: Dictionary = world.get("area", {})
	_water_fill = MapShapes.river_pieces(area, 0.0)
	_water_rim = MapShapes.river_pieces(area, SHORE_M)
	_pond = MapShapes.pond(area)
	_roads = MapShapes.roads(area)
	# Kind and colour are read off each site's layout path once here, not per site per frame.
	_site_at.clear()
	_site_colour.clear()
	for row: Variant in world.get("sites", []):
		var site: Dictionary = row
		_site_at.append(MapShapes.point(site.get("at")))
		_site_colour.append(MapDraw.colour_of(MapDraw.kind_of_site(site)))
	_labels.clear()
	queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_labels.clear()
		_marks.clear()


## Redraws only when something moved: the full map is paused, so it costs nothing while open.
func refresh(at: Vector2, bearing: float) -> void:
	if at.is_equal_approx(player) and is_equal_approx(bearing, player_bearing):
		return
	player = at
	player_bearing = bearing
	queue_redraw()


func _draw() -> void:
	if world.is_empty():
		return
	var rect := Rect2(Vector2.ZERO, size)
	var scale: float = MapDraw.scale_for(span, rect)
	draw_rect(rect, VOID)
	draw_set_transform(rect.position + rect.size * 0.5 - centre * scale, 0.0, Vector2(scale, scale))
	var area: Dictionary = world.get("area", {})
	if relief != null and relief.is_ready():
		draw_texture_rect(relief.texture, relief.world_rect(), false)
	else:
		_draw_flat_ground(area)
	_draw_wood(scale)
	_draw_water(scale)
	_draw_roads(scale)
	_draw_sites(rect, scale)
	draw_set_transform_matrix(Transform2D.IDENTITY)
	if show_names:
		_draw_names(rect)
	if show_compass:
		_draw_compass(rect)
	_draw_player(rect)


## What the map shows until the relief texture exists: the ridge ring, the floor and the flat tops.
func _draw_flat_ground(area: Dictionary) -> void:
	var ridge: Dictionary = area.get("ridge", {})
	draw_circle(Vector2.ZERO, float(ridge.get("outer_radius", 520.0)), RIDGE)
	draw_circle(Vector2.ZERO, float(ridge.get("inner_radius", 410.0)), GROUND)
	for row: Variant in area.get("plateaus", []):
		var p: Dictionary = row
		draw_circle(MapShapes.point(p.get("centre")), float(p.get("radius", 0.0)), FLAT)


func _draw_wood(scale: float) -> void:
	var grove: Dictionary = world.get("grove", {})
	var radius: float = float(grove.get("radius", 0.0))
	if radius <= 0.0:
		return
	var at: Vector2 = MapShapes.point(grove.get("centre"))
	draw_circle(at, radius, WOOD)
	draw_circle(at, radius, WOOD_EDGE, false, 1.2 / scale, true)


func _draw_water(scale: float) -> void:
	_draw_ribbon(_water_rim, SHORE)
	_draw_ribbon(_water_fill, WATER)
	var radius: float = float(_pond.get("radius", 0.0))
	if radius <= 0.0:
		return
	draw_circle(_pond["centre"], radius + SHORE_M, SHORE, true, -1.0, true)
	draw_circle(_pond["centre"], radius, WATER, true, -1.0, true)
	# A hairline at the water's edge reads as a shore however far out the map is.
	draw_circle(_pond["centre"], radius + SHORE_M, SHORE, false, 1.0 / scale, true)


func _draw_ribbon(pieces: Dictionary, colour: Color) -> void:
	for quad: PackedVector2Array in pieces.get("quads", []):
		draw_colored_polygon(quad, colour)
	for joint: Vector3 in pieces.get("joints", PackedVector3Array()):
		draw_circle(Vector2(joint.x, joint.y), joint.z, colour)


## The old road as a cased line (dark edge, pale centre), the worn tracks as dashes.
func _draw_roads(scale: float) -> void:
	var spine: PackedVector2Array = _roads.get("spine", PackedVector2Array())
	var width: float = maxf(ROAD_M, 2.0 / scale)
	if spine.size() >= 2:
		draw_polyline(spine, ROAD_EDGE, width + 2.0 / scale, true)
		draw_polyline(spine, ROAD, width, true)
	for track: PackedVector2Array in _roads.get("tracks", []):
		draw_dashed_line(track[0], track[1], TRACK, maxf(ROAD_M * 0.5, 1.5 / scale), 10.0 / scale, true, true)


## Every building as a speck of ink coloured by what it is. Small on the full map, where the villages
## read as clusters and the names do the talking; larger on the corner map, where they are the content.
func _draw_sites(rect: Rect2, scale: float) -> void:
	var r: float = (dot_size * 0.65 if show_names else dot_size) / scale
	for i: int in _site_at.size():
		if MapDraw.in_view(_site_at[i], centre, span, rect):
			draw_circle(_site_at[i], r, _site_colour[i])


func _draw_names(rect: Rect2) -> void:
	var font: Font = get_theme_default_font()
	if font == null:
		return
	if _labels.is_empty():
		_labels = MapLabels.layout(_label_items(rect, font), rect)
	for item: Dictionary in _labels:
		var em: int = item["em"]
		var marker: float = float(item.get("marker", 0.0))
		if marker > 0.0:
			var at: Vector2 = item["at"]
			draw_circle(at, marker + 1.2, HALO, true, -1.0, true)
			draw_circle(at, marker, item["marker_colour"], true, -1.0, true)
		if not bool(item["placed"]):
			continue
		var base: Vector2 = (item["pos"] as Vector2) + Vector2(0.0, font.get_ascent(em))
		var text: String = item["text"]
		if bool(item.get("solid", true)):
			draw_string_outline(font, base, text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, em, 3, HALO)
		draw_string(font, base, text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, em, item["colour"])


## The names as layout items, regions first and faint, then places by rank, then the river's reaches.
func _label_items(rect: Rect2, font: Font) -> Array[Dictionary]:
	var items: Array[Dictionary] = []
	var places: Dictionary = world.get("places", {})
	for row: Variant in places.get("regions", []):
		var r: Dictionary = row
		var text: String = str(r.get("name", "")).to_upper()
		items.append(_item(text, MapShapes.point(r.get("centre")), rect, font, MapLabels.EM_REGION, 0,
				REGION, true, false))
	for row: Variant in places.get("places", []):
		var p: Dictionary = row
		var kind: String = str(p.get("kind", ""))
		var rank: int = MapLabels.rank_of(kind)
		var colour: Color = WATER_INK if kind == "water" else INK
		var item: Dictionary = _item(str(p.get("name", "")), MapShapes.point(p.get("at")), rect, font,
				MapLabels.em_of(kind), rank, colour, false, true)
		# Areas (woods, water) have no one point to mark; everything else gets a dot sized by rank.
		item["marker"] = 0.0 if rank == 2 else (4.0 if rank == 1 else 2.6)
		item["marker_colour"] = MapDraw.colour_of(kind)
		items.append(item)
	for row: Variant in places.get("waters", []):
		var w: Dictionary = row
		var pts: Array = w.get("points", [])
		if pts.is_empty():
			continue
		items.append(_item(str(w.get("name", "")), MapShapes.point(pts[pts.size() >> 1]), rect, font,
				MapLabels.EM_SMALL, 2, WATER_INK, false, true))
	return items


func _item(text: String, at_world: Vector2, rect: Rect2, font: Font, em: int, rank: int, colour: Color,
		centred: bool, solid: bool) -> Dictionary:
	var size := Vector2(font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, em).x, font.get_height(em))
	return {"text": text, "at": MapDraw.to_panel(at_world, centre, span, rect), "size": size, "em": em,
			"rank": rank, "colour": colour, "centred": centred, "solid": solid, "marker": 0.0,
			"marker_colour": colour, "gap": 7.0 if rank <= 1 else 5.0}


func _draw_compass(rect: Rect2) -> void:
	var font: Font = get_theme_default_font()
	if font == null:
		return
	if _marks.is_empty():
		_marks = MapDraw.compass_marks(rect, 12.0 if show_names else 7.0)
	var mid: Vector2 = rect.position + rect.size * 0.5
	for mark: Dictionary in _marks:
		var text: String = str(mark["text"])
		var em: int = 15 if show_names else 11
		var at: Vector2 = mark["at"]
		var inward: Vector2 = (mid - at).normalized()
		draw_line(at + inward * (em * 0.9), at + inward * (em * 0.9 + (8.0 if show_names else 4.0)),
				INK if text == "N" else DIM, 1.0, true)
		var w: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, em).x
		draw_string_outline(font, at - Vector2(w * 0.5, -em * 0.35), text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, em, 3, HALO)
		draw_string(font, at - Vector2(w * 0.5, -em * 0.35), text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, em,
				INK if text == "N" else DIM)


## An arrow for where the player stands and a faint wedge for where they are looking.
func _draw_player(rect: Rect2) -> void:
	var at: Vector2 = MapDraw.to_panel(player, centre, span, rect)
	var dir: Vector2 = MapDraw.heading(player_bearing)
	var side := Vector2(-dir.y, dir.x)
	var r: float = dot_size * 3.2
	var reach: float = dot_size * 11.0
	var half: float = deg_to_rad(CONE_DEG) * 0.5
	_cone[0] = at
	for i: int in CONE_STEPS + 1:
		var a: float = deg_to_rad(player_bearing) - half + half * 2.0 * float(i) / float(CONE_STEPS)
		_cone[i + 1] = at + Vector2(sin(a), -cos(a)) * reach
	draw_colored_polygon(_cone, CONE)
	_arrow[0] = at + dir * r
	_arrow[1] = at - dir * r * 0.55 + side * r * 0.65
	_arrow[2] = at - dir * r * 0.55 - side * r * 0.65
	draw_colored_polygon(_arrow, PLAYER)
	draw_polyline(_arrow, PLAYER_EDGE, 1.2, true)
	draw_line(_arrow[2], _arrow[0], PLAYER_EDGE, 1.2, true)
	draw_circle(at, r * 1.6, Color(PLAYER, 0.35), false, 1.0, true)
