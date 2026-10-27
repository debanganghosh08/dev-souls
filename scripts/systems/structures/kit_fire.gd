class_name StructureKitFire
extends RefCounted
## The lit pieces of the kit (W9-F): brazier, torch post, wall torch, hearth remains, lamp stone, pyre and
## beacon. Each one is ordinary geometry plus a `lights` list on the returned piece, which
## StructureKit.make_node/make_multi turns into FireLight nodes. A layout lights itself by naming one of
## these kinds; nothing else in the chain changes.
##
## Conventions are StructureKitProps: origin at the base centre, width along X, depth along Z, `sink`
## metres of the base buried so a piece on a slope never hangs in the air. A wall torch is the exception,
## mounted on a wall at whatever height its layout gives it, so it does not sink and does not collide.
##
## Light fields are tuning, so every one of them can be overridden from the layout params: `energy`,
## `range`, `flame`, `flicker`, `day`, `cull` (how far off the flame can still be seen) and `color`
## ([r, g, b]). The defaults below are a first
## estimate of what reads at night without washing the ground out (UNVERIFIED: nobody has seen them yet).

const EMBER := "ember"
const CHAR := "char"


static func make(kind: String, p: Dictionary, name: String = "") -> Dictionary:
	var mat: String = str(p.get("mat", ""))
	var sink: float = StructureKitProps.sink_of(p)
	match kind:
		"brazier":
			return brazier(_f(p, "h", 1.05), _f(p, "radius", 0.42), _or(mat, "iron"), sink, p, name)
		"torch_post":
			return torch_post(_f(p, "h", 2.1), _or(mat, "timber"), sink, p, name)
		"wall_torch":
			return wall_torch(_f(p, "out", 0.42), _or(mat, "iron"), p, name)
		"hearth_remains":
			return hearth_remains(_f(p, "radius", 0.95), int(p.get("seed", 1)), _or(mat, "stone"),
					str(p.get("wood", CHAR)), sink, p, name)
		"lamp_stone":
			return lamp_stone(_f(p, "radius", 0.55), _or(mat, "stone"), sink, p, name)
		"pyre":
			return pyre(_f(p, "h", 1.5), _f(p, "radius", 1.1), _or(mat, CHAR), sink, p, name)
		"beacon":
			return beacon(_f(p, "h", 1.3), _f(p, "radius", 0.55), _or(mat, "iron"), sink, p, name)
	return {}


## An iron fire bowl on three splayed legs, coals glowing in it. The whole thing is one low cylinder
## collider so the player cannot walk through it but can step onto the kerb of its base.
static func brazier(h: float, r: float, mat: String, sink: float, p: Dictionary, name: String) -> Dictionary:
	var b := StructureKit.builder(mat, name)
	for i: int in range(3):
		var a: float = TAU * float(i) / 3.0
		var foot := Vector3(cos(a) * r * 0.9, -sink, sin(a) * r * 0.9)
		var head := Vector3(cos(a) * r * 0.3, h, sin(a) * r * 0.3)
		_strut(b, foot, head, 0.07)
	b.add_lathe(Transform3D(Basis.IDENTITY, Vector3(0.0, h, 0.0)), PackedVector2Array([
			Vector2(r * 0.35, 0.0), Vector2(r, 0.26), Vector2(r * 0.94, 0.3)]), 10, null)
	var e := StructureKit.builder(EMBER, name)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(p.get("seed", 1))
	for i: int in range(5):
		var a: float = TAU * float(i) / 5.0 + rng.randf_range(-0.3, 0.3)
		StructureKitProps.box(e, Vector3(cos(a) * r * 0.45, h + 0.16, sin(a) * r * 0.45),
				Vector3(r * 0.5, 0.12, r * 0.5), false)
	var shape := CylinderShape3D.new()
	shape.radius = r * 0.95
	shape.height = h + sink
	b.shapes.append({"shape": shape, "transform": Transform3D(Basis.IDENTITY, Vector3(0.0, (h - sink) * 0.5, 0.0))})
	return _lit("brazier", [[b, mat], [e, EMBER]],
			[_light(p, Vector3(0.0, h + 0.22, 0.0), 2.6, 11.0, 0.62, 90.0)])


