class_name StructureKitProps
extends RefCounted
## Kit pieces for small points of interest: wells, carts, fences, haystacks, scarecrows, cairns (W8-P). The
## camp and wayside pieces (signpost, campfire, tent frame, weapon rack, grave mound, trough) live in
## StructureKitPropsCamp to keep this file short; make() forwards to it. StructureBuilder.make_piece falls
## through to make() for any kind it does not know. Return a piece dictionary like StructureKit's
## ({kind, mesh, shapes, verts}) for a kind this file owns, {} otherwise. Build with
## StructureKit.builder(mat, name) so tiling and UV offsets match the rest of the kit.
##
## Conventions follow StructureKit: origin at the base centre, width along X, depth along Z, up Y. Every
## piece that stands on the ground reaches `sink` metres below y = 0, because Settlements floors a site at
## the HIGHEST ground under its footprint and these have no foundation of their own: a fence post on the low
## side of a 0.8 m drop would otherwise hang in the air. A piece built from two materials (a well's stone
## ring and its timber frame) is one ArrayMesh with one surface per material, so it still places as one
## node and one body. None of these kinds is a Footprint ground kind: a layout declares the ground its
## pieces cover with `keep_out` rects, which is what grass, trees and the placement rules read.

const SINK := 0.8
const POST := 0.12


static func make(kind: String, p: Dictionary, name: String = "") -> Dictionary:
	var mat: String = str(p.get("mat", ""))
	match kind:
		"well":
			return well(_f(p, "radius", 0.9), _f(p, "h", 1.0), _f(p, "post_h", 2.3), _or(mat, "stone"),
					str(p.get("wood", "planks")), sink_of(p), name)
		"cart":
			return cart(_f(p, "w", 2.6), _f(p, "d", 1.4), _f(p, "wheel", 0.55), _or(mat, "planks"), name)
		"fence":
			return fence(_f(p, "length", 6.0), _f(p, "h", 1.1), _f(p, "spacing", 2.0), int(p.get("rails", 2)),
					bool(p.get("broken", false)), int(p.get("seed", 1)), _or(mat, "planks"), sink_of(p), name)
		"haystack":
			return haystack(_f(p, "radius", 1.3), _f(p, "h", 2.0), int(p.get("sides", 10)), _or(mat, "plaster"),
					sink_of(p), name)
		"scarecrow":
			return scarecrow(_f(p, "h", 2.2), _or(mat, "planks"), sink_of(p), name)
		"cairn":
			return cairn(_f(p, "radius", 0.6), _f(p, "h", 1.2), int(p.get("count", 7)), int(p.get("seed", 1)),
					_or(mat, "stone"), sink_of(p), name)
		"garden_bed":
			return garden_bed(_f(p, "w", 1.4), _f(p, "d", 2.6), int(p.get("rows", 3)), int(p.get("seed", 1)),
					_or(mat, "soil"), str(p.get("crop", "sprout")), sink_of(p), name)
	return StructureKitPropsCamp.make(kind, p, name)


