extends Node3D
## Ashen Vale: the first real area. Composes Terrain, Sky, Forest, LevelDressing, the Mirror Pond's water
## plane and the player on a Heightfield-driven landscape. Everything that touches the ground samples
## the terrain, nothing invents a height. Debug readout behind `debug_toggle` (F3). With the user arg
## `--probe` (tests/test_terrain.gd) it prints machine-readable PROBE lines once the terrain is built and
## the player has settled, then quits -- only when it is the root scene, so main.tscn can load it.

const PROBE_SETTLE_FRAMES := 240
const PROBE_MAX_FRAMES := 1500
## `--probe-sprint` (W8-G): once the lattice has settled, the player runs at sprint speed along a straight
## line for SPRINT_FRAMES simulated 60 fps frames, Grass is stepped once per frame by hand (its own _process
## is off, so headless frame pacing cannot flatter it), and every frame the lattice cells still unfilled
## within SPRINT_NEAR metres are counted. The line leaves the spawn for the castle hill: meadow, the east
## road and the densest zone in the Vale, all dry and gentle (checked against the heightfield, W8-G report).
const SPRINT_FRAMES := 1500
const SPRINT_FPS := 60.0
const SPRINT_NEAR := 30.0
## The far band too (W8-G2): the grass layer's shader fade starts at 52 m and the far ring is thinned to a
## quarter, so a cell still unfilled inside 50 m is the first that could ever be seen.
const SPRINT_FAR := 50.0
const SPRINT_FROM := Vector2(60.0, 80.0)
const SPRINT_TOWARD := Vector2(300.0, -120.0)
const SPAWN_LIFT := 0.6
const SETTLE_TOLERANCE := 0.5
const TREE_MAX_SLOPE := 38.0
const TREE_SHORE_CLEARANCE := 0.8
const PROP_MAX_SLOPE := 34.0
const RIDGE_MARGIN := 15.0
const WATER_COLOUR := Color(0.33, 0.37, 0.39, 0.62)
## Fitting the Sluice Wheel in the castle sets this; the pond then empties and the basin can be walked into,
## which is the only way down to the Hearth (docs/GAME_DESIGN.md). The wheel itself is found in the Barrens,
## so until that area exists the socket refuses and this never fires in play -- `--probe-drained` sets it.
const DRAINED_FLAG := &"pond_drained"
const WATER_FALL_SEC := 7.0
## Grass stops this far inside the ridge's inner radius; the ridge slopes would kill it anyway.
const GRASS_RIDGE_MARGIN := 30.0
## Built ground, from data/sites/ (D-022). Grass stops this far outside a wall or floor; trees and scattered
## props need more room than a point, so they keep a clearance.
const SITE_KEEP_OUT_MARGIN := 0.3
const TREE_SITE_CLEARANCE := 3.0
const PROP_SITE_CLEARANCE := 1.5
const READOUT := "pos  (%.1f, %.1f, %.1f)\nterrain h  %.2f   slope  %.1f deg   %s\nchunks  %d / %d built   collision  %d   build  %d ms\ntrees  %d   dressing  %d\ngrass  %d cells   %d instances   %d pending\nfps  %d\n\nWASD move   Shift sprint   Space dodge   mouse look   F3 hide this readout"

@onready var _terrain: Terrain = %Terrain
@onready var _forest: Forest = %Forest
@onready var _dressing: LevelDressing = %Dressing
@onready var _grass: Grass = %Grass
@onready var _rivers: Water = get_node_or_null(^"%Rivers") as Water
@onready var _player: PlayerController = %Player
@onready var _label: Label = %DebugLabel
@onready var _water: MeshInstance3D = %Water
@onready var _settlements: Settlements = get_node_or_null(^"%Settlements") as Settlements

