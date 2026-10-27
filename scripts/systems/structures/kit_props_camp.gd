class_name StructureKitPropsCamp
extends RefCounted
## The camp and wayside pieces of the props kit (W8-P): signpost, campfire ring, tent frame, weapon rack,
## grave mound, trough. StructureKitProps forwards here and holds the conventions (origin at the base
## centre, `sink` below ground, one surface per material); nothing dispatches to this file directly.


static func make(kind: String, p: Dictionary, name: String = "") -> Dictionary:
	var mat: String = str(p.get("mat", ""))
	var sink: float = StructureKitProps.sink_of(p)
	match kind:
		"signpost":
			return signpost(_f(p, "h", 2.4), _yaws(p), _or(mat, "planks"), sink, name)
		"campfire":
			return campfire(_f(p, "radius", 0.8), int(p.get("stones", 8)), int(p.get("seed", 1)), _or(mat, "stone"),
					str(p.get("wood", "timber")), sink, name)
		"tent_frame":
			return tent_frame(_f(p, "w", 2.4), _f(p, "d", 2.2), _f(p, "h", 1.7), bool(p.get("covered", false)),
					_or(mat, "planks"), sink, name)
		"weapon_rack":
			return weapon_rack(_f(p, "w", 1.6), _f(p, "h", 1.5), int(p.get("spears", 4)), _or(mat, "planks"), sink, name)
		"grave_mound":
			return grave_mound(_f(p, "w", 0.9), _f(p, "d", 2.0), _or(mat, "stone"), str(p.get("wood", "planks")), sink, name)
		"trough":
			return trough(_f(p, "w", 1.8), _f(p, "d", 0.6), _f(p, "h", 0.5), _or(mat, "planks"), sink, name)
	return {}


## A post with one board per entry in `yaws`, each pointing out along its own X. Only the post collides.
static func signpost(h: float, yaws: Array, mat: String, sink: float, name: String) -> Dictionary:
	var b := StructureKit.builder(mat, name)
	StructureKitProps.box(b, Vector3(0.0, (h - sink) * 0.5, 0.0), Vector3(0.14, h + sink, 0.14))
	for i: int in range(yaws.size()):
		var t := Transform3D(Basis(Vector3.UP, deg_to_rad(float(yaws[i]))), Vector3(0.0, h - 0.35 - 0.3 * float(i), 0.0))
		b.add_box(t.translated_local(Vector3(0.45, 0.0, 0.0)), Vector3(0.9, 0.2, 0.04), false)
	return StructureKitProps.finish("signpost", [[b, mat]])


## A ring of stones round three charred logs on a dark disc of burnt ground (the disc also hides the gap a
## slope leaves under the ring). One low cylinder collider: a kerb the player's step-up climbs.
static func campfire(r: float, stones: int, seed: int, mat: String, wood: String, sink: float, name: String) -> Dictionary:
	var s := StructureKit.builder(mat, name)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var n: int = maxi(3, stones)
	for i: int in range(n):
		var a: float = TAU * float(i) / float(n) + rng.randf_range(-0.15, 0.15)
		var size := Vector3(rng.randf_range(0.26, 0.38), rng.randf_range(0.18, 0.26), rng.randf_range(0.22, 0.3))
		s.add_box(Transform3D(Basis(Vector3.UP, -a + rng.randf_range(-0.3, 0.3)), Vector3(cos(a) * r, size.y * 0.35, sin(a) * r)),
				size, false)
	var w := StructureKit.builder(wood, name)
	w.add_lathe(Transform3D.IDENTITY, PackedVector2Array([Vector2(r + 0.2, -sink), Vector2(r + 0.2, 0.03), Vector2(0.02, 0.05)]),
			10, null)
	for i: int in range(3):
		var t := Transform3D(Basis(Vector3.UP, float(i) * 1.05) * Basis(Vector3.BACK, 0.18 * float(i)),
				Vector3(0.0, 0.1 + 0.07 * float(i), 0.0))
		w.add_box(t, Vector3(0.9, 0.13, 0.13), false)
	var shape := CylinderShape3D.new()
	shape.radius = r + 0.15
	shape.height = 0.3
	s.shapes.append({"shape": shape, "transform": Transform3D(Basis.IDENTITY, Vector3(0.0, 0.05, 0.0))})
	return StructureKitProps.finish("campfire", [[s, mat], [w, wood]])


