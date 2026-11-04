class_name MapLabels
extends RefCounted
## Where the names go on the full map (W21-C). Twenty-nine places, nine regions and four reaches of river
## would be a wall of text if each were simply written beside its dot, so the names are placed in rank
## order, each one tried on four sides of its point, and a name that fits nowhere without covering another
## is left off: its marker still shows, and the owner can read the ones that are there.
##
## Pure arithmetic over rectangles, so a test can hand it a crowd and check that nothing overlaps.

## Type sizes, in pixels, by what a name is. Regions are large and faint, behind everything; castles
## and villages are the largest ink; towers and ruins next; crofts and shacks smallest.
const EM_REGION := 18
const EM_MAJOR := 15
const EM_MINOR := 12
const EM_SMALL := 11

## Lower is placed first and gets the better slot.
const RANK := {
	"castle": 1, "village": 1,
	"water": 2, "forest": 2,
	"tower": 3, "ruin": 3, "chapel": 3, "shrine": 3, "vista": 3, "pass": 3, "crossing": 3,
}
const RANK_OTHER := 4


static func rank_of(kind: String) -> int:
	return int(RANK.get(kind, RANK_OTHER))


static func em_of(kind: String) -> int:
	match rank_of(kind):
		1:
			return EM_MAJOR
		2, 3:
			return EM_MINOR
	return EM_SMALL


## Places every item it can. Each item is {"text", "at": Vector2 (the point it names, in panel pixels),
## "size": Vector2 (the text's box), "rank": int, "centred": bool, "solid": bool, "gap": float}; a centred
## item sits over its point, a side one beside it; a non-solid item (a region name) is placed but does
## not block anyone. Returns the same items with "pos" (top-left of the text box) and "placed" added, in
## placement order.
static func layout(items: Array[Dictionary], rect: Rect2, pad: float = 2.0) -> Array[Dictionary]:
	var order: Array[Dictionary] = []
	for i: int in items.size():
		var item: Dictionary = items[i].duplicate()
		item["index"] = i
		order.append(item)
	order.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a.get("rank", RANK_OTHER)) != int(b.get("rank", RANK_OTHER)):
			return int(a.get("rank", RANK_OTHER)) < int(b.get("rank", RANK_OTHER))
		return int(a["index"]) < int(b["index"]))
	var taken: Array[Rect2] = []
	var inner: Rect2 = rect.grow(-pad)
	for item: Dictionary in order:
		var size: Vector2 = item.get("size", Vector2.ZERO)
		var at: Vector2 = item.get("at", Vector2.ZERO)
		var gap: float = float(item.get("gap", 6.0))
		var candidates: Array[Vector2] = []
		if bool(item.get("centred", false)):
			candidates.append(at - size * 0.5)
		else:
			candidates.append(Vector2(at.x + gap, at.y - size.y * 0.5))
			candidates.append(Vector2(at.x - gap - size.x, at.y - size.y * 0.5))
			candidates.append(Vector2(at.x - size.x * 0.5, at.y - gap - size.y))
			candidates.append(Vector2(at.x - size.x * 0.5, at.y + gap))
			# The near slots above and below sit closer to the point than a side label's half height, so
			# they can never share the point with one. These two clear a side label, so a crowded point can
			# carry four names: right, left, over and under.
			var clear: float = size.y * 0.5 + pad * 2.0 + 1.0
			candidates.append(Vector2(at.x - size.x * 0.5, at.y - clear - size.y))
			candidates.append(Vector2(at.x - size.x * 0.5, at.y + clear))
		item["placed"] = false
		item["pos"] = candidates[0]
		for c: Vector2 in candidates:
			var box := Rect2(c, size)
			if not inner.encloses(box):
				continue
			if _hits(box.grow(pad), taken):
				continue
			item["pos"] = c
			item["placed"] = true
			if bool(item.get("solid", true)):
				taken.append(box.grow(pad))
			break
	return order


static func _hits(box: Rect2, taken: Array[Rect2]) -> bool:
	for r: Rect2 in taken:
		if r.intersects(box):
			return true
	return false


## True when any two placed solid boxes overlap: what the layout promises never happens.
static func overlaps(placed: Array[Dictionary]) -> bool:
	var boxes: Array[Rect2] = []
	for item: Dictionary in placed:
		if not bool(item.get("placed", false)) or not bool(item.get("solid", true)):
			continue
		var box := Rect2(item["pos"], item["size"])
		if _hits(box, boxes):
			return true
		boxes.append(box)
	return false
