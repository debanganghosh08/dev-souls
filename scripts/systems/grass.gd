class_name Grass
extends Node3D
## Instanced ground cover (blade clumps, pebbles, leaf drifts, small foliage) that follows the player. A
## lattice of square cells covers `radius` around the player; each cell owns one pooled MultiMeshInstance3D
## per layer, written when the cell enters the lattice and recycled, not rebuilt, when it leaves: a cell
## crossing refills only the ring that came into reach, a few cells per frame. Placement is seeded from the
## cell key so a spot regrows identically on every visit. Layers and wind: data/grass/<area>.json; where
## grass is dense, tall, flowered and what colour: its `zones` file (GrassZones, W8-G); pure maths:
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
## A frame fills until this much CPU time has gone to it: always one unit of work, then more only while
## the budget lasts, the way Terrain spends build_budget_ms. W6-04 measured a whole cell at
## about 1.2 ms on the lead's machine; W8-G's zoned cells are about 1.7x that and the unit became a layer so
## the worst frame stays near one grass layer whether the player walks or sprints. fill_cells_per_frame
## caps how many cells may start in a frame regardless. W8-G2 measured a dense cell's grass layer alone
## at 4.0-4.6 ms idle (240 candidates), four times a budget that is checked only between units, so a
## unit is now a step of at most fill_step_candidates candidates of one layer (0: a whole layer): the
## overrun past the budget is one step (32 candidates: about 0.6 ms), and the world built is the same
## whatever the step (tests/test_grass_budget.gd). Smaller steps cost nothing per candidate, only one
## clock read per step; what they do cost is the first fill at the spawn, which takes more frames.
## first_fill_budget_ms is spent instead until the lattice has settled once after rebuild(): the fill
## round the spawn is a load, not play, and the old schedule overran to 2.3 ms a frame there anyway
## (p95 6.2, worst 11 ms, measured W8-G2); 2 ms plus one step keeps the same throughput at a third
## of the worst frame. After that first settle the play budget rules, cell crossings included.
## W9-G raised both: the field is 2.4x denser than it was (the owner played it and the grass read as
## desert scrub a metre apart), and at the old 1 ms a sprinting player outran the fill -- cells inside
## 50 m of them were still empty. A bigger slice per frame is the price of the denser field.
@export var fill_budget_ms: float = 2.2
@export var first_fill_budget_ms: float = 3.0
## Deliberately small. The budget above caps what a frame SPENDS, so letting more cells make progress
## at once does not buy more work -- it spreads the same work thinner and the nearest cell, the one
## the player is standing in, finishes later. Raised to 6 in W12 and reverted: cells left unfilled
## within 50 m of a sprinting player went from 9 to 14.
@export var fill_cells_per_frame: int = 3
@export var fill_step_candidates: int = 32
@export var auto_build: bool = false

var cluster_points: PackedVector3Array = PackedVector3Array()
## Edge of the buckets the cluster points are indexed into, in metres. Comfortably wider than any cell plus
## its cluster reach, so a cell touches four buckets at worst.
const CLUSTER_BUCKET := 64.0
# The trees, bucketed. prepare() used to walk EVERY cluster point for every lattice cell it filled, which
# cost nothing while the wood was six hundred trees and broke the sprint fill the day it became three
# thousand four hundred (W19). The index is built once per bind and read once per cell.
var _cluster_index: Dictionary = {}
## The area's zones (density, palette, tall grass and flowers by place), built from the data file's
## `zones` path once a Heightfield is bound; null leaves every layer on the land alone.
var zones: GrassZones