var _game: Node
var _flags: Node
var _keep_out: KeepOutMask
var _water_material: StandardMaterial3D
var _drained: bool = false
var _spawn: Vector3 = Vector3.ZERO
var _probe: bool = false
var _probe_frames: int = 0
var _probe_done: bool = false
var _sprint: bool = false
var _sprint_running: bool = false
## `--probe-phases` (W8-G2): profile every grass layer's fill phases through the sprint and print them.
## Its clock reads inflate the cost figures, so it is a separate run from a timing one.
var _phases: bool = false
## The probe frame on which the grass lattice first settled (every cell filled), -1 until it has: a sprint
## waits for it, so the sprint measures running into new grass, not the tail of the spawn fill.
var _settle_frame: int = -1
var _sprint_max_unfilled_far: int = 0
var _sprint_frame: int = 0
var _sprint_max_unfilled: int = 0
var _sprint_unfilled_frames: int = 0
var _sprint_settled: bool = false


func _ready() -> void:
	_game = get_node_or_null(^"/root/Game")
	_label.visible = false
	var hf: Heightfield = _terrain.heightfield
	_spawn = hf.spawn_point() + Vector3.UP * SPAWN_LIFT
	_terrain.begin_build(_spawn)
	_place_water(hf)
	_bind_pond(hf)
	# Before anything scatters: every placement filter below asks this mask what is built where.
	_keep_out = SiteRegistry.keep_out("vale", SITE_KEEP_OUT_MARGIN)
	if _settlements != null:
		_settlements.build(hf)
	_forest.height_sampler = _terrain.height_at
	_forest.placement_filter = _tree_allowed
	_forest.rebuild()
	_forest.track(_player)
	_dressing.height_sampler = _terrain.height_at
	_dressing.placement_filter = _prop_allowed
	_dressing.normal_sampler = hf.normal_at
	_dressing.build(LevelDressing.load_data(_dressing.data_path))
	_grass.bind(_terrain, _grass_density, _forest.positions())
	_grass.rebuild()
	# The respawn point starts at the origin, which in this valley is a hole in the ground over the Hearth
	# chamber. Claim it for the spawn before anything can die.
	if _game != null and _game.respawn_point.is_equal_approx(Vector3.ZERO):
		_game.set_respawn(&"vale", _spawn)
	_player.global_position = _spawn
	_player.velocity = Vector3.ZERO
	if _game != null:
		_game.state = _game.State.PLAYING
		_game.set_respawn(&"vale", _spawn)
	_sprint = OS.get_cmdline_user_args().has("--probe-sprint") and get_tree().current_scene == self
	_phases = _sprint and OS.get_cmdline_user_args().has("--probe-phases")
	_probe = (OS.get_cmdline_user_args().has("--probe") and get_tree().current_scene == self) or _sprint


func _process(_delta: float) -> void:
	_rescue_if_fallen()
	if _sprint_running and _sprint_frame < SPRINT_FRAMES:
		_sprint_step()
	if not _label.visible:
		return
	var p: Vector3 = _player.global_position
	var stats: Dictionary = _terrain.stats()
	var grass: Dictionary = _grass.stats()
	_label.text = READOUT % [
		p.x, p.y, p.z,
		_terrain.height_at(p.x, p.z), _terrain.heightfield.slope_at(p.x, p.z),
		"underwater" if _terrain.heightfield.is_underwater(p.x, p.z) else "",
		stats["built"], stats["chunks"], stats["collision_chunks"], stats["build_ms"],
		_forest.tree_count(), _dressing.stats()["instances"],
		grass["cells"], grass["instances"], grass["pending"],
		Engine.get_frames_per_second(),
	]


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"debug_toggle"):
		_label.visible = not _label.visible


