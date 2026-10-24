class_name Forest
extends Node3D
## Places a clustered conifer forest from TreeGen meshes. One mesh per archetype (not per tree), drawn
## through MultiMeshInstance3D nodes grouped into spatial chunks: per chunk and archetype one trunk
## multimesh, one full-detail card multimesh (near) and one reduced card multimesh (far). Per-instance
## scale and yaw hide the repetition. Everything is driven by one RNG seeded from seed_value, so a given
## seed always builds the same forest: save files only have to store the seed, and a bug report with a seed
## reproduces the exact layout the player saw.

const WORLD_LAYER := 1
const MIN_SPACING := 1.6
const PLACE_ATTEMPTS := 12

@export var archetype_mix: Dictionary = {"fir": 6.0, "pine": 3.0, "dead": 1.0}
@export var count: int = 200
@export var radius: float = 60.0
@export var clearing_radius: float = 8.0
@export var seed_value: int = 1
@export var lod1_distance: float = 45.0
@export var cull_distance: float = 140.0
## Only the collider_count trees nearest the origin get a StaticBody3D. LIMITATION: every other tree is
## walk-through until a streaming task gives colliders to whatever is near the player instead of the origin.
@export var collider_count: int = 40
## Edge length of the square chunks that visibility ranges (LOD and culling) are evaluated per.
@export var chunk_size: float = 40.0

var _layout: Dictionary = {}
var _stats: Dictionary = {}
var _built: Array[Node] = []


func _ready() -> void:
	rebuild()


func rebuild() -> void:
	for node: Node in _built:
		node.queue_free()
	_built.clear()
	_layout = plan_layout(count, radius, clearing_radius, seed_value, archetype_mix)
	_stats = {"per_archetype": {}, "trunk_vertices": 0, "card_vertices": 0, "card_vertices_lod1": 0,
		"multimeshes": 0, "colliders": 0}
	var positions: PackedVector3Array = _layout["positions"]
	var names: PackedStringArray = _layout["archetypes"]
	var yaws: PackedFloat32Array = _layout["yaws"]
	var scales: PackedFloat32Array = _layout["scales"]
	# Plain Arrays, not Packed*Arrays: a packed array read out of a Dictionary is a copy, so appends vanish.
	var by_archetype: Dictionary = {}
	for i: int in positions.size():
		if not by_archetype.has(names[i]):
			by_archetype[names[i]] = []
		(by_archetype[names[i]] as Array).append(i)
	var trees: Dictionary = {}
	for archetype: String in by_archetype.keys():
		var p: Dictionary = TreeGen.params_for(archetype)
		var mesh_seed: int = hash(archetype) ^ seed_value
		var lod0: Dictionary = TreeGen.build(p, mesh_seed)
		var lod1: Dictionary = TreeGen.build(TreeGen.lod_params(p, 1), mesh_seed)
		(lod0["trunk"] as ArrayMesh).surface_set_material(0, TreeMaterials.bark_for(archetype))
		for cards: ArrayMesh in [lod0["cards"], lod1["cards"]]:
			if cards.get_surface_count() > 0:
				cards.surface_set_material(0, TreeMaterials.cards_for(archetype))
		trees[archetype] = {"lod0": lod0, "lod1": lod1}
		var ids: Array = by_archetype[archetype]
		(_stats["per_archetype"] as Dictionary)[archetype] = ids.size()
		_stats["trunk_vertices"] += _vertex_count(lod0["trunk"]) * ids.size()
		_stats["card_vertices"] += _vertex_count(lod0["cards"]) * ids.size()
		_stats["card_vertices_lod1"] += _vertex_count(lod1["cards"]) * ids.size()
		_build_chunks(archetype, ids, positions, yaws, scales, lod0, lod1)
	_build_colliders(trees, positions, names, yaws, scales)


func tree_count() -> int:
	return (_layout.get("positions", PackedVector3Array()) as PackedVector3Array).size()


func stats() -> Dictionary:
	return _stats.duplicate(true)


func positions() -> PackedVector3Array:
	return _layout.get("positions", PackedVector3Array())


## Order-independent fingerprint of the placed layout, for reproducibility probes.
func layout_hash() -> int:
	return hash([_layout.get("positions", PackedVector3Array()), _layout.get("archetypes", PackedStringArray()),
		_layout.get("yaws", PackedFloat32Array()), _layout.get("scales", PackedFloat32Array())])


