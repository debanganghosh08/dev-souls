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
## Edge of the buckets the trees are indexed into, for asking which are near a point.
const INDEX_BUCKET := 32.0
const PLACE_ATTEMPTS := 12

@export var archetype_mix: Dictionary = {"fir": 6.0, "pine": 3.0, "dead": 1.0}
@export var count: int = 200
@export var radius: float = 60.0
@export var clearing_radius: float = 8.0
@export var seed_value: int = 1
@export var lod1_distance: float = 45.0
@export var cull_distance: float = 140.0
## How many trees carry a StaticBody3D at once. The bodies are a POOL: they are made once and moved onto
## whichever trees are near the player, so this is the number of solid trees in reach and not the number of
## solid trees in the Vale. Sized against the densest wood -- see collider_reach.
@export var collider_count: int = 40
## Trees within this many metres of the player are the ones that get the pool. At 11,600 trees the Vale has
## woods holding about one tree per 10 m2, so 30 m is roughly 280 trees: the pool covers a dense wood at
## this reach and no further. The pool is only re-dealt once the player has moved collider_step, so at a
## sprint the solid shell still reaches some 20 m ahead of them.
@export var collider_reach: float = 30.0
## How far the player moves before the pool is re-dealt.
@export var collider_step: float = 8.0
## Where the pool sits before anything is tracked -- one frame in the real game, the whole run in a headless
## probe with no player. Pick somewhere with trees: Thornwood's centre was tried and it is a 36 m clearing,
## so the pool found nothing to be solid and dealt nothing at all.
@export var collider_anchors: PackedVector2Array = PackedVector2Array()
## Edge length of the square chunks that visibility ranges (LOD and culling) are evaluated per.
@export var chunk_size: float = 40.0
## Off when a level sets height_sampler / placement_filter first and calls rebuild() itself.
@export var auto_build: bool = true
@export_group("Band")
## A corridor of trees along a polyline, on top of the radial wood: the owner asked for a forest area with
## a road through it and dense trees down both sides. Points are world XZ; leave it empty and the forest is
## exactly what it was.
@export var band_points: PackedVector2Array = PackedVector2Array()
## Trees reach from band_gap to band_half either side of the line, so the road itself stays walkable.
@export var band_gap: float = 5.0
@export var band_half: float = 26.0
@export var band_count: int = 0
@export_group("Grove")
## A dense wood in one place, on top of the thinned radial forest: the owner asked for a forest of
## thousands with something hidden inside it, and a wood you can lose a village in has to be far denser
## than the scatter that covers the whole valley. A clearing is left at its heart for whatever stands
## there, and the trees crowd hardest just inside the outer edge, which is what makes it read as a wall of
## wood from outside and a room from within.
@export var grove_centre: Vector2 = Vector2.ZERO
@export var grove_radius: float = 0.0
@export var grove_clearing: float = 0.0
@export var grove_count: int = 0
## More woods, as data. One wood is four exports; the owner asked for the Vale's open quarters to be filled,
## and five woods would be twenty. Each row is {"name", "centre": [x, z], "radius", "clearing", "count"},
## and the name is there so a failure can say which wood it came from.
@export_file("*.json") var groves_path: String = ""
## One tree far bigger than the rest, this far along the band (0 start, 1 end), at this scale: the landmark
## the owner asked for. Scale 0 leaves it out.
@export_range(0.0, 1.0) var landmark_at: float = 0.5
@export var landmark_scale: float = 0.0

## Optional world-space ground: (x, z) -> y. When valid, trees stand on it instead of this node's XZ plane.
var height_sampler: Callable = Callable()
## Optional (x, z) -> bool in world space; trees failing it are dropped, so tree_count() can be below count.
var placement_filter: Callable = Callable()

var _layout: Dictionary = {}
# The collider pool and what it needs to deal itself out again: the trees' own data, a bucket index to ask
# which are near a point, the bodies themselves, and where the pool was last dealt.
var _bodies: Array[StaticBody3D] = []
var _body_shapes: Array[CylinderShape3D] = []
var _tree_index: Dictionary = {}
var _tree_rows: Array[Dictionary] = []
var _dealt_at: Vector3 = Vector3(INF, INF, INF)
var _dealt: int = 0
var _tracked: Node3D = null
var _stats: Dictionary = {}
var _built: Array[Node] = []


func _ready() -> void:
	if auto_build:
		rebuild()


func _process(_delta: float) -> void:
	if _tracked == null or not is_instance_valid(_tracked):
		return
	deal(_tracked.global_position)


