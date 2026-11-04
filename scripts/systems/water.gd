class_name Water
extends Node3D
## Rivers and standing water (W14). There was no water anywhere in this game until now -- the Mirror Pond
## is a hole in the ground with a name. This builds a surface from a polyline: a ribbon of quads at a fixed
## height, wearing a shader that moves, plus a body of killing water underneath it.
##
## The owner's rule for the river: "in the river you are not allowed to go for now. If you go or cross the
## river with the character, the character will die." So the surface is scenery and the volume is the rule.
## A player who touches the volume drowns -- not instantly, which would feel like a bug, but over
## `drown_seconds`, which reads as the current taking them.
##
## Shapes come from data (data/areas/*.json "waters"), so a new river is a row in a file and the channel it
## runs in is a cut in the same file. Nothing here knows where any particular river is.
##
## A water is {name, points: [[x, z, level], ...], half_width, spread, depth} (W21). `half_width` is the
## channel: the part dug to full depth, the width the map draws. `spread` is how much further the SHEET runs
## out on either side, into the bank, the way the Mirror Pond's disc runs under its shore. The bank is a
## long slope, so the ground meets the surface somewhere out in it; a sheet only as wide as the channel left
## ten to twenty metres of bare bed between its edge and the real waterline, and the owner filmed "the water
## is not rendering". A reach that shares its points with a longer water (the Wide Water) is folded into it,
## so the river is one sheet with a width at every point, and two sheets never fight over the same pixels.

const WATER_LAYER := 8
const DROWN_GROUP := &"player"
## The water only takes you once it is this deep at your feet. The sheet runs over the shallows of the
## bank now, and a kill box reaching up to the surface would drown you on ground an ankle under it.
const WADE_DEPTH := 0.5
## Two points closer than this are the same point, which is how a reach is known to belong to a river.
const SAME_POINT := 1.0

## Metres between the points the ribbon is built from. Smaller follows a bend more closely and costs more.
@export var segment: float = 6.0
@export var drown_seconds: float = 1.6
@export var drown_damage_per_sec: float = 90.0
## Built by the level, which knows the area file; empty means this node does nothing.
@export var auto_build: bool = false
@export_file("*.json") var area_path: String = "res://data/areas/vale.json"

var _surfaces: int = 0
var _volumes: int = 0
var _drowning: Array[Node] = []
var _material: Material = null


func _ready() -> void:
	if auto_build:
		rebuild(waters_of(area_path))


## The "waters" list of an area file, or nothing when it names none.
static func waters_of(path: String) -> Array:
	if path == "" or not FileAccess.file_exists(path):
		return []
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not data is Dictionary:
		return []
	var waters: Variant = (data as Dictionary).get("waters", [])
	return waters if waters is Array else []


## One mesh and one kill volume per water, reaches folded into the water that owns their points; both are
## rebuilt from scratch, so calling this twice is safe.
func rebuild(waters: Array) -> void:
	for child: Node in get_children():
		remove_child(child)
		child.queue_free()
	_surfaces = 0
	_volumes = 0
	for entry: Dictionary in fold_reaches(waters):
		_build_one(entry)
	set_physics_process(_volumes > 0)


## Empties every pool that was waiting on this flag: the surface goes and so does the drowning. The
## Mirror Pond is the one that matters -- the player drains it to reach the Hearth, and water still lying
## over the stair afterwards would be a lie and a death trap.
func drain(flag: StringName) -> int:
	var emptied: int = 0
	for child: Node in get_children():
		if str(child.get_meta(&"drains_with", "")) != String(flag):
			continue
		if child is Area3D:
			(child as Area3D).monitoring = false
			_drowning.erase(child)
		if child is Node3D:
			(child as Node3D).visible = false
		emptied += 1
	_drowning = _drowning.filter(func(n: Node) -> bool: return is_instance_valid(n))
	return emptied


func stats() -> Dictionary:
	return {"surfaces": _surfaces, "volumes": _volumes, "drowning": _drowning.size()}