## A post with an iron band and a rag head: the fire holder beside a door. Only the post collides.
static func torch_post(h: float, mat: String, sink: float, p: Dictionary, name: String) -> Dictionary:
	var b := StructureKit.builder(mat, name)
	StructureKitProps.box(b, Vector3(0.0, (h - sink) * 0.5, 0.0), Vector3(0.13, h + sink, 0.13))
	var i := StructureKit.builder("iron", name)
	StructureKitProps.box(i, Vector3(0.0, h - 0.26, 0.0), Vector3(0.18, 0.06, 0.18), false)
	var c := StructureKit.builder("cloth", name)
	StructureKitProps.box(c, Vector3(0.0, h + 0.05, 0.0), Vector3(0.21, 0.3, 0.21), false)
	return _lit("torch_post", [[b, mat], [i, "iron"], [c, "cloth"]],
			[_light(p, Vector3(0.0, h + 0.3, 0.0), 2.1, 8.5, 0.46, 80.0)])


## A sconce on a bracket reaching out along +Z, for a castle wall or a gate pier. No sink and no collider:
## it hangs at whatever height its layout places it, and the player walks under it.
static func wall_torch(out: float, mat: String, p: Dictionary, name: String) -> Dictionary:
	var b := StructureKit.builder(mat, name)
	StructureKitProps.box(b, Vector3(0.0, 0.0, out * 0.5), Vector3(0.06, 0.06, out), false)
	StructureKitProps.box(b, Vector3(0.0, -0.1, 0.03), Vector3(0.1, 0.26, 0.1), false)
	_strut(b, Vector3(0.0, -0.22, 0.02), Vector3(0.0, -0.02, out * 0.7), 0.04)
	b.add_lathe(Transform3D(Basis.IDENTITY, Vector3(0.0, 0.02, out)), PackedVector2Array([
			Vector2(0.05, 0.0), Vector2(0.11, 0.17), Vector2(0.1, 0.2)]), 8, null)
	var c := StructureKit.builder("cloth", name)
	StructureKitProps.box(c, Vector3(0.0, 0.16, out), Vector3(0.14, 0.2, 0.14), false)
	# The sconce alone collides, not the bracket: every piece in a house layout has to carry collision
	# (tests/test_houses.gd), and a torch mounted at head height is something to duck, not to walk through.
	StructureKitProps.collide(b, Vector3(0.0, 0.08, out), Vector3(0.28, 0.44, 0.28))
	return _lit("wall_torch", [[b, mat], [c, "cloth"]],
			[_light(p, Vector3(0.0, 0.28, out), 2.3, 10.0, 0.42, 70.0)])


## An outdoor fireplace that somebody left: the ring of stones and its charred logs still burning, a back
## slab against the wind, and around it what they were carrying -- a bundle of half-burnt cloth, a pot on
## its side, bones. The kit has no cloth or bone texture, so those wear flat colours. One kerb collider.
static func hearth_remains(r: float, seed: int, mat: String, wood: String, sink: float, p: Dictionary,
		name: String) -> Dictionary:
	var s := StructureKit.builder(mat, name)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	for i: int in range(8):
		var a: float = TAU * float(i) / 8.0 + rng.randf_range(-0.14, 0.14)
		var size := Vector3(rng.randf_range(0.26, 0.38), rng.randf_range(0.2, 0.28), rng.randf_range(0.22, 0.3))
		s.add_box(Transform3D(Basis(Vector3.UP, -a + rng.randf_range(-0.3, 0.3)),
				Vector3(cos(a) * r, size.y * 0.35, sin(a) * r)), size, false)
	s.add_box(Transform3D(Basis(Vector3.RIGHT, 0.22), Vector3(0.0, 0.42, -r - 0.42)),
			Vector3(r * 2.0, 0.84, 0.16), false)
	var w := StructureKit.builder(wood, name)
	w.add_lathe(Transform3D.IDENTITY, PackedVector2Array([Vector2(r + 0.3, -sink), Vector2(r + 0.3, 0.03),
			Vector2(0.02, 0.06)]), 10, null)
	for i: int in range(3):
		w.add_box(Transform3D(Basis(Vector3.UP, float(i) * 1.05) * Basis(Vector3.BACK, 0.2 * float(i)),
				Vector3(0.0, 0.11 + 0.07 * float(i), 0.0)), Vector3(r * 1.2, 0.14, 0.14), false)
	var c := StructureKit.builder("cloth", name)
	c.add_box(Transform3D(Basis(Vector3.UP, 0.7), Vector3(-r - 0.5, 0.09, r * 0.6)), Vector3(0.9, 0.18, 0.6), false)
	c.add_box(Transform3D(Basis(Vector3.UP, -0.4), Vector3(r * 0.5, 0.05, r + 0.75)), Vector3(0.6, 0.1, 0.45), false)
	var o := StructureKit.builder("bone", name)
	for i: int in range(4):
		var a: float = TAU * (0.12 + 0.21 * float(i))
		var d: float = r + rng.randf_range(0.55, 1.15)
		o.add_box(Transform3D(Basis(Vector3.UP, rng.randf_range(0.0, TAU)) * Basis(Vector3.BACK, 1.5),
				Vector3(cos(a) * d, 0.05, sin(a) * d)), Vector3(0.07, rng.randf_range(0.28, 0.5), 0.07), false)
	var t := StructureKit.builder("iron", name)
	t.add_lathe(Transform3D(Basis(Vector3.BACK, 1.3), Vector3(-r * 0.4, 0.14, r + 0.6)), PackedVector2Array([
			Vector2(0.17, -0.12), Vector2(0.2, 0.0), Vector2(0.18, 0.2), Vector2(0.2, 0.24)]), 8, null)
	StructureKitProps.box(t, Vector3(r + 0.5, 0.08, -r * 0.3), Vector3(0.22, 0.16, 0.22), false)
	var kerb := CylinderShape3D.new()
	kerb.radius = r + 0.2
	kerb.height = 0.3
	s.shapes.append({"shape": kerb, "transform": Transform3D(Basis.IDENTITY, Vector3(0.0, 0.05, 0.0))})
	return _lit("hearth_remains", [[s, mat], [w, wood], [c, "cloth"], [o, "bone"], [t, "iron"]],
			[_light(p, Vector3(0.0, 0.3, 0.0), 2.4, 10.5, 0.72, 95.0)])


