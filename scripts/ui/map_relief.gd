class_name MapRelief
extends RefCounted
## The land under the map (W21-C): a hillshaded, contoured picture of the Vale sampled from the SAME
## Heightfield the terrain is built from, so the map's hills are the world's hills and not a second set of
## blobs. It is built once per area into an Image, turned into one ImageTexture, and then drawn with a
## single draw_texture_rect by both the corner map and the full one.
##
## Building it means tens of thousands of height_at calls, which is too much for one frame on the laptop,
## so the work is sliced: MapPanel calls step() with a microsecond budget each frame while playing, and
## build_all() finishes it in one go if the full map is opened before the slices are done. Nothing here
## runs per frame once `is_ready()`.

## Pixels per side of the relief image. One constant: raise it for crisper contours at more build cost.
const DEFAULT_PX := 256
## Metres between contour lines, and how many lines apart the heavy ones are.
const CONTOUR_M := 8.0
const BOLD_EVERY := 5
## Heights that map to the darkest and the palest land. The ridge top (95 m) saturates to the palest.
const LOW_M := -8.0
const HIGH_M := 64.0
## Beyond the boundary ridge the land fades toward the panel's shade over this many metres, so the Vale
## reads as one landmass and the eye is not asked to read noise nobody can walk to.
const FADE_M := 40.0
const FADE_TO := 0.15
## Light from the north-west, as every drawn relief has had since the eighteenth century: it is the
## direction the eye reads as "lit from above", and the opposite one makes hills look like hollows.
const LIGHT := Vector3(-0.5, 0.7, -0.5)

const LOW := Color(0.18, 0.19, 0.16)
const MID := Color(0.27, 0.27, 0.23)
const HIGH := Color(0.44, 0.41, 0.36)
const WATER := Color(0.16, 0.27, 0.33)
const DEEP := Color(0.09, 0.16, 0.21)
const INK := Color(0.08, 0.07, 0.06)

## How many reliefs have finished building since the game started. A test reads this to prove that
## opening the map or rebinding the level does not build a second one.
static var builds: int = 0

## What this relief was built for; MapPanel reuses it while the area name matches.
var key: String = ""
var px: int = DEFAULT_PX
var span: float = 1100.0
var centre: Vector2 = Vector2.ZERO
var image: Image
var texture: ImageTexture

var _hf: Heightfield
var _heights := PackedFloat32Array()
var _wet := PackedByteArray()
var _row: int = 0
var _paint_row: int = 0
var _done: bool = false
var _water_level: float = 0.0
var _pond_centre := Vector2.ZERO
var _pond_reach: float = 0.0
var _ridge_outer: float = 0.0


static func create(area: Dictionary, area_key: String, size_px: int = DEFAULT_PX, metres: float = 1100.0,
		mid: Vector2 = Vector2.ZERO) -> MapRelief:
	var r := MapRelief.new()
	r.key = area_key
	r.px = maxi(2, size_px)
	r.span = maxf(1.0, metres)
	r.centre = mid
	r._hf = Heightfield.from_dict(area)
	r._water_level = r._hf.water_level()
	r._pond_centre = r._hf.pond_centre()
	r._pond_reach = r._hf.pond_falloff()
	r._ridge_outer = float((area.get("ridge", {}) as Dictionary).get("outer_radius", 0.0))
	r._heights.resize(r.px * r.px)
	r._wet.resize(r.px * r.px)
	r.image = Image.create_empty(r.px, r.px, false, Image.FORMAT_RGBA8)
	return r


func is_ready() -> bool:
	return _done


## 0 at nothing done, 1 when the texture exists.
func progress() -> float:
	return float(_row + _paint_row) / float(2 * px)


## The world square the image covers, for draw_texture_rect.
func world_rect() -> Rect2:
	return Rect2(centre - Vector2(span, span) * 0.5, Vector2(span, span))


func metres_per_pixel() -> float:
	return span / float(px)


