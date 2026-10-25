extends Node3D
class_name LevelDressing
## Non-gameplay set dressing (rocks, logs, stumps, ferns, shrubs, crates) built from a JSON description in
## data/dressing/ so the level scene stays small and every placement is reviewable text. Repeated models go
## through MultiMesh, one per model per `chunk_size` cell, so distance culling and mesh LOD act on local
## groups instead of one level-wide bounding box. Only sets marked `collide` get a StaticBody3D; the JSON's
## keep_out rectangles fence random scatter off the probe routes, the props and the pit.
##
## Set keys: model (gltf/glb path) · mesh (one MeshInstance3D name: its glTF offset is dropped so the piece
## centres on the placement) or meshes (several names: their offsets are kept so a multi-part prop assembles)
## · y · scale [min, max] for scatter · place [{at: [x, z], yaw, scale}] · scatter [{zone: {min, max},
## count, min_gap}] · range_end · shadows · collide.

const WORLD_LAYER := 1
const DEFAULT_RANGE_END := 90.0
const COLLIDER_SHRINK := 0.85
const SCATTER_TRIES := 30

@export_file("*.json") var data_path: String = ""
@export var chunk_size: float = 24.0
## Off when a level sets height_sampler / placement_filter first and calls build() itself.
@export var auto_build: bool = true

## Optional world ground (x, z) -> y: a set's `y` then becomes an offset above the ground, not absolute.
var height_sampler: Callable = Callable()
## Optional (x, z) -> bool: scatter points failing it (water, cliffs) are dropped; `place` entries are kept.
var placement_filter: Callable = Callable()
## Optional world ground normal (x, z) -> Vector3. When valid, scattered props tilt `align` of the way toward
## it and sink `sink` metres (per set, else the file's align_default / sink_default), so nothing hangs off a
## slope by one edge. Flat levels without it (greybox) place exactly as before.
var normal_sampler: Callable = Callable()
var _align_default: float = 0.5
var _sink_default: float = 0.0

var _instances: int = 0
var _multimeshes: int = 0
var _colliders: int = 0
var _triangles: int = 0
var _origins: PackedVector3Array = PackedVector3Array()
var _mesh_cache: Dictionary = {}


func _ready() -> void:
	if data_path != "" and auto_build:
		build(load_data(data_path))


## instances placed · multimeshes (one draw each, before culling) · colliders · LOD0 triangles if all drew.
func stats() -> Dictionary:
	return {"instances": _instances, "multimeshes": _multimeshes, "colliders": _colliders, "triangles": _triangles}


## World origin of every placed instance, kept CPU-side: a headless (dummy) renderer discards MultiMesh
## buffers, so transforms cannot be read back from the MultiMesh there.
func origins() -> PackedVector3Array:
	return _origins


static func load_data(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_error("LevelDressing: %s missing" % path)
		return {}
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(path)) != OK or not json.data is Dictionary:
		push_error("LevelDressing: %s is not a JSON object" % path)
		return {}
	return json.data


## True when the XZ point lies inside a {"min": [x, z], "max": [x, z]} rectangle, edges inclusive.
static func in_rect(point: Vector3, rect: Dictionary) -> bool:
	var lo: Array = rect.get("min", [0, 0])
	var hi: Array = rect.get("max", [0, 0])
	return point.x >= float(lo[0]) and point.x <= float(hi[0]) \
		and point.z >= float(lo[1]) and point.z <= float(hi[1])


static func chunk_key(point: Vector3, size: float) -> Vector2i:
	var cell: float = maxf(size, 0.001)
	return Vector2i(floori(point.x / cell), floori(point.z / cell))


