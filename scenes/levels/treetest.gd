extends Node3D
## Forest inspection level: ground, a Forest node, the day/night sky and a free-flying camera.
## Keys: WASD/QE fly (Shift fast), hold right mouse to look, 1-4 single-archetype forests, 0 mixed,
## R rebuild with the next seed, Esc quit. With the user arg `--probe` (tests/test_forest.gd) it prints
## machine-readable PROBE lines and quits. Launch by path; greybox stays the main scene.

const FLY_SPEED := 14.0
const FAST_MULTIPLIER := 4.0
const LOOK_SENSITIVITY := 0.0025
const LABEL_EVERY_FRAMES := 15
const READOUT := "trees %d   seed %d   mode %s\ntrunk verts %d   card verts %d (lod1 %d)   multimeshes %d   colliders %d\ndraw calls %d   primitives %d   objects %d\n\nWASD/QE fly  Shift fast  RMB look  1-4 archetype  0 mixed  R reseed  Esc quit"
const PROBE_FOREST_FRAME := 3

@onready var _forest: Forest = %Forest
@onready var _camera: Camera3D = %Camera
@onready var _label: Label = %DebugLabel

var _mixed: Dictionary = {}
var _mode: String = "mixed"
var _probe: bool = false
var _frame: int = 0
var _label_tick: int = 0
var _look: Vector2 = Vector2.ZERO


func _ready() -> void:
	var game: Node = get_node_or_null(^"/root/Game")
	if game != null:
		game.state = game.State.PLAYING
	_mixed = _forest.archetype_mix.duplicate()
	_look = Vector2(_camera.rotation.y, _camera.rotation.x)
	_probe = OS.get_cmdline_user_args().has("--probe")
	if _probe:
		_probe_treegen()


func _process(delta: float) -> void:
	if _probe:
		_probe_frame()
		return
	_fly(delta)
	_label_tick += 1
	if _label_tick >= LABEL_EVERY_FRAMES:
		_label_tick = 0
		_update_label()


func _fly(delta: float) -> void:
	var dir := Vector3.ZERO
	if Input.is_key_pressed(KEY_W):
		dir -= _camera.transform.basis.z
	if Input.is_key_pressed(KEY_S):
		dir += _camera.transform.basis.z
	if Input.is_key_pressed(KEY_A):
		dir -= _camera.transform.basis.x
	if Input.is_key_pressed(KEY_D):
		dir += _camera.transform.basis.x
	if Input.is_key_pressed(KEY_E):
		dir += Vector3.UP
	if Input.is_key_pressed(KEY_Q):
		dir -= Vector3.UP
	var speed: float = FLY_SPEED * (FAST_MULTIPLIER if Input.is_key_pressed(KEY_SHIFT) else 1.0)
	_camera.position += dir.normalized() * speed * delta


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_RIGHT:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if event.is_pressed() else Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_look -= (event as InputEventMouseMotion).relative * LOOK_SENSITIVITY
		_look.y = clampf(_look.y, -1.5, 1.5)
		_camera.rotation = Vector3(_look.y, _look.x, 0.0)
	elif event is InputEventKey and event.is_pressed() and not event.is_echo():
		_key((event as InputEventKey).keycode)


func _key(keycode: Key) -> void:
	var names: PackedStringArray = TreeGen.archetypes()
	match keycode:
		KEY_ESCAPE:
			get_tree().quit()
		KEY_R:
			_forest.seed_value += 1
			_forest.rebuild()
		KEY_0:
			_set_mode("mixed", _mixed)
		KEY_1, KEY_2, KEY_3, KEY_4:
			var i: int = keycode - KEY_1
			if i < names.size():
				_set_mode(names[i], {names[i]: 1.0})


func _set_mode(mode: String, mix: Dictionary) -> void:
	_mode = mode
	_forest.archetype_mix = mix
	_forest.rebuild()


func _update_label() -> void:
	var s: Dictionary = _forest.stats()
	_label.text = READOUT % [
		_forest.tree_count(), _forest.seed_value, _mode,
		int(s["trunk_vertices"]), int(s["card_vertices"]), int(s["card_vertices_lod1"]),
		int(s["multimeshes"]), int(s["colliders"]),
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME),
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME),
	]


func _probe_treegen() -> void:
	for archetype: String in TreeGen.archetypes():
		var p: Dictionary = TreeGen.params_for(archetype)
		var a: Dictionary = TreeGen.build(p, 1234)
		var b: Dictionary = TreeGen.build(p, 1234)
		var same: bool = _arrays(a["trunk"]) == _arrays(b["trunk"]) and _arrays(a["cards"]) == _arrays(b["cards"])
		print("PROBE treegen archetype=%s trunk_verts=%d card_verts=%d height=%.3f radius=%.3f deterministic=%s" % [
			archetype, _verts(a["trunk"]), _verts(a["cards"]), float(a["height"]), float(a["radius"]), same])


## A few frames in so RenderingServer counters reflect a drawn frame (they stay 0 under --headless).
func _probe_frame() -> void:
	_frame += 1
	if _frame == PROBE_FOREST_FRAME:
		var s: Dictionary = _forest.stats()
		var first_hash: int = _forest.layout_hash()
		print("PROBE forest trees=%d count=%d trunk_verts=%d card_verts=%d draw_calls=%d primitives=%d objects=%d multimeshes=%d colliders=%d min_dist=%.3f clearing=%.1f layout_hash=%d" % [
			_forest.tree_count(), _forest.count, int(s["trunk_vertices"]), int(s["card_vertices"]),
			RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
			RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME),
			RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME),
			int(s["multimeshes"]), int(s["colliders"]), _min_distance(), _forest.clearing_radius, first_hash])
		_forest.rebuild()
		var second_hash: int = _forest.layout_hash()
		print("PROBE forest_repeat layout_hash=%d same=%s" % [second_hash, first_hash == second_hash])
		_forest.seed_value += 1
		_forest.rebuild()
		print("PROBE forest_reseed layout_hash=%d differs=%s" % [_forest.layout_hash(), _forest.layout_hash() != first_hash])
	elif _frame > PROBE_FOREST_FRAME:
		get_tree().quit()


func _min_distance() -> float:
	var best: float = INF
	for p: Vector3 in _forest.positions():
		best = minf(best, Vector2(p.x, p.z).length())
	return best


static func _arrays(mesh: ArrayMesh) -> Array:
	return mesh.surface_get_arrays(0) if mesh.get_surface_count() > 0 else []


static func _verts(mesh: ArrayMesh) -> int:
	return (mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() if mesh.get_surface_count() > 0 else 0
