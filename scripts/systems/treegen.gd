class_name TreeGen
extends RefCounted
## Procedural conifer builder (D-002/D-009): a tapered, bent trunk plus a crown of flat twig cards cut
## from a Poly Haven twig atlas. Pure: it returns meshes and never touches the scene tree, so the maths runs
## in the headless test runner. Same params + seed => byte-identical geometry (every random draw comes from
## one RandomNumberGenerator seeded here, in a fixed order), which Forest relies on for reproducible layouts.

const MAX_LEAN_DEG := 60.0

## Builds one tree. Returns {"trunk": ArrayMesh, "cards": ArrayMesh (0 surfaces when no cards),
## "height": float, "radius": float (crown reach), "collider_radius": float (trunk base radius)}.
static func build(params: Dictionary, seed_value: int) -> Dictionary:
	var p: Dictionary = TreeParams.merge_over_base(params)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var height: float = maxf(0.01, _pick(p["height"], rng))
	var base_r: float = maxf(0.01, absf(_pick(p["base_radius"], rng)))
	var spine: Dictionary = _spine(p, rng, height, base_r)
	var trunk: ArrayMesh = _trunk(p, spine)
	var crown: Dictionary = _cards(p, rng, spine)
	return {
		"trunk": trunk, "cards": crown["mesh"], "height": height,
		"radius": maxf(base_r, float(crown["radius"])), "collider_radius": base_r,
	}


static func params_for(archetype: String) -> Dictionary:
	return TreeParams.params_for(archetype)


static func archetypes() -> PackedStringArray:
	return TreeParams.archetypes()


## Cheaper crown for distant instances: fewer, larger cards keep the silhouette mass at a fraction of the
## vertices. Level 0 returns the params unchanged.
static func lod_params(params: Dictionary, level: int) -> Dictionary:
	var p: Dictionary = TreeParams.merge_over_base(params)
	if level <= 0:
		return p
	p["whorls"] = int(ceil(float(p["whorls"]) * float(p["lod1_whorl_scale"])))
	p["branches_per_whorl"] = int(ceil(float(p["branches_per_whorl"]) * float(p["lod1_branch_scale"])))
	p["card_length"] = float(p["card_length"]) * float(p["lod1_card_scale"])
	return p


## Ring centres and radii up the trunk: a straight lean plus a quadratic bend, radius easing from base to
## tip by taper_power, with optional per-ring "gnarl" noise for old trunks.
static func _spine(p: Dictionary, rng: RandomNumberGenerator, height: float, base_r: float) -> Dictionary:
	var rings: int = maxi(1, int(p["rings"]))
	var lean: float = deg_to_rad(clampf(rng.randf_range(0.0, absf(float(p["lean_deg"]))), 0.0, MAX_LEAN_DEG))
	var lean_dir: Vector2 = Vector2.from_angle(rng.randf_range(0.0, TAU))
	var bend_dir: Vector2 = Vector2.from_angle(rng.randf_range(0.0, TAU))
	var bend: float = float(p["bend"]) * height
	var tip_r: float = maxf(0.005, base_r * absf(float(p["tip_ratio"])))
	var taper: float = maxf(0.05, float(p["taper_power"]))
	var gnarl: float = clampf(float(p["gnarl"]), 0.0, 0.9)
	var centres := PackedVector3Array()
	var radii := PackedFloat32Array()
	for i: int in rings + 1:
		var t: float = float(i) / float(rings)
		var off: Vector2 = lean_dir * tan(lean) * t * height + bend_dir * bend * t * t
		centres.append(Vector3(off.x, t * height, off.y))
		var r: float = lerpf(base_r, tip_r, pow(t, taper))
		if gnarl > 0.0:
			r *= 1.0 + rng.randf_range(-gnarl, gnarl)
		radii.append(r)
	return {"centres": centres, "radii": radii, "rings": rings, "height": height}