## The image pixel a world point falls in. Row 0 is north, as on the map.
func pixel_of(world: Vector2) -> Vector2i:
	var m: float = metres_per_pixel()
	return Vector2i(floori((world.x - centre.x + span * 0.5) / m), floori((world.y - centre.y + span * 0.5) / m))


## The colour the relief gives a world point, or transparent black outside the image or before it is built.
func colour_at(world: Vector2) -> Color:
	var p: Vector2i = pixel_of(world)
	if image == null or p.x < 0 or p.y < 0 or p.x >= px or p.y >= px:
		return Color(0.0, 0.0, 0.0, 0.0)
	return image.get_pixelv(p)


## Does up to `budget_usec` of building and returns true once the texture exists. A zero budget still does
## one row, so progress is always made.
func step(budget_usec: int) -> bool:
	var started: int = Time.get_ticks_usec()
	while not _done:
		if _row < px:
			_sample(_row)
			_row += 1
		elif _paint_row < px:
			_paint(_paint_row)
			_paint_row += 1
		else:
			_finish()
		if Time.get_ticks_usec() - started >= budget_usec:
			break
	return _done


func build_all() -> void:
	while not _done:
		step(1 << 30)


func _world_of(i: int, j: int) -> Vector2:
	var m: float = metres_per_pixel()
	return Vector2(centre.x - span * 0.5 + (float(i) + 0.5) * m, centre.y - span * 0.5 + (float(j) + 0.5) * m)


func _sample(j: int) -> void:
	for i: int in px:
		var w: Vector2 = _world_of(i, j)
		var h: float = _hf.height_at(w.x, w.y)
		var k: int = j * px + i
		_heights[k] = h
		var wet: int = 0
		if h < _water_level and w.distance_to(_pond_centre) <= _pond_reach:
			wet = 1
		elif _hf.in_river(w.x, w.y):
			wet = 2
		_wet[k] = wet


func _paint(j: int) -> void:
	var m: float = metres_per_pixel()
	var light: Vector3 = LIGHT.normalized()
	for i: int in px:
		var k: int = j * px + i
		var h: float = _heights[k]
		var left: float = _heights[k - 1] if i > 0 else h
		var right: float = _heights[k + 1] if i < px - 1 else h
		var up: float = _heights[k - px] if j > 0 else h
		var down: float = _heights[k + px] if j < px - 1 else h
		var normal := Vector3(-(right - left) / (2.0 * m), 1.0, -(down - up) / (2.0 * m)).normalized()
		var lit: float = 0.55 + 0.6 * clampf(normal.dot(light), 0.0, 1.0)
		var t: float = clampf((h - LOW_M) / (HIGH_M - LOW_M), 0.0, 1.0)
		var colour: Color = LOW.lerp(MID, minf(1.0, t * 2.0)).lerp(HIGH, maxf(0.0, t * 2.0 - 1.0))
		colour = Color(colour.r * lit, colour.g * lit, colour.b * lit, 1.0)
		var band: int = floori(h / CONTOUR_M)
		var neighbour: int = mini(floori(left / CONTOUR_M), floori(up / CONTOUR_M))
		if band != neighbour:
			var bold: bool = posmod(mini(band, neighbour), BOLD_EVERY) == 0
			colour = colour.lerp(INK, 0.42 if bold else 0.26)
		if _wet[k] != 0:
			colour = WATER.lerp(DEEP, clampf((_water_level - h) / 8.0, 0.0, 1.0))
		if _ridge_outer > 0.0:
			var d: float = _world_of(i, j).length()
			colour.a = 1.0 - (1.0 - FADE_TO) * clampf((d - _ridge_outer) / FADE_M, 0.0, 1.0)
		image.set_pixel(i, j, colour)


func _finish() -> void:
	texture = ImageTexture.create_from_image(image)
	_heights = PackedFloat32Array()
	_wet = PackedByteArray()
	_done = true
	builds += 1