var _layers: Array[GrassLayer] = []
var _hf: Heightfield
var _zones_path: String = ""
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
# True from rebuild() until the lattice first has nothing pending: the spawn fill, on its own budget.
var _first_fill: bool = true
# CPU cost of _fill_pending in microseconds over every frame that filled at least one cell: two clock reads
# and a few integer adds on a working frame, one clock read per unit, nothing per blade. Read through
# stats(). The histogram (HIST_USEC-wide buckets, the last one open-ended) gives the 95th percentile and
# the counts over 4, 8 and 16 ms without keeping a sample per frame.
const HIST_USEC := 100
const HIST_BUCKETS := 1000
var _fill_usec: int = 0
var _fill_worst_usec: int = 0
var _fill_frames: int = 0
var _fill_cells: int = 0
var _fill_steps: int = 0
var _fill_hist: PackedInt32Array = PackedInt32Array()
var _fill_over_4: int = 0
var _fill_over_8: int = 0
var _fill_over_16: int = 0
# The dearest single unit of work (one step of one layer, or a cell's prepare) and the layer it was in
# (-1: prepare): whether a unit alone can blow the budget is the question W8-G2 had to answer.
var _fill_worst_unit_usec: int = 0
var _fill_worst_unit_layer: int = -1
var _fill_prepare_usec: int = 0
# The re-thinning pass over every held cell: outside the fill timer, but a frame pays for it too.
var _thin_usec: int = 0
var _thin_worst_usec: int = 0
var _thin_count: int = 0
# The cell whose layers are still being filled across frames (slot, next layer), or -1 between cells.
var _partial_slot: int = -1
var _partial_layer: int = 0


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
	_index_clusters()
	_hf = hf
	_build_zones()


## Buckets every cluster point by position. Cheap, and it is the whole of the fix: the cost of preparing a
## cell stops depending on how many trees the level planted anywhere else.
func _index_clusters() -> void:
	_cluster_index.clear()
	for p: Vector3 in cluster_points:
		# Plain Array, not PackedVector3Array: a packed array read back out of a Dictionary is a copy, so
		# the append would be thrown away and every bucket would stay empty -- which reads as "no tree is
		# near any cell" and quietly removes the clustering this index exists to serve.
		var key := Vector2i(int(floor(p.x / CLUSTER_BUCKET)), int(floor(p.z / CLUSTER_BUCKET)))
		if not _cluster_index.has(key):
			_cluster_index[key] = []
		(_cluster_index[key] as Array).append(p)


## The cluster points that could reach into the cell at `origin`, gathered from the buckets that overlap it
## grown by `reach`. A superset of what the cell needs, which is all prepare() wants: it filters again.
func clusters_near(origin: Vector2, size: float, reach: float) -> PackedVector3Array:
	var out := PackedVector3Array()
	if _cluster_index.is_empty():
		return out
	var low := Vector2(origin.x - reach, origin.y - reach)
	var high := Vector2(origin.x + size + reach, origin.y + size + reach)
	for bx: int in range(int(floor(low.x / CLUSTER_BUCKET)), int(floor(high.x / CLUSTER_BUCKET)) + 1):
		for bz: int in range(int(floor(low.y / CLUSTER_BUCKET)), int(floor(high.y / CLUSTER_BUCKET)) + 1):
			var bucket: Variant = _cluster_index.get(Vector2i(bx, bz))
			if bucket == null:
				continue
			for p: Vector3 in bucket as Array:
				out.append(p)
	return out


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
	_zones_path = str(data.get("zones", ""))
	_cluster_reach = 0.0
	for entry: Variant in data.get("layers", []):
		if not entry is Dictionary:
			continue
		var layer: GrassLayer = GrassLayer.from_dict(entry, seed_value, _layers.size())
		layer.density *= maxf(0.0, density)
		layer.max_slope = minf(layer.max_slope, max_slope)
		# The override is for the meadow blades; the tall layer keeps its own waist-high range.
		if layer.kind == "clump" and layer.zone_channel != "tall" and blade_height_min > 0.0 and blade_height_max > 0.0:
			layer.height_range = Vector2(blade_height_min, blade_height_max)
		_cluster_reach = maxf(_cluster_reach, layer.cluster_radius + layer.cluster_falloff)
		if layer.usable():
			_layers.append(layer)
	_build_zones()
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
	reset_cost_counters()
	_partial_slot = -1
	_partial_layer = 0
	_first_fill = true
	_built = true


func apply_wind() -> void:
	var dir: Vector2 = Vector2.from_angle(deg_to_rad(wind_direction_deg))
	for layer: GrassLayer in _layers:
		layer.set_wind(wind_strength, dir, wind_speed, wind_ripple)


# Zones need both the data file's path (rebuild) and a Heightfield (bind); whichever comes second builds
# them, and every "grass" layer learns the densest zone so its candidate pool can reach it.
func _build_zones() -> void:
	if _zones_path == "" or _hf == null:
		return
	if zones == null:
		zones = GrassZones.load_file(_zones_path, _hf)
	if zones == null:
		return
	for layer: GrassLayer in _layers:
		layer.zone_max = zones.max_density()


