class_name GrassMesh
extends RefCounted
## Builds the shared meshes and materials Grass instances: a textureless blade clump, a wildflower, a
## textured leaf patch quad, a low-poly pebble, and a mesh lifted out of an imported foliage model. Pure
## builders: no nodes, no scene, so tests can count vertices without a renderer.
##
## There is no grass texture and none is coming (D-002: vegetation is geometry). What sells a blade with
## no texture is colour, and since W8-G the colour is per instance: the blade mesh is white, the
## MultiMesh instance colour carries the tip colour (from the zone palette, GrassZones), INSTANCE_CUSTOM
## the root colour as a fraction of it, and the shader ramps root to tip along UV2.y. The mesh keeps
## only what is per blade: UV.y (0 root, 1 tip) as the bend mask and a shade jitter in vertex alpha.

const GRASS_SHADER := "res://scripts/systems/grass.gdshader"
const PATCH_SHADER := "res://scripts/systems/ground_patch.gdshader"
## W21-D: 0.12 -> 0.25. A needle tip is under a pixel from a few metres and shimmers; a broader tip keeps
## the top half of the blade, the lit part, on screen. Same vertex count.
const TIP_WIDTH_FRACTION := 0.25
const LEAN_MIN := 0.18
const LEAN_MAX := 0.42
## Per-blade brightness jitter, encoded in vertex alpha as (shade - SHADE_MIN) / SHADE_RANGE; the shader
## decodes it with the same two numbers.
const SHADE_MIN := 0.85
const SHADE_RANGE := 0.3
const PEBBLE_SEGMENTS := 5
const PEBBLE_RINGS := 3
const FLOWER_STEM_SEGMENTS := 2
const FLOWER_STEM_WIDTH := 0.02
const FLOWER_STEM_TOP := 0.86
const FLOWER_HEAD_HALF := 0.06
## The head's bend mask: full lean on a 0.25 m stalk would lay it flat, so the head takes a quarter.
const FLOWER_HEAD_BEND := 0.5

static var _grass_shader: Shader
static var _patch_shader: Shader


## A clump of `blades` tapered strips of unit height splayed around the origin, each `segments` quads
## tall so the shader can bend it. Per-blade jitter in yaw, lean and shade breaks the stamp.
static func clump(blades: int, segments: int, width: float, rng: RandomNumberGenerator) -> ArrayMesh:
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
		var shade: Color = shade_color(rng.randf_range(0.88, 1.12))
		var first: int = verts.size()
		for s: int in n_seg + 1:
			var t: float = float(s) / float(n_seg)
			var half: float = width * 0.5 * lerpf(1.0, TIP_WIDTH_FRACTION, t)
			var p: Vector3 = base + Vector3.UP * t + dir * lean * t * t
			for k: int in 2:
				verts.append(p + side * (half if k == 0 else -half))
				normals.append(dir)
				uvs.append(Vector2(float(k), t))
				colors.append(shade)
		for s: int in n_seg:
			var i: int = first + s * 2
			indices.append_array(PackedInt32Array([i, i + 2, i + 1, i + 1, i + 2, i + 3]))
	return _mesh(verts, normals, uvs, colors, indices)


