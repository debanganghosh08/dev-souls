class_name Terrain
extends Node3D
## Turns a Heightfield into chunks you can see and walk on. Every chunk gets one MeshInstance3D per LOD
## level with visibility_range_begin/end set, so Godot picks the level by camera distance per chunk with
## no per-frame script work (4.7 has no runtime mesh-LOD API for generated meshes; rebuilding meshes on
## distance thresholds would cost CPU every time the player walks). Collision exists only for chunks
## within collision_radius of the player: a 1 km^2 trimesh everywhere is memory and Jolt build time for
## ground nobody stands on. Chunks are built across frames inside build_budget_ms so a full area never
## hangs one frame; begin_build() primes the chunks around the spawn synchronously so the first physics
## tick has ground under the player.

signal build_finished()

const WORLD_LAYER := 1
const NO_CHUNK := Vector2i(1 << 30, 1 << 30)

@export_file("*.json") var data_path: String = "res://data/areas/vale.json"
@export var chunk_size: float = 64.0
## Vertex spacing at LOD0 in metres; coarser levels take every 2nd, 4th, 8th vertex of the same grid.
@export var lod0_spacing: float = 2.0
## Camera distance at which LOD0, LOD1, LOD2 end; the last level runs to infinity.
@export var lod_distances: PackedFloat32Array = PackedFloat32Array([128.0, 288.0, 576.0])
@export var lod_fade_margin: float = 12.0
@export var skirt_depth: float = 6.0
## Metres from the player within which chunks carry a ConcavePolygonShape3D. LIMITATION: anything beyond
## it (far creatures, thrown objects) falls through the ground until the player comes near.
@export var collision_radius: float = 110.0
@export var collision_refresh_sec: float = 0.4
@export var build_budget_ms: float = 6.0
@export var auto_build: bool = true

var heightfield: Heightfield
var _holes: Array[Rect2] = []

var _chunks: Dictionary = {}
var _queue: Array[Vector2i] = []
var _per_side: int = 0
var _cells: int = 0
var _build_start_ms: int = 0
var _build_ms: int = -1
var _started: bool = false
var _finished: bool = false
var _player: Node3D
var _refresh_timer: float = 0.0
var _collision_centre: Vector3 = Vector3.ZERO
var _last_player_chunk: Vector2i = NO_CHUNK
var _material: ShaderMaterial
var _collision_chunks: int = 0


func _ready() -> void:
	var data: Dictionary = load_data(data_path)
	heightfield = Heightfield.from_dict(data)
	_holes = heightfield.holes()
	_material = TerrainMaterial.get_material(data.get("material", {}), heightfield.water_level())
	_per_side = maxi(1, roundi(heightfield.size() / maxf(1.0, chunk_size)))
	_cells = maxi(1, roundi(chunk_size / maxf(0.1, lod0_spacing)))
	if auto_build:
		begin_build(Vector3.ZERO)


static func load_data(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_error("Terrain: %s missing" % path)
		return {}
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(path)) != OK or not json.data is Dictionary:
		push_error("Terrain: %s is not a JSON object" % path)
		return {}
	return json.data


## Queues every chunk nearest-first from `centre` and builds the ones inside collision_radius right now.
func begin_build(centre: Vector3) -> void:
	if _started:
		return
	_started = true
	_build_start_ms = Time.get_ticks_msec()
	_collision_centre = centre
	for j: int in _per_side:
		for i: int in _per_side:
			_queue.append(Vector2i(i, j))
	_queue.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return _chunk_centre(a).distance_squared_to(centre) < _chunk_centre(b).distance_squared_to(centre))
	while not _queue.is_empty() and _chunk_centre(_queue[0]).distance_to(centre) <= collision_radius + chunk_size:
		_build_chunk(_queue.pop_front())
	_check_finished()


func _process(delta: float) -> void:
	if not _queue.is_empty():
		var deadline: int = Time.get_ticks_usec() + int(build_budget_ms * 1000.0)
		_build_chunk(_queue.pop_front())
		while not _queue.is_empty() and Time.get_ticks_usec() < deadline:
			_build_chunk(_queue.pop_front())
		_check_finished()
	_refresh_timer -= delta
	if _refresh_timer > 0.0:
		return
	_refresh_timer = collision_refresh_sec
	if _player == null:
		_player = get_tree().get_first_node_in_group(&"player") as Node3D
	if _player == null:
		return
	var key: Vector2i = _chunk_key(_player.global_position)
	if key != _last_player_chunk:
		_last_player_chunk = key
		_collision_centre = _player.global_position
		_update_collision()


func _check_finished() -> void:
	if _finished or not _queue.is_empty():
		return
	_finished = true
	_build_ms = Time.get_ticks_msec() - _build_start_ms
	build_finished.emit()


