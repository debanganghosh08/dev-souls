class_name Grass
extends Node3D
## Instanced ground cover (blade clumps, pebbles, leaf drifts, small foliage) that follows the player. A
## lattice of square cells covers `radius` around the player; each cell owns one pooled MultiMeshInstance3D
## per layer, written when the cell enters the lattice and recycled, not rebuilt, when it leaves: a cell
## crossing refills only the ring that came into reach, a few cells per frame. Placement is seeded from the
## cell key so a spot regrows identically on every visit. Layers and wind: data/grass/<area>.json; pure maths:
## GrassLattice. Density thins with distance per ring (visible_instance_count) and the shaders sink blades
## into the ground over the last metres, so the field dissolves into fog instead of ending in a wall.

const NO_CELL := Vector2i(1 << 30, 1 << 30)
const THIN_MOVE := 2.0

@export_file("*.json") var data_path: String = "res://data/grass/vale.json"
@export var radius: float = 70.0
@export var cell_size: float = 12.0
## density multiplies every layer's data-file density; max_slope caps every layer's slope limit (degrees).
@export var density: float = 1.0
@export var max_slope: float = 32.0
## Overrides the clump layer's blade height range when both are > 0.
@export var blade_height_min: float = 0.0
@export var blade_height_max: float = 0.0
@export var wind_strength: float = 0.28
@export var wind_direction_deg: float = 35.0
@export var wind_speed: float = 1.1
@export var wind_ripple: float = 0.09
@export var seed_value: int = 20261024
## Fraction of radius inside which every placed instance is shown; density thins from there to the edge.
@export var near_fraction: float = 0.45
## A frame fills cells until this much CPU time has gone to them: always the first, then another only
## while the budget lasts, the way Terrain spends build_budget_ms. W6-04 measured a cell at about 1.2 ms
## and a fixed three cells at 5.4 ms worst on the lead's machine; 2 ms makes that one or two cells, so the
## worst frame stays near 4 ms whether the player walks or sprints. fill_cells_per_frame caps it regardless.
@export var fill_budget_ms: float = 2.0
@export var fill_cells_per_frame: int = 3
@export var auto_build: bool = false

var cluster_points: PackedVector3Array = PackedVector3Array()

var _layers: Array[GrassLayer] = []
var _cell: GrassCell = GrassCell.new()
var _offsets: Array[Vector2i] = []
var _slots: Array[Array] = []
var _slot_key: Array[Vector2i] = []
var _slot_counts: PackedInt32Array = PackedInt32Array()
var _slot_positions: Array[PackedVector3Array] = []
var _cells: Dictionary = {}
var _free: PackedInt32Array = PackedInt32Array()
var _free_count: int = 0
var _pending: Array[Vector2i] = []
var _centre: Vector2i = NO_CELL
var _last_thin: Vector3 = Vector3(INF, INF, INF)
var _tracked: Node3D
var _height_sampler: Callable = Callable()
var _exact_slope: Callable = Callable()
var _density_filter: Callable = Callable()
var _water: float = -INF
var _cluster_reach: float = 0.0
var _built: bool = false
# CPU cost of _fill_pending in microseconds over every frame that filled at least one cell: two clock reads
# and three integer adds on a working frame, nothing per cell or per blade. Read through stats().
var _fill_usec: int = 0
var _fill_worst_usec: int = 0
var _fill_frames: int = 0
var _fill_cells: int = 0


func _ready() -> void:
	if auto_build:
		rebuild()


## Grows on `terrain`'s heightfield; `filter` is an optional (x, z) -> float density multiplier.
func bind(terrain: Terrain, filter: Callable = Callable(), clusters: PackedVector3Array = PackedVector3Array()) -> void:
	bind_heightfield(terrain.heightfield, filter, clusters)


## The same on a bare Heightfield, so tests can grow without a Terrain node or a scene tree.
func bind_heightfield(hf: Heightfield, filter: Callable = Callable(), clusters: PackedVector3Array = PackedVector3Array()) -> void:
	_height_sampler = hf.height_at
	_exact_slope = hf.slope_at
	_water = hf.water_level()
	_density_filter = filter
	cluster_points = clusters


