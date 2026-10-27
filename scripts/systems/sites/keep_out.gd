class_name KeepOutMask
extends RefCounted
## Ground that grass, trees and scattered props must leave alone because something is built on it. The
## footprints are rasterised once into half-metre cells, so the question grass asks thousands of times per
## lattice cell is one dictionary lookup rather than a test against every wall in the valley.

const CELL := 0.5

var _cells: Dictionary = {}
var _obbs: Array[Dictionary] = []


## Marks every cell whose centre falls inside the OBB grown by `margin`. The margin is what keeps a grass
## clump's blades from leaning through the foot of a wall.
func add_obb(obb: Dictionary, margin: float = 0.0) -> void:
	_obbs.append(obb)
	var box: Rect2 = Footprint.bounds(obb, margin)
	var i0: int = floori(box.position.x / CELL)
	var i1: int = floori(box.end.x / CELL)
	var j0: int = floori(box.position.y / CELL)
	var j1: int = floori(box.end.y / CELL)
	for i: int in range(i0, i1 + 1):
		var x: float = (float(i) + 0.5) * CELL
		for j: int in range(j0, j1 + 1):
			if Footprint.has_point(obb, x, (float(j) + 0.5) * CELL, margin):
				_cells[Vector2i(i, j)] = true


func blocks(x: float, z: float) -> bool:
	return _cells.has(Vector2i(floori(x / CELL), floori(z / CELL)))


## True when any built ground lies within `radius`: a tree's canopy and a prop's bulk need room, not just a
## free point.
func blocks_near(x: float, z: float, radius: float) -> bool:
	if radius <= 0.0:
		return blocks(x, z)
	var r: int = ceili(radius / CELL)
	var ci: int = floori(x / CELL)
	var cj: int = floori(z / CELL)
	var r2: float = radius * radius
	for di: int in range(-r, r + 1):
		for dj: int in range(-r, r + 1):
			if not _cells.has(Vector2i(ci + di, cj + dj)):
				continue
			var cx: float = (float(ci + di) + 0.5) * CELL - x
			var cz: float = (float(cj + dj) + 0.5) * CELL - z
			if cx * cx + cz * cz <= r2:
				return true
	return false


## True when the two masks share any cell. Used to keep two sites from being built into each other.
func overlaps(other: KeepOutMask) -> bool:
	var small: Dictionary = _cells if _cells.size() <= other._cells.size() else other._cells
	var large: Dictionary = other._cells if small == _cells else _cells
	for key: Variant in small:
		if large.has(key):
			return true
	return false


func cell_count() -> int:
	return _cells.size()


func obb_count() -> int:
	return _obbs.size()


func obbs() -> Array[Dictionary]:
	return _obbs
