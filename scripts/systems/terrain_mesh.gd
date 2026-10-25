class_name TerrainMesh
extends RefCounted
## Pure mesh maths for one terrain chunk, split out of terrain.gd so the node stays small and the
## geometry can be tested without a scene. A chunk samples its heights ONCE into a grid with a one-cell
## border (for central-difference normals), then every LOD is cut from that same grid by taking every
## `step`-th vertex: no re-sampling per LOD and all LODs agree on the LOD0 normals, so lighting does not
## pop when a chunk changes level. A vertical skirt hangs from every edge to hide the cracks that appear
## where two neighbouring chunks are drawn at different LODs.


## Heights for a chunk whose min corner is `origin`, `cells` cells of `spacing` metres per side, plus a
## one-cell border on every side: (cells + 3)^2 floats, x fastest.
static func sample_grid(hf: Heightfield, origin: Vector2, cells: int, spacing: float) -> PackedFloat32Array:
	var n: int = cells + 3
	var grid := PackedFloat32Array()
	grid.resize(n * n)
	for j: int in n:
		var z: float = origin.y + float(j - 1) * spacing
		for i: int in n:
			grid[j * n + i] = hf.height_at(origin.x + float(i - 1) * spacing, z)
	return grid


static func grid_height(grid: PackedFloat32Array, cells: int, i: int, j: int) -> float:
	return grid[(j + 1) * (cells + 3) + (i + 1)]


static func grid_normal(grid: PackedFloat32Array, cells: int, i: int, j: int, spacing: float) -> Vector3:
	var inv: float = 1.0 / maxf(0.001, 2.0 * spacing)
	var dx: float = (grid_height(grid, cells, i + 1, j) - grid_height(grid, cells, i - 1, j)) * inv
	var dz: float = (grid_height(grid, cells, i, j + 1) - grid_height(grid, cells, i, j - 1)) * inv
	return Vector3(-dx, 1.0, -dz).normalized()


## One LOD mesh in chunk-local space (vertex 0 at the chunk's min corner). `step` is the stride through
## the LOD0 grid (1, 2, 4, ...); `uv_origin`/`uv_scale` map local XZ to the whole-area UV so the shader
## could use UVs, although it maps textures in world space anyway.
static func build_lod(grid: PackedFloat32Array, cells: int, step: int, spacing: float, skirt_depth: float,
		uv_origin: Vector2, uv_scale: float, origin: Vector2 = Vector2.ZERO,
		holes: Array[Rect2] = [] as Array[Rect2]) -> ArrayMesh:
	var stride: int = maxi(1, step)
	var side: int = maxi(1, cells / stride)
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	for j: int in side + 1:
		for i: int in side + 1:
			var gi: int = mini(cells, i * stride)
			var gj: int = mini(cells, j * stride)
			verts.append(Vector3(float(gi) * spacing, grid_height(grid, cells, gi, gj), float(gj) * spacing))
			normals.append(grid_normal(grid, cells, gi, gj, spacing))
			uvs.append((uv_origin + Vector2(float(gi), float(gj)) * spacing) * uv_scale)
	for j: int in side:
		for i: int in side:
			# Quads whose centre falls in a hole are simply not emitted; their vertices stay in the array so
			# the index arithmetic below is unaffected. Unreferenced vertices cost nothing visible.
			if not holes.is_empty():
				var cx: float = origin.x + (float(i) + 0.5) * float(stride) * spacing
				var cz: float = origin.y + (float(j) + 0.5) * float(stride) * spacing
				if Heightfield.point_in_holes(holes, cx, cz):
					continue
			var a: int = j * (side + 1) + i
			var b: int = a + 1
			var c: int = a + side + 1
			var d: int = c + 1
			# Godot's front face winds CLOCKWISE seen from the front (+Y here): a-b-c and b-d-c. The other
			# way round the player fell straight through the ConcavePolygonShape3D (front-face collision only).
			indices.append_array(PackedInt32Array([a, b, c, b, d, c]))
	if skirt_depth > 0.0:
		_add_skirt(verts, normals, uvs, indices, side, skirt_depth)
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


# Duplicates each edge vertex `depth` lower and stitches a quad strip facing outward.
static func _add_skirt(verts: PackedVector3Array, normals: PackedVector3Array, uvs: PackedVector2Array,
		indices: PackedInt32Array, side: int, depth: float) -> void:
	var edges: Array[PackedInt32Array] = [PackedInt32Array(), PackedInt32Array(), PackedInt32Array(), PackedInt32Array()]
	for k: int in side + 1:
		edges[0].append(k)                                   # -Z edge, walked +X
		edges[1].append(side * (side + 1) + (side - k))      # +Z edge, walked -X
		edges[2].append((side - k) * (side + 1))             # -X edge, walked -Z
		edges[3].append(k * (side + 1) + side)               # +X edge, walked +Z
	for edge: PackedInt32Array in edges:
		var base: int = verts.size()
		for idx: int in edge:
			verts.append(verts[idx] - Vector3(0.0, depth, 0.0))
			normals.append(normals[idx])
			uvs.append(uvs[idx])
		for k: int in side:
			var top0: int = edge[k]
			var top1: int = edge[k + 1]
			var low0: int = base + k
			var low1: int = base + k + 1
			indices.append_array(PackedInt32Array([top0, low0, top1, top1, low0, low1]))


## Triangle soup of the LOD0 surface (no skirt) for a ConcavePolygonShape3D, in chunk-local space.
static func collision_faces(grid: PackedFloat32Array, cells: int, spacing: float,
		origin: Vector2 = Vector2.ZERO, holes: Array[Rect2] = [] as Array[Rect2]) -> PackedVector3Array:
	var faces := PackedVector3Array()
	faces.resize(cells * cells * 6)
	var k: int = 0
	for j: int in cells:
		for i: int in cells:
			# Collision must agree with the visible mesh, or the player walks on air over a hole.
			if not holes.is_empty():
				var cx: float = origin.x + (float(i) + 0.5) * spacing
				var cz: float = origin.y + (float(j) + 0.5) * spacing
				if Heightfield.point_in_holes(holes, cx, cz):
					continue
			var a := Vector3(float(i) * spacing, grid_height(grid, cells, i, j), float(j) * spacing)
			var b := Vector3(float(i + 1) * spacing, grid_height(grid, cells, i + 1, j), float(j) * spacing)
			var c := Vector3(float(i) * spacing, grid_height(grid, cells, i, j + 1), float(j + 1) * spacing)
			var d := Vector3(float(i + 1) * spacing, grid_height(grid, cells, i + 1, j + 1), float(j + 1) * spacing)
			faces[k] = a
			faces[k + 1] = b
			faces[k + 2] = c
			faces[k + 3] = b
			faces[k + 4] = d
			faces[k + 5] = c
			k += 6
	faces.resize(k)  # holes leave the preallocated tail unused
	return faces


## Outward normal of the first triangle under Godot's clockwise-front convention ((v2-v0) x (v1-v0)):
## a cheap check that the winding faces up.
static func first_face_normal(mesh: ArrayMesh) -> Vector3:
	if mesh.get_surface_count() == 0:
		return Vector3.ZERO
	var arrays: Array = mesh.surface_get_arrays(0)
	var v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	if idx.size() < 3:
		return Vector3.ZERO
	return (v[idx[2]] - v[idx[0]]).cross(v[idx[1]] - v[idx[0]]).normalized()
