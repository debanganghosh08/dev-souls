class_name StructureKit
extends RefCounted
## Modular ruin kit: every function returns a "piece" {kind, mesh: ArrayMesh, shapes: [{shape, transform}],
## verts} built from honest primitives wearing the real PBR textures (D-001: no toy kits). Pieces are placed
## with make_node (one) or make_multi (many identical, one MultiMesh + one body). Conventions: origin at the
## base centre, width along X, thickness/depth along Z, height up; stairs climb toward -Z from the foot.
## Roofs, rubble, bells and headstones live in StructureKitParts, the opt-in plinth and string course in
## StructureKitTrim, to keep this file under 250 lines. Every function takes the piece entry's `name` last:
## it only seeds the UV offset (see StructureMeshBuilder.uv_offset_for), so leaving it empty is harmless.

## PlayerController.max_step_height is 0.4 m; a riser is clamped to 0.3 so the capsule still clears a tread
## while sliding along a wall. The greybox staircase the player provably climbs uses 0.25.
const MAX_RISER := 0.3
const DEFAULT_RISER := 0.25
const DEFAULT_TREAD := 0.35
const WORLD_LAYER := 1
const ARCH_STRIPS := 10
const BROKEN_SEGMENT := 0.8


## plinth {h, out} and course {y, h, out} are off unless given (a plain wall stays one box, which
## tests/test_structures.gd pins); both break around the opening and carry their own collision.
static func wall(w: float, h: float, t: float, mat: String, opening: Dictionary = {}, plinth: Dictionary = {},
		course: Dictionary = {}, name: String = "") -> Dictionary:
	var b := builder(mat, name)
	if opening.is_empty():
		b.add_box(_at(0.0, h * 0.5, 0.0), Vector3(w, h, t))
	else:
		var ow: float = float(opening.get("width", 1.4))
		var oh: float = float(opening.get("height", 2.4))
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
	StructureKitTrim.wall_bands(b, w, h, t, opening, plinth, course)
	return _piece(b, mat, "wall")


## Jagged top falling from full height at -X to h*keep at +X: the silhouette of a wall that lost its far end.
static func broken_wall(w: float, h: float, t: float, mat: String, seed: int, keep: float = 0.4, name: String = "") -> Dictionary:
	var b := builder(mat, name)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var n: int = maxi(2, roundi(w / BROKEN_SEGMENT))
	var seg: float = w / float(n)
	for i: int in range(n):
		var f: float = (float(i) + 0.5) / float(n)
		var target: float = lerpf(h, h * keep, smoothstep(0.0, 1.0, f))
		var hi: float = maxf(0.3, target * rng.randf_range(0.78, 1.06))
		b.add_box(_at(-w * 0.5 + seg * (float(i) + 0.5), hi * 0.5, 0.0), Vector3(seg, hi, t))
	return _piece(b, mat, "broken_wall")


static func pillar(radius: float, h: float, mat: String, sides: int = 10, name: String = "") -> Dictionary:
	var b := builder(mat, name)
	var flare: float = radius * 1.18
	var band: float = minf(0.35, h * 0.1)
	var profile := PackedVector2Array([
		Vector2(flare, 0.0), Vector2(flare, band), Vector2(radius, band + 0.05),
		Vector2(radius, h - band - 0.05), Vector2(flare, h - band), Vector2(flare, h),
	])
	var shape := CylinderShape3D.new()
	shape.radius = flare
	shape.height = h
	b.add_lathe(Transform3D.IDENTITY, profile, sides, shape, Vector3(0.0, h * 0.5, 0.0))
	return _piece(b, mat, "pillar")


## A wall with an arched opening: two piers and vertical strips above the arc so the opening reads curved.
static func arch(w: float, h: float, t: float, mat: String, ow: float, oh: float, name: String = "") -> Dictionary:
	var b := builder(mat, name)
	var pier: float = (w - ow) * 0.5
	b.add_box(_at(-w * 0.5 + pier * 0.5, h * 0.5, 0.0), Vector3(pier, h, t))
	b.add_box(_at(w * 0.5 - pier * 0.5, h * 0.5, 0.0), Vector3(pier, h, t))
	var r: float = ow * 0.5
	var spring: float = oh - r
	var strip: float = ow / float(ARCH_STRIPS)
	for i: int in range(ARCH_STRIPS):
		var xm: float = -ow * 0.5 + strip * (float(i) + 0.5)
		var bottom: float = spring + sqrt(maxf(0.0, r * r - xm * xm))
		if bottom < h - 0.01:
			b.add_box(_at(xm, (h + bottom) * 0.5, 0.0), Vector3(strip, h - bottom, t))
	return _piece(b, mat, "arch")


## Solid flight climbing toward -Z. Every step is its own box so the step-up probe finds a real tread.
static func stairs(w: float, rise: float, mat: String, riser: float = DEFAULT_RISER, tread: float = DEFAULT_TREAD,
		name: String = "") -> Dictionary:
	var b := builder(mat, name)
	var capped: float = minf(riser, MAX_RISER)
	var steps: int = maxi(1, ceili(rise / capped - 0.001))
	var actual: float = rise / float(steps)
	for i: int in range(steps):
		var top: float = actual * float(i + 1)
		b.add_box(_at(0.0, top * 0.5, -tread * (float(i) + 0.5)), Vector3(w, top, tread))
	var piece: Dictionary = _piece(b, mat, "stairs")
	piece["riser"] = actual
	piece["steps"] = steps
	piece["run"] = tread * float(steps)
	return piece