# A flat translucent disc at water level over the pond basin; a real water shader is a later task.
func _place_water(hf: Heightfield) -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2.ONE * hf.pond_falloff() * 2.0
	# The same moving water the river wears (W15). It falls back to flat glass if the shader is missing,
	# because a level that will not load is worse than a level that looks plain.
	var shader: Shader = load("res://scripts/systems/water.gdshader") as Shader
	if shader != null:
		var moving := ShaderMaterial.new()
		moving.shader = shader
		plane.material = moving
		_water_material = null
	else:
		var material := StandardMaterial3D.new()
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.albedo_color = WATER_COLOUR
		material.roughness = 0.08
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
		plane.material = material
		_water_material = material
	_water.mesh = plane
	var c: Vector2 = hf.pond_centre()
	_water.global_position = Vector3(c.x, hf.water_level(), c.y)


# The pond is state, not scenery: it is full until the Sluice Wheel is fitted and empty forever after, and
# a loaded save must come back already empty rather than re-draining in front of the player.
func _bind_pond(hf: Heightfield) -> void:
	_flags = get_node_or_null(^"/root/Flags")
	if OS.get_cmdline_user_args().has("--probe-drained") and _flags != null:
		_flags.set_flag(DRAINED_FLAG)
	_drained = _flags != null and _flags.has(DRAINED_FLAG)
	if _drained and _rivers != null:
		_rivers.drain(DRAINED_FLAG)
	_apply_pond_state(hf, true)
	if _flags != null and not _flags.flag_set.is_connected(_on_flag_set):
		_flags.flag_set.connect(_on_flag_set)


func _on_flag_set(id: StringName) -> void:
	if id != DRAINED_FLAG or _drained:
		return
	_drained = true
	if _rivers != null:
		_rivers.drain(DRAINED_FLAG)
	_apply_pond_state(_terrain.heightfield, false)


## Drained, the disc sinks to the basin floor and fades out, then stops being drawn at all. `instant` is the
## load path: the water left before this session began, so there is nothing to watch.
func _apply_pond_state(hf: Heightfield, instant: bool) -> void:
	if not _drained:
		_water.visible = true
		return
	if instant or not is_inside_tree():
		_water.visible = false
		return
	var c: Vector2 = hf.pond_centre()
	var floor_y: float = hf.height_at(c.x, c.y)
	var tween: Tween = create_tween().set_parallel(true)
	tween.tween_property(_water, ^"global_position", Vector3(c.x, floor_y, c.y), WATER_FALL_SEC) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	if _water_material != null:
		tween.tween_property(_water_material, ^"albedo_color:a", 0.0, WATER_FALL_SEC)
	tween.chain().tween_callback(func() -> void: _water.visible = false)


func pond_drained() -> bool:
	return _drained


func _tree_allowed(x: float, z: float) -> bool:
	var hf: Heightfield = _terrain.heightfield
	if hf.height_at(x, z) < hf.water_level() + TREE_SHORE_CLEARANCE or hf.slope_at(x, z) > TREE_MAX_SLOPE:
		return false
	if Vector2(x, z).length() > hf.ridge_inner_radius() - RIDGE_MARGIN:
		return false
	if _keep_out != null and _keep_out.blocks_near(x, z, TREE_SITE_CLEARANCE):
		return false
	for site: Dictionary in hf.plateaus():
		if Vector2(x, z).distance_to(site["centre"]) < float(site["radius"]) + float(site["blend"]) * 0.5:
			return false
	return true


func _prop_allowed(x: float, z: float) -> bool:
	var hf: Heightfield = _terrain.heightfield
	if _keep_out != null and _keep_out.blocks_near(x, z, PROP_SITE_CLEARANCE):
		return false
	return hf.height_at(x, z) >= hf.water_level() + TREE_SHORE_CLEARANCE * 0.5 and hf.slope_at(x, z) <= PROP_MAX_SLOPE


