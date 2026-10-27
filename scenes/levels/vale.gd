extends Node3D
## Ashen Vale: the first real area. Composes Terrain, Sky, Forest, LevelDressing, the Mirror Pond's water
## plane and the player on a Heightfield-driven landscape. Everything that touches the ground samples
## the terrain, nothing invents a height. Debug readout behind `debug_toggle` (F3). With the user arg
## `--probe` (tests/test_terrain.gd) it prints machine-readable PROBE lines once the terrain is built and
## the player has settled, then quits -- only when it is the root scene, so main.tscn can load it.

const PROBE_SETTLE_FRAMES := 240
const PROBE_MAX_FRAMES := 1500
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
	_dressing.height_sampler = _terrain.height_at
	_dressing.placement_filter = _prop_allowed
	_dressing.normal_sampler = hf.normal_at
	_dressing.build(LevelDressing.load_data(_dressing.data_path))
	_grass.bind(_terrain, _grass_density, _forest.positions())
	_grass.rebuild()
	_player.global_position = _spawn
	_player.velocity = Vector3.ZERO
	if _game != null:
		_game.state = _game.State.PLAYING
		_game.set_respawn(&"vale", _spawn)
	_probe = OS.get_cmdline_user_args().has("--probe") and get_tree().current_scene == self


func _process(_delta: float) -> void:
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
	_apply_pond_state(hf, true)
	if _flags != null and not _flags.flag_set.is_connected(_on_flag_set):
		_flags.flag_set.connect(_on_flag_set)


func _on_flag_set(id: StringName) -> void:
	if id != DRAINED_FLAG or _drained:
		return
	_drained = true
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


# Density multiplier for Grass: nothing on the paved plateau tops (skirts fade in), nothing up the ridge.
func _grass_density(x: float, z: float) -> float:
	var hf: Heightfield = _terrain.heightfield
	if Vector2(x, z).length() > hf.ridge_inner_radius() - GRASS_RIDGE_MARGIN:
		return 0.0
	if _keep_out != null and _keep_out.blocks(x, z):
		return 0.0
	return GrassLattice.site_factor(x, z, hf.plateaus())


# --- headless probe --------------------------------------------------------------------------------------

func _physics_process(_delta: float) -> void:
	if not _probe or _probe_done:
		return
	_probe_frames += 1
	var ready: bool = _terrain.is_built() and _probe_frames >= PROBE_SETTLE_FRAMES
	if not ready and _probe_frames < PROBE_MAX_FRAMES:
		return
	_probe_done = true
	_print_probe()
	get_tree().quit()


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
	print("PROBE forest trees=%d on_ground=%s" % [_forest.tree_count(), on_ground])
	print("PROBE dressing instances=%d multimeshes=%d colliders=%d" % [
		_dressing.stats()["instances"], _dressing.stats()["multimeshes"], _dressing.stats()["colliders"],
	])
	var grass: Dictionary = _grass.stats()
	var audit: Dictionary = _grass.audit(hf)
	print("PROBE grass cells=%d instances=%d blade_verts=%d underwater=%d steep=%d floating=%d pending=%d layers=%d pool=%d" % [
		grass["cells"], grass["instances"], grass["blade_verts"], audit["underwater"], audit["steep"], audit["floating"],
		grass["pending"], grass["layers"], grass["pool"],
	])
	# CPU time only: headless has no renderer, so this says nothing about draw cost. terrain_build_ms is the
	# wall-clock of the budgeted build across frames; the other _ms figures are what the CPU actually spent.
	print("PROBE cost grass_fill_frames=%d grass_fill_cells=%d grass_fill_mean_ms=%.3f grass_fill_worst_ms=%.3f terrain_build_ms=%d terrain_build_frames=%d terrain_cpu_ms=%.1f terrain_sample_ms=%.1f terrain_mesh_ms=%.1f terrain_collision_ms=%.1f" % [
		grass["fill_frames"], grass["fill_cells"], grass["fill_mean_ms"], grass["fill_worst_ms"],
		stats["build_ms"], stats["build_frames"], stats["build_cpu_ms"], stats["sample_ms"], stats["mesh_ms"], stats["collision_ms"],
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