func rebuild() -> void:
	for node: Node in _built:
		node.queue_free()
	_built.clear()
	var plan: Dictionary = plan_layout(count, radius, clearing_radius, seed_value, archetype_mix)
	merge_layout(plan, plan_band(band_points, band_gap, band_half, band_count, seed_value + 7919,
			archetype_mix, landmark_at, landmark_scale))
	merge_layout(plan, plan_grove(grove_centre, grove_radius, grove_clearing, grove_count,
			seed_value + 104729, archetype_mix))
	var extra: Array = groves_of(groves_path)
	for i: int in extra.size():
		var g: Dictionary = extra[i]
		merge_layout(plan, plan_grove(_vec(g.get("centre")), float(g.get("radius", 0.0)),
				float(g.get("clearing", 0.0)), int(g.get("count", 0)),
				seed_value + 104729 + (i + 1) * 7717, archetype_mix))
	_layout = _grounded(plan)
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


## Trees scattered along a polyline rather than round a centre: a random point on the line, pushed out
## sideways between `gap` and `half`, which is what a road through a wood looks like. Same shape as
## plan_layout returns, so merge_layout can pour one into the other.
static func plan_band(points: PackedVector2Array, gap: float, half: float, tree_count: int, seed_v: int,
		mix: Dictionary, landmark_t: float = 0.5, landmark_scale: float = 0.0) -> Dictionary:
	var positions := PackedVector3Array()
	var archetypes := PackedStringArray()
	var yaws := PackedFloat32Array()
	var scales := PackedFloat32Array()
	var out: Dictionary = {"positions": positions, "archetypes": archetypes, "yaws": yaws, "scales": scales}
	if points.size() < 2 or tree_count <= 0:
		return out
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var names: Array[String] = []
	var weights: Array[float] = []
	for key: Variant in mix.keys():
		if float(mix[key]) > 0.0:
			names.append(str(key))
			weights.append(float(mix[key]))
	if names.is_empty():
		return out
	var reach: float = maxf(gap + 0.5, half)
	for i: int in tree_count:
		var t: float = rng.randf()
		var spot: Vector2 = point_on(points, t)
		var side: float = 1.0 if rng.randf() < 0.5 else -1.0
		# Crowded near the road and thinning outward: the power biases the draw toward the gap.
		var push: float = lerpf(gap, reach, pow(rng.randf(), 0.7))
		var cand: Vector2 = spot + heading_at(points, t).orthogonal() * push * side
		if _too_close(cand, positions):
			continue
		positions.append(Vector3(cand.x, 0.0, cand.y))
		archetypes.append(_weighted(names, weights, rng))
		yaws.append(rng.randf_range(0.0, TAU))
		scales.append(rng.randf_range(0.85, 1.3))
	if landmark_scale > 0.0:
		var lt: float = clampf(landmark_t, 0.0, 1.0)
		var where: Vector2 = point_on(points, lt) + heading_at(points, lt).orthogonal() * (reach * 0.55)
		positions.append(Vector3(where.x, 0.0, where.y))
		archetypes.append(names[0])
		yaws.append(rng.randf_range(0.0, TAU))
		scales.append(landmark_scale)
	return {"positions": positions, "archetypes": archetypes, "yaws": yaws, "scales": scales}


## The woods listed in `path`, or an empty array when there is no file or it is the wrong shape. A wood
## with no name is dropped: an unnamed row is almost always a typo, and a silent one would be a wood that
## nobody could find a mistake in.
static func groves_of(path: String) -> Array:
	var out: Array = []
	if path == "" or not FileAccess.file_exists(path):
		return out
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not data is Dictionary:
		push_error("Forest: %s is not a JSON object" % path)
		return out
	for row: Variant in (data as Dictionary).get("groves", []):
		if row is Dictionary and str((row as Dictionary).get("name", "")) != "":
			out.append(row)
	return out


static func _vec(raw: Variant) -> Vector2:
	if raw is Array and (raw as Array).size() >= 2:
		return Vector2(float((raw as Array)[0]), float((raw as Array)[1]))
	return Vector2.ZERO


