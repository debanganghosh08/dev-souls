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
## Grass stops this far inside the ridge's inner radius; the ridge slopes would kill it anyway.
const GRASS_RIDGE_MARGIN := 30.0
const READOUT := "pos  (%.1f, %.1f, %.1f)\nterrain h  %.2f   slope  %.1f deg   %s\nchunks  %d / %d built   collision  %d   build  %d ms\ntrees  %d   dressing  %d\ngrass  %d cells   %d instances   %d pending\nfps  %d\n\nWASD move   Shift sprint   Space dodge   mouse look   F3 hide this readout"

@onready var _terrain: Terrain = %Terrain
@onready var _forest: Forest = %Forest
@onready var _dressing: LevelDressing = %Dressing
@onready var _grass: Grass = %Grass
@onready var _player: PlayerController = %Player
@onready var _label: Label = %DebugLabel
@onready var _water: MeshInstance3D = %Water

var _game: Node
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
	_water.mesh = plane
	var c: Vector2 = hf.pond_centre()
	_water.global_position = Vector3(c.x, hf.water_level(), c.y)


func _tree_allowed(x: float, z: float) -> bool:
	var hf: Heightfield = _terrain.heightfield
	if hf.height_at(x, z) < hf.water_level() + TREE_SHORE_CLEARANCE or hf.slope_at(x, z) > TREE_MAX_SLOPE:
		return false
	if Vector2(x, z).length() > hf.ridge_inner_radius() - RIDGE_MARGIN:
		return false
	for site: Dictionary in hf.plateaus():
		if Vector2(x, z).distance_to(site["centre"]) < float(site["radius"]) + float(site["blend"]) * 0.5:
			return false
	return true


func _prop_allowed(x: float, z: float) -> bool:
	var hf: Heightfield = _terrain.heightfield
	return hf.height_at(x, z) >= hf.water_level() + TREE_SHORE_CLEARANCE * 0.5 and hf.slope_at(x, z) <= PROP_MAX_SLOPE


# Density multiplier for Grass: nothing on the paved plateau tops (skirts fade in), nothing up the ridge.
func _grass_density(x: float, z: float) -> float:
	var hf: Heightfield = _terrain.heightfield
	if Vector2(x, z).length() > hf.ridge_inner_radius() - GRASS_RIDGE_MARGIN:
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
