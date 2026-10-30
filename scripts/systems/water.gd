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
static func ribbon(points: PackedVector2Array, half: float, level: float) -> ArrayMesh:
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
		verts.append(Vector3(here.x - side.x, level, here.y - side.y))
		verts.append(Vector3(here.x + side.x, level, here.y + side.y))
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
	for raw: Variant in entry.get("points", []):
		if raw is Array and (raw as Array).size() >= 2:
			var p: Array = raw
			points.append(Vector2(float(p[0]), float(p[1])))
	if points.size() < 2:
		return
	var half: float = maxf(0.5, float(entry.get("half_width", 8.0)))
	var level: float = float(entry.get("level", 0.0))
	var walked: PackedVector2Array = walk(points, segment)
	var surface := MeshInstance3D.new()
	surface.name = "Water_" + str(entry.get("name", _surfaces))
	surface.mesh = ribbon(walked, half, level)
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
		shape.transform = Transform3D(Basis(Vector3.UP, yaw), Vector3(mid.x, level - depth * 0.5 + 0.4, mid.y))
		body.add_child(shape)
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