## Trunk surface from the spine. Built with add_surface_from_arrays rather than SurfaceTool: the explicit
## vertex order is what makes the determinism test ("same first/last vertex") meaningful and lets tests
## read the arrays straight back. Godot front faces wind clockwise, so quads are emitted (a,b,c),(b,d,c).
static func _trunk(p: Dictionary, spine: Dictionary) -> ArrayMesh:
	var segments: int = maxi(3, int(p["segments"]))
	var rings: int = spine["rings"]
	var centres: PackedVector3Array = spine["centres"]
	var radii: PackedFloat32Array = spine["radii"]
	var tile: float = float(p["bark_tile_m"])
	if tile <= 0.0:
		tile = 1.0
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	for i: int in rings + 1:
		var y: float = centres[i].y
		var lo: int = maxi(0, i - 1)
		var hi: int = mini(rings, i + 1)
		var dy: float = maxf(0.0001, centres[hi].y - centres[lo].y)
		var slope: float = -(radii[hi] - radii[lo]) / dy
		for s: int in segments + 1:
			var a: float = TAU * float(s) / float(segments)
			var radial := Vector3(cos(a), 0.0, sin(a))
			verts.append(centres[i] + radial * radii[i])
			normals.append((radial + Vector3.UP * slope).normalized())
			uvs.append(Vector2(float(s) / float(segments), y / tile))
	var apex: int = verts.size()
	verts.append(centres[rings] + Vector3.UP * radii[rings] * 1.5)
	normals.append(Vector3.UP)
	uvs.append(Vector2(0.5, (centres[rings].y + radii[rings] * 1.5) / tile))
	var stride: int = segments + 1
	for i: int in rings:
		for s: int in segments:
			var a: int = i * stride + s
			var b: int = a + 1
			var c: int = a + stride
			var d: int = c + 1
			indices.append_array(PackedInt32Array([a, b, c, b, d, c]))
	for s: int in segments:
		indices.append_array(PackedInt32Array([rings * stride + s, rings * stride + s + 1, apex]))
	return _mesh(verts, normals, uvs, indices)


## Crown: `whorls` rings of `branches_per_whorl` flat quads up the top (1 - crown_start) of the trunk,
## pitched and rolled outward with jitter, shrinking toward the tip. One quad per branch, one surface per
## tree (a tree is 2 draw calls, not 2 + cards); double-sidedness comes from the material's cull_disabled,
## not from a second winding, so vertex count = cards * 4.
static func _cards(p: Dictionary, rng: RandomNumberGenerator, spine: Dictionary) -> Dictionary:
	var mesh := ArrayMesh.new()
	var whorls: int = maxi(0, int(p["whorls"]))
	var per_whorl: int = maxi(0, int(p["branches_per_whorl"]))
	var cells: Array[Dictionary] = _atlas_cells(p)
	if whorls == 0 or per_whorl == 0 or cells.is_empty():
		return {"mesh": mesh, "radius": 0.0}
	var centres: PackedVector3Array = spine["centres"]
	var radii: PackedFloat32Array = spine["radii"]
	var rings: int = spine["rings"]
	var crown_start: float = clampf(float(p["crown_start"]), 0.0, 0.98)
	var card_len: float = maxf(0.01, float(p["card_length"]))
	var tip_scale: float = clampf(float(p["tip_scale"]), 0.05, 1.0)
	var pitch: float = deg_to_rad(float(p["pitch_deg"]))
	var pitch_j: float = deg_to_rad(float(p["pitch_jitter_deg"]))
	var roll_j: float = deg_to_rad(float(p["roll_jitter_deg"]))
	var yaw_j: float = deg_to_rad(float(p["yaw_jitter_deg"]))
	var len_j: float = clampf(float(p["length_jitter"]), 0.0, 0.9)
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	var reach: float = 0.0
	for w: int in whorls:
		var tw: float = crown_start + (1.0 - crown_start) * (float(w) + 0.5) / float(whorls)
		var ring_f: float = tw * float(rings)
		var i0: int = clampi(int(floor(ring_f)), 0, rings - 1)
		var f: float = ring_f - float(i0)
		var centre: Vector3 = centres[i0].lerp(centres[i0 + 1], f)
		var r: float = lerpf(radii[i0], radii[i0 + 1], f)
		var shrink: float = lerpf(1.0, tip_scale, float(w) / maxf(1.0, float(whorls - 1)))
		var offset: float = 0.5 * float(w % 2)
		for b: int in per_whorl:
			var yaw: float = TAU * (float(b) + offset) / float(per_whorl) + rng.randf_range(-yaw_j, yaw_j)
			var pitch_b: float = pitch + rng.randf_range(-pitch_j, pitch_j)
			var roll: float = rng.randf_range(-roll_j, roll_j)
			var length: float = card_len * shrink * (1.0 + rng.randf_range(-len_j, len_j))
			var cell: Dictionary = cells[rng.randi_range(0, cells.size() - 1)]
			var mirror: bool = rng.randf() < 0.5
			var flat := Vector3(cos(yaw), 0.0, sin(yaw))
			var dir: Vector3 = (flat * cos(pitch_b) + Vector3.UP * sin(pitch_b)).normalized()
			var across: Vector3 = Vector3.UP.cross(flat).normalized().rotated(dir, roll)
			var width: float = length * float(cell["aspect"])
			var base: Vector3 = centre + flat * r * 0.6
			var tip: Vector3 = base + dir * length
			# Normals bend toward "outward + up" instead of the card plane, the usual foliage trick so the
			# crown shades like one rounded mass rather than a fan of individually lit planes.
			var n: Vector3 = (flat * 0.6 + Vector3.UP * 0.8).normalized()
			var first: int = verts.size()
			verts.append_array(PackedVector3Array([
				base - across * width * 0.5, base + across * width * 0.5,
				tip + across * width * 0.5, tip - across * width * 0.5,
			]))
			for k: int in 4:
				normals.append(n)
			uvs.append_array(_cell_uvs(cell, mirror))
			indices.append_array(PackedInt32Array([first, first + 1, first + 2, first, first + 2, first + 3]))
			reach = maxf(reach, Vector2(tip.x, tip.z).length() + width * 0.5)
	return {"mesh": _mesh(verts, normals, uvs, indices), "radius": reach}


