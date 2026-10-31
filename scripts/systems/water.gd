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
## runs in is a negative crest in the same file. Nothing here knows where any particular river is.

const WATER_LAYER := 8
const DROWN_GROUP := &"player"

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


## `waters` is a list of {name, points: [[x, z], ...], level, half_width}. One mesh and one kill volume per
## entry; both are rebuilt from scratch, so calling this twice is safe.
func rebuild(waters: Array) -> void:
	for child: Node in get_children():
		remove_child(child)
		child.queue_free()
	_surfaces = 0
	_volumes = 0
	for raw: Variant in waters:
		if raw is Dictionary:
			_build_one(raw)
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


## The ribbon itself: two vertices per point, offset either side of the line by `half`.
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


## The level at each walked point, interpolated from the levels the authored points carried. A river whose
## surface does not follow its bed disappears wherever the land rises over it.
static func _levels_along(authored: PackedVector2Array, levels: PackedFloat32Array,
		walked: PackedVector2Array, fallback: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var usable: bool = false
	for v: float in levels:
		usable = usable or not is_nan(v)
	for w: Vector2 in walked:
		if not usable:
			out.append(fallback)
			continue
		# Nearest two authored points, weighted by how far between them this one sits.
		var best_i: int = 0
		var best_d: float = INF
		for i: int in range(authored.size()):
			var d: float = w.distance_to(authored[i])
			if d < best_d:
				best_d = d
				best_i = i
		var a_i: int = maxi(0, best_i - 1)
		var b_i: int = mini(authored.size() - 1, best_i + 1)
		var la: float = levels[a_i] if not is_nan(levels[a_i]) else fallback
		var lb: float = levels[b_i] if not is_nan(levels[b_i]) else fallback
		var span: float = authored[a_i].distance_to(authored[b_i])
		var t: float = 0.5 if span < 0.01 else clampf(authored[a_i].distance_to(w) / span, 0.0, 1.0)
		out.append(lerpf(la, lb, t))
	return out


static func ribbon(points: PackedVector2Array, half: float, level: float,
		levels: PackedFloat32Array = PackedFloat32Array()) -> ArrayMesh:
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
		var side: Vector2 = dir.normalized().orthogonal() * half
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


func _build_one(entry: Dictionary) -> void:
	var points := PackedVector2Array()
	var levels := PackedFloat32Array()
	for raw: Variant in entry.get("points", []):
		if raw is Array and (raw as Array).size() >= 2:
			var p: Array = raw
			points.append(Vector2(float(p[0]), float(p[1])))
			levels.append(float(p[2]) if (p as Array).size() >= 3 else NAN)
	var radius: float = float(entry.get("radius", 0.0))
	# A pool is one centre and a radius; a river is a line. Requiring two points refused every pool.
	if points.is_empty() or (points.size() < 2 and radius <= 0.0):
		return
	var half: float = maxf(0.5, float(entry.get("half_width", 8.0)))
	var level: float = float(entry.get("level", 0.0))
	var walked: PackedVector2Array = walk(points, segment)
	var surface := MeshInstance3D.new()
	surface.name = "Water_" + str(entry.get("name", _surfaces))
	var walked_levels: PackedFloat32Array = _levels_along(points, levels, walked, level)
	surface.mesh = disc(points[0], radius, level) if radius > 0.0 else ribbon(walked, half, level, walked_levels)
	surface.material_override = _water_material()
	surface.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(surface)
	_surfaces += 1
	# The rule, under the scenery: one box per step, deep enough that the bed is inside it.
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
		pool.transform = Transform3D(Basis.IDENTITY, Vector3(points[0].x, level - depth * 0.5 + 0.4, points[0].y))
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
		box.size = Vector3(half * 2.0, depth, span + 0.4)
		shape.shape = box
		var yaw: float = atan2(b.x - a.x, b.y - a.y)
		var seg_level: float = level
		if i < walked_levels.size():
			seg_level = (walked_levels[i] + walked_levels[mini(i + 1, walked_levels.size() - 1)]) * 0.5
		shape.transform = Transform3D(Basis(Vector3.UP, yaw),
				Vector3(mid.x, seg_level - depth * 0.5 + 0.4, mid.y))
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