# Density multiplier for Grass: nothing up the ridge, nothing on built ground or over a terrain hole
# (KeepOutMask, D-022). Everything else grows; how much, how tall and what colour is the zones' call
# (data/grass/zones_vale.json, applied inside Grass). The plateau factor that bared the whole castle hill
# (zero within 118 m of the castle, 81 m of the village) is gone: that was the owner's complaint (W8-G).
func _grass_density(x: float, z: float) -> float:
	var hf: Heightfield = _terrain.heightfield
	if Vector2(x, z).length() > hf.ridge_inner_radius() - GRASS_RIDGE_MARGIN:
		return 0.0
	if _keep_out != null and _keep_out.blocks(x, z):
		return 0.0
	return 1.0


# --- headless probe --------------------------------------------------------------------------------------

func _physics_process(_delta: float) -> void:
	if not _probe or _probe_done:
		return
	_probe_frames += 1
	if _settle_frame < 0:
		var g: Dictionary = _grass.stats()
		if int(g["cells"]) > 0 and int(g["pending"]) == 0:
			_settle_frame = _probe_frames
	# Since W8-G2 the probe also waits (to PROBE_MAX_FRAMES) for the grass lattice to settle, and reports
	# how long that took, instead of printing a snapshot of the spawn fill still in progress.
	var ready: bool = _terrain.is_built() and _probe_frames >= PROBE_SETTLE_FRAMES and _settle_frame >= 0
	if not ready and _probe_frames < PROBE_MAX_FRAMES:
		return
	# The sprint runs in _process, one simulated frame per process frame, and reports when it has run.
	if _sprint:
		if not _sprint_running:
			_begin_sprint()
		if _sprint_frame < SPRINT_FRAMES:
			return
	_probe_done = true
	_print_probe()
	get_tree().quit()


## Anything below this has left the world: the lowest ground in the Vale is the pond floor at about
## -12 m, so -80 m is unreachable by walking. Falling through a terrain hole, a physics tunnel or a bad
## respawn all end here, and all of them end the same way -- put back on solid ground rather than falling
## for ever in the dark, which is what the owner filmed.
const VOID_Y := -80.0


func _rescue_if_fallen() -> void:
	if _player == null or _player.global_position.y > VOID_Y:
		return
	var back: Vector3 = _spawn
	if _game != null and not _game.respawn_point.is_equal_approx(Vector3.ZERO):
		back = _game.respawn_point
	_player.global_position = back + Vector3.UP * 1.0
	_player.velocity = Vector3.ZERO
	push_warning("Vale: the player fell out of the world and was put back at %s" % back)