## A boulder with a little iron lantern cage standing on it: the wayside light along a road, at knee height
## so it shows the verge rather than the sky. The boulder carries the collider.
static func lamp_stone(r: float, mat: String, sink: float, p: Dictionary, name: String) -> Dictionary:
	var b := StructureKit.builder(mat, name)
	var shape := CylinderShape3D.new()
	shape.radius = r * 0.95
	shape.height = r + sink
	b.add_lathe(Transform3D.IDENTITY, PackedVector2Array([Vector2(r, -sink), Vector2(r * 1.02, r * 0.35),
			Vector2(r * 0.8, r * 0.8), Vector2(r * 0.5, r)]), 8, shape, Vector3(0.0, (r - sink) * 0.5, 0.0))
	var i := StructureKit.builder("iron", name)
	var top: float = r
	StructureKitProps.box(i, Vector3(0.0, top + 0.02, 0.0), Vector3(0.3, 0.04, 0.3), false)
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			StructureKitProps.box(i, Vector3(sx * 0.12, top + 0.2, sz * 0.12), Vector3(0.03, 0.34, 0.03), false)
	StructureKitProps.box(i, Vector3(0.0, top + 0.4, 0.0), Vector3(0.34, 0.06, 0.34), false)
	var e := StructureKit.builder(EMBER, name)
	StructureKitProps.box(e, Vector3(0.0, top + 0.14, 0.0), Vector3(0.16, 0.12, 0.16), false)
	return _lit("lamp_stone", [[b, mat], [i, "iron"], [e, EMBER]],
			[_light(p, Vector3(0.0, top + 0.2, 0.0), 1.7, 7.5, 0.22, 70.0)])


## Crossed timbers stacked into a square well and burning hard: the big fire of a camp or a courtyard, the
## one meant to be seen from across the valley. The stack collides as one box.
static func pyre(h: float, r: float, mat: String, sink: float, p: Dictionary, name: String) -> Dictionary:
	var b := StructureKit.builder(mat, name)
	var courses: int = maxi(2, roundi(h / 0.26))
	var log_t: float = h / float(courses) * 0.9
	for i: int in range(courses):
		var y: float = log_t * (float(i) + 0.5)
		var span: float = r * 2.0 * (1.0 - 0.12 * float(i) / float(courses))
		var along_x: bool = i % 2 == 0
		for side: float in [-1.0, 1.0]:
			var off: float = side * span * 0.38
			var at: Vector3 = Vector3(off, y, 0.0) if along_x else Vector3(0.0, y, off)
			var size: Vector3 = Vector3(span, log_t, log_t) if along_x else Vector3(log_t, log_t, span)
			StructureKitProps.box(b, at, size, false)
	# A buried footing under the stack: the logs themselves start at ground level, so on falling ground a
	# pyre would otherwise stand on air at its low side (the rule every standing piece obeys).
	StructureKitProps.box(b, Vector3(0.0, -sink * 0.5, 0.0), Vector3(r * 1.7, sink, r * 1.7), false)
	var e := StructureKit.builder(EMBER, name)
	StructureKitProps.box(e, Vector3(0.0, h * 0.35, 0.0), Vector3(r * 0.9, h * 0.6, r * 0.9), false)
	StructureKitProps.collide(b, Vector3(0.0, (h - sink) * 0.5, 0.0), Vector3(r * 2.0, h + sink, r * 2.0))
	return _lit("pyre", [[b, mat], [e, EMBER]],
			[_light(p, Vector3(0.0, h * 0.8, 0.0), 4.2, 19.0, 1.5, 170.0)])


