class_name GrassMesh
extends RefCounted
## Builds the shared meshes and materials Grass instances: a textureless blade clump, a textured leaf
## patch quad, a low-poly pebble, and a mesh lifted out of an imported foliage model. Pure builders:
## no nodes, no scene, so tests can count vertices without a renderer.
##
## There is no grass texture and none is coming (D-002: vegetation is geometry). What sells a blade with
## no texture is the vertex colour: dark and green-grey at the root, pale and straw-dry at the tip. The
## shader reads COLOR for albedo and UV.y (0 root, 1 tip) as the bend mask, so one mesh serves both.

const GRASS_SHADER := "res://scripts/systems/grass.gdshader"
const PATCH_SHADER := "res://scripts/systems/ground_patch.gdshader"
const TIP_WIDTH_FRACTION := 0.12
const LEAN_MIN := 0.18
const LEAN_MAX := 0.42
const PEBBLE_SEGMENTS := 5
const PEBBLE_RINGS := 3

static var _grass_shader: Shader
static var _patch_shader: Shader


## A clump of `blades` tapered strips of unit height splayed around the origin, each `segments` quads
## tall so the shader can bend it. Per-blade jitter in yaw, lean and brightness breaks the stamp.
static func clump(blades: int, segments: int, width: float, root: Color, tip: Color, rng: RandomNumberGenerator) -> ArrayMesh:
	var n_blades: int = maxi(1, blades)
	var n_seg: int = maxi(1, segments)
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	for b: int in n_blades:
		var yaw: float = float(b) * TAU / float(n_blades) + rng.randf_range(-0.4, 0.4)
		var dir := Vector3(cos(yaw), 0.0, sin(yaw))
		var side := Vector3(-dir.z, 0.0, dir.x)
		var base: Vector3 = dir * rng.randf_range(0.0, 0.06)
		var lean: float = rng.randf_range(LEAN_MIN, LEAN_MAX)
		var shade: float = rng.randf_range(0.88, 1.12)
		var first: int = verts.size()
		for s: int in n_seg + 1:
			var t: float = float(s) / float(n_seg)
			var half: float = width * 0.5 * lerpf(1.0, TIP_WIDTH_FRACTION, t)
			var p: Vector3 = base + Vector3.UP * t + dir * lean * t * t
			var c: Color = root.lerp(tip, t) * shade
			c.a = 1.0
			for k: int in 2:
				verts.append(p + side * (half if k == 0 else -half))
				normals.append(dir)
				uvs.append(Vector2(float(k), t))
				colors.append(c)
		for s: int in n_seg:
			var i: int = first + s * 2
			indices.append_array(PackedInt32Array([i, i + 2, i + 1, i + 1, i + 2, i + 3]))
	return _mesh(verts, normals, uvs, colors, indices)


## A flat unit quad on the ground plane (y = 0, x/z in -0.5..0.5) for leaf-drift patches.
static func patch_quad() -> ArrayMesh:
	var verts := PackedVector3Array([Vector3(-0.5, 0.0, -0.5), Vector3(0.5, 0.0, -0.5), Vector3(0.5, 0.0, 0.5), Vector3(-0.5, 0.0, 0.5)])
	var normals := PackedVector3Array([Vector3.UP, Vector3.UP, Vector3.UP, Vector3.UP])
	var uvs := PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)])
	var colors := PackedColorArray([Color.WHITE, Color.WHITE, Color.WHITE, Color.WHITE])
	return _mesh(verts, normals, uvs, colors, PackedInt32Array([0, 2, 1, 0, 3, 2]))