func _print_probe() -> void:
	var hf: Heightfield = _terrain.heightfield
	var stats: Dictionary = _terrain.stats()
	print("PROBE terrain chunks=%d built=%s build_ms=%d collision_chunks=%d lod_levels=%d chunk_size=%.0f size=%.0f winding_up=%s" % [
		stats["chunks"], stats["finished"], stats["build_ms"], stats["collision_chunks"], stats["lod_levels"],
		stats["chunk_size"], hf.size(), _terrain.first_face_normal().y > 0.0,
	])
	var pond: Vector2 = hf.pond_centre()
	var twin: Heightfield = Heightfield.from_dict(hf.config())
	var deterministic: bool = true
	for p: Vector2 in [pond, Vector2(123.0, -77.0), Vector2(-300.0, 210.0), Vector2(450.0, 450.0)]:
		deterministic = deterministic and is_equal_approx(hf.height_at(p.x, p.y), twin.height_at(p.x, p.y))
	print("PROBE heightfield pond_depth=%.2f ridge_height=%.1f village_flat=%s castle_flat=%s deterministic=%s" % [
		hf.water_level() - hf.height_at(pond.x, pond.y),
		hf.height_at(hf.size() * 0.5, 0.0) - hf.height_at(hf.ridge_inner_radius() * 0.5, 0.0),
		_plateau_flat(hf, 0), _plateau_flat(hf, 1), deterministic,
	])
	# With --probe-drained the flag is set before the first _apply_pond_state, so this reports the LOADED
	# drained state (water gone at once). The seven-second fall animation is not probe-covered: it needs the
	# flag to arrive mid-session, which only the castle socket does.
	# Slope, deliberately not sample_walkable: that also rejects anything under the heightfield's water
	# level, and draining does NOT move that level. The static level still drives where grass and trees may
	# grow, and a basin that has just stopped being a pond must stay bare mud. "Drained" is the flag plus the
	# disc being gone; the ground underneath was always solid and always had collision.
	var pond_floor: float = hf.height_at(pond.x, pond.y)
	var basin_slope: float = hf.slope_at(pond.x, pond.y)
	print("PROBE pond drained=%s water_visible=%s water_y=%.2f basin_floor=%.2f basin_slope=%.1f slope_ok=%s" % [
		_drained, _water.visible, _water.global_position.y, pond_floor, basin_slope,
		basin_slope <= _player.floor_max_angle * 180.0 / PI,
	])
	var p: Vector3 = _player.global_position
	var ground: float = _terrain.height_at(p.x, p.z)
	print("PROBE spawn walkable=%s y=%.3f ground=%.3f settled=%s on_floor=%s" % [
		hf.sample_walkable(_spawn.x, _spawn.z, _player.floor_max_angle * 180.0 / PI), p.y, ground,
		_player.is_on_floor() and absf(p.y - ground) <= SETTLE_TOLERANCE, _player.is_on_floor(),
	])
	var on_ground: bool = true
	for t: Vector3 in _forest.positions():
		var w: Vector3 = _forest.global_position + t
		on_ground = on_ground and absf(w.y - _terrain.height_at(w.x, w.z)) < 0.05
	# The collider pool is the thing a screenshot cannot show: 11,600 trees and only a few hundred of them
	# solid at a time, so what matters is whether the solid ones are the ones the player is standing among.
	# `dealt` is how many bodies landed on a tree and `nearest_solid` how far the nearest of them is.
	var nearest_solid: float = INF
	for body: Node in _forest.get_children():
		if body is StaticBody3D and (body as StaticBody3D).global_position.y > -1000.0:
			nearest_solid = minf(nearest_solid, Vector2(
					(body as StaticBody3D).global_position.x - _player.global_position.x,
					(body as StaticBody3D).global_position.z - _player.global_position.z).length())
	print("PROBE forest trees=%d on_ground=%s pool=%d dealt=%d nearest_solid=%.1f" % [
		_forest.tree_count(), on_ground, _forest.collider_count, _forest.colliders_dealt(),
		nearest_solid if nearest_solid < INF else -1.0,
	])
	print("PROBE dressing instances=%d multimeshes=%d colliders=%d" % [
		_dressing.stats()["instances"], _dressing.stats()["multimeshes"], _dressing.stats()["colliders"],
	])
	var grass: Dictionary = _grass.stats()
	var audit: Dictionary = _grass.audit(hf)
	var per_layer: Dictionary = grass["per_layer"]
	print("PROBE grass cells=%d instances=%d blade_verts=%d underwater=%d steep=%d floating=%d pending=%d layers=%d pool=%d tall=%d flowers=%d zones=%s settle_frames=%d" % [
		grass["cells"], grass["instances"], grass["blade_verts"], audit["underwater"], audit["steep"], audit["floating"],
		grass["pending"], grass["layers"], grass["pool"], per_layer.get("tall_grass", 0), per_layer.get("wildflowers", 0), grass["zones"], _settle_frame,
	])
	# CPU time only: headless has no renderer, so this says nothing about draw cost. terrain_build_ms is the
	# wall-clock of the budgeted build across frames; the other _ms figures are what the CPU actually spent.
	print("PROBE cost grass_fill_frames=%d grass_fill_cells=%d grass_fill_mean_ms=%.3f grass_fill_p95_ms=%.1f grass_fill_worst_ms=%.3f grass_fill_over_4ms=%d grass_fill_over_8ms=%d grass_fill_over_16ms=%d grass_fill_steps=%d grass_fill_worst_unit_ms=%.3f grass_fill_worst_unit_layer=%s grass_fill_prepare_ms=%.1f grass_thin_count=%d grass_thin_total_ms=%.1f grass_thin_worst_ms=%.3f terrain_build_ms=%d terrain_build_frames=%d terrain_cpu_ms=%.1f terrain_sample_ms=%.1f terrain_mesh_ms=%.1f terrain_collision_ms=%.1f" % [
		grass["fill_frames"], grass["fill_cells"], grass["fill_mean_ms"], grass["fill_p95_ms"], grass["fill_worst_ms"],
		grass["fill_over_4ms"], grass["fill_over_8ms"], grass["fill_over_16ms"], grass["fill_steps"],
		grass["fill_worst_unit_ms"], grass["fill_worst_unit_layer"], grass["fill_prepare_ms"],
		grass["thin_count"], grass["thin_total_ms"], grass["thin_worst_ms"],
		stats["build_ms"], stats["build_frames"], stats["build_cpu_ms"], stats["sample_ms"], stats["mesh_ms"], stats["collision_ms"],
	])
	# Where a fill's time goes, per candidate phase, summed over every layer of the sprint (--probe-phases).
	if _phases and GrassLayer.phase_usec.size() >= GrassLayer.Phase.COUNT:
		var parts: PackedStringArray = PackedStringArray()
		var total: float = float(grass["fill_prepare_ms"])
		for k: int in GrassLayer.Phase.COUNT:
			parts.append("%s_ms=%.1f" % [GrassLayer.PHASE_NAMES[k], float(GrassLayer.phase_usec[k]) / 1000.0])
			total += float(GrassLayer.phase_usec[k]) / 1000.0
		print("PROBE phase prepare_ms=%.1f %s profiled_ms=%.1f" % [grass["fill_prepare_ms"], " ".join(parts), total])
	# In a --probe-sprint run the fill counters were zeroed when the sprint began, so the cost line above and
	# this one both describe the sprint alone, not the first fill around the spawn.
	if _sprint:
		print("PROBE sprint frames=%d speed=%.1f distance=%.0f max_unfilled_30m=%d frames_with_unfilled=%d max_unfilled_50m=%d settled_before=%s settle_frames=%d cells_filled=%d fill_frames=%d fill_mean_ms=%.3f fill_p95_ms=%.1f fill_worst_ms=%.3f fill_over_4ms=%d fill_over_8ms=%d fill_over_16ms=%d" % [
			_sprint_frame, _player.sprint_speed, float(_sprint_frame) * _player.sprint_speed / SPRINT_FPS, _sprint_max_unfilled,
			_sprint_unfilled_frames, _sprint_max_unfilled_far, _sprint_settled, _settle_frame, grass["fill_cells"], grass["fill_frames"], grass["fill_mean_ms"], grass["fill_p95_ms"], grass["fill_worst_ms"],
			grass["fill_over_4ms"], grass["fill_over_8ms"], grass["fill_over_16ms"],
		])
	var fixed: int = 0
	for site: Dictionary in SiteRegistry.load_area("vale"):
		if bool(site.get("fixed", false)):
			fixed += 1
	var built: Dictionary = _settlements.stats() if _settlements != null else {"sites": 0, "props": 0, "pieces": 0}
	print("PROBE sites fixed=%d spawned=%d props=%d pieces=%d keepout_cells=%d keepout_obbs=%d" % [
		fixed, built["sites"], built["props"], built["pieces"],
		_keep_out.cell_count() if _keep_out != null else -1, _keep_out.obb_count() if _keep_out != null else -1,
	])
	_print_fires()