static func points_of(entry: Dictionary) -> PackedVector2Array:
	var out := PackedVector2Array()
	for raw: Variant in entry.get("points", []):
		if raw is Array and (raw as Array).size() >= 2:
			out.append(Vector2(float((raw as Array)[0]), float((raw as Array)[1])))
	return out


## The level each point carries, NAN where it carries none.
static func levels_of(entry: Dictionary) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for raw: Variant in entry.get("points", []):
		if raw is Array and (raw as Array).size() >= 2:
			out.append(float((raw as Array)[2]) if (raw as Array).size() >= 3 else NAN)
	return out


## How far the sheet reaches from the line: the channel plus the spread over the bank.
static func sheet_half(entry: Dictionary) -> float:
	return maxf(0.5, float(entry.get("half_width", 8.0))) + maxf(0.0, float(entry.get("spread", 0.0)))


## Every water with its sheet half width at every point under "_halves" (and its points under "_points").
## A reach -- a water whose every point is a point of a longer one -- is folded into that water: its width
## wins at the points it shares and so does its depth, and it builds nothing of its own.
static func fold_reaches(waters: Array) -> Array[Dictionary]:
	var all: Array[Dictionary] = []
	for raw: Variant in waters:
		if raw is Dictionary:
			var entry: Dictionary = (raw as Dictionary).duplicate()
			entry["_points"] = points_of(entry)
			var halves := PackedFloat32Array()
			halves.resize((entry["_points"] as PackedVector2Array).size())
			halves.fill(sheet_half(entry))
			entry["_halves"] = halves
			all.append(entry)
	var out: Array[Dictionary] = []
	for entry: Dictionary in all:
		var spine: Dictionary = _spine_of(entry, all)
		if spine.is_empty():
			out.append(entry)
			continue
		var spine_points: PackedVector2Array = spine["_points"]
		var halves: PackedFloat32Array = (spine["_halves"] as PackedFloat32Array).duplicate()
		for p: Vector2 in (entry["_points"] as PackedVector2Array):
			for i: int in spine_points.size():
				if p.distance_to(spine_points[i]) < SAME_POINT:
					halves[i] = maxf(halves[i], sheet_half(entry))
		spine["_halves"] = halves
		spine["depth"] = maxf(float(spine.get("depth", 6.0)), float(entry.get("depth", 6.0)))
	return out


## The longest other water that has every one of this one's points, or nothing.
static func _spine_of(entry: Dictionary, all: Array[Dictionary]) -> Dictionary:
	var mine: PackedVector2Array = entry["_points"]
	var best: Dictionary = {}
	if mine.size() < 2:
		return best
	for other: Dictionary in all:
		var theirs: PackedVector2Array = other["_points"]
		if is_same(other, entry) or theirs.size() <= mine.size():
			continue
		if not best.is_empty() and theirs.size() <= (best["_points"] as PackedVector2Array).size():
			continue
		var covered: bool = true
		for p: Vector2 in mine:
			var found: bool = false
			for q: Vector2 in theirs:
				found = found or p.distance_to(q) < SAME_POINT
			covered = covered and found
		if covered:
			best = other
	return best