## A dry well: a stone ring open at the top down to a floor at 0.15 m, two posts, a crossbar, a little
## pitched cap of two boards, and a bucket on its rope. The ring is the only collider.
static func well(r: float, h: float, post_h: float, mat: String, wood: String, sink: float, name: String) -> Dictionary:
	var s := StructureKit.builder(mat, name)
	var inner: float = r * 0.78
	var ring := CylinderShape3D.new()
	ring.radius = r
	ring.height = h + sink
	s.add_lathe(Transform3D.IDENTITY, PackedVector2Array([Vector2(r, -sink), Vector2(r, h), Vector2(inner, h),
			Vector2(inner, 0.15)]), 10, ring, Vector3(0.0, (h - sink) * 0.5, 0.0))
	var w := StructureKit.builder(wood, name)
	var px: float = r + 0.15
	for sx: float in [-1.0, 1.0]:
		box(w, Vector3(sx * px, (post_h - sink) * 0.5, 0.0), Vector3(POST, post_h + sink, POST), false)
	box(w, Vector3(0.0, post_h - 0.1, 0.0), Vector3(2.0 * px + POST, 0.1, 0.1), false)
	var ridge: float = post_h + 0.45
	var pitch: float = deg_to_rad(35.0)
	for sz: float in [-1.0, 1.0]:
		w.add_box(Transform3D(Basis(Vector3.RIGHT, sz * pitch), Vector3(0.0, ridge - 0.4 * sin(pitch), sz * 0.4 * cos(pitch))),
				Vector3(2.0 * px + 0.6, 0.05, 0.85), false)
	box(w, Vector3(0.0, post_h - 0.33, 0.0), Vector3(0.02, 0.36, 0.02), false)
	w.add_lathe(Transform3D(Basis.IDENTITY, Vector3(0.0, post_h - 0.78, 0.0)),
			PackedVector2Array([Vector2(0.13, 0.0), Vector2(0.16, 0.26)]), 6, null)
	return finish("well", [[s, mat], [w, wood]])


## A two-wheeled hand cart: bed, two sides and a tailboard at -X, an axle, two wheel discs, and shafts
## reaching out past +X with their tips on the ground. Placed with `tilt` it lies tipped on one wheel.
static func cart(w: float, d: float, wheel: float, mat: String, name: String) -> Dictionary:
	var b := StructureKit.builder(mat, name)
	var bed_y: float = wheel + 0.1
	box(b, Vector3(0.0, bed_y, 0.0), Vector3(w, 0.1, d))
	for sz: float in [-1.0, 1.0]:
		box(b, Vector3(0.0, bed_y + 0.25, sz * (d * 0.5 - 0.03)), Vector3(w, 0.4, 0.06))
	box(b, Vector3(-w * 0.5 + 0.03, bed_y + 0.25, 0.0), Vector3(0.06, 0.4, d - 0.12))
	box(b, Vector3(0.0, wheel, 0.0), Vector3(0.1, 0.1, d + 0.3), false)
	for sz: float in [-1.0, 1.0]:
		var disc := CylinderShape3D.new()
		disc.radius = wheel
		disc.height = 0.1
		b.add_lathe(Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0.0, wheel, sz * (d * 0.5 + 0.12))),
				PackedVector2Array([Vector2(wheel, -0.05), Vector2(wheel, 0.05)]), 10, disc)
	var reach: float = w * 0.55
	var tip_y: float = 0.2
	var ang: float = atan2(bed_y - tip_y, reach)
	var shaft: float = sqrt(reach * reach + (bed_y - tip_y) * (bed_y - tip_y))
	for sz: float in [-1.0, 1.0]:
		b.add_box(Transform3D(Basis(Vector3.BACK, -ang), Vector3(w * 0.5 + reach * 0.5, (bed_y + tip_y) * 0.5, sz * d * 0.35)),
				Vector3(shaft, 0.07, 0.07), false)
	return finish("cart", [[b, mat]])