## The lit kit (W9-F). `drawing` is how many fires passed their distance cull on the last frame, which is
## what the GPU is actually paying for; `worst_crowd` is the most that could ever be lit at once anywhere
## in the valley, which is the number to watch when more fires are added.
func _print_fires() -> void:
	var fires: Array[Node] = get_tree().get_nodes_in_group(FireLight.GROUP)
	var at: Array[Vector3] = []
	for node: Node in fires:
		if node is Node3D:
			at.append((node as Node3D).global_position)
	var worst: int = 0
	var cull: float = 0.0
	for i: int in range(at.size()):
		var near: int = 1
		for j: int in range(at.size()):
			if i != j and at[i].distance_squared_to(at[j]) < 3600.0:
				near += 1
		worst = maxi(worst, near)
	if not fires.is_empty() and fires[0] is FireLight:
		cull = (fires[0] as FireLight).cull_distance
	var nearest: float = INF
	if _player != null:
		for p: Vector3 in at:
			nearest = minf(nearest, _player.global_position.distance_to(p))
	print("PROBE fires total=%d drawing=%d worst_crowd_60m=%d cull=%.0f nearest_to_spawn=%.1f" % [
		fires.size(), FireLight.lit_count, worst, cull, nearest if nearest < INF else -1.0,
	])


