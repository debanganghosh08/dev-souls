class_name StructureKitRock
extends RefCounted
## Rock (W12). The owner, looking at his own footage: the ground is flat. Four kinds carry the whole job --
## a crag to break a skyline, a boulder field to break a meadow, standing stones to mark a place, and a cut
## face for the rock wall a road is driven through. Each is designed once here and placed many times from
## data, which is the arrangement the owner asked for.
##
## Conventions are StructureKitProps: origin at the base centre, `sink` metres buried so nothing floats on a
## slope (D-029). Rock is not cut stone, so every piece leans, tapers and turns on its own seed; two
## placements of one layout share meshes and still read as different rock.

const SINK := 2.4


static func make(kind: String, p: Dictionary, name: String = "") -> Dictionary:
	var mat: String = str(p.get("mat", "rock"))
	var sink: float = _f(p, "sink", SINK)
	var seed: int = int(p.get("seed", 1))
	match kind:
		"crag":
			return crag(_f(p, "h", 9.0), _f(p, "radius", 3.4), int(p.get("slabs", 7)), seed, mat, sink, name)
		"boulders":
			return boulders(_f(p, "radius", 5.0), int(p.get("count", 7)), _f(p, "size", 1.6), seed, mat, sink, name)
		"standing_stones":
			return standing_stones(_f(p, "radius", 4.5), int(p.get("count", 7)), _f(p, "h", 3.2), seed, mat, sink, name)
		"cut_face":
			return cut_face(_f(p, "length", 18.0), _f(p, "h", 11.0), _f(p, "t", 3.0), seed, mat, sink, name)
	return {}


## A crag: slabs stacked and leaning, narrowing as they rise, with a shoulder of fallen rock at the foot.
## The thing that breaks a flat horizon.
static func crag(h: float, radius: float, slabs: int, seed: int, mat: String, sink: float, name: String) -> Dictionary:
	var b := StructureKit.builder(mat, name)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var n: int = maxi(2, slabs)
	var y: float = -sink
	for i: int in range(n):
		var f: float = float(i) / float(n)
		var course: float = (h + sink) / float(n) * rng.randf_range(0.8, 1.25)
		var wide: float = radius * 2.0 * (1.0 - 0.62 * f) * rng.randf_range(0.8, 1.15)
		var deep: float = radius * 2.0 * (1.0 - 0.62 * f) * rng.randf_range(0.8, 1.15)
		var lean: float = rng.randf_range(-0.13, 0.13) * (0.4 + f)
		var basis := Basis(Vector3.UP, rng.randf_range(0.0, TAU)) * Basis(Vector3.BACK, lean)
		var off: float = radius * 0.22 * f
		b.add_box(Transform3D(basis, Vector3(rng.randf_range(-off, off), y + course * 0.5, rng.randf_range(-off, off))),
				Vector3(wide, course, deep), false)
		y += course * rng.randf_range(0.82, 0.96)
	for i: int in range(maxi(3, n - 2)):
		var a: float = TAU * float(i) / float(maxi(3, n - 2)) + rng.randf_range(-0.4, 0.4)
		var r: float = radius * rng.randf_range(0.95, 1.5)
		var lump: float = radius * rng.randf_range(0.22, 0.45)
		b.add_box(Transform3D(Basis(Vector3.UP, rng.randf_range(0.0, TAU)) * Basis(Vector3.RIGHT, rng.randf_range(-0.5, 0.5)),
				Vector3(cos(a) * r, lump * 0.2, sin(a) * r)), Vector3(lump * 2.0, lump, lump * 1.7), false)
	var shape := CylinderShape3D.new()
	shape.radius = radius * 1.05
	shape.height = h + sink
	b.shapes.append({"shape": shape, "transform": Transform3D(Basis.IDENTITY, Vector3(0.0, (h - sink) * 0.5, 0.0))})
	return StructureKitProps.finish("crag", [[b, mat]])


