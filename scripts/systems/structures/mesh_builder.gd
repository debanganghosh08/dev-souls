class_name StructureMeshBuilder
extends RefCounted
## Accumulates boxes, wedges and lathes into one ArrayMesh with flat per-face normals, and records a matching
## collision shape for every solid added. UVs are the face's model-space position in metres divided by
## METRES_PER_TILE: a 4 m wall shows four 1 m stone tiles instead of one image stretched across it, and two
## boxes butted together continue the same tiling without a seam. Normals are faceted on purpose (cut stone).

const METRES_PER_TILE := 1.0

var shapes: Array[Dictionary] = []

var _verts := PackedVector3Array()
var _normals := PackedVector3Array()
var _uvs := PackedVector2Array()
var _indices := PackedInt32Array()


func vertex_count() -> int:
	return _verts.size()


## A quad whose corners run counter-clockwise seen from the outside (Godot's front face).
func add_quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	var n: Vector3 = (b - a).cross(c - a).normalized()
	var base: int = _verts.size()
	for p: Vector3 in [a, b, c, d]:
		_verts.append(p)
		_normals.append(n)
		_uvs.append(_uv_for(p, n))
	_indices.append_array(PackedInt32Array([base, base + 1, base + 2, base, base + 2, base + 3]))


## A box of `size` whose centre sits at xform.origin, with a BoxShape3D recorded when collide is true.
func add_box(xform: Transform3D, size: Vector3, collide: bool = true) -> void:
	var h: Vector3 = size * 0.5
	_add_face(xform, Vector3.RIGHT, Vector3.FORWARD, Vector3.UP, h)
	_add_face(xform, Vector3.LEFT, Vector3.BACK, Vector3.UP, h)
	_add_face(xform, Vector3.UP, Vector3.RIGHT, Vector3.FORWARD, h)
	_add_face(xform, Vector3.DOWN, Vector3.RIGHT, Vector3.BACK, h)
	_add_face(xform, Vector3.BACK, Vector3.RIGHT, Vector3.UP, h)
	_add_face(xform, Vector3.FORWARD, Vector3.LEFT, Vector3.UP, h)
	if collide:
		var shape := BoxShape3D.new()
		shape.size = size
		shapes.append({"shape": shape, "transform": xform})


## A triangular prism: right-angled cross-section in the local Y/Z plane (vertical back face at -Z, sloped
## front from the top of the back face down to +Z), extruded along X. Origin is the bottom of the back face.
## Collision is a thin box lying on the slope so the player slides off it instead of standing inside it.
func add_wedge(xform: Transform3D, width: float, height: float, depth: float, collide: bool = true) -> void:
	var hw: float = width * 0.5
	var a: Vector3 = xform * Vector3(-hw, 0.0, 0.0)
	var b: Vector3 = xform * Vector3(hw, 0.0, 0.0)
	var c: Vector3 = xform * Vector3(hw, height, 0.0)
	var d: Vector3 = xform * Vector3(-hw, height, 0.0)
	var e: Vector3 = xform * Vector3(-hw, 0.0, depth)
	var f: Vector3 = xform * Vector3(hw, 0.0, depth)
	add_quad(a, d, c, b) # back (faces -Z)
	add_quad(e, f, c, d) # slope
	add_quad(a, b, f, e) # bottom
	_add_tri(a, e, d) # left end (faces -X)
	_add_tri(b, c, f) # right end (faces +X)
	if collide:
		var slope_len: float = sqrt(height * height + depth * depth)
		var shape := BoxShape3D.new()
		shape.size = Vector3(width, 0.1, slope_len)
		var tilt := Transform3D(Basis(Vector3.RIGHT, atan2(height, depth)), Vector3(0.0, height * 0.5, depth * 0.5))
		shapes.append({"shape": shape, "transform": xform * tilt})


