class_name SiteRegistry
extends RefCounted
## Every built place in an area, as data: `data/sites/<area>.json` plus any `data/sites/<area>_*.json`
## (houses and points of interest live in their own files so two people can add to the map at once).
##
## A site is {"id", "layout", "at": [x, z], "yaw", ...}. `fixed: true` sites (the castle, the village, the
## Hearth's chamber) are already instanced in the level scene and appear here only so that grass, trees and
## props know to keep off them; tests/test_sites.gd checks they agree with the scene. Every other site is
## built at run time by Settlements. Pure and static: no nodes, so the test runner can use it directly.

const DIR := "res://data/sites/"
const AREAS_DIR := "res://data/areas/"
## Terrain.lod0_spacing's default: the grid a hole snaps to.
const HOLE_SPACING := 2.0


static func load_area(area: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for path: String in files_for(area):
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if not data is Dictionary:
			push_error("SiteRegistry: %s is not a JSON object" % path)
			continue
		for raw: Variant in (data as Dictionary).get("sites", []):
			if raw is Dictionary:
				var site: Dictionary = (raw as Dictionary).duplicate()
				site["_file"] = path.get_file()
				out.append(site)
	return out


## The area's own file first, then its extra files in name order, so load order never depends on the disk.
static func files_for(area: String) -> Array[String]:
	var out: Array[String] = []
	var main: String = DIR + area + ".json"
	if FileAccess.file_exists(main):
		out.append(main)
	var extra: Array[String] = []
	for name: String in DirAccess.get_files_at(DIR):
		if name.begins_with(area + "_") and name.ends_with(".json"):
			extra.append(DIR + name)
	extra.sort()
	out.append_array(extra)
	return out


static func at_of(site: Dictionary) -> Vector2:
	var a: Array = site.get("at", [0.0, 0.0])
	return Vector2(float(a[0]), float(a[1])) if a.size() >= 2 else Vector2.ZERO


static func yaw_of(site: Dictionary) -> float:
	var v: Variant = site.get("yaw", 0.0)
	return float(v) if v is float or v is int else 0.0


## The site's ground OBBs in world XZ.
static func world_obbs(site: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var layout: Dictionary = StructureBuilder.load_layout(str(site.get("layout", "")))
	for obb: Dictionary in Footprint.layout_obbs(layout):
		out.append(Footprint.transform_obb(obb, at_of(site), yaw_of(site)))
	return out


## World transform for a site whose floor sits at `ground_y`.
static func site_transform(site: Dictionary, ground_y: float) -> Transform3D:
	var at: Vector2 = at_of(site)
	return Transform3D(Basis(Vector3.UP, deg_to_rad(yaw_of(site))), Vector3(at.x, ground_y, at.y))


## One mask for the whole area: every site's ground pieces grown by `margin` (so blades do not lean through
## wall feet), plus every terrain hole at its snapped size, because there is no ground there for anything to
## stand on -- whatever floors a hole is the floor, and grass on it would hang in the air over the shaft.
static func keep_out(area: String, margin: float = 0.3) -> KeepOutMask:
	var mask := KeepOutMask.new()
	for site: Dictionary in load_area(area):
		for obb: Dictionary in world_obbs(site):
			mask.add_obb(obb, margin)
	for hole: Rect2 in snapped_holes(area):
		mask.add_obb(Footprint.rect_obb(hole), margin)
	return mask


static func snapped_holes(area: String) -> Array[Rect2]:
	var out: Array[Rect2] = []
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(AREAS_DIR + area + ".json"))
	if not data is Dictionary:
		return out
	var size: float = float((data as Dictionary).get("size", 1024.0))
	for raw: Variant in (data as Dictionary).get("holes", []):
		if raw is Array and (raw as Array).size() >= 4:
			var r: Array = raw
			var rect := Rect2(float(r[0]), float(r[1]), float(r[2]), float(r[3])).abs()
			if rect.size.x > 0.0 and rect.size.y > 0.0:
				out.append(Footprint.snap_hole(rect, size, HOLE_SPACING))
	return out
