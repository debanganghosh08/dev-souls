class_name GarmentKit
extends RefCounted
## Clothes the player can find and put on (W9-C): a cloak, a leather coat, a shoulder mantle. Each one is a
## curved sheet of cloth hanging from the shoulders, built here as a plain ArrayMesh so nothing has to be
## rigged, imported or downloaded (D-005 keeps binaries out of git).
##
## The sheet is a half-cylinder wrapped round the body: `spread` degrees of arc centred on the player's
## back, `length` metres down, widening by `flare` as it falls, with a little backward lean so it does not
## sit flat against the legs. A collar and a hem band in the trim colour sell the garment's cut. Nothing
## here animates: the cloth is rigid and attached to a bone, so it swings with the chest but does not
## billow. UNVERIFIED by eye.

const SEGMENTS_ACROSS := 10
const SEGMENTS_DOWN := 6


## One garment as a Node3D with a single MeshInstance3D child, ready to parent to a bone.
static func make(entry: Dictionary, name: String = "garment") -> Node3D:
	var root := Node3D.new()
	root.name = name
	var cloth := MeshInstance3D.new()
	cloth.name = "Cloth"
	cloth.mesh = sheet(entry)
	cloth.material_override = material(_colour(entry.get("colour", "#3a3129")), _f(entry, "roughness", 0.85))
	cloth.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	root.add_child(cloth)
	var collar_h: float = _f(entry, "collar", 0.0)
	if collar_h > 0.001:
		var collar := MeshInstance3D.new()
		collar.name = "Collar"
		collar.mesh = sheet(entry, collar_h, 0.03)
		collar.material_override = material(_colour(entry.get("trim", "#241d18")), 0.7)
		root.add_child(collar)
	root.position = Vector3(0.0, _f(entry, "lift", 0.0), -_f(entry, "back", 0.03))
	root.rotation.y = deg_to_rad(_f(entry, "yaw_deg", 0.0))
	return root


## The cloth itself. `only_length` builds a short band instead of the full fall (the collar), `grow` pushes
## it out from the body so the collar sits over the cloak rather than inside it.
static func sheet(entry: Dictionary, only_length: float = 0.0, grow: float = 0.0) -> ArrayMesh:
	var spread: float = deg_to_rad(clampf(_f(entry, "spread_deg", 125.0), 20.0, 179.0))
	var top_r: float = _f(entry, "radius", 0.2) + grow
	var flare: float = _f(entry, "flare", 0.12)
	var length: float = only_length if only_length > 0.001 else _f(entry, "length", 0.78)
	var lean: float = _f(entry, "lean", 0.06)
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	for row: int in range(SEGMENTS_DOWN + 1):
		var v: float = float(row) / float(SEGMENTS_DOWN)
		var radius: float = top_r + flare * v * v
		var y: float = -length * v
		var z_push: float = -lean * v * v
		for col: int in range(SEGMENTS_ACROSS + 1):
			var u: float = float(col) / float(SEGMENTS_ACROSS)
			var a: float = lerpf(-spread * 0.5, spread * 0.5, u)
			# a = 0 is straight behind the player, so the opening falls at the front.
			var dir := Vector3(sin(a), 0.0, -cos(a))
			verts.append(dir * radius + Vector3(0.0, y, z_push))
			normals.append(dir)
			uvs.append(Vector2(u, v))
	for row: int in range(SEGMENTS_DOWN):
		for col: int in range(SEGMENTS_ACROSS):
			var a: int = row * (SEGMENTS_ACROSS + 1) + col
			var b: int = a + 1
			var c: int = a + SEGMENTS_ACROSS + 1
			var d: int = c + 1
			indices.append_array(PackedInt32Array([a, c, b, b, c, d]))
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## Cloth is seen from both sides, so it is never backface-culled and never shades the inside black.
static func material(colour: Color, roughness: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = colour
	m.roughness = clampf(roughness, 0.0, 1.0)
	m.metallic = 0.0
	m.metallic_specular = 0.15
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


static func _colour(value: Variant) -> Color:
	if value is String:
		return Color(str(value))
	if value is Array and (value as Array).size() >= 3:
		var a: Array = value
		return Color(float(a[0]), float(a[1]), float(a[2]))
	return Color(0.23, 0.19, 0.16)


static func _f(d: Dictionary, key: String, fallback: float) -> float:
	var v: Variant = d.get(key, fallback)
	return float(v) if v is float or v is int else fallback