## Deterministic random XZ points inside `zone`, outside every keep_out rect and at least `min_gap` apart.
## A point that finds no room in SCATTER_TRIES is dropped, so a crowded zone yields fewer, never a hang.
static func scatter_points(zone: Dictionary, count: int, min_gap: float, keep_out: Array,
		rng: RandomNumberGenerator) -> Array[Vector3]:
	var out: Array[Vector3] = []
	var lo: Array = zone.get("min", [0, 0])
	var hi: Array = zone.get("max", [0, 0])
	for _i: int in count:
		for _attempt: int in SCATTER_TRIES:
			var p := Vector3(rng.randf_range(float(lo[0]), float(hi[0])), 0.0, rng.randf_range(float(lo[1]), float(hi[1])))
			if _blocked(p, keep_out) or _too_close(p, out, min_gap):
				continue
			out.append(p)
			break
	return out


func build(data: Dictionary) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(data.get("seed", 1))
	_align_default = float(data.get("align_default", 0.5))
	_sink_default = float(data.get("sink_default", 0.0))
	var keep_out: Array = data.get("keep_out", [])
	for set: Variant in data.get("sets", []):
		if set is Dictionary:
			_build_set(set, keep_out, rng)


func _build_set(set: Dictionary, keep_out: Array, rng: RandomNumberGenerator) -> void:
	var model: String = str(set.get("model", ""))
	var parts: Array[Dictionary] = []
	if set.has("meshes"):
		for mesh_name: Variant in set["meshes"]:
			var part: Dictionary = _mesh_for(model, str(mesh_name), true)
			if not part.is_empty():
				parts.append(part)
	else:
		var part: Dictionary = _mesh_for(model, str(set.get("mesh", "")), false)
		if not part.is_empty():
			parts.append(part)
	if parts.is_empty():
		return
	var transforms: Array[Transform3D] = _transforms_for(set, keep_out, rng)
	if transforms.is_empty():
		return
	var set_name: String = str(set.get("name", parts[0]["name"]))
	var range_end: float = float(set.get("range_end", DEFAULT_RANGE_END))
	var shadows: bool = bool(set.get("shadows", true))
	for part: Dictionary in parts:
		var local: Transform3D = part["local"]
		var chunks: Dictionary = {}
		for t: Transform3D in transforms:
			var key: Vector2i = chunk_key(t.origin, chunk_size)
			if not chunks.has(key):
				chunks[key] = [] as Array[Transform3D]
			(chunks[key] as Array[Transform3D]).append(t * local)
		for key: Vector2i in chunks:
			_add_multimesh("%s_%s_%d_%d" % [set_name, part["name"], key.x, key.y], part["mesh"], chunks[key], range_end, shadows)
		_triangles += int(part["triangles"]) * transforms.size()
	_instances += transforms.size()
	for t: Transform3D in transforms:
		_origins.append(t.origin)
	if bool(set.get("collide", false)):
		for t: Transform3D in transforms:
			_add_collider(set_name, t, parts[0]["aabb"], parts[0]["local"])


func _transforms_for(set: Dictionary, keep_out: Array, rng: RandomNumberGenerator) -> Array[Transform3D]:
	var out: Array[Transform3D] = []
	var y: float = float(set.get("y", 0.0))
	var scale_range: Array = set.get("scale", [1.0, 1.0])
	for placed: Variant in set.get("place", []):
		if placed is Dictionary:
			var at: Array = placed.get("at", [0, 0])
			out.append(_make_transform(GroundPlacement.ground(float(at[0]), float(at[1]), y, height_sampler), float(placed.get("yaw", 0.0)), float(placed.get("scale", 1.0))))
	var grounded: bool = normal_sampler.is_valid()
	var align: float = float(set.get("align", _align_default)) if grounded else 0.0
	var sink: float = float(set.get("sink", _sink_default)) if grounded else 0.0
	for zone: Variant in set.get("scatter", []):
		if zone is Dictionary:
			var points: Array[Vector3] = scatter_points(zone.get("zone", {}), int(zone.get("count", 0)), float(zone.get("min_gap", 0.0)), keep_out, rng)
			for p: Vector3 in points:
				var s: float = rng.randf_range(float(scale_range[0]), float(scale_range[1]))
				if placement_filter.is_valid() and not bool(placement_filter.call(p.x, p.z)):
					continue
				var n: Vector3 = normal_sampler.call(p.x, p.z) if grounded else Vector3.UP
				out.append(_make_transform(GroundPlacement.ground(p.x, p.z, y - sink * s, height_sampler), rng.randf_range(0.0, 360.0), s, n, align))
	return out


