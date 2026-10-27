class_name StructureKitHouse
extends RefCounted
## Kit pieces for houses, sheds, barns, watch huts and shrines (W8-H). StructureBuilder.make_piece falls
## through to make() for any kind it does not know; a kind this file owns returns a piece dictionary like
## StructureKit's ({kind, mesh, shapes, verts}), anything else {}. Built with StructureKit.builder so
## tiling and UV offsets match the rest of the kit. Same conventions: origin at the base centre, width
## along X, thickness along Z, height up.
##
## Three pieces are enough for five archetypes. A lean_roof is the one-slope roof of a shack; a lean_wall is
## the side wall under it, whose top climbs from the low eave to the high one; a gable is the triangle that
## closes the end of a pitched roof, which the kit's flat-topped walls never did (the village shacks are
## open under their roofs, which reads as ruin there and would read as a mistake on an intact cottage).

## Thickness of the little plate laid along a lean-to's high eave, so the roof reads as resting on something.
const PLATE := 0.14


static func make(kind: String, p: Dictionary, name: String = "") -> Dictionary:
	var mat: String = str(p.get("mat", "planks"))
	match kind:
		"lean_roof":
			return lean_roof(_f(p, "w", 3.0), _f(p, "d", 4.0), _f(p, "drop", 0.6), _f(p, "t", 0.1), mat,
					_f(p, "overhang", 0.3), name)
		"lean_wall":
			return lean_wall(_f(p, "w", 4.0), _f(p, "h", 2.5), _f(p, "rise", 0.6), _f(p, "t", 0.1), mat,
					_d(p, "opening"), name)
		"gable":
			return gable(_f(p, "w", 5.0), _f(p, "rise", 2.0), _f(p, "t", 0.5), mat, name)
	return {}


## One slab sloping down toward +Z: level with the origin along the high eave at z = -d/2 and `drop` lower
## at the low eave z = +d/2, overhanging every edge. Place it at the HIGH wall's height; the low wall is
## `drop` shorter. One box, one collider.
static func lean_roof(w: float, d: float, drop: float, t: float, mat: String, overhang: float = 0.3,
		name: String = "") -> Dictionary:
	var b := StructureKit.builder(mat, name)
	var phi: float = atan2(drop, d)
	var length: float = sqrt(drop * drop + d * d) + 2.0 * overhang
	var out := Vector3(0.0, cos(phi), sin(phi))
	var centre: Vector3 = Vector3(0.0, -drop * 0.5, 0.0) + out * (t * 0.5)
	b.add_box(Transform3D(Basis(Vector3.RIGHT, phi), centre), Vector3(w + 2.0 * overhang, t, length))
	b.add_box(Transform3D(Basis.IDENTITY, Vector3(0.0, -PLATE * 0.5, -d * 0.5)), Vector3(w, PLATE, PLATE), false)
	return _piece(b, mat, "lean_roof")


## A wall whose top climbs from h at the -X end to h + rise at the +X end: the side wall of a lean-to. The
## box part takes an opening exactly as StructureKit.wall does (same pier arithmetic, so a door cut here
## matches one cut there); the opening must fit under h. The sloped top is one wedge with its vertical face
## at the high end, so the eave line is a straight edge and not a stair of boxes.
static func lean_wall(w: float, h: float, rise: float, t: float, mat: String, opening: Dictionary = {},
		name: String = "") -> Dictionary:
	var b := StructureKit.builder(mat, name)
	if opening.is_empty():
		b.add_box(_at(0.0, h * 0.5, 0.0), Vector3(w, h, t))
	else:
		var ow: float = float(opening.get("width", 1.1))
		var oh: float = float(opening.get("height", 2.2))
		var sill: float = float(opening.get("sill", 0.0))
		var ox: float = float(opening.get("offset", 0.0))
		var left_w: float = (ox - ow * 0.5) + w * 0.5
		var right_w: float = w * 0.5 - (ox + ow * 0.5)
		if left_w > 0.01:
			b.add_box(_at(-w * 0.5 + left_w * 0.5, h * 0.5, 0.0), Vector3(left_w, h, t))
		if right_w > 0.01:
			b.add_box(_at(w * 0.5 - right_w * 0.5, h * 0.5, 0.0), Vector3(right_w, h, t))
		var top: float = sill + oh
		if top < h - 0.01:
			b.add_box(_at(ox, (h + top) * 0.5, 0.0), Vector3(ow, h - top, t))
		if sill > 0.01:
			b.add_box(_at(ox, sill * 0.5, 0.0), Vector3(ow, sill, t))
	if rise > 0.001:
		# A wedge's vertical face is at its local z = 0 and its slope runs down toward local +Z. Turned -90
		# degrees about Y, local +Z becomes -X: the face stands at the high end x = +w/2 and the top descends
		# to -w/2; local X (the wedge's width, here the wall's thickness) becomes Z.
		b.add_wedge(Transform3D(Basis(Vector3.UP, -PI * 0.5), Vector3(w * 0.5, h, 0.0)), t, rise, w)
	return _piece(b, mat, "lean_wall")


## An isosceles triangle, base w along X at the origin and apex `rise` up, `t` thick along Z: two wedges
## back to back, each with its vertical face on the centre line. Sits on a wall of the same width to close
## the end of a pitched roof of the same rise. Collision is the two slope boxes the wedges carry.
static func gable(w: float, rise: float, t: float, mat: String, name: String = "") -> Dictionary:
	var b := StructureKit.builder(mat, name)
	b.add_wedge(Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3.ZERO), t, rise, w * 0.5)
	b.add_wedge(Transform3D(Basis(Vector3.UP, -PI * 0.5), Vector3.ZERO), t, rise, w * 0.5)
	return _piece(b, mat, "gable")


static func _piece(b: StructureMeshBuilder, mat: String, kind: String) -> Dictionary:
	return {"kind": kind, "mesh": b.commit(StructureMaterials.get_material(mat)), "shapes": b.shapes, "verts": b.vertex_count()}


static func _at(x: float, y: float, z: float) -> Transform3D:
	return Transform3D(Basis.IDENTITY, Vector3(x, y, z))


static func _f(d: Dictionary, key: String, fallback: float) -> float:
	var v: Variant = d.get(key, fallback)
	return float(v) if v is float or v is int else fallback


static func _d(d: Dictionary, key: String) -> Dictionary:
	var v: Variant = d.get(key, {})
	return v if v is Dictionary else {}