## A surface of revolution around local Y from a (radius, y) profile running bottom to top, closed with flat
## caps at either end when the profile does not already reach the axis. Used for pillars and bells.
func add_lathe(xform: Transform3D, profile: PackedVector2Array, sides: int, collider: Shape3D = null,
		collider_offset: Vector3 = Vector3.ZERO) -> void:
	for i: int in range(profile.size() - 1):
		var lo: Vector2 = profile[i]
		var hi: Vector2 = profile[i + 1]
		for s: int in range(sides):
			var a0: float = TAU * float(s) / float(sides)
			var a1: float = TAU * float(s + 1) / float(sides)
			var p0 := Vector3(cos(a0) * lo.x, lo.y, sin(a0) * lo.x)
			var p1 := Vector3(cos(a1) * lo.x, lo.y, sin(a1) * lo.x)
			var p2 := Vector3(cos(a1) * hi.x, hi.y, sin(a1) * hi.x)
			var p3 := Vector3(cos(a0) * hi.x, hi.y, sin(a0) * hi.x)
			# Outward winding: travelling +angle at the bottom then up is clockwise seen from outside, so flip.
			add_quad(xform * p0, xform * p3, xform * p2, xform * p1)
	_cap(xform, profile[0], sides, false)
	_cap(xform, profile[profile.size() - 1], sides, true)
	if collider != null:
		shapes.append({"shape": collider, "transform": xform.translated_local(collider_offset)})


func commit(material: Material) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	if _verts.is_empty():
		return mesh
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = _verts
	arrays[Mesh.ARRAY_NORMAL] = _normals
	arrays[Mesh.ARRAY_TEX_UV] = _uvs
	arrays[Mesh.ARRAY_INDEX] = _indices
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, material)
	return mesh


func _add_face(xform: Transform3D, n: Vector3, t1: Vector3, t2: Vector3, h: Vector3) -> void:
	# t1 x t2 == n for every call above, so (-t1,-t2) -> (+t1,-t2) -> (+t1,+t2) -> (-t1,+t2) is CCW from outside.
	var centre: Vector3 = n * h
	var e1: Vector3 = t1 * h
	var e2: Vector3 = t2 * h
	add_quad(xform * (centre - e1 - e2), xform * (centre + e1 - e2), xform * (centre + e1 + e2), xform * (centre - e1 + e2))


func _add_tri(a: Vector3, b: Vector3, c: Vector3) -> void:
	var n: Vector3 = (b - a).cross(c - a).normalized()
	var base: int = _verts.size()
	for p: Vector3 in [a, b, c]:
		_verts.append(p)
		_normals.append(n)
		_uvs.append(_uv_for(p, n))
	_indices.append_array(PackedInt32Array([base, base + 1, base + 2]))


func _cap(xform: Transform3D, ring: Vector2, sides: int, up: bool) -> void:
	if ring.x <= 0.001:
		return
	var centre: Vector3 = xform * Vector3(0.0, ring.y, 0.0)
	for s: int in range(sides):
		var a0: float = TAU * float(s) / float(sides)
		var a1: float = TAU * float(s + 1) / float(sides)
		var p0: Vector3 = xform * Vector3(cos(a0) * ring.x, ring.y, sin(a0) * ring.x)
		var p1: Vector3 = xform * Vector3(cos(a1) * ring.x, ring.y, sin(a1) * ring.x)
		if up:
			_add_tri(centre, p1, p0)
		else:
			_add_tri(centre, p0, p1)


# Planar projection per face: horizontal faces tile on X/Z, everything else on (along-the-wall, up). V is
# negated so a texture's top edge is the wall's top edge.
func _uv_for(p: Vector3, n: Vector3) -> Vector2:
	if absf(n.y) > 0.9:
		return Vector2(p.x, p.z) / METRES_PER_TILE
	var along: Vector3 = n.cross(Vector3.UP).normalized()
	return Vector2(p.dot(along), -p.y) / METRES_PER_TILE