## A timber A-frame: a ridge pole along X on two pairs of legs. Bare, the legs collide; covered, two plank
## slabs lean on it (the kit has no cloth) and they collide instead.
static func tent_frame(w: float, d: float, h: float, covered: bool, mat: String, sink: float, name: String) -> Dictionary:
	var b := StructureKit.builder(mat, name)
	var half: float = d * 0.5
	var leg: float = sqrt(h * h + half * half)
	var ext: float = sink * leg / maxf(0.1, h)
	var tilt: float = atan2(half, h)
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			var dir: Vector3 = Vector3(0.0, -h, sz * half) / leg
			var centre: Vector3 = Vector3(sx * (w * 0.5 - 0.05), h, 0.0) + dir * ((leg + ext) * 0.5)
			b.add_box(Transform3D(Basis(Vector3.RIGHT, -sz * tilt), centre), Vector3(0.09, leg + ext, 0.09), not covered)
	StructureKitProps.box(b, Vector3(0.0, h, 0.0), Vector3(w + 0.3, 0.09, 0.09), false)
	if covered:
		for sz: float in [-1.0, 1.0]:
			var dir: Vector3 = Vector3(0.0, -h, sz * half) / leg
			var centre: Vector3 = Vector3(0.0, h + 0.06, 0.0) + dir * (leg * 0.5)
			b.add_box(Transform3D(Basis(Vector3.RIGHT, atan2(h, sz * half)), centre), Vector3(w, 0.04, leg), true)
	return StructureKitProps.finish("tent_frame", [[b, mat]])


## Two posts, two rails and spears leaning against the front (+Z). One box collider round the lot.
static func weapon_rack(w: float, h: float, spears: int, mat: String, sink: float, name: String) -> Dictionary:
	var b := StructureKit.builder(mat, name)
	for sx: float in [-1.0, 1.0]:
		StructureKitProps.box(b, Vector3(sx * (w * 0.5 - 0.06), (h - sink) * 0.5, 0.0), Vector3(0.12, h + sink, 0.12), false)
	StructureKitProps.box(b, Vector3(0.0, h - 0.04, 0.0), Vector3(w, 0.08, 0.08), false)
	StructureKitProps.box(b, Vector3(0.0, h * 0.45, 0.0), Vector3(w, 0.06, 0.06), false)
	var n: int = maxi(1, spears)
	var lean: float = deg_to_rad(12.0)
	for i: int in range(n):
		var x: float = -w * 0.5 + w * (float(i) + 0.5) / float(n)
		b.add_box(Transform3D(Basis(Vector3.RIGHT, -lean), Vector3(x, 0.95 * cos(lean), 0.42 - 0.95 * sin(lean))),
				Vector3(0.05, 1.9, 0.05), false)
	StructureKitProps.collide(b, Vector3(0.0, h * 0.5, 0.15), Vector3(w, h, 0.5))
	return StructureKitProps.finish("weapon_rack", [[b, mat]])


## Three stepped courses of stones over a grave running along Z, with a small timber cross at the -Z head.
## Only the bottom course collides, low enough for the step-up.
static func grave_mound(w: float, d: float, mat: String, wood: String, sink: float, name: String) -> Dictionary:
	var s := StructureKit.builder(mat, name)
	StructureKitProps.box(s, Vector3(0.0, (0.16 - sink) * 0.5, 0.0), Vector3(w, 0.16 + sink, d))
	StructureKitProps.box(s, Vector3(0.0, 0.23, 0.0), Vector3(w * 0.75, 0.14, d * 0.85), false)
	StructureKitProps.box(s, Vector3(0.0, 0.36, 0.0), Vector3(w * 0.5, 0.12, d * 0.65), false)
	var m := StructureKit.builder(wood, name)
	var head: float = -d * 0.5 - 0.06
	StructureKitProps.box(m, Vector3(0.0, (0.8 - sink) * 0.5, head), Vector3(0.08, 0.8 + sink, 0.08), false)
	StructureKitProps.box(m, Vector3(0.0, 0.6, head), Vector3(0.4, 0.07, 0.06), false)
	return StructureKitProps.finish("grave_mound", [[s, mat], [m, wood]])


## An open plank box on two sunk sleepers. One box collider.
static func trough(w: float, d: float, h: float, mat: String, sink: float, name: String) -> Dictionary:
	var b := StructureKit.builder(mat, name)
	for sx: float in [-1.0, 1.0]:
		StructureKitProps.box(b, Vector3(sx * (w * 0.5 - 0.25), (0.12 - sink) * 0.5, 0.0), Vector3(0.12, 0.12 + sink, d), false)
	StructureKitProps.box(b, Vector3(0.0, 0.15, 0.0), Vector3(w, 0.06, d), false)
	for sz: float in [-1.0, 1.0]:
		StructureKitProps.box(b, Vector3(0.0, h * 0.5 + 0.12, sz * (d * 0.5 - 0.025)), Vector3(w, h, 0.05), false)
	for sx: float in [-1.0, 1.0]:
		StructureKitProps.box(b, Vector3(sx * (w * 0.5 - 0.025), h * 0.5 + 0.12, 0.0), Vector3(0.05, h, d - 0.1), false)
	StructureKitProps.collide(b, Vector3(0.0, (h + 0.12) * 0.5, 0.0), Vector3(w, h + 0.12, d))
	return StructureKitProps.finish("trough", [[b, mat]])


static func _yaws(p: Dictionary) -> Array:
	var v: Variant = p.get("yaws", [0.0, 80.0])
	return v if v is Array and not (v as Array).is_empty() else [0.0, 80.0]


static func _f(d: Dictionary, key: String, fallback: float) -> float:
	var v: Variant = d.get(key, fallback)
	return float(v) if v is float or v is int else fallback


static func _or(mat: String, fallback: String) -> String:
	return fallback if mat.is_empty() else mat