## Rounded masses half buried in the ground, the way a field of glacial rock sits.
static func boulders(radius: float, count: int, size: float, seed: int, mat: String, sink: float, name: String) -> Dictionary:
	var b := StructureKit.builder(mat, name)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var n: int = maxi(1, count)
	for i: int in range(n):
		var a: float = TAU * float(i) / float(n) + rng.randf_range(-0.5, 0.5)
		var r: float = radius * sqrt(rng.randf())
		var s: float = size * rng.randf_range(0.55, 1.45)
		var at := Vector3(cos(a) * r, s * 0.18, sin(a) * r)
		var basis := Basis(Vector3.UP, rng.randf_range(0.0, TAU)) * Basis(Vector3.RIGHT, rng.randf_range(-0.35, 0.35))
		b.add_box(Transform3D(basis, at), Vector3(s * 1.7, s, s * 1.5), false)
		b.add_box(Transform3D(basis * Basis(Vector3.UP, 0.7), at + Vector3(0.0, s * 0.3, 0.0)),
				Vector3(s * 1.25, s * 0.7, s * 1.1), false)
		var cs := BoxShape3D.new()
		cs.size = Vector3(s * 1.7, s + sink, s * 1.5)
		b.shapes.append({"shape": cs, "transform": Transform3D(Basis(Vector3.UP, 0.0),
				at - Vector3(0.0, sink * 0.5, 0.0))})
	return StructureKitProps.finish("boulders", [[b, mat]])


## Upright slabs set in a ring: somebody put these here, which is why they read as a place.
static func standing_stones(radius: float, count: int, h: float, seed: int, mat: String, sink: float, name: String) -> Dictionary:
	var b := StructureKit.builder(mat, name)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var n: int = maxi(2, count)
	for i: int in range(n):
		var a: float = TAU * float(i) / float(n)
		var tall: float = h * rng.randf_range(0.6, 1.25)
		var fallen: bool = rng.randf() < 0.22
		var basis := Basis(Vector3.UP, -a + rng.randf_range(-0.2, 0.2))
		if fallen:
			basis = basis * Basis(Vector3.RIGHT, 1.45)
		else:
			basis = basis * Basis(Vector3.BACK, rng.randf_range(-0.1, 0.1))
		var at := Vector3(cos(a) * radius, (tall - sink) * 0.5 if not fallen else 0.35, sin(a) * radius)
		b.add_box(Transform3D(basis, at), Vector3(tall * 0.42, tall + sink, tall * 0.2), false)
		var cs := BoxShape3D.new()
		cs.size = Vector3(tall * 0.5, tall + sink, tall * 0.5)
		b.shapes.append({"shape": cs, "transform": Transform3D(Basis.IDENTITY, at)})
	return StructureKitProps.finish("standing_stones", [[b, mat]])


## A wall of rock with a worked, broken face: what a road driven through a hill leaves behind on either
## side. Long along X, so a layout puts two of them facing each other with the road between.
static func cut_face(length: float, h: float, t: float, seed: int, mat: String, sink: float, name: String) -> Dictionary:
	var b := StructureKit.builder(mat, name)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var steps: int = maxi(3, roundi(length / 2.6))
	var step: float = length / float(steps)
	for i: int in range(steps):
		var x: float = -length * 0.5 + step * (float(i) + 0.5)
		var tall: float = h * rng.randf_range(0.62, 1.1)
		var lean: float = rng.randf_range(-0.12, 0.04)
		b.add_box(Transform3D(Basis(Vector3.RIGHT, lean), Vector3(x, (tall - sink) * 0.5, rng.randf_range(-0.2, 0.2))),
				Vector3(step * rng.randf_range(1.0, 1.25), tall + sink, t * rng.randf_range(0.8, 1.2)), false)
		if rng.randf() < 0.45:
			var lump: float = t * rng.randf_range(0.3, 0.6)
			b.add_box(Transform3D(Basis(Vector3.UP, rng.randf_range(0.0, TAU)),
					Vector3(x + rng.randf_range(-1.0, 1.0), lump * 0.3, -t * 0.5 - lump * rng.randf_range(0.6, 1.6))),
					Vector3(lump * 2.0, lump, lump * 1.6), false)
	var cs := BoxShape3D.new()
	cs.size = Vector3(length, h + sink, t)
	b.shapes.append({"shape": cs, "transform": Transform3D(Basis.IDENTITY, Vector3(0.0, (h - sink) * 0.5, 0.0))})
	return StructureKitProps.finish("cut_face", [[b, mat]])


static func _f(d: Dictionary, key: String, fallback: float) -> float:
	var v: Variant = d.get(key, fallback)
	return float(v) if v is float or v is int else fallback