## Builds the layers and the slot pool from `data`, or from data_path when it is empty (the normal case).
func rebuild(data: Dictionary = {}) -> void:
	for slot: Array in _slots:
		for mmi: MultiMeshInstance3D in slot:
			mmi.queue_free()
	_slots.clear()
	_slot_key.clear()
	_slot_positions.clear()
	_cells.clear()
	_pending.clear()
	_layers.clear()
	if data.is_empty():
		data = Terrain.load_data(data_path)
	var wind: Dictionary = data.get("wind", {})
	wind_strength = float(wind.get("strength", wind_strength))
	wind_direction_deg = float(wind.get("direction_deg", wind_direction_deg))
	wind_speed = float(wind.get("speed", wind_speed))
	wind_ripple = float(wind.get("ripple_scale", wind_ripple))
	seed_value = int(data.get("seed", seed_value))
	_cluster_reach = 0.0
	for entry: Variant in data.get("layers", []):
		if not entry is Dictionary:
			continue
		var layer: GrassLayer = GrassLayer.from_dict(entry, seed_value, _layers.size())
		layer.density *= maxf(0.0, density)
		layer.max_slope = minf(layer.max_slope, max_slope)
		if layer.kind == "clump" and blade_height_min > 0.0 and blade_height_max > 0.0:
			layer.height_range = Vector2(blade_height_min, blade_height_max)
		_cluster_reach = maxf(_cluster_reach, layer.cluster_radius + layer.cluster_falloff)
		if layer.usable():
			_layers.append(layer)
	apply_wind()
	_offsets = GrassLattice.lattice_offsets(radius, cell_size)
	var pool: int = _offsets.size()
	_slot_counts.resize(pool * _layers.size())
	_slot_counts.fill(0)
	_free.resize(pool)
	for s: int in pool:
		var nodes: Array = []
		for layer: GrassLayer in _layers:
			var mmi: MultiMeshInstance3D = layer.make_instance(s)
			mmi.top_level = true
			add_child(mmi)
			nodes.append(mmi)
			var positions := PackedVector3Array()
			positions.resize(layer.max_per_cell)
			_slot_positions.append(positions)
		_slots.append(nodes)
		_slot_key.append(NO_CELL)
		_free[s] = s
	_free_count = pool
	_centre = NO_CELL
	_last_thin = Vector3(INF, INF, INF)
	_fill_usec = 0
	_fill_worst_usec = 0
	_fill_frames = 0
	_fill_cells = 0
	_built = true


func apply_wind() -> void:
	var dir: Vector2 = Vector2.from_angle(deg_to_rad(wind_direction_deg))
	for layer: GrassLayer in _layers:
		layer.set_wind(wind_strength, dir, wind_speed, wind_ripple)


func _process(_delta: float) -> void:
	if _tracked == null:
		_tracked = get_tree().get_first_node_in_group(&"player") as Node3D
	step(_tracked.global_position if _tracked != null else global_position)


## One frame of lattice work for a player at `p`: recycle on a cell crossing, fill a few pending cells,
## re-thin once the player has moved. Public so tests can drive frames without a scene tree.
func step(p: Vector3) -> void:
	if not _built or not _height_sampler.is_valid():
		return
	var centre: Vector2i = GrassLattice.cell_of(p.x, p.z, cell_size)
	if centre != _centre:
		_relayout(centre)
	_fill_pending()
	if p.distance_squared_to(_last_thin) > THIN_MOVE * THIN_MOVE:
		_update_thinning(p)


# The only allocation on a cell crossing: the wanted-set and its diff. That is once per cell_size metres
# walked, never per frame; every fill below writes into buffers sized at rebuild().
func _relayout(centre: Vector2i) -> void:
	_centre = centre
	var want: Array[Vector2i] = []
	for o: Vector2i in _offsets:
		want.append(centre + o)
	var diff: Dictionary = GrassLattice.cell_diff(_cells, want)
	for key: Vector2i in diff["drop"]:
		_release(key)
	for key: Vector2i in diff["add"]:
		_pending.append(key)
	_pending.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return (a - centre).length_squared() < (b - centre).length_squared())


func _release(key: Vector2i) -> void:
	var slot: int = _cells[key]
	_cells.erase(key)
	_slot_key[slot] = NO_CELL
	for l: int in _layers.size():
		_slot_counts[slot * _layers.size() + l] = 0
		var mmi: MultiMeshInstance3D = _slots[slot][l]
		mmi.multimesh.visible_instance_count = 0
		mmi.visible = false
	_free[_free_count] = slot
	_free_count += 1