## A dense ring of wood round a clearing. Density rises toward the outer edge so the wood closes behind
## you: from inside the clearing it is a wall, and from outside there is no clearing at all.
static func plan_grove(centre: Vector2, radius: float, clearing: float, tree_count: int, seed_v: int,
		mix: Dictionary) -> Dictionary:
	var positions := PackedVector3Array()
	var archetypes := PackedStringArray()
	var yaws := PackedFloat32Array()
	var scales := PackedFloat32Array()
	var out: Dictionary = {"positions": positions, "archetypes": archetypes, "yaws": yaws, "scales": scales}
	if radius <= 0.0 or tree_count <= 0:
		return out
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var names: Array[String] = []
	var weights: Array[float] = []
	for key: Variant in mix.keys():
		if float(mix[key]) > 0.0:
			names.append(str(key))
			weights.append(float(mix[key]))
	if names.is_empty():
		return out
	var inner: float = maxf(0.0, clearing)
	# A wood asks for thousands of candidates and _too_close walks every tree placed so far, which is
	# quadratic and would cost seconds of load time here. Same rule, read out of 1.6 m buckets.
	var grid: Dictionary = {}
	for i: int in tree_count:
		# sqrt spreads evenly by area; the extra power crowds the outer edge, which is what makes the wood
		# a wall from outside and a room from within.
		var t: float = pow(rng.randf(), 0.55)
		var r: float = lerpf(inner, radius, sqrt(t))
		var a: float = rng.randf_range(0.0, TAU)
		var cand: Vector2 = centre + Vector2(cos(a), sin(a)) * r
		if _crowded(cand, grid):
			continue
		_mark(cand, grid)
		positions.append(Vector3(cand.x, 0.0, cand.y))
		archetypes.append(_weighted(names, weights, rng))
		yaws.append(rng.randf_range(0.0, TAU))
		scales.append(rng.randf_range(0.8, 1.2))
	return out


## Pours `extra` into `into`, in place. Both carry the four parallel arrays.
static func merge_layout(into: Dictionary, extra: Dictionary) -> void:
	if (extra.get("positions", PackedVector3Array()) as PackedVector3Array).is_empty():
		return
	for key: String in ["positions", "archetypes", "yaws", "scales"]:
		var merged: Variant = into[key]
		for item: Variant in extra[key]:
			merged.append(item)
		into[key] = merged


## The point `t` of the way along a polyline, measured by distance rather than by segment count.
static func point_on(points: PackedVector2Array, t: float) -> Vector2:
	var lengths: Array[float] = []
	var total: float = 0.0
	for i: int in range(points.size() - 1):
		var seg: float = points[i].distance_to(points[i + 1])
		lengths.append(seg)
		total += seg
	if total <= 0.0:
		return points[0]
	var want: float = clampf(t, 0.0, 1.0) * total
	for i: int in range(lengths.size()):
		if want <= lengths[i] or i == lengths.size() - 1:
			return points[i].lerp(points[i + 1], clampf(want / maxf(0.001, lengths[i]), 0.0, 1.0))
		want -= lengths[i]
	return points[points.size() - 1]


## The unit direction of the polyline at `t`, for pushing a tree out sideways from it.
static func heading_at(points: PackedVector2Array, t: float) -> Vector2:
	var here: Vector2 = point_on(points, t)
	var dir: Vector2 = point_on(points, minf(1.0, t + 0.02)) - here
	if dir.length_squared() < 0.0001:
		dir = point_on(points, 1.0) - point_on(points, 0.0)
	return dir.normalized() if dir.length_squared() > 0.0001 else Vector2.RIGHT


func _grounded(layout: Dictionary) -> Dictionary:
	var origin: Vector3 = global_position if is_inside_tree() else position
	return GroundPlacement.ground_layout(layout, origin, height_sampler, placement_filter)


## Puts the collider pool on the trees nearest `at`, nearest first, and returns how many bodies were used.
## Does nothing when the player has not moved collider_step since the last deal, so a frame of walking costs
## one distance check. Public so a test can drive it without a scene tree.
func deal(at: Vector3) -> int:
	if _bodies.is_empty():
		return 0
	if _dealt_at.distance_squared_to(at) < collider_step * collider_step:
		return _dealt
	_dealt_at = at
	var near: Array[int] = near_trees(at, collider_reach)
	near.sort_custom(func(a: int, b: int) -> bool:
		return _flat(_tree_rows[a]["at"], at) < _flat(_tree_rows[b]["at"], at))
	var used: int = mini(_bodies.size(), near.size())
	for k: int in _bodies.size():
		var body: StaticBody3D = _bodies[k]
		if k >= used:
			# A body with nothing to stand on is parked far below the world rather than freed: freeing and
			# remaking bodies on every deal is what makes a streaming pool hitch.
			body.position = Vector3(0.0, -4000.0, 0.0)
			continue
		var row: Dictionary = _tree_rows[near[k]]
		_body_shapes[k].radius = float(row["radius"])
		_body_shapes[k].height = float(row["height"])
		body.transform = Transform3D(Basis.from_euler(Vector3(0.0, float(row["yaw"]), 0.0)),
				(row["at"] as Vector3) + Vector3.UP * float(row["height"]) * 0.5)
	_dealt = used
	return used


## Which trees are within `reach` of `at`, by index, read out of the bucket index rather than by walking
## every tree. Unordered.
func near_trees(at: Vector3, reach: float) -> Array[int]:
	var out: Array[int] = []
	var lo := Vector2(at.x - reach, at.z - reach)
	var hi := Vector2(at.x + reach, at.z + reach)
	var reach_sq: float = reach * reach
	for bx: int in range(floori(lo.x / INDEX_BUCKET), floori(hi.x / INDEX_BUCKET) + 1):
		for bz: int in range(floori(lo.y / INDEX_BUCKET), floori(hi.y / INDEX_BUCKET) + 1):
			var bucket: Variant = _tree_index.get(Vector2i(bx, bz))
			if bucket == null:
				continue
			for i: int in bucket as Array:
				if _flat(_tree_rows[i]["at"], at) <= reach_sq:
					out.append(i)
	return out