## Points every `segment` metres along the polyline, so a ribbon follows a bend instead of cutting it.
static func walk(points: PackedVector2Array, step: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	if points.size() < 2:
		return out
	out.append(points[0])
	for i: int in range(points.size() - 1):
		var a: Vector2 = points[i]
		var b: Vector2 = points[i + 1]
		var length: float = a.distance_to(b)
		var n: int = maxi(1, int(length / maxf(0.5, step)))
		for k: int in range(1, n + 1):
			out.append(a.lerp(b, float(k) / float(n)))
	return out


## A round pool: a fan of triangles about a centre. Used for the Mirror Pond, which a ribbon cannot be.
static func disc(centre: Vector2, radius: float, level: float, sides: int = 48) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	if radius <= 0.0:
		return mesh
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	verts.append(Vector3(centre.x, level, centre.y))
	normals.append(Vector3.UP)
	uvs.append(Vector2(0.5, 0.5))
	for i: int in range(sides + 1):
		var a: float = TAU * float(i) / float(sides)
		verts.append(Vector3(centre.x + cos(a) * radius, level, centre.y + sin(a) * radius))
		normals.append(Vector3.UP)
		uvs.append(Vector2(0.5 + cos(a) * 0.5, 0.5 + sin(a) * 0.5))
		if i > 0:
			indices.append_array(PackedInt32Array([0, i, i + 1]))
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## A per-point value (the level, the sheet's half width) at each walked point: the authored values of the
## nearest segment, blended by how far along it the point lies -- the same arithmetic as
## Heightfield._nearest_on, so the sheet and the bed it was cut for are the same numbers to the millimetre.
## (Blending between the two authored neighbours of the nearest POINT, as this once did, put a small step in
## the surface wherever the nearest point changed.) NAN values fall back to `fallback`.
static func _levels_along(authored: PackedVector2Array, levels: PackedFloat32Array,
		walked: PackedVector2Array, fallback: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var usable: bool = false
	for v: float in levels:
		usable = usable or not is_nan(v)
	for w: Vector2 in walked:
		if not usable or authored.is_empty() or levels.size() < authored.size():
			out.append(fallback)
			continue
		var value: float = levels[0] if not is_nan(levels[0]) else fallback
		var best: float = INF
		for i: int in range(authored.size() - 1):
			var ab: Vector2 = authored[i + 1] - authored[i]
			var span: float = ab.length_squared()
			var f: float = 0.0 if span < 0.000001 else clampf((w - authored[i]).dot(ab) / span, 0.0, 1.0)
			var d: float = w.distance_squared_to(authored[i] + ab * f)
			if d < best:
				best = d
				var la: float = levels[i] if not is_nan(levels[i]) else fallback
				var lb: float = levels[i + 1] if not is_nan(levels[i + 1]) else fallback
				value = lerpf(la, lb, f)
		out.append(value)
	return out


## The ribbon itself: two vertices per point, offset either side of the line by `half` (or by that point's
## own entry in `halves`, for a river that widens).
static func ribbon(points: PackedVector2Array, half: float, level: float,
		levels: PackedFloat32Array = PackedFloat32Array(), halves: PackedFloat32Array = PackedFloat32Array()) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	if points.size() < 2:
		return mesh
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	var run: float = 0.0
	for i: int in range(points.size()):
		var here: Vector2 = points[i]
		var ahead: Vector2 = points[mini(i + 1, points.size() - 1)]
		var behind: Vector2 = points[maxi(i - 1, 0)]
		var dir: Vector2 = (ahead - behind)
		if dir.length_squared() < 0.0001:
			dir = Vector2.RIGHT
		var side: Vector2 = dir.normalized().orthogonal() * (halves[i] if i < halves.size() else half)
		if i > 0:
			run += here.distance_to(behind)
		var y: float = levels[i] if i < levels.size() else level
		verts.append(Vector3(here.x - side.x, y, here.y - side.y))
		verts.append(Vector3(here.x + side.x, y, here.y + side.y))
		normals.append(Vector3.UP)
		normals.append(Vector3.UP)
		uvs.append(Vector2(0.0, run * 0.08))
		uvs.append(Vector2(1.0, run * 0.08))
		if i < points.size() - 1:
			var a: int = i * 2
			indices.append_array(PackedInt32Array([a, a + 1, a + 2, a + 1, a + 3, a + 2]))
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## `entry` is a water as fold_reaches hands it out, "_points" and "_halves" filled in.
func _build_one(entry: Dictionary) -> void:
	var points: PackedVector2Array = entry.get("_points", points_of(entry))
	var levels: PackedFloat32Array = levels_of(entry)
	var radius: float = float(entry.get("radius", 0.0))
	# A pool is one centre and a radius; a river is a line. Requiring two points refused every pool.
	if points.is_empty() or (points.size() < 2 and radius <= 0.0):
		return
	var half: float = sheet_half(entry)
	var halves: PackedFloat32Array = entry.get("_halves", PackedFloat32Array())
	var level: float = float(entry.get("level", 0.0))
	var walked: PackedVector2Array = walk(points, segment)
	var surface := MeshInstance3D.new()
	surface.name = "Water_" + str(entry.get("name", _surfaces))
	var walked_levels: PackedFloat32Array = _levels_along(points, levels, walked, level)
	var walked_halves: PackedFloat32Array = _levels_along(points, halves, walked, half)
	surface.mesh = disc(points[0], radius, level) if radius > 0.0 else ribbon(walked, half, level, walked_levels, walked_halves)
	surface.material_override = _water_material()
	surface.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(surface)
	_surfaces += 1
	# The rule, under the scenery: one box per step, as wide as the sheet, its top WADE_DEPTH under the
	# surface and deep enough that the bed is inside it. Ground above that top is a bank, not a river.
	var body := Area3D.new()
	body.name = "Drown_" + str(entry.get("name", _volumes))
	body.collision_layer = 0
	body.collision_mask = 1 | 2
	body.monitoring = true
	var depth: float = maxf(2.0, float(entry.get("depth", 6.0)))
	if radius > 0.0:
		var pool := CollisionShape3D.new()
		var cyl := CylinderShape3D.new()
		cyl.radius = radius
		cyl.height = depth
		pool.shape = cyl
		pool.transform = Transform3D(Basis.IDENTITY, Vector3(points[0].x, level - WADE_DEPTH - depth * 0.5, points[0].y))
		body.add_child(pool)
		walked = PackedVector2Array()
	for i: int in range(walked.size() - 1):
		var a: Vector2 = walked[i]
		var b: Vector2 = walked[i + 1]
		var mid: Vector2 = (a + b) * 0.5
		var span: float = a.distance_to(b)
		if span < 0.05:
			continue
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		var width: float = half * 2.0
		if i + 1 < walked_halves.size():
			width = walked_halves[i] + walked_halves[i + 1]
		box.size = Vector3(width, depth, span + 0.4)
		shape.shape = box
		var yaw: float = atan2(b.x - a.x, b.y - a.y)
		var seg_level: float = level
		if i + 1 < walked_levels.size():
			seg_level = (walked_levels[i] + walked_levels[i + 1]) * 0.5
		shape.transform = Transform3D(Basis(Vector3.UP, yaw),
				Vector3(mid.x, seg_level - WADE_DEPTH - depth * 0.5, mid.y))
		body.add_child(shape)
	var drains: String = str(entry.get("drains_with", ""))
	if drains != "":
		surface.set_meta(&"drains_with", drains)
		body.set_meta(&"drains_with", drains)
	body.body_entered.connect(_on_entered)
	body.body_exited.connect(_on_exited)
	add_child(body)
	_volumes += 1


func _physics_process(delta: float) -> void:
	if _drowning.is_empty():
		return
	for who: Node in _drowning:
		if is_instance_valid(who) and who.has_method(&"take_damage"):
			who.take_damage(drown_damage_per_sec * delta, self)


func _on_entered(body: Node3D) -> void:
	if body.is_in_group(DROWN_GROUP) and not _drowning.has(body):
		_drowning.append(body)


func _on_exited(body: Node3D) -> void:
	_drowning.erase(body)


## Deep green glass that moves. No texture: the ripple is two scrolling noise fields in the shader, which
## costs nothing to ship and cannot be a missing asset (D-005).
func _water_material() -> Material:
	if _material != null:
		return _material
	var shader: Shader = load("res://scripts/systems/water.gdshader") as Shader
	if shader == null:
		var fallback := StandardMaterial3D.new()
		fallback.albedo_color = Color(0.16, 0.27, 0.29, 0.82)
		fallback.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		fallback.roughness = 0.12
		fallback.metallic = 0.25
		_material = fallback
		return _material
	var m := ShaderMaterial.new()
	m.shader = shader
	_material = m
	return _material