## A wildflower: one thin stalk of unit height and a small head of two crossed quads at the top. Colour
## runs stalk (root) to petal (tip) along UV2.y, which jumps to 1 at the head so the petals take the
## whole instance tip colour; UV.y is the bend mask and stays small so the head nods instead of lying down.
static func flower(rng: RandomNumberGenerator) -> ArrayMesh:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var uv2s := PackedVector2Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	var yaw: float = rng.randf_range(0.0, TAU)
	var dir := Vector3(cos(yaw), 0.0, sin(yaw))
	var side := Vector3(-dir.z, 0.0, dir.x)
	var lean: float = rng.randf_range(0.05, 0.18)
	var shade: Color = shade_color(rng.randf_range(0.92, 1.08))
	for s: int in FLOWER_STEM_SEGMENTS + 1:
		var t: float = float(s) / float(FLOWER_STEM_SEGMENTS)
		var p: Vector3 = Vector3.UP * t * FLOWER_STEM_TOP + dir * lean * t * t
		for k: int in 2:
			verts.append(p + side * (FLOWER_STEM_WIDTH * 0.5 if k == 0 else -FLOWER_STEM_WIDTH * 0.5))
			normals.append(dir)
			uvs.append(Vector2(float(k), t * FLOWER_HEAD_BEND))
			uv2s.append(Vector2(float(k), t * 0.25))
			colors.append(shade)
	for s: int in FLOWER_STEM_SEGMENTS:
		var i: int = s * 2
		indices.append_array(PackedInt32Array([i, i + 2, i + 1, i + 1, i + 2, i + 3]))
	var top: Vector3 = Vector3.UP * FLOWER_STEM_TOP + dir * lean
	for q: int in 2:
		var a: float = yaw + float(q) * PI * 0.5 + rng.randf_range(-0.2, 0.2)
		var u := Vector3(cos(a), 0.0, sin(a)) * FLOWER_HEAD_HALF
		var v := Vector3.UP * FLOWER_HEAD_HALF
		var first: int = verts.size()
		for corner: Vector3 in [top - u, top + u, top + u + v * 2.0, top - u + v * 2.0]:
			verts.append(corner)
			normals.append(Vector3(-u.z, 0.0, u.x).normalized())
			uvs.append(Vector2(0.0, FLOWER_HEAD_BEND))
			uv2s.append(Vector2(0.0, 1.0))
			colors.append(shade)
		indices.append_array(PackedInt32Array([first, first + 2, first + 1, first, first + 3, first + 2]))
	return _mesh(verts, normals, uvs, colors, indices, uv2s)


## A flat unit quad on the ground plane (y = 0, x/z in -0.5..0.5) for leaf-drift patches.
static func patch_quad() -> ArrayMesh:
	var verts := PackedVector3Array([Vector3(-0.5, 0.0, -0.5), Vector3(0.5, 0.0, -0.5), Vector3(0.5, 0.0, 0.5), Vector3(-0.5, 0.0, 0.5)])
	var normals := PackedVector3Array([Vector3.UP, Vector3.UP, Vector3.UP, Vector3.UP])
	var uvs := PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)])
	var colors := PackedColorArray([Color.WHITE, Color.WHITE, Color.WHITE, Color.WHITE])
	return _mesh(verts, normals, uvs, colors, PackedInt32Array([0, 2, 1, 0, 3, 2]))


## A squashed, jittered unit sphere: a pebble. UV.y stays 0 so the grass shader never bends it, and its
## colour lives in the mesh (alpha 0.5 decodes to a shade of 1); the instance colour only jitters brightness.
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
			var c: Color = color.darkened(0.45 * float(r) / float(PEBBLE_RINGS))
			c.a = shade_color(1.0).a
			colors.append(c)
	for r: int in PEBBLE_RINGS:
		for s: int in PEBBLE_SEGMENTS:
			var a: int = r * PEBBLE_SEGMENTS + s
			var b: int = r * PEBBLE_SEGMENTS + (s + 1) % PEBBLE_SEGMENTS
			var c: int = a + PEBBLE_SEGMENTS
			var d: int = b + PEBBLE_SEGMENTS
			indices.append_array(PackedInt32Array([a, b, c, b, d, c]))
	return _mesh(verts, normals, uvs, colors, indices)


## White with the shade jitter in alpha, the way the grass shader reads a vertex colour.
static func shade_color(shade: float) -> Color:
	return Color(1.0, 1.0, 1.0, clampf((shade - SHADE_MIN) / SHADE_RANGE, 0.0, 1.0))


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


static func grass_material(fade: Vector2) -> ShaderMaterial:
	if _grass_shader == null:
		_grass_shader = load(GRASS_SHADER) as Shader
	var material := ShaderMaterial.new()
	material.shader = _grass_shader
	material.set_shader_parameter("fade_start", fade.x)
	material.set_shader_parameter("fade_end", fade.y)
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


## UV2 defaults to UV: for a blade the colour ramp and the bend mask are the same height fraction.
static func _mesh(verts: PackedVector3Array, normals: PackedVector3Array, uvs: PackedVector2Array, colors: PackedColorArray, indices: PackedInt32Array, uv2s: PackedVector2Array = PackedVector2Array()) -> ArrayMesh:
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_TEX_UV2] = uv2s if uv2s.size() == verts.size() else uvs
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