func _chunk_origin(key: Vector2i) -> Vector2:
	var half: float = heightfield.size() * 0.5
	return Vector2(float(key.x) * chunk_size - half, float(key.y) * chunk_size - half)


func _chunk_centre(key: Vector2i) -> Vector3:
	var o: Vector2 = _chunk_origin(key) + Vector2.ONE * chunk_size * 0.5
	return Vector3(o.x, 0.0, o.y)


func _chunk_key(world: Vector3) -> Vector2i:
	var half: float = heightfield.size() * 0.5
	return Vector2i(floori((world.x + half) / chunk_size), floori((world.z + half) / chunk_size))


func _build_chunk(key: Vector2i) -> void:
	var origin: Vector2 = _chunk_origin(key)
	var grid: PackedFloat32Array = TerrainMesh.sample_grid(heightfield, origin, _cells, lod0_spacing)
	var root := Node3D.new()
	root.name = "Chunk_%d_%d" % [key.x, key.y]
	root.position = Vector3(origin.x, 0.0, origin.y)
	add_child(root)
	var levels: int = lod_distances.size() + 1
	var uv_origin: Vector2 = origin + Vector2.ONE * heightfield.size() * 0.5
	var uv_scale: float = 1.0 / maxf(1.0, heightfield.size())
	for level: int in levels:
		var step: int = 1 << level
		if _cells / step < 1:
			break
		var mesh: ArrayMesh = TerrainMesh.build_lod(grid, _cells, step, lod0_spacing, skirt_depth, uv_origin,
				uv_scale, origin, _holes)
		mesh.surface_set_material(0, _material)
		var mi := MeshInstance3D.new()
		mi.name = "LOD%d" % level
		mi.mesh = mesh
		mi.visibility_range_begin = 0.0 if level == 0 else lod_distances[level - 1]
		mi.visibility_range_end = 0.0 if level == levels - 1 else lod_distances[level]
		mi.visibility_range_begin_margin = 0.0 if level == 0 else lod_fade_margin
		mi.visibility_range_end_margin = 0.0 if level == levels - 1 else lod_fade_margin
		mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		root.add_child(mi)
	_chunks[key] = {"root": root, "grid": grid, "body": null}
	if _chunk_centre(key).distance_to(_collision_centre) <= collision_radius + chunk_size * 0.5:
		_add_collision(key)


func _update_collision() -> void:
	for key: Vector2i in _chunks:
		var near: bool = _chunk_centre(key).distance_to(_collision_centre) <= collision_radius + chunk_size * 0.5
		var chunk: Dictionary = _chunks[key]
		if near and chunk["body"] == null:
			_add_collision(key)
		elif not near and chunk["body"] != null:
			(chunk["body"] as Node).queue_free()
			chunk["body"] = null
			_collision_chunks -= 1


func _add_collision(key: Vector2i) -> void:
	var chunk: Dictionary = _chunks[key]
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(TerrainMesh.collision_faces(chunk["grid"], _cells, lod0_spacing,
			_chunk_origin(key), _holes))
	var body := StaticBody3D.new()
	body.name = "Collision"
	body.collision_layer = WORLD_LAYER
	body.collision_mask = 0
	var col := CollisionShape3D.new()
	col.shape = shape
	body.add_child(col)
	(chunk["root"] as Node3D).add_child(body)
	chunk["body"] = body
	_collision_chunks += 1


# --- queries ---------------------------------------------------------------------------------------------

func height_at(x: float, z: float) -> float:
	return heightfield.height_at(x, z)


func chunk_count() -> int:
	return _per_side * _per_side


func built_count() -> int:
	return _chunks.size()


func is_built() -> bool:
	return _finished


func collision_chunk_count() -> int:
	return _collision_chunks


func lod_levels() -> int:
	return lod_distances.size() + 1


## Geometric normal of the first LOD0 triangle of any built chunk: probes assert its y is positive.
func first_face_normal() -> Vector3:
	for key: Vector2i in _chunks:
		var mi: MeshInstance3D = (_chunks[key]["root"] as Node3D).get_node_or_null(^"LOD0") as MeshInstance3D
		if mi != null:
			return TerrainMesh.first_face_normal(mi.mesh as ArrayMesh)
	return Vector3.ZERO


func stats() -> Dictionary:
	return {"chunks": chunk_count(), "built": _chunks.size(), "finished": _finished, "build_ms": _build_ms,
		"collision_chunks": _collision_chunks, "lod_levels": lod_levels(), "chunk_size": chunk_size,
		"lod0_vertices": (_cells + 1) * (_cells + 1) * _chunks.size()}