## An iron fire basket on a short mast: the watch fire, put on a roof or a wall head so it carries. Its
## light reaches furthest of the lot, which is the whole point of lighting one.
static func beacon(h: float, r: float, mat: String, sink: float, p: Dictionary, name: String) -> Dictionary:
	var b := StructureKit.builder(mat, name)
	StructureKitProps.box(b, Vector3(0.0, (h - sink) * 0.5, 0.0), Vector3(0.14, h + sink, 0.14))
	for i: int in range(8):
		var a: float = TAU * float(i) / 8.0
		_strut(b, Vector3(cos(a) * r * 0.45, h, sin(a) * r * 0.45), Vector3(cos(a) * r, h + 0.42, sin(a) * r), 0.045)
	b.add_lathe(Transform3D(Basis.IDENTITY, Vector3(0.0, h, 0.0)), PackedVector2Array([
			Vector2(r * 0.5, 0.0), Vector2(r * 0.55, 0.06)]), 8, null)
	b.add_lathe(Transform3D(Basis.IDENTITY, Vector3(0.0, h + 0.42, 0.0)), PackedVector2Array([
			Vector2(r, 0.0), Vector2(r * 1.04, 0.07)]), 8, null)
	var e := StructureKit.builder(EMBER, name)
	StructureKitProps.box(e, Vector3(0.0, h + 0.2, 0.0), Vector3(r * 1.1, 0.3, r * 1.1), false)
	return _lit("beacon", [[b, mat], [e, EMBER]],
			[_light(p, Vector3(0.0, h + 0.5, 0.0), 4.6, 26.0, 1.15, 240.0)])


# --- helpers -----------------------------------------------------------------------------------------------

## A square bar from `a` to `b`, however it leans: legs, bracket stays, basket ribs.
static func _strut(b: StructureMeshBuilder, a: Vector3, to: Vector3, thickness: float) -> void:
	var span: Vector3 = to - a
	var length: float = span.length()
	if length < 0.001:
		return
	var up: Vector3 = span / length
	var side: Vector3 = Vector3.RIGHT if absf(up.dot(Vector3.RIGHT)) < 0.9 else Vector3.BACK
	var x: Vector3 = side.cross(up).normalized()
	b.add_box(Transform3D(Basis(x, up, x.cross(up)), (a + to) * 0.5),
			Vector3(thickness, length, thickness), false)


## One light spec, with every field the layout chose to override folded in.
static func _light(p: Dictionary, at: Vector3, energy: float, light_range: float, flame: float,
		sight: float = 90.0) -> Dictionary:
	var spec: Dictionary = {
		"at": [at.x, at.y + _f(p, "light_lift", 0.0), at.z],
		"energy": _f(p, "energy", energy),
		"range": _f(p, "range", light_range),
		"flame": _f(p, "flame", flame),
		"flicker": _f(p, "flicker", 0.3),
		"day": _f(p, "day", 0.5),
		"cull": _f(p, "cull", sight),
	}
	if p.has("color"):
		spec["color"] = p["color"]
	return spec


## StructureKitProps.finish plus the lights, which is the only thing a lit piece adds to a plain one.
static func _lit(kind: String, parts: Array, lights: Array) -> Dictionary:
	var piece: Dictionary = StructureKitProps.finish(kind, parts)
	piece["lights"] = lights
	return piece


static func _f(d: Dictionary, key: String, fallback: float) -> float:
	var v: Variant = d.get(key, fallback)
	return float(v) if v is float or v is int else fallback


static func _or(mat: String, fallback: String) -> String:
	return fallback if mat.is_empty() else mat
