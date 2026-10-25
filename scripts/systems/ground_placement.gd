class_name GroundPlacement
extends RefCounted
## Shared by Forest and LevelDressing: drops a planned XZ placement onto a world-space ground sampler
## and through a placement filter. Both callables are optional; with neither set the input is returned
## untouched, which keeps the flat test levels (greybox, treetest) exactly as they were.


## Basis for a prop standing on ground with `normal`, yawed by `yaw_rad` and uniformly scaled. `align` is
## how far the prop tilts from upright toward the normal: 0 stays vertical, 1 lies flat on the slope.
## Partial on purpose: a fully normal-aligned stump or shrub on a 30 degree bank looks pushed over (real
## plants grow toward the sky), while a fully upright log floats off a slope on one edge. Halfway reads
## as settled. Used by LevelDressing (with a normal sampler) and Grass; without a normal it is upright.
static func aligned_basis(normal: Vector3, yaw_rad: float, align: float, scale: float) -> Basis:
	var basis: Basis = Basis.from_euler(Vector3(0.0, yaw_rad, 0.0))
	var n: Vector3 = normal.normalized() if normal.length_squared() > 0.0001 else Vector3.UP
	var up: Vector3 = Vector3.UP.slerp(n, clampf(align, 0.0, 1.0))
	var axis: Vector3 = Vector3.UP.cross(up)
	if axis.length_squared() > 0.000001:
		basis = Basis(axis.normalized(), Vector3.UP.angle_to(up)) * basis
	return basis.scaled(Vector3.ONE * scale)


## World ground under (x, z) plus `offset`, or `offset` alone when there is no sampler.
static func ground(x: float, z: float, offset: float, sampler: Callable) -> Vector3:
	return Vector3(x, offset + (float(sampler.call(x, z)) if sampler.is_valid() else 0.0), z)


## Re-grounds a Forest.plan_layout() result whose positions are local to `origin`. Entries failing
## `filter` are dropped; `y` becomes ground height minus origin.y so the node's own height still applies.
static func ground_layout(layout: Dictionary, origin: Vector3, sampler: Callable, filter: Callable) -> Dictionary:
	if not sampler.is_valid() and not filter.is_valid():
		return layout
	var src: PackedVector3Array = layout["positions"]
	var src_names: PackedStringArray = layout["archetypes"]
	var src_yaws: PackedFloat32Array = layout["yaws"]
	var src_scales: PackedFloat32Array = layout["scales"]
	# Local packed arrays, assigned at the end: a packed array read out of a Dictionary is a copy.
	var positions := PackedVector3Array()
	var names := PackedStringArray()
	var yaws := PackedFloat32Array()
	var scales := PackedFloat32Array()
	for i: int in src.size():
		var wx: float = origin.x + src[i].x
		var wz: float = origin.z + src[i].z
		if filter.is_valid() and not bool(filter.call(wx, wz)):
			continue
		var y: float = float(sampler.call(wx, wz)) - origin.y if sampler.is_valid() else src[i].y
		positions.append(Vector3(src[i].x, y, src[i].z))
		names.append(src_names[i])
		yaws.append(src_yaws[i])
		scales.append(src_scales[i])
	return {"positions": positions, "archetypes": names, "yaws": yaws, "scales": scales, "clusters": layout["clusters"]}