## Posts every `spacing` along X with `rails` rails between them. Intact, the whole run is one collider.
## Broken, half the posts lean, at least one bay (more by chance) loses its top rail to the ground, and
## only whole bays block.
static func fence(length: float, h: float, spacing: float, rails: int, broken: bool, seed: int, mat: String,
		sink: float, name: String) -> Dictionary:
	var b := StructureKit.builder(mat, name)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var bays: int = maxi(1, roundi(length / maxf(0.5, spacing)))
	var bay: float = length / float(bays)
	var x0: float = -length * 0.5
	var surely_fallen: int = rng.randi_range(0, bays - 1)
	for i: int in range(bays + 1):
		var lean: float = rng.randf_range(-0.2, 0.2) if broken and rng.randf() < 0.5 else 0.0
		b.add_box(Transform3D(Basis(Vector3.BACK, lean), Vector3(x0 + bay * float(i), (h - sink) * 0.5, 0.0)),
				Vector3(POST, h + sink, POST), false)
	var n_rails: int = maxi(1, rails)
	for i: int in range(bays):
		var cx: float = x0 + bay * (float(i) + 0.5)
		var fallen: bool = broken and (i == surely_fallen or rng.randf() < 0.4)
		for r: int in range(n_rails):
			var y: float = h * (0.5 + 0.45 * float(r) / float(maxi(1, n_rails - 1)))
			if fallen and r == n_rails - 1:
				b.add_box(Transform3D(Basis(Vector3.BACK, -atan2(y, bay)), Vector3(cx, y * 0.5, 0.12)),
						Vector3(sqrt(bay * bay + y * y), 0.08, 0.05), false)
			else:
				box(b, Vector3(cx, y, 0.0), Vector3(bay + POST, 0.08, 0.05), false)
		if broken and not fallen:
			collide(b, Vector3(cx, h * 0.5, 0.0), Vector3(bay + POST, h, POST))
	if not broken:
		collide(b, Vector3(0.0, h * 0.5, 0.0), Vector3(length + POST, h, POST))
	return finish("fence", [[b, mat]])


## A rounded stack that swells at a third of its height and closes to a point. No hay texture exists in the
## kit, so it wears whatever `mat` says (plaster by default, UNVERIFIED by eye).
static func haystack(r: float, h: float, sides: int, mat: String, sink: float, name: String) -> Dictionary:
	var b := StructureKit.builder(mat, name)
	var shape := CylinderShape3D.new()
	shape.radius = r * 0.95
	shape.height = h + sink
	b.add_lathe(Transform3D.IDENTITY, PackedVector2Array([Vector2(r * 0.85, -sink), Vector2(r * 0.95, 0.0),
			Vector2(r, h * 0.35), Vector2(r * 0.86, h * 0.7), Vector2(r * 0.5, h * 0.92), Vector2(0.03, h)]),
			maxi(5, sides), shape, Vector3(0.0, (h - sink) * 0.5, 0.0))
	return finish("haystack", [[b, mat]])


## A post with a crossbar, a slab of coat hanging under it, a head on top and one sleeve drooping off the
## bar's end. Only the post collides.
static func scarecrow(h: float, mat: String, sink: float, name: String) -> Dictionary:
	var b := StructureKit.builder(mat, name)
	box(b, Vector3(0.0, (h - sink) * 0.5, 0.0), Vector3(0.1, h + sink, 0.1))
	var arm_y: float = h * 0.72
	box(b, Vector3(0.0, arm_y, 0.0), Vector3(1.3, 0.08, 0.08), false)
	box(b, Vector3(0.0, arm_y - 0.36, 0.0), Vector3(0.55, 0.7, 0.16), false)
	box(b, Vector3(0.0, h + 0.12, 0.0), Vector3(0.26, 0.26, 0.26), false)
	b.add_box(Transform3D(Basis(Vector3.BACK, 0.9), Vector3(0.62, arm_y - 0.2, 0.0)), Vector3(0.45, 0.14, 0.14), false)
	return finish("scarecrow", [[b, mat]])


## Stacked stones narrowing upward, each turned a little; the bottom stone is sunk. One cylinder collider.
static func cairn(r: float, h: float, count: int, seed: int, mat: String, sink: float, name: String) -> Dictionary:
	var b := StructureKit.builder(mat, name)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var n: int = maxi(2, count)
	var course: float = h / float(n)
	var y: float = 0.0
	for i: int in range(n):
		var taper: float = 2.0 * r * (1.0 - 0.55 * float(i) / float(n))
		var size := Vector3(taper * rng.randf_range(0.85, 1.1), course, taper * rng.randf_range(0.85, 1.1))
		var at := Vector3(rng.randf_range(-0.06, 0.06), y + course * 0.5, rng.randf_range(-0.06, 0.06))
		if i == 0:
			size.y += sink
			at.y -= sink * 0.5
		b.add_box(Transform3D(Basis(Vector3.UP, rng.randf_range(-0.6, 0.6)), at), size, false)
		y += course
	var shape := CylinderShape3D.new()
	shape.radius = r * 1.05
	shape.height = h + sink
	b.shapes.append({"shape": shape, "transform": Transform3D(Basis.IDENTITY, Vector3(0.0, (h - sink) * 0.5, 0.0))})
	return finish("cairn", [[b, mat]])