# Grass stops stepping itself so that each simulated frame below is exactly one fill budget, whatever the
# headless frame rate; the counters restart so the cost and sprint lines describe the sprint alone.
func _begin_sprint() -> void:
	_sprint_running = true
	_sprint_settled = int(_grass.stats()["pending"]) == 0
	_grass.set_process(false)
	# The settled lattice round the spawn, before a single sprint frame: the one live-scene snapshot that
	# is the same whatever the schedule, so a scheduling change can show it changed nothing (W8-G2).
	var g: Dictionary = _grass.stats()
	var per_layer: Dictionary = g["per_layer"]
	print("PROBE grass_settled cells=%d instances=%d blade_verts=%d pending=%d tall=%d flowers=%d settle_frames=%d" % [
		g["cells"], g["instances"], g["blade_verts"], g["pending"], per_layer.get("tall_grass", 0), per_layer.get("wildflowers", 0), _settle_frame,
	])
	_grass.reset_cost_counters()
	if _phases:
		GrassLayer.profile = true
		GrassLayer.phase_usec.resize(GrassLayer.Phase.COUNT)
		GrassLayer.phase_usec.fill(0)


# One simulated 60 fps frame of sprinting: place the player on the line, step the lattice once, and count
# the cells within SPRINT_NEAR metres that it has not filled yet -- the ground the player is running into.
func _sprint_step() -> void:
	_sprint_frame += 1
	var dir: Vector2 = (SPRINT_TOWARD - SPRINT_FROM).normalized()
	var at: Vector2 = SPRINT_FROM + dir * float(_sprint_frame) * _player.sprint_speed / SPRINT_FPS
	var p := Vector3(at.x, _terrain.height_at(at.x, at.y) + SPAWN_LIFT, at.y)
	_player.global_position = p
	_player.velocity = Vector3.ZERO
	_grass.step(p)
	var unfilled: int = _grass.unfilled_within(p, SPRINT_NEAR)
	_sprint_max_unfilled = maxi(_sprint_max_unfilled, unfilled)
	_sprint_max_unfilled_far = maxi(_sprint_max_unfilled_far, _grass.unfilled_within(p, SPRINT_FAR))
	if unfilled > 0:
		_sprint_unfilled_frames += 1


func _plateau_flat(hf: Heightfield, index: int) -> bool:
	if index >= hf.plateaus().size():
		return false
	var site: Dictionary = hf.plateaus()[index]
	var c: Vector2 = site["centre"]
	for k: int in 16:
		var p: Vector2 = c + Vector2.from_angle(float(k) * TAU / 16.0) * float(site["radius"]) * 0.95
		if absf(hf.height_at(p.x, p.y) - float(site["height"])) > 0.05:
			return false
	return true