static func floor_slab(w: float, d: float, t: float, mat: String, name: String = "") -> Dictionary:
	return block(Vector3(w, t, d), mat, "floor_slab", {}, {}, name)


## A block is free-standing (a tower, a pew), so its plinth and course wrap all four sides.
static func block(size: Vector3, mat: String, kind: String = "block", plinth: Dictionary = {}, course: Dictionary = {},
		name: String = "") -> Dictionary:
	var b := builder(mat, name)
	b.add_box(_at(0.0, size.y * 0.5, 0.0), size)
	StructureKitTrim.block_bands(b, size, plinth, course)
	return _piece(b, mat, kind)


## Four posts and four top plates; plank or plaster walls are separate pieces so each can be ruined alone.
static func timber_frame(w: float, h: float, d: float, beam: float, mat: String, name: String = "") -> Dictionary:
	var b := builder(mat, name)
	var hx: float = w * 0.5 - beam * 0.5
	var hz: float = d * 0.5 - beam * 0.5
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			b.add_box(_at(sx * hx, h * 0.5, sz * hz), Vector3(beam, h, beam))
		b.add_box(_at(0.0, h - beam * 0.5, sx * hz), Vector3(w, beam, beam))
		b.add_box(_at(sx * hx, h - beam * 0.5, 0.0), Vector3(beam, beam, d - 2.0 * beam))
	return _piece(b, mat, "timber_frame")


## Stands against a wall face at z=0 and leans out to +Z: a block with a sloping wedge cap.
static func buttress(w: float, h: float, depth: float, mat: String, name: String = "") -> Dictionary:
	var b := builder(mat, name)
	var base_h: float = h * 0.55
	b.add_box(_at(0.0, base_h * 0.5, depth * 0.5), Vector3(w, base_h, depth))
	b.add_wedge(_at(0.0, base_h, 0.0), w, h - base_h, depth)
	return _piece(b, mat, "buttress")


static func pitched_roof(w: float, d: float, rise: float, t: float, mat: String, overhang: float = 0.3, name: String = "") -> Dictionary:
	return StructureKitParts.pitched_roof(w, d, rise, t, mat, overhang, name)


static func collapsed_roof(w: float, d: float, rise: float, t: float, mat: String, seed: int, name: String = "") -> Dictionary:
	return StructureKitParts.collapsed_roof(w, d, rise, t, mat, seed, name)


static func rubble(radius: float, count: int, mat: String, seed: int, name: String = "") -> Dictionary:
	return StructureKitParts.rubble(radius, count, mat, seed, name)


static func bell(radius: float, h: float, mat: String, name: String = "") -> Dictionary:
	return StructureKitParts.bell(radius, h, mat, name)


static func headstone(w: float, h: float, t: float, mat: String, name: String = "") -> Dictionary:
	return StructureKitParts.headstone(w, h, t, mat, name)


## A builder tiling at the material's metres_per_tile, its UVs shifted by the piece name's fixed offset.
static func builder(mat: String, name: String = "") -> StructureMeshBuilder:
	return StructureMeshBuilder.new(StructureMaterials.metres_per_tile(mat), StructureMeshBuilder.uv_offset_for(name))


## One MeshInstance3D plus a StaticBody3D on the world layer carrying every recorded shape.
static func make_node(piece: Dictionary, name: String) -> Node3D:
	var root := Node3D.new()
	root.name = name
	root.set_meta(&"piece_kind", str(piece["kind"]))
	var mi := MeshInstance3D.new()
	mi.name = "Mesh"
	mi.mesh = piece["mesh"]
	root.add_child(mi)
	var shapes: Array = piece["shapes"]
	if not shapes.is_empty():
		root.add_child(_body(shapes, [Transform3D.IDENTITY]))
	return root


## Many placements of one piece: a single MultiMesh draw and one body with the shapes repeated per instance.
static func make_multi(piece: Dictionary, transforms: Array[Transform3D], name: String) -> Node3D:
	var root := Node3D.new()
	root.name = name
	root.set_meta(&"piece_kind", str(piece["kind"]))
	root.set_meta(&"instances", transforms.size())
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = piece["mesh"]
	mm.instance_count = transforms.size()
	for i: int in range(transforms.size()):
		mm.set_instance_transform(i, transforms[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Multi"
	mmi.multimesh = mm
	root.add_child(mmi)
	var shapes: Array = piece["shapes"]
	if not shapes.is_empty():
		root.add_child(_body(shapes, transforms))
	return root


static func _body(shapes: Array, placements: Array) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = "Body"
	body.collision_layer = WORLD_LAYER
	body.collision_mask = 0
	for placement: Transform3D in placements:
		for s: Dictionary in shapes:
			var cs := CollisionShape3D.new()
			cs.shape = s["shape"]
			cs.transform = placement * (s["transform"] as Transform3D)
			body.add_child(cs)
	return body


static func _piece(b: StructureMeshBuilder, mat: String, kind: String) -> Dictionary:
	var mesh: ArrayMesh = b.commit(StructureMaterials.get_material(mat))
	return {"kind": kind, "mesh": mesh, "shapes": b.shapes, "verts": b.vertex_count()}


static func _at(x: float, y: float, z: float) -> Transform3D:
	return Transform3D(Basis.IDENTITY, Vector3(x, y, z))
