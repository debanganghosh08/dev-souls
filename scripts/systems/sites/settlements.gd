class_name Settlements
extends Node3D
## Builds every non-fixed site of an area from data/sites/: houses, sheds, shrines, wells, carts. Each site
## is a StructureBuilder layout placed on the terrain, plus whatever interactables its entry lists. The same
## layout placed twenty times shares one set of meshes and collision shapes (StructureBuilder.share_pieces),
## which is the whole point of building a village from a handful of archetypes.
##
## Ground: a site's floor goes at the HIGHEST terrain point under its footprint by default, so no corner ever
## hangs over a gap; the layout is expected to carry a foundation that reaches down into the low side. `ground`
## may instead be "min" or an absolute height, and `lift` adds to whichever is chosen.
##
## Props: {"scene": "res://scenes/props/chest.tscn", "at": [x, y, z], "yaw": deg, "set": {"prop": value}}.
## `at` is site-local, with y = 0 the site's floor. `set` assigns exported properties by name, so a new
## interactable needs no code here. Every interactable `id` must be unique in the area (test_sites.gd).

## Metres beyond which a site's meshes stop drawing. A house is a few metres across; at 300 m it is pixels.
@export var draw_distance: float = 320.0
@export var draw_fade: float = 30.0
@export var area: String = "vale"
## Ground sampling step under a footprint, in metres.
@export var sample_step: float = 1.0

var _sites: int = 0
var _props: int = 0
var _pieces: int = 0


func build(hf: Heightfield) -> void:
	for child: Node in get_children():
		remove_child(child)
		child.free()
	_sites = 0
	_props = 0
	_pieces = 0
	for site: Dictionary in SiteRegistry.load_area(area):
		if bool(site.get("fixed", false)):
			continue
		_spawn_site(site, hf)


func stats() -> Dictionary:
	return {"sites": _sites, "props": _props, "pieces": _pieces}


## (lowest, highest) terrain height under the site's ground footprint. A layout with no ground pieces is
## sampled at its origin alone.
static func ground_span(site: Dictionary, hf: Heightfield, step: float = 1.0) -> Vector2:
	var lo: float = INF
	var hi: float = -INF
	var obbs: Array[Dictionary] = SiteRegistry.world_obbs(site)
	if obbs.is_empty():
		var at: Vector2 = SiteRegistry.at_of(site)
		var h: float = hf.height_at(at.x, at.y)
		return Vector2(h, h)
	var s: float = maxf(0.25, step)
	for obb: Dictionary in obbs:
		var c: Vector2 = obb["centre"]
		var ux: Vector2 = obb["ux"]
		var uz: Vector2 = obb["uz"]
		var nx: int = maxi(1, ceili(float(obb["hx"]) * 2.0 / s))
		var nz: int = maxi(1, ceili(float(obb["hz"]) * 2.0 / s))
		for i: int in range(nx + 1):
			var a: float = -float(obb["hx"]) + float(obb["hx"]) * 2.0 * float(i) / float(nx)
			for j: int in range(nz + 1):
				var b: float = -float(obb["hz"]) + float(obb["hz"]) * 2.0 * float(j) / float(nz)
				var p: Vector2 = c + ux * a + uz * b
				var h: float = hf.height_at(p.x, p.y)
				lo = minf(lo, h)
				hi = maxf(hi, h)
	return Vector2(lo, hi)


static func ground_height(site: Dictionary, hf: Heightfield, step: float = 1.0) -> float:
	var lift: float = float(site.get("lift", 0.0)) if (site.get("lift", 0.0) is float or site.get("lift", 0.0) is int) else 0.0
	var mode: Variant = site.get("ground", "max")
	if mode is float or mode is int:
		return float(mode) + lift
	var span: Vector2 = ground_span(site, hf, step)
	return (span.x if str(mode) == "min" else span.y) + lift


func _spawn_site(site: Dictionary, hf: Heightfield) -> void:
	var root := Node3D.new()
	root.name = str(site.get("id", "site_%d" % _sites)).validate_node_name()
	root.transform = SiteRegistry.site_transform(site, ground_height(site, hf, sample_step))
	root.set_meta(&"site_id", str(site.get("id", "")))
	var builder := StructureBuilder.new()
	builder.name = "Builder"
	builder.layout_path = str(site.get("layout", ""))
	builder.share_pieces = true
	builder.build()
	root.add_child(builder)
	_pieces += int(builder.stats().get("pieces", 0))
	_limit_draw(builder)
	for raw: Variant in site.get("props", []):
		if raw is Dictionary:
			var prop: Node = spawn_prop(raw)
			if prop != null:
				root.add_child(prop)
				_props += 1
	add_child(root)
	_sites += 1


## Instances one prop entry. Public and static-free of the tree so a test can check the `set` coercion.
static func spawn_prop(entry: Dictionary) -> Node:
	var path: String = str(entry.get("scene", ""))
	if not ResourceLoader.exists(path):
		push_error("Settlements: prop scene %s missing" % path)
		return null
	var node: Node = (load(path) as PackedScene).instantiate()
	if node is Node3D:
		var a: Array = entry.get("at", [0.0, 0.0, 0.0])
		var yaw: float = float(entry.get("yaw", 0.0))
		(node as Node3D).transform = Transform3D(Basis(Vector3.UP, deg_to_rad(yaw)),
				Vector3(float(a[0]), float(a[1]), float(a[2])) if a.size() >= 3 else Vector3.ZERO)
	var values: Dictionary = entry.get("set", {})
	for key: Variant in values:
		set_coerced(node, str(key), values[key])
	return node


## JSON has no StringName, and an exported StringName or int assigned a String or a float would otherwise
## keep the wrong type silently. Coerce to whatever the property already holds.
static func set_coerced(node: Object, key: String, value: Variant) -> void:
	var current: Variant = node.get(key)
	match typeof(current):
		TYPE_STRING_NAME:
			node.set(key, StringName(str(value)))
		TYPE_INT:
			node.set(key, int(value))
		TYPE_FLOAT:
			node.set(key, float(value))
		TYPE_BOOL:
			node.set(key, bool(value))
		_:
			node.set(key, value)


func _limit_draw(node: Node) -> void:
	if node is GeometryInstance3D:
		var g: GeometryInstance3D = node
		g.visibility_range_end = draw_distance
		g.visibility_range_end_margin = draw_fade
		g.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	for child: Node in node.get_children():
		_limit_draw(child)
