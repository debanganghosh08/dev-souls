class_name Footprint
extends RefCounted
## Where a structure meets the ground, as oriented rectangles in XZ. Grass, trees and props ask this so they
## stop at a wall or a floor instead of being kept off a whole plateau -- the old rule that left the castle
## hill bare for 118 m around the castle.
##
## An OBB is {"centre": Vector2, "ux": Vector2, "uz": Vector2, "hx": float, "hz": float}: a centre, the two
## unit axes of the rectangle and its half extents along each. Building it from the placement's own basis
## (rather than from a yaw angle) keeps it in Godot's rotation convention whatever that convention is.
## The rectangles mirror StructureKit's conventions; tests/test_crypt_mouth.gd keeps an independent copy of
## the same arithmetic on purpose, so a mistake here cannot silently agree with itself there.

## Pieces that stand on the ground. Roofs, rubble, frames, bells and headstones are left out: grass growing
## round rubble or under a bell frame is what a ruin looks like.
const GROUND_KINDS: Array[String] = ["floor_slab", "block", "wall", "broken_wall", "stairs", "arch", "pillar",
		"buttress"]
## A piece counts as on the ground when its origin sits in this band of layout-local y. Wall-walks and lofts
## are above it. Anything starting lower than GROUND_Y_MIN is buried: under terrain it is invisible (the crypt's
## ceiling lies 0.3 m under the graveyard, and counting it would leave an 11 m bare patch there), and where it
## is visible it is because a terrain hole exposes it -- and holes are masked whole by SiteRegistry.keep_out.
const GROUND_Y_MIN := -0.1
const GROUND_Y_MAX := 0.5


## The piece's footprint in its own space, before placement. Rect2() for anything that is not a ground kind.
static func local_rect(kind: String, p: Dictionary) -> Rect2:
	var w: float = _f(p, "w", 0.0)
	match kind:
		"floor_slab", "block":
			var d: float = _f(p, "d", 0.0)
			return Rect2(-w * 0.5, -d * 0.5, w, d)
		"wall", "broken_wall", "arch":
			var t: float = _f(p, "t", 0.5)
			return Rect2(-w * 0.5, -t * 0.5, w, t)
		"stairs":
			var run: float = stair_run(p)
			return Rect2(-w * 0.5, -run, w, run)
		"pillar":
			# StructureKit.pillar flares its base and capital to 1.18x the radius.
			var flare: float = _f(p, "radius", 0.4) * 1.18
			return Rect2(-flare, -flare, flare * 2.0, flare * 2.0)
		"buttress":
			# Stands against a wall face at z = 0 and leans out to +Z.
			var depth: float = _f(p, "depth", 1.2)
			return Rect2(-w * 0.5, 0.0, w, depth)
	return Rect2()


## Must mirror StructureKit.stairs: the riser is capped, then rounded up to a whole number of steps.
static func stair_run(p: Dictionary) -> float:
	var capped: float = minf(_f(p, "riser", StructureKit.DEFAULT_RISER), StructureKit.MAX_RISER)
	var steps: int = maxi(1, ceili(_f(p, "rise", 0.0) / capped - 0.001))
	return _f(p, "tread", StructureKit.DEFAULT_TREAD) * float(steps)