## Pure, scene-free placement so tests can check it directly. Trees gather around a handful of cluster
## centres with density falling off from each centre (a uniform scatter reads as wallpaper, clumps read as
## woodland), never inside clearing_radius of the origin and never on top of each other.
static func plan_layout(tree_count: int, forest_radius: float, clearing: float, seed_v: int, mix: Dictionary) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var n: int = maxi(0, tree_count)
	var outer: float = maxf(clearing + 1.0, forest_radius)
	var cluster_n: int = clampi(n / 25, 3, 12)
	var cluster_r: float = outer * 0.45
	var centres := PackedVector2Array()
	for c: int in cluster_n:
		var d: float = rng.randf_range(clearing + cluster_r * 0.3, outer - cluster_r * 0.3)
		centres.append(Vector2.from_angle(rng.randf_range(0.0, TAU)) * d)
	var weights: Array[float] = []
	var names: Array[String] = []
	for key: Variant in mix.keys():
		if float(mix[key]) > 0.0:
			names.append(str(key))
			weights.append(float(mix[key]))
	var positions := PackedVector3Array()
	var archetypes := PackedStringArray()
	var yaws := PackedFloat32Array()
	var scales := PackedFloat32Array()
	for i: int in n:
		var pos: Vector2 = Vector2.ZERO
		var ok: bool = false
		for attempt: int in PLACE_ATTEMPTS:
			var c: Vector2 = centres[rng.randi_range(0, cluster_n - 1)]
			var cand: Vector2 = c + Vector2.from_angle(rng.randf_range(0.0, TAU)) * cluster_r * pow(rng.randf(), 0.65)
			var d: float = cand.length()
			if d < clearing or d > outer or _too_close(cand, positions):
				continue
			pos = cand
			ok = true
			break
		if not ok:
			pos = Vector2.from_angle(rng.randf_range(0.0, TAU)) * rng.randf_range(clearing, outer)
		positions.append(Vector3(pos.x, 0.0, pos.y))
		archetypes.append(_weighted(names, weights, rng))
		yaws.append(rng.randf_range(0.0, TAU))
		scales.append(rng.randf_range(0.8, 1.25))
	return {"positions": positions, "archetypes": archetypes, "yaws": yaws, "scales": scales, "clusters": centres}


static func _too_close(cand: Vector2, placed: PackedVector3Array) -> bool:
	for q: Vector3 in placed:
		if Vector2(q.x, q.z).distance_squared_to(cand) < MIN_SPACING * MIN_SPACING:
			return true
	return false


static func _weighted(names: Array[String], weights: Array[float], rng: RandomNumberGenerator) -> String:
	if names.is_empty():
		return "fir"
	var total: float = 0.0
	for w: float in weights:
		total += w
	var roll: float = rng.randf() * total
	for i: int in names.size():
		roll -= weights[i]
		if roll <= 0.0:
			return names[i]
	return names[names.size() - 1]


func _build_chunks(archetype: String, ids: Array, positions: PackedVector3Array, yaws: PackedFloat32Array, scales: PackedFloat32Array, lod0: Dictionary, lod1: Dictionary) -> void:
	var chunks: Dictionary = {}
	var size: float = maxf(1.0, chunk_size)
	for i: int in ids:
		var key := Vector2i(int(floor(positions[i].x / size)), int(floor(positions[i].z / size)))
		if not chunks.has(key):
			chunks[key] = []
		(chunks[key] as Array).append(i)
	for key: Vector2i in chunks.keys():
		var members: Array = chunks[key]
		var xforms: Array[Transform3D] = []
		for i: int in members:
			xforms.append(Transform3D(Basis.from_euler(Vector3(0.0, yaws[i], 0.0)).scaled(Vector3.ONE * scales[i]), positions[i]))
		var tag: String = "%s_%d_%d" % [archetype, key.x, key.y]
		_add_multimesh("Trunk_" + tag, lod0["trunk"], xforms, 0.0, cull_distance)
		_add_multimesh("Cards0_" + tag, lod0["cards"], xforms, 0.0, lod1_distance)
		_add_multimesh("Cards1_" + tag, lod1["cards"], xforms, lod1_distance, cull_distance)


func _add_multimesh(node_name: String, mesh: ArrayMesh, xforms: Array[Transform3D], range_begin: float, range_end: float) -> void:
	if mesh.get_surface_count() == 0 or xforms.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for i: int in xforms.size():
		mm.set_instance_transform(i, xforms[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = node_name
	mmi.multimesh = mm
	mmi.visibility_range_begin = range_begin
	mmi.visibility_range_end = range_end
	add_child(mmi)
	_built.append(mmi)
	_stats["multimeshes"] += 1


## Cylinder StaticBody3D on the world layer for the collider_count trees nearest the origin only.
func _build_colliders(trees: Dictionary, positions: PackedVector3Array, names: PackedStringArray, yaws: PackedFloat32Array, scales: PackedFloat32Array) -> void:
	var order: Array[int] = []
	for i: int in positions.size():
		order.append(i)
	order.sort_custom(func(a: int, b: int) -> bool: return positions[a].length_squared() < positions[b].length_squared())
	var limit: int = mini(collider_count, order.size())
	for k: int in limit:
		var i: int = order[k]
		var tree: Dictionary = (trees[names[i]] as Dictionary)["lod0"]
		var shape := CylinderShape3D.new()
		shape.radius = float(tree["collider_radius"]) * scales[i]
		shape.height = float(tree["height"]) * scales[i]
		var body := StaticBody3D.new()
		body.name = "TreeBody_%d" % i
		body.collision_layer = WORLD_LAYER
		body.collision_mask = 0
		body.transform = Transform3D(Basis.from_euler(Vector3(0.0, yaws[i], 0.0)), positions[i] + Vector3.UP * shape.height * 0.5)
		var col := CollisionShape3D.new()
		col.shape = shape
		body.add_child(col)
		add_child(body)
		_built.append(body)
		_stats["colliders"] += 1


static func _vertex_count(mesh: ArrayMesh) -> int:
	if mesh.get_surface_count() == 0:
		return 0
	return (mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