## How many bodies the last deal put on a tree.
func colliders_dealt() -> int:
	return _dealt


## Follows `player` from the next frame on. Null parks the pool back on the anchors.
func track(player: Node3D) -> void:
	_tracked = player
	if player == null:
		_dealt_at = Vector3(INF, INF, INF)
		deal(_first_anchor())


static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length_squared()


func _first_anchor() -> Vector3:
	if collider_anchors.is_empty():
		return Vector3.ZERO
	return Vector3(collider_anchors[0].x, 0.0, collider_anchors[0].y)


## Distance from a tree to the nearest anchor, the origin included. Pure, so a test can check that a
## far-off anchor really does win colliders away from the trees beside the spawn.
static func anchor_distance(at: Vector3, anchors: PackedVector2Array) -> float:
	var flat := Vector2(at.x, at.z)
	var best: float = flat.length()
	for a: Vector2 in anchors:
		best = minf(best, flat.distance_to(a))
	return best


## Whether anything already in `grid` is inside MIN_SPACING of `cand`. The grid is keyed on MIN_SPACING
## cells, so one candidate reads nine buckets however large the wood is.
## The buckets hold plain Arrays, NOT PackedVector2Arrays: a packed array read back out of a Dictionary is
## a copy, so `(grid[key] as PackedVector2Array).append(p)` throws the append away and every candidate then
## passes. That is not a guess -- it is how this went wrong the first time, and the wood placed every one of
## 15,000 candidates on top of itself.
static func _crowded(cand: Vector2, grid: Dictionary) -> bool:
	var key := Vector2i(floori(cand.x / MIN_SPACING), floori(cand.y / MIN_SPACING))
	for dx: int in [-1, 0, 1]:
		for dz: int in [-1, 0, 1]:
			var bucket: Variant = grid.get(Vector2i(key.x + dx, key.y + dz))
			if bucket == null:
				continue
			for p: Vector2 in bucket as Array:
				if p.distance_squared_to(cand) < MIN_SPACING * MIN_SPACING:
					return true
	return false


static func _mark(at: Vector2, grid: Dictionary) -> void:
	var key := Vector2i(floori(at.x / MIN_SPACING), floori(at.y / MIN_SPACING))
	if not grid.has(key):
		grid[key] = []
	(grid[key] as Array).append(at)


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


## Builds the collider pool and deals it out for the first time. The pool is collider_count bodies, made
## once here and moved onto whichever trees are near the player from then on (see deal). Before W19 the
## bodies were made per tree and never moved, which meant the trees you could lean on were decided at load:
## fine while the forest was six hundred trees round the spawn, useless at 11,600 across five woods.
func _build_colliders(trees: Dictionary, positions: PackedVector3Array, names: PackedStringArray, yaws: PackedFloat32Array, scales: PackedFloat32Array) -> void:
	_tree_rows.clear()
	_tree_index.clear()
	for i: int in positions.size():
		var tree: Dictionary = (trees[names[i]] as Dictionary)["lod0"]
		_tree_rows.append({
			"at": positions[i],
			"yaw": yaws[i],
			"radius": float(tree["collider_radius"]) * scales[i],
			"height": float(tree["height"]) * scales[i],
		})
		# Plain Array, not PackedInt32Array: see _crowded. A packed array out of a Dictionary is a copy.
		var key := Vector2i(floori(positions[i].x / INDEX_BUCKET), floori(positions[i].z / INDEX_BUCKET))
		if not _tree_index.has(key):
			_tree_index[key] = []
		(_tree_index[key] as Array).append(i)
	var limit: int = mini(collider_count, _tree_rows.size())
	for k: int in limit:
		var shape := CylinderShape3D.new()
		shape.radius = 0.2
		shape.height = 1.0
		var body := StaticBody3D.new()
		body.name = "TreeBody_%d" % k
		body.collision_layer = WORLD_LAYER
		body.collision_mask = 0
		var col := CollisionShape3D.new()
		col.shape = shape
		body.add_child(col)
		add_child(body)
		_built.append(body)
		_bodies.append(body)
		_body_shapes.append(shape)
		_stats["colliders"] += 1
	_dealt_at = Vector3(INF, INF, INF)
	deal(_first_anchor())


static func _vertex_count(mesh: ArrayMesh) -> int:
	if mesh.get_surface_count() == 0:
		return 0
	return (mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