## Lattice cells the player should have within `within` metres that are not filled yet. The sprint probe
## samples this every frame: the failure D-019 guards against is not a slow frame but bare ground ahead.
func unfilled_within(p: Vector3, within: float) -> int:
	if _centre == NO_CELL:
		return 0
	var count: int = 0
	var at := Vector2(p.x, p.z)
	for o: Vector2i in _offsets:
		var key: Vector2i = _centre + o
		var partial: bool = _partial_slot >= 0 and _slot_key[_partial_slot] == key
		if (not _cells.has(key) or partial) and GrassLattice.cell_centre(key, cell_size).distance_to(at) <= within:
			count += 1
	return count


## Zeroes the fill cost counters so a probe can time one stretch (a sprint) on its own.
func reset_cost_counters() -> void:
	_fill_usec = 0
	_fill_worst_usec = 0
	_fill_frames = 0
	_fill_cells = 0
	_fill_steps = 0
	_fill_over_4 = 0
	_fill_over_8 = 0
	_fill_over_16 = 0
	_fill_worst_unit_usec = 0
	_fill_worst_unit_layer = -1
	_fill_prepare_usec = 0
	_thin_usec = 0
	_thin_worst_usec = 0
	_thin_count = 0
	_fill_hist.resize(HIST_BUCKETS)
	_fill_hist.fill(0)


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
	_fill_pending(p)
	if p.distance_squared_to(_last_thin) > THIN_MOVE * THIN_MOVE:
		var t0: int = Time.get_ticks_usec()
		_update_thinning(p)
		var dt: int = Time.get_ticks_usec() - t0
		_thin_usec += dt
		_thin_worst_usec = maxi(_thin_worst_usec, dt)
		_thin_count += 1


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
	if _partial_slot == slot:
		_partial_slot = -1


# The unit of work is one step of one layer of one cell (W8-G made it a layer, W8-G2 a step of at most
# fill_step_candidates candidates): always one unit, then more while the budget lasts, with
# fill_cells_per_frame capping how many cells may start in a frame. A frame overruns the budget by at
# most the unit that crossed it, so the step size is what bounds the worst frame; a cell's prepare (its
# height and zone grid) is its own unit before the first layer. A cell part-way through keeps _cell
# prepared and the layer's cursor between frames, and counts as unfilled until its last layer is done.
# A layer is thinned for the player at `p` the moment it completes; the whole-lattice pass used to
# rerun on every working frame (W8-G2 measured it at 0.6-0.8 ms, worst 1.4-3.7 ms, as dear as a step)
# and now runs only when the player has moved THIN_MOVE.
func _fill_pending(p: Vector3) -> void:
	if _pending.is_empty() and _partial_slot < 0:
		_first_fill = false
		return
	var t0: int = Time.get_ticks_usec()
	var budget_ms: float = first_fill_budget_ms if _first_fill else fill_budget_ms
	var deadline: int = t0 + int(maxf(0.0, budget_ms) * 1000.0)
	var starts: int = maxi(1, fill_cells_per_frame)
	var completed: int = 0
	var worked: bool = false
	var unit_t0: int = t0
	while true:
		if _partial_slot < 0:
			if starts <= 0 or _pending.is_empty():
				break
			var key: Vector2i = _pending.pop_front()
			if _cells.has(key) or (key - _centre).length() * cell_size > radius + cell_size or _free_count == 0:
				continue
			starts -= 1
			_free_count -= 1
			var slot: int = _free[_free_count]
			_cells[key] = slot
			_slot_key[slot] = key
			_cell.prepare(key, cell_size, _height_sampler, _water,
					clusters_near(Vector2(key) * cell_size, cell_size, _cluster_reach), _cluster_reach, zones)
			_partial_slot = slot
			_partial_layer = 0
			worked = true
			if _layers.is_empty():
				_partial_slot = -1
				completed += 1
			else:
				_layers[0].begin(key, 0, seed_value, _cell)
			var prepared: int = Time.get_ticks_usec()
			_fill_prepare_usec += prepared - unit_t0
			_note_unit(prepared - unit_t0, -1)
			unit_t0 = prepared
			if prepared >= deadline:
				break
			continue
		var l: int = _partial_layer
		var i: int = _partial_slot * _layers.size() + l
		var layer: GrassLayer = _layers[l]
		var done: bool = layer.step(_cell, _slots[_partial_slot][l], _slot_positions[i], _density_filter, _exact_slope, fill_step_candidates)
		worked = true
		_fill_steps += 1
		if done:
			_slot_counts[i] = layer.placed
			_thin_layer(_partial_slot, l, p)
			_partial_layer += 1
			if _partial_layer >= _layers.size():
				_partial_slot = -1
				completed += 1
			else:
				_layers[_partial_layer].begin(_slot_key[_partial_slot], _partial_layer, seed_value, _cell)
		var now: int = Time.get_ticks_usec()
		_note_unit(now - unit_t0, l)
		unit_t0 = now
		if now >= deadline:
			break
	if worked:
		var dt: int = Time.get_ticks_usec() - t0
		_fill_usec += dt
		_fill_worst_usec = maxi(_fill_worst_usec, dt)
		_fill_frames += 1
		_fill_cells += completed
		_fill_hist[mini(dt / HIST_USEC, HIST_BUCKETS - 1)] += 1
		if dt > 4000:
			_fill_over_4 += 1
		if dt > 8000:
			_fill_over_8 += 1
		if dt > 16000:
			_fill_over_16 += 1


