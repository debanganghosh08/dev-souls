class_name StructureKitTrim
extends RefCounted
## The opt-in silhouette trim StructureKit.wall and .block add when a layout asks for it: a plinth (a
## slightly wider base course) and a string course (a projecting band at height y). A flat slab with one
## sharp top edge is most of why a wall reads as card; a lip at the foot and a shadow line part-way up give
## the eye a scale. Both are plain boxes with their own BoxShape3D so what the player sees is exactly what
## stops them -- no invisible lip, nothing to stand inside. Off unless the params name them, so every
## existing piece is unchanged (tests/test_structures.gd pins a plain wall at one box).

## Below this a band is a sliver that would only z-fight; it is dropped rather than drawn.
const MIN_BAND := 0.01


## Bands along a wall's two faces, broken around the opening where their heights overlap it (a plinth must
## not seal a doorway; a course must not cross a window). `plinth` = {h, out}; `course` = {y, h, out}.
static func wall_bands(b: StructureMeshBuilder, w: float, h: float, t: float, opening: Dictionary,
		plinth: Dictionary, course: Dictionary) -> void:
	if not plinth.is_empty():
		_wall_band(b, w, h, t, opening, 0.0, float(plinth.get("h", 0.4)), float(plinth.get("out", 0.12)))
	if not course.is_empty():
		_wall_band(b, w, h, t, opening, float(course.get("y", h * 0.6)), float(course.get("h", 0.25)), float(course.get("out", 0.1)))


## Bands around all four sides of a free-standing block: one box each, grown by `out` on X and Z.
static func block_bands(b: StructureMeshBuilder, size: Vector3, plinth: Dictionary, course: Dictionary) -> void:
	if not plinth.is_empty():
		_block_band(b, size, 0.0, float(plinth.get("h", 0.4)), float(plinth.get("out", 0.12)))
	if not course.is_empty():
		_block_band(b, size, float(course.get("y", size.y * 0.6)), float(course.get("h", 0.25)), float(course.get("out", 0.1)))


static func _wall_band(b: StructureMeshBuilder, w: float, h: float, t: float, opening: Dictionary,
		y: float, band_h: float, out: float) -> void:
	var top: float = minf(y + band_h, h)
	if y < 0.0 or top - y < MIN_BAND or out <= 0.0:
		return
	var size_z: float = t + 2.0 * out
	var cy: float = (y + top) * 0.5
	var ow: float = float(opening.get("width", 1.4))
	var sill: float = float(opening.get("sill", 0.0))
	var ox: float = float(opening.get("offset", 0.0))
	var crosses: bool = not opening.is_empty() and y < sill + float(opening.get("height", 2.4)) and top > sill
	if not crosses:
		b.add_box(Transform3D(Basis.IDENTITY, Vector3(0.0, cy, 0.0)), Vector3(w, top - y, size_z))
		return
	# Same pier arithmetic as StructureKit.wall, so the band ends exactly where the jambs do.
	var left_w: float = (ox - ow * 0.5) + w * 0.5
	var right_w: float = w * 0.5 - (ox + ow * 0.5)
	if left_w > MIN_BAND:
		b.add_box(Transform3D(Basis.IDENTITY, Vector3(-w * 0.5 + left_w * 0.5, cy, 0.0)), Vector3(left_w, top - y, size_z))
	if right_w > MIN_BAND:
		b.add_box(Transform3D(Basis.IDENTITY, Vector3(w * 0.5 - right_w * 0.5, cy, 0.0)), Vector3(right_w, top - y, size_z))


static func _block_band(b: StructureMeshBuilder, size: Vector3, y: float, band_h: float, out: float) -> void:
	var top: float = minf(y + band_h, size.y)
	if y < 0.0 or top - y < MIN_BAND or out <= 0.0:
		return
	b.add_box(Transform3D(Basis.IDENTITY, Vector3(0.0, (y + top) * 0.5, 0.0)), Vector3(size.x + 2.0 * out, top - y, size.z + 2.0 * out))