## A squashed, jittered unit sphere: a pebble. UV.y stays 0 so the grass shader never bends it.
static func pebble(color: Color, rng: RandomNumberGenerator) -> ArrayMesh:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	var squash := Vector3(rng.randf_range(0.8, 1.2), rng.randf_range(0.45, 0.65), rng.randf_range(0.8, 1.2))
	for r: int in PEBBLE_RINGS + 1:
		var phi: float = PI * float(r) / float(PEBBLE_RINGS)
		for s: int in PEBBLE_SEGMENTS:
			var theta: float = TAU * float(s) / float(PEBBLE_SEGMENTS)
			var p := Vector3(sin(phi) * cos(theta), cos(phi), sin(phi) * sin(theta))
			if r > 0 and r < PEBBLE_RINGS:
				p *= rng.randf_range(0.8, 1.15)
			p = p * squash * 0.5 + Vector3.UP * 0.5 * squash.y
			verts.append(p)
			normals.append(p.normalized())
			uvs.append(Vector2.ZERO)
			colors.append(color.darkened(0.45 * float(r) / float(PEBBLE_RINGS)))
	for r: int in PEBBLE_RINGS:
		for s: int in PEBBLE_SEGMENTS:
			var a: int = r * PEBBLE_SEGMENTS + s
			var b: int = r * PEBBLE_SEGMENTS + (s + 1) % PEBBLE_SEGMENTS
			var c: int = a + PEBBLE_SEGMENTS
			var d: int = b + PEBBLE_SEGMENTS
			indices.append_array(PackedInt32Array([a, b, c, b, d, c]))
	return _mesh(verts, normals, uvs, colors, indices)


## {mesh, local} for one named MeshInstance3D of an imported model, or {} when it cannot be found.
## `local` is the node's own transform so the piece keeps the scale its glTF gave it.
static func model_mesh(model_path: String, mesh_name: String) -> Dictionary:
	var packed: PackedScene = load(model_path) as PackedScene
	if packed == null:
		push_error("GrassMesh: cannot load %s" % model_path)
		return {}
	var scene: Node = packed.instantiate()
	var found: MeshInstance3D = scene.find_child(mesh_name, true, false) as MeshInstance3D
	if found == null and mesh_name == "":
		var all: Array[Node] = scene.find_children("*", "MeshInstance3D", true, false)
		found = all[0] as MeshInstance3D if not all.is_empty() else null
	var out: Dictionary = {}
	if found == null or found.mesh == null:
		push_error("GrassMesh: no mesh '%s' in %s" % [mesh_name, model_path])
	else:
		out = {"mesh": found.mesh, "local": found.transform}
	scene.free()
	return out


static func grass_material(fade: Vector2, dry_tint: Color) -> ShaderMaterial:
	if _grass_shader == null:
		_grass_shader = load(GRASS_SHADER) as Shader
	var material := ShaderMaterial.new()
	material.shader = _grass_shader
	material.set_shader_parameter("fade_start", fade.x)
	material.set_shader_parameter("fade_end", fade.y)
	material.set_shader_parameter("dry_tint", Vector3(dry_tint.r, dry_tint.g, dry_tint.b))
	return material


static func patch_material(texture_path: String, fade: Vector2, uv_tiles: float) -> ShaderMaterial:
	if _patch_shader == null:
		_patch_shader = load(PATCH_SHADER) as Shader
	var material := ShaderMaterial.new()
	material.shader = _patch_shader
	if ResourceLoader.exists(texture_path):
		material.set_shader_parameter("albedo_tex", load(texture_path) as Texture2D)
	else:
		push_warning("GrassMesh: patch texture %s missing; patches draw flat" % texture_path)
	material.set_shader_parameter("fade_start", fade.x)
	material.set_shader_parameter("fade_end", fade.y)
	material.set_shader_parameter("uv_tiles", uv_tiles)
	return material


static func vertex_count(mesh: Mesh) -> int:
	if mesh == null or mesh.get_surface_count() == 0:
		return 0
	var total: int = 0
	for surface: int in mesh.get_surface_count():
		total += (mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	return total


static func _mesh(verts: PackedVector3Array, normals: PackedVector3Array, uvs: PackedVector2Array, colors: PackedColorArray, indices: PackedInt32Array) -> ArrayMesh:
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