## A kitchen garden bed: a low mound of turned earth with rows of something coming up in it. The owner,
## after playing: "there should be small gardens and all". Not a Footprint ground kind on purpose -- a bed
## beside a house must not grow the footprint the house is floored on, or twenty houses move up and down.
## One low kerb collider the player steps over rather than walks through.
static func garden_bed(w: float, d: float, rows: int, seed: int, mat: String, crop: String, sink: float,
		name: String) -> Dictionary:
	var b := StructureKit.builder(mat, name)
	var h: float = 0.22
	box(b, Vector3(0.0, (h - sink) * 0.5, 0.0), Vector3(w, h + sink, d), false)
	box(b, Vector3(0.0, h * 0.5 + 0.08, 0.0), Vector3(w * 0.84, h * 0.6, d * 0.94), false)
	var g := StructureKit.builder(crop, name)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var lines: int = maxi(1, rows)
	for r: int in range(lines):
		var x: float = -w * 0.5 + w * (float(r) + 0.5) / float(lines)
		var per: int = maxi(2, int(d / 0.42))
		for i: int in range(per):
			var z: float = -d * 0.5 + d * (float(i) + 0.5) / float(per)
			var tall: float = rng.randf_range(0.12, 0.26)
			g.add_box(Transform3D(Basis(Vector3.UP, rng.randf_range(0.0, TAU)),
					Vector3(x + rng.randf_range(-0.05, 0.05), h + tall * 0.5, z + rng.randf_range(-0.05, 0.05))),
					Vector3(0.09, tall, 0.09), false)
	collide(b, Vector3(0.0, (h - sink) * 0.5, 0.0), Vector3(w, h + sink, d))
	return finish("garden_bed", [[b, mat], [g, crop]])


# --- shared helpers (also used by StructureKitPropsCamp) ----------------------------------------------------

static func box(b: StructureMeshBuilder, at: Vector3, size: Vector3, collide_too: bool = true) -> void:
	b.add_box(Transform3D(Basis.IDENTITY, at), size, collide_too)


## A collision box with no geometry of its own: one body for a whole fence run, or for a rack of thin sticks.
static func collide(b: StructureMeshBuilder, at: Vector3, size: Vector3) -> void:
	var shape := BoxShape3D.new()
	shape.size = size
	b.shapes.append({"shape": shape, "transform": Transform3D(Basis.IDENTITY, at)})


## One piece from several builders: the first material's surface, then one more surface per extra
## material, with every builder's shapes and vertices pooled. StructureBuilder places it as one node.
static func finish(kind: String, parts: Array) -> Dictionary:
	var mesh: ArrayMesh = null
	var shapes: Array[Dictionary] = []
	var verts: int = 0
	for part: Array in parts:
		var b: StructureMeshBuilder = part[0]
		var material: Material = StructureMaterials.get_material(str(part[1]))
		var sub: ArrayMesh = b.commit(material)
		if mesh == null:
			mesh = sub
		elif sub.get_surface_count() > 0:
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, sub.surface_get_arrays(0))
			mesh.surface_set_material(mesh.get_surface_count() - 1, material)
		shapes.append_array(b.shapes)
		verts += b.vertex_count()
	return {"kind": kind, "mesh": mesh, "shapes": shapes, "verts": verts}


static func sink_of(p: Dictionary) -> float:
	return _f(p, "sink", SINK)


static func _f(d: Dictionary, key: String, fallback: float) -> float:
	var v: Variant = d.get(key, fallback)
	return float(v) if v is float or v is int else fallback


static func _or(mat: String, fallback: String) -> String:
	return fallback if mat.is_empty() else mat