func _fill_pending() -> void:
	if _pending.is_empty():
		return
	var t0: int = Time.get_ticks_usec()
	var deadline: int = t0 + int(maxf(0.0, fill_budget_ms) * 1000.0)
	var budget: int = maxi(1, fill_cells_per_frame)
	while budget > 0 and not _pending.is_empty():
		var key: Vector2i = _pending.pop_front()
		if _cells.has(key) or (key - _centre).length() * cell_size > radius + cell_size or _free_count == 0:
			continue
		budget -= 1
		_free_count -= 1
		var slot: int = _free[_free_count]
		_cells[key] = slot
		_slot_key[slot] = key
		_cell.prepare(key, cell_size, _height_sampler, _water, cluster_points, _cluster_reach)
		for l: int in _layers.size():
			var i: int = slot * _layers.size() + l
			_slot_counts[i] = _layers[l].fill(key, l, seed_value, _cell, _slots[slot][l], _slot_positions[i], _density_filter, _exact_slope)
		if Time.get_ticks_usec() >= deadline:
			break
	var filled: int = maxi(1, fill_cells_per_frame) - budget
	if filled > 0:
		var dt: int = Time.get_ticks_usec() - t0
		_fill_usec += dt
		_fill_worst_usec = maxi(_fill_worst_usec, dt)
		_fill_frames += 1
		_fill_cells += filled
		_last_thin = Vector3(INF, INF, INF)


func _update_thinning(p: Vector3) -> void:
	_last_thin = p
	var near: float = radius * near_fraction
	for slot: int in _slots.size():
		if _slot_key[slot] == NO_CELL:
			continue
		var c: Vector2 = GrassLattice.cell_centre(_slot_key[slot], cell_size)
		var d: float = Vector2(p.x, p.z).distance_to(c)
		for l: int in _layers.size():
			var mmi: MultiMeshInstance3D = _slots[slot][l]
			var count: int = _slot_counts[slot * _layers.size() + l]
			mmi.multimesh.visible_instance_count = int(float(count) * GrassLattice.thin_factor(d, radius, near, _layers[l].far_fraction))


func instance_count() -> int:
	var total: int = 0
	for n: int in _slot_counts:
		total += n
	return total


func stats() -> Dictionary:
	var per_layer: Dictionary = {}
	var blade_verts: int = 0
	for l: int in _layers.size():
		var n: int = 0
		for slot: int in _slots.size():
			n += _slot_counts[slot * _layers.size() + l]
		per_layer[_layers[l].name] = n
		if _layers[l].kind == "clump":
			blade_verts += n * _layers[l].vertex_count
	return {"cells": _cells.size(), "pool": _slots.size(), "pending": _pending.size(), "instances": instance_count(),
		"blade_verts": blade_verts, "layers": _layers.size(), "per_layer": per_layer,
		"fill_frames": _fill_frames, "fill_cells": _fill_cells, "fill_total_ms": float(_fill_usec) / 1000.0,
		"fill_mean_ms": float(_fill_usec) / 1000.0 / float(maxi(1, _fill_frames)), "fill_worst_ms": float(_fill_worst_usec) / 1000.0}


## Probe-time copy of every placed instance's world origin, so a test can compare two lattices exactly.
func positions() -> PackedVector3Array:
	var out := PackedVector3Array()
	for slot: int in _slots.size():
		for l: int in _layers.size():
			var i: int = slot * _layers.size() + l
			out.append_array(_slot_positions[i].slice(0, _slot_counts[i]))
	return out


## Probe-time count of placed instances under water, above their layer's slope limit, or off the ground.
func audit(hf: Heightfield, tolerance: float = 0.05) -> Dictionary:
	var out: Dictionary = {"underwater": 0, "steep": 0, "floating": 0, "checked": 0}
	for slot: int in _slots.size():
		for l: int in _layers.size():
			var i: int = slot * _layers.size() + l
			for k: int in _slot_counts[i]:
				var p: Vector3 = _slot_positions[i][k]
				out["checked"] += 1
				if hf.is_underwater(p.x, p.z):
					out["underwater"] += 1
				if hf.slope_at(p.x, p.z) > _layers[l].max_slope:
					out["steep"] += 1
				var dy: float = p.y - hf.height_at(p.x, p.z)
				if dy > tolerance or dy < -(_layers[l].sink * _layers[l].scale_range.y + tolerance):
					out["floating"] += 1
	return out
