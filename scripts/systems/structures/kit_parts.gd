class_name StructureKitParts
extends RefCounted
## The kit pieces that are not plain walls: roofs (intact and collapsed), rubble piles, bells and headstones.
## Same conventions and piece dictionary as StructureKit, which forwards to these.

const RAFTER := 0.16
const SAG_EXTRA_RAD := 0.45
const RUBBLE_SINK := 0.3


## Two sloped slabs meeting on a ridge along X at y = rise; origin on the eave line's centre.
static func pitched_roof(w: float, d: float, rise: float, t: float, mat: String, overhang: float) -> Dictionary:
	var b := StructureMeshBuilder.new()
	var full_w: float = w + 2.0 * overhang
	_slope(b, 0.0, full_w, d, rise, t, overhang, 1.0, 0.0)
	_slope(b, 0.0, full_w, d, rise, t, overhang, -1.0, 0.0)
	b.add_box(Transform3D(Basis.IDENTITY, Vector3(0.0, rise + t * 0.5, 0.0)), Vector3(full_w, RAFTER, RAFTER))
	return {"kind": "pitched_roof", "mesh": b.commit(StructureMaterials.get_material(mat)), "shapes": b.shapes, "verts": b.vertex_count()}


## One slope intact; the other in three bays: one sagging from the ridge, one fallen inside, one down to
## bare rafters. The seed only sets how the fallen bay lies.
static func collapsed_roof(w: float, d: float, rise: float, t: float, mat: String, seed: int) -> Dictionary:
	var b := StructureMeshBuilder.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var overhang: float = 0.3
	var full_w: float = w + 2.0 * overhang
	var bay: float = full_w / 3.0
	var half: float = d * 0.5
	var slope_len: float = sqrt(rise * rise + half * half) + overhang
	_slope(b, 0.0, full_w, d, rise, t, overhang, -1.0, 0.0)
	_slope(b, -bay, bay, d, rise, t, overhang, 1.0, SAG_EXTRA_RAD)
	var tilt: float = rng.randf_range(0.12, 0.3)
	var yaw: float = rng.randf_range(-0.5, 0.5)
	var fallen := Transform3D(Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, tilt), Vector3(0.0, 0.3 + t, half * 0.45))
	b.add_box(fallen, Vector3(bay * 0.9, t, slope_len * 0.85))
	var phi: float = atan2(rise, half)
	for k: float in [-0.3, 0.3]:
		var x: float = bay + k * bay
		var centre := Vector3(x, rise, 0.0) + Vector3(0.0, -rise, half).normalized() * (slope_len * 0.5)
		b.add_box(Transform3D(Basis(Vector3.RIGHT, phi), centre), Vector3(RAFTER, RAFTER, slope_len))
	b.add_box(Transform3D(Basis.IDENTITY, Vector3(0.0, rise + t * 0.5, 0.0)), Vector3(full_w, RAFTER, RAFTER))
	return {"kind": "collapsed_roof", "mesh": b.commit(StructureMaterials.get_material(mat)), "shapes": b.shapes, "verts": b.vertex_count()}


## Fallen blocks partly sunk into the ground. Each stays under ~0.4 m proud so the player's step-up clears it.
static func rubble(radius: float, count: int, mat: String, seed: int) -> Dictionary:
	var b := StructureMeshBuilder.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	for i: int in range(count):
		var size := Vector3(rng.randf_range(0.35, 0.9), rng.randf_range(0.25, 0.5), rng.randf_range(0.35, 0.9))
		var r: float = radius * sqrt(rng.randf())
		var a: float = rng.randf() * TAU
		var basis: Basis = Basis(Vector3.UP, rng.randf() * TAU) * Basis(Vector3.RIGHT, rng.randf_range(-0.25, 0.25)) \
			* Basis(Vector3.FORWARD, rng.randf_range(-0.25, 0.25))
		b.add_box(Transform3D(basis, Vector3(cos(a) * r, size.y * RUBBLE_SINK, sin(a) * r)), size)
	return {"kind": "rubble", "mesh": b.commit(StructureMaterials.get_material(mat)), "shapes": b.shapes, "verts": b.vertex_count()}


## A closed bell profile (the mouth is capped: an open shell would be back-face culled from below).
static func bell(radius: float, h: float, mat: String) -> Dictionary:
	var b := StructureMeshBuilder.new()
	var profile := PackedVector2Array([
		Vector2(radius, 0.0), Vector2(radius * 0.96, h * 0.07), Vector2(radius * 0.78, h * 0.22),
		Vector2(radius * 0.62, h * 0.45), Vector2(radius * 0.52, h * 0.7), Vector2(radius * 0.42, h * 0.88),
		Vector2(radius * 0.24, h), Vector2(radius * 0.1, h * 1.06), Vector2(0.0, h * 1.06),
	])
	var shape := CylinderShape3D.new()
	shape.radius = radius
	shape.height = h
	b.add_lathe(Transform3D.IDENTITY, profile, 16, shape, Vector3(0.0, h * 0.5, 0.0))
	return {"kind": "bell", "mesh": b.commit(StructureMaterials.get_material(mat)), "shapes": b.shapes, "verts": b.vertex_count()}


static func headstone(w: float, h: float, t: float, mat: String) -> Dictionary:
	var b := StructureMeshBuilder.new()
	var cap: float = w * 0.45
	b.add_box(Transform3D(Basis.IDENTITY, Vector3(0.0, (h - cap) * 0.5, 0.0)), Vector3(w, h - cap, t))
	b.add_box(Transform3D(Basis.IDENTITY, Vector3(0.0, h - cap * 0.5, 0.0)), Vector3(w * 0.7, cap, t), false)
	return {"kind": "headstone", "mesh": b.commit(StructureMaterials.get_material(mat)), "shapes": b.shapes, "verts": b.vertex_count()}


# One roof slab from the ridge down past the eave on the `side` (+1 toward +Z) of the ridge, `width` wide
# and centred on x_centre so bays line up. extra_sag steepens the slab about the ridge (a roof giving way).
static func _slope(b: StructureMeshBuilder, x_centre: float, width: float, d: float, rise: float, t: float,
		overhang: float, side: float, extra_sag: float) -> void:
	var half: float = d * 0.5
	var l0: float = sqrt(rise * rise + half * half)
	var length: float = l0 + overhang
	var phi: float = atan2(rise, half) + extra_sag
	var down := Vector3(0.0, -sin(phi), side * cos(phi))
	var out := Vector3(0.0, cos(phi), side * sin(phi))
	var centre: Vector3 = Vector3(x_centre, rise, 0.0) + down * (length * 0.5) + out * (t * 0.5)
	b.add_box(Transform3D(Basis(Vector3.RIGHT, side * phi), centre), Vector3(width, t, length))