## UV corners for (base-left, base-right, tip-right, tip-left) so the spray's stem sits at the trunk end.
static func _cell_uvs(cell: Dictionary, mirror: bool) -> PackedVector2Array:
	var base: Vector2 = cell["base"]
	var along: Vector2 = cell["along"]
	var across: Vector2 = cell["across"]
	if mirror:
		across = -across
	return PackedVector2Array([
		base - across * 0.5, base + across * 0.5, base + along + across * 0.5, base + along - across * 0.5,
	])


## Converts atlas_cells (pixel rects + stem edge) to UV frames; falls back to a uniform atlas_grid.
static func _atlas_cells(p: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var size: Array = p["atlas_size"] if p["atlas_size"] is Array and (p["atlas_size"] as Array).size() == 2 else [1024, 1024]
	var sw: float = maxf(1.0, float(size[0]))
	var sh: float = maxf(1.0, float(size[1]))
	var cells: Array = p["atlas_cells"] if p["atlas_cells"] is Array else []
	for c: Variant in cells:
		if c is Dictionary and (c as Dictionary).get("px", []) is Array and ((c as Dictionary)["px"] as Array).size() == 4:
			var px: Array = (c as Dictionary)["px"]
			var rect := Rect2(float(px[0]) / sw, float(px[1]) / sh, float(px[2] - px[0]) / sw, float(px[3] - px[1]) / sh)
			out.append(_cell_frame(rect, str((c as Dictionary).get("stem", "bottom")), sw / sh))
	if out.is_empty():
		var grid: Array = p["atlas_grid"] if p["atlas_grid"] is Array and (p["atlas_grid"] as Array).size() == 2 else [1, 1]
		var cols: int = maxi(1, int(grid[0]))
		var rows: int = maxi(1, int(grid[1]))
		for y: int in rows:
			for x: int in cols:
				out.append(_cell_frame(Rect2(float(x) / cols, float(y) / rows, 1.0 / cols, 1.0 / rows), "bottom", sw / sh))
	return out


## A cell frame: UV point where the stem attaches, the UV vector along the spray and across it, and the
## pixel-true width/length ratio so the quad never stretches the spray. UV v runs downward in Godot.
static func _cell_frame(r: Rect2, stem: String, px_aspect: float) -> Dictionary:
	var c: Vector2 = r.get_center()
	var w: float = r.size.x * px_aspect
	var h: float = r.size.y
	match stem:
		"top":
			return {"base": Vector2(c.x, r.position.y), "along": Vector2(0.0, r.size.y), "across": Vector2(-r.size.x, 0.0), "aspect": w / maxf(h, 0.0001)}
		"left":
			return {"base": Vector2(r.position.x, c.y), "along": Vector2(r.size.x, 0.0), "across": Vector2(0.0, -r.size.y), "aspect": h / maxf(w, 0.0001)}
		"right":
			return {"base": Vector2(r.end.x, c.y), "along": Vector2(-r.size.x, 0.0), "across": Vector2(0.0, r.size.y), "aspect": h / maxf(w, 0.0001)}
		_:
			return {"base": Vector2(c.x, r.end.y), "along": Vector2(0.0, -r.size.y), "across": Vector2(r.size.x, 0.0), "aspect": w / maxf(h, 0.0001)}


static func _mesh(v: PackedVector3Array, n: PackedVector3Array, uv: PackedVector2Array, idx: PackedInt32Array) -> ArrayMesh:
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = v
	arrays[Mesh.ARRAY_NORMAL] = n
	arrays[Mesh.ARRAY_TEX_UV] = uv
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


static func _pick(range_v: Variant, rng: RandomNumberGenerator) -> float:
	if range_v is Array and (range_v as Array).size() >= 2:
		var lo: float = float((range_v as Array)[0])
		var hi: float = float((range_v as Array)[1])
		return rng.randf_range(minf(lo, hi), maxf(lo, hi))
	rng.randf()
	return float(range_v)