func _thin_layer(slot: int, l: int, p: Vector3) -> void:
	var d: float = Vector2(p.x, p.z).distance_to(GrassLattice.cell_centre(_slot_key[slot], cell_size))
	var count: int = _slot_counts[slot * _layers.size() + l]
	_slots[slot][l].multimesh.visible_instance_count = int(float(count) * GrassLattice.thin_factor(d, radius, radius * near_fraction, _layers[l].far_fraction))


func _note_unit(usec: int, layer: int) -> void:
	if usec > _fill_worst_unit_usec:
		_fill_worst_unit_usec = usec
		_fill_worst_unit_layer = layer


## The working-frame cost under which `fraction` (0..1) of working frames fell, to the histogram's
## resolution (the upper edge of the bucket, so never flattering); 0 before any frame has worked.
func fill_percentile_ms(fraction: float) -> float:
	if _fill_frames <= 0 or _fill_hist.size() < HIST_BUCKETS:
		return 0.0
	var need: int = ceili(clampf(fraction, 0.0, 1.0) * float(_fill_frames))
	var seen: int = 0
	for b: int in HIST_BUCKETS:
		seen += _fill_hist[b]
		if seen >= need:
			return float((b + 1) * HIST_USEC) / 1000.0
	return float(_fill_worst_usec) / 1000.0


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
		if _layers[l].is_blade():
			blade_verts += n * _layers[l].vertex_count
	return {"cells": _cells.size(), "pool": _slots.size(), "pending": _pending.size() + (1 if _partial_slot >= 0 else 0), "instances": instance_count(),
		"blade_verts": blade_verts, "layers": _layers.size(), "per_layer": per_layer, "zones": zones != null,
		"fill_frames": _fill_frames, "fill_cells": _fill_cells, "fill_total_ms": float(_fill_usec) / 1000.0,
		"fill_mean_ms": float(_fill_usec) / 1000.0 / float(maxi(1, _fill_frames)), "fill_worst_ms": float(_fill_worst_usec) / 1000.0,
		"fill_p95_ms": fill_percentile_ms(0.95), "fill_over_4ms": _fill_over_4, "fill_over_8ms": _fill_over_8, "fill_over_16ms": _fill_over_16,
		"fill_steps": _fill_steps, "fill_worst_unit_ms": float(_fill_worst_unit_usec) / 1000.0,
		"fill_worst_unit_layer": _layers[_fill_worst_unit_layer].name if _fill_worst_unit_layer >= 0 and _fill_worst_unit_layer < _layers.size() else "prepare",
		"fill_prepare_ms": float(_fill_prepare_usec) / 1000.0,
		"thin_count": _thin_count, "thin_total_ms": float(_thin_usec) / 1000.0, "thin_worst_ms": float(_thin_worst_usec) / 1000.0}


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
