class_name MapDraw
extends RefCounted
## The arithmetic behind the map (W19), with no Control and no drawing in it, so a test can check that the
## map puts things where the world put them without opening a window.
##
## The map is north-up and never rotates. A rotating minimap is easier to read while running and far harder
## to read against a drawn map, and the owner asked for the big map to be "exactly" the world with the
## eight compass points marked on it -- which only means anything if north stays where it is.
##
## Every drawn thing comes from the data the world is built from: the area file for the ridge, the pond, the
## river and the plateaus, and SiteRegistry for the buildings. Nothing is listed here by hand, so anything
## added to the Vale appears on the map without this file being touched.

## Metres per side of the little map in the corner. Small enough that a village fills it.
const MINI_SPAN := 320.0
## Dot sizes, in panel pixels, for the small map and the full one.
const MINI_DOT := 1.6
const FULL_DOT := 2.8

## One colour per kind of thing, so the map reads at a glance. Keyed by the kind string a site's layout
## path implies (see kind_of_site) and by the kinds data/places.json uses for its named places.
const COLOURS := {
	"castle": Color(0.86, 0.74, 0.42),
	"village": Color(0.92, 0.84, 0.62),
	"house": Color(0.74, 0.66, 0.52),
	"tower": Color(0.80, 0.70, 0.86),
	"chapel": Color(0.86, 0.86, 0.94),
	"shrine": Color(0.86, 0.86, 0.94),
	"graves": Color(0.60, 0.62, 0.66),
	"camp": Color(0.86, 0.52, 0.36),
	"rock": Color(0.56, 0.56, 0.58),
	"forest": Color(0.32, 0.48, 0.30),
	"water": Color(0.36, 0.56, 0.62),
	"ruin": Color(0.70, 0.60, 0.50),
	"pass": Color(0.66, 0.60, 0.48),
	"farm": Color(0.72, 0.74, 0.48),
	"vista": Color(0.90, 0.80, 0.50),
	"crossing": Color(0.74, 0.62, 0.44),
	"fire": Color(0.95, 0.66, 0.30),
	"prop": Color(0.52, 0.50, 0.46),
}
const UNKNOWN_COLOUR := Color(0.52, 0.50, 0.46)


## Where a world point lands inside `rect`. `centre` is the world point drawn at the middle of the rect and
## `span` is how many metres fit across its shorter side. World +X is right and world -Z is up, because
## north is -Z.
static func to_panel(world: Vector2, centre: Vector2, span: float, rect: Rect2) -> Vector2:
	var scale: float = scale_for(span, rect)
	var mid: Vector2 = rect.position + rect.size * 0.5
	return mid + Vector2((world.x - centre.x) * scale, (world.y - centre.y) * scale)


## Panel pixels per world metre.
static func scale_for(span: float, rect: Rect2) -> float:
	var short: float = minf(rect.size.x, rect.size.y)
	return short / maxf(1.0, span)


## The reverse of to_panel, so a click on the full map can say where in the world it landed.
static func to_world(panel: Vector2, centre: Vector2, span: float, rect: Rect2) -> Vector2:
	var scale: float = scale_for(span, rect)
	var mid: Vector2 = rect.position + rect.size * 0.5
	return centre + (panel - mid) / maxf(0.0001, scale)


## The kind of thing a site is, read off the folder its layout sits in and then its file name. This is how
## the map stays automatic: a new site in data/structures/village/ is a village dot without anyone saying so.
static func kind_of_site(site: Dictionary) -> String:
	var path: String = str(site.get("layout", ""))
	var file: String = path.get_file().get_basename()
	var folder: String = path.get_base_dir().get_file()
	# The file name wins where it is clearly more specific than its folder.
	if file.begins_with("dead_dragon") or file.begins_with("fallen_ring"):
		return "ruin"
	if file.begins_with("hanging_bridge") or file.begins_with("river_bridge") or file.begins_with("stone_bridge"):
		return "crossing"
	if file.begins_with("graveyard") or file.begins_with("lone_grave") or file.begins_with("field_graves"):
		return "graves"
	if file.begins_with("watch") or file.begins_with("tower"):
		return "tower"
	if file.begins_with("chapel") or file.begins_with("shrine"):
		return "chapel"
	if file.begins_with("war_camp") or file.begins_with("siege_camp") or file.begins_with("campsite"):
		return "camp"
	if file.begins_with("flood_pool"):
		return "water"
	if file.begins_with("road_cut"):
		return "pass"
	match folder:
		"castles":
			return "castle"
		"village":
			return "village"
		"houses":
			return "house"
		"towers":
			return "tower"
		"rocks":
			return "rock"
		"pois":
			return "prop"
	return "prop"


static func colour_of(kind: String) -> Color:
	return COLOURS.get(kind, UNKNOWN_COLOUR)


## The eight compass labels, placed just inside the edge of `rect`: [{"text", "at"}, ...]. North is up.
static func compass_marks(rect: Rect2, inset: float = 16.0) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var mid: Vector2 = rect.position + rect.size * 0.5
	var reach: Vector2 = rect.size * 0.5 - Vector2(inset, inset)
	for i: int in Places.COMPASS.size():
		var bearing: float = 45.0 * i
		var dir := Vector2(sin(deg_to_rad(bearing)), -cos(deg_to_rad(bearing)))
		# Push the point out to the edge of the box rather than onto a circle inside it, so the diagonals
		# land in the corners where there is room for them.
		var longest: float = maxf(absf(dir.x), absf(dir.y))
		var at: Vector2 = mid + dir / maxf(0.0001, longest) * reach
		out.append({"text": Places.COMPASS[i], "at": at, "bearing": bearing})
	return out


## Whether a world point is worth drawing at all for this view, with a margin so a dot half outside still
## gets drawn. Cheap, and on the small map it skips nine sites in ten.
static func in_view(world: Vector2, centre: Vector2, span: float, rect: Rect2, margin: float = 8.0) -> bool:
	var at: Vector2 = to_panel(world, centre, span, rect)
	return Rect2(rect.position - Vector2(margin, margin), rect.size + Vector2(margin, margin) * 2.0).has_point(at)


## A polyline in world metres, as panel points.
static func panel_line(points: PackedVector2Array, centre: Vector2, span: float, rect: Rect2) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p: Vector2 in points:
		out.append(to_panel(p, centre, span, rect))
	return out


## Points of a circle, for the pond, the plateaus, the wood and the ridge.
static func circle_points(at: Vector2, radius: float, sides: int = 48) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i: int in sides + 1:
		var a: float = TAU * i / sides
		out.append(at + Vector2(cos(a), sin(a)) * radius)
	return out