static func _make_transform(at: Vector3, yaw_deg: float, scale: float, normal: Vector3 = Vector3.UP, align: float = 0.0) -> Transform3D:
	return Transform3D(GroundPlacement.aligned_basis(normal, deg_to_rad(yaw_deg), align, scale), at)


func _add_multimesh(node_name: String, mesh: Mesh, transforms: Array[Transform3D], range_end: float, shadows: bool) -> void:
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = mesh
	multimesh.instance_count = transforms.size()
	for i: int in transforms.size():
		multimesh.set_instance_transform(i, transforms[i])
	var instance := MultiMeshInstance3D.new()
	instance.name = node_name
	instance.multimesh = multimesh
	instance.visibility_range_end = range_end
	instance.visibility_range_end_margin = range_end * 0.1
	instance.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(instance)
	_multimeshes += 1


func _add_collider(set_name: String, t: Transform3D, aabb: AABB, local: Transform3D) -> void:
	var body := StaticBody3D.new()
	body.name = "%s_collider_%d" % [set_name, _colliders]
	body.collision_layer = WORLD_LAYER
	body.collision_mask = 0
	var scale: Vector3 = t.basis.get_scale() * local.basis.get_scale()
	body.transform = Transform3D(t.basis.orthonormalized(), t.origin)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = aabb.size * scale * COLLIDER_SHRINK
	shape.shape = box
	shape.position = (local.origin + aabb.get_center() * local.basis.get_scale()) * t.basis.get_scale()
	body.add_child(shape)
	add_child(body)
	_colliders += 1


# Pulls one named MeshInstance3D out of an imported model scene. Cached per (model, mesh) so a set used by
# several entries instantiates the heavy scene once. `local` is the glTF node's own transform (scale always,
# offset only for multi-part props) so the piece lands where the placement says.
func _mesh_for(model: String, mesh_name: String, keep_offset: bool) -> Dictionary:
	var key: String = "%s::%s::%s" % [model, mesh_name, keep_offset]
	if _mesh_cache.has(key):
		return _mesh_cache[key]
	var packed: PackedScene = load(model) as PackedScene
	if packed == null:
		push_error("LevelDressing: cannot load model %s" % model)
		return {}
	var scene: Node = packed.instantiate()
	var found: MeshInstance3D = null
	if mesh_name == "":
		var all: Array[Node] = scene.find_children("*", "MeshInstance3D", true, false)
		found = all[0] as MeshInstance3D if not all.is_empty() else null
	else:
		found = scene.find_child(mesh_name, true, false) as MeshInstance3D
	if found == null or found.mesh == null:
		push_error("LevelDressing: no mesh '%s' in %s" % [mesh_name, model])
		scene.free()
		return {}
	var local: Transform3D = found.transform if keep_offset else Transform3D(found.transform.basis, Vector3.ZERO)
	var entry: Dictionary = {
		"name": found.name,
		"mesh": found.mesh,
		"local": local,
		"aabb": found.mesh.get_aabb(),
		"triangles": triangle_count(found.mesh),
	}
	scene.free()
	_mesh_cache[key] = entry
	return entry


static func triangle_count(mesh: Mesh) -> int:
	var total: int = 0
	for surface: int in mesh.get_surface_count():
		var arrays: Array = mesh.surface_get_arrays(surface)
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		if indices.size() > 0:
			total += indices.size() / 3
		else:
			total += (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
	return total


static func _blocked(p: Vector3, keep_out: Array) -> bool:
	for rect: Variant in keep_out:
		if rect is Dictionary and in_rect(p, rect):
			return true
	return false


static func _too_close(p: Vector3, others: Array[Vector3], gap: float) -> bool:
	if gap <= 0.0:
		return false
	for other: Vector3 in others:
		if Vector2(p.x - other.x, p.z - other.z).length_squared() < gap * gap:
			return true
	return false