## Every ground OBB of a layout, in layout-local XZ. A layout may also list `keep_out` rects
## ([x, z, w, d], layout-local, axis-aligned) for ground the pieces do not cover but grass must not grow on,
## such as a house's earth floor.
static func layout_obbs(layout: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for raw: Variant in layout.get("pieces", []):
		if not raw is Dictionary:
			continue
		var entry: Dictionary = raw
		var kind: String = str(entry.get("kind", ""))
		if not GROUND_KINDS.has(kind):
			continue
		var rect: Rect2 = local_rect(kind, entry.get("params", {}))
		if rect.size.x <= 0.0 or rect.size.y <= 0.0:
			continue
		for t: Transform3D in StructureBuilder.placements_of(entry):
			if t.origin.y < GROUND_Y_MIN or t.origin.y > GROUND_Y_MAX:
				continue
			out.append(_placed(rect, t))
	for raw: Variant in layout.get("keep_out", []):
		if raw is Array and (raw as Array).size() >= 4:
			var r: Array = raw
			out.append(_placed(Rect2(float(r[0]), float(r[1]), float(r[2]), float(r[3])).abs(), Transform3D.IDENTITY))
	return out


## A terrain hole as the ground actually loses it: TerrainMesh drops a cell when the cell's CENTRE lies in the
## authored rect, so the gap is the rect grown outwards to whole cells (D-014).
static func snap_hole(rect: Rect2, world_size: float, spacing: float) -> Rect2:
	var half: float = world_size * 0.5
	var lo := Vector2(_first_edge(rect.position.x, half, spacing), _first_edge(rect.position.y, half, spacing))
	var hi := Vector2(_last_edge(rect.end.x, half, spacing), _last_edge(rect.end.y, half, spacing))
	return Rect2(lo, hi - lo)


static func _first_edge(v: float, half: float, spacing: float) -> float:
	return -half + float(ceili((v - spacing * 0.5 + half) / spacing)) * spacing


static func _last_edge(v: float, half: float, spacing: float) -> float:
	return -half + float(floori((v - spacing * 0.5 + half) / spacing) + 1) * spacing


## An axis-aligned world rect as an OBB.
static func rect_obb(rect: Rect2) -> Dictionary:
	return {"centre": rect.get_center(), "ux": Vector2.RIGHT, "uz": Vector2(0.0, 1.0),
			"hx": rect.size.x * 0.5, "hz": rect.size.y * 0.5}


## Moves a layout-local OBB to where a site puts it: rotated by yaw about the site origin, then translated.
static func transform_obb(obb: Dictionary, origin: Vector2, yaw_deg: float) -> Dictionary:
	var basis := Basis(Vector3.UP, deg_to_rad(yaw_deg))
	var c: Vector2 = obb["centre"]
	var moved: Vector3 = basis * Vector3(c.x, 0.0, c.y)
	return {
		"centre": Vector2(moved.x, moved.z) + origin,
		"ux": _rotate(basis, obb["ux"]), "uz": _rotate(basis, obb["uz"]),
		"hx": obb["hx"], "hz": obb["hz"],
	}


static func has_point(obb: Dictionary, x: float, z: float, margin: float = 0.0) -> bool:
	var d: Vector2 = Vector2(x, z) - (obb["centre"] as Vector2)
	return absf(d.dot(obb["ux"])) <= float(obb["hx"]) + margin and absf(d.dot(obb["uz"])) <= float(obb["hz"]) + margin


## Axis-aligned box around an OBB grown by margin: the region worth testing cell by cell.
static func bounds(obb: Dictionary, margin: float = 0.0) -> Rect2:
	var ux: Vector2 = obb["ux"]
	var uz: Vector2 = obb["uz"]
	var ex: float = absf(ux.x) * (float(obb["hx"]) + margin) + absf(uz.x) * (float(obb["hz"]) + margin)
	var ez: float = absf(ux.y) * (float(obb["hx"]) + margin) + absf(uz.y) * (float(obb["hz"]) + margin)
	var c: Vector2 = obb["centre"]
	return Rect2(c.x - ex, c.y - ez, ex * 2.0, ez * 2.0)


static func _placed(rect: Rect2, t: Transform3D) -> Dictionary:
	var centre: Vector2 = rect.get_center()
	var at: Vector3 = t * Vector3(centre.x, 0.0, centre.y)
	return {
		"centre": Vector2(at.x, at.z),
		"ux": _flat(t.basis.x), "uz": _flat(t.basis.z),
		"hx": rect.size.x * 0.5, "hz": rect.size.y * 0.5,
	}


# A basis axis projected onto the ground and normalised; a tilted piece still covers its full width.
static func _flat(v: Vector3) -> Vector2:
	var f := Vector2(v.x, v.z)
	return f.normalized() if f.length_squared() > 0.000001 else Vector2.RIGHT


static func _rotate(basis: Basis, v: Vector2) -> Vector2:
	var r: Vector3 = basis * Vector3(v.x, 0.0, v.y)
	return Vector2(r.x, r.z)


static func _f(d: Dictionary, key: String, fallback: float) -> float:
	var v: Variant = d.get(key, fallback)
	return float(v) if v is float or v is int else fallback
