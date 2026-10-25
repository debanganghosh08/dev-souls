extends Node3D
## Structure inspection level: flat ground, Castle Morrow and the broken village side by side, a free-flying
## camera and a readout of mesh/collision counts. Keys: WASD/QE fly (Shift fast), hold RMB to look,
## 1 gatehouse  2 chapel  3 crypt  4 village  5 keep, Esc quit. With the user arg `--probe`
## (tests/test_structures.gd) it prints machine-readable PROBE lines, rings the bells through the real
## Bell/BellPuzzle nodes and quits. Launch by path; main.tscn stays the main scene.

const FLY_SPEED := 12.0
const FAST_MULTIPLIER := 4.0
const LOOK_SENSITIVITY := 0.0025
const LABEL_EVERY_FRAMES := 15
const PROBE_FRAME := 3
const AREA_FILE := "res://data/areas/vale.json"
const TELEPORTS: Dictionary = {
	KEY_1: ^"Castle/Landmarks/Gatehouse", KEY_2: ^"Castle/Landmarks/Chapel", KEY_3: ^"Castle/Landmarks/Crypt",
	KEY_4: ^"Village/Landmarks/Village", KEY_5: ^"Castle/Landmarks/Keep",
}
const READOUT := "fps %d   cam (%.1f, %.1f, %.1f)\ncastle  meshes %d  multimeshes %d  colliders %d  verts %d  bells %d  interactables %d\nvillage meshes %d  multimeshes %d  colliders %d  verts %d  shacks %d  props %d  interactables %d\nbells  progress %s  resets %d  solved %s\n\nWASD/QE fly  Shift fast  RMB look  1 gate 2 chapel 3 crypt 4 village 5 keep  Esc quit"

@onready var _camera: Camera3D = %Camera
@onready var _label: Label = %DebugLabel
@onready var _castle: Node3D = $Castle
@onready var _village: Node3D = $Village

var _probe: bool = false
var _frame: int = 0
var _label_tick: int = 0
var _look: Vector2 = Vector2.ZERO


func _ready() -> void:
	var game: Node = get_node_or_null(^"/root/Game")
	if game != null:
		game.state = game.State.PLAYING
	_look = Vector2(_camera.rotation.y, _camera.rotation.x)
	_probe = OS.get_cmdline_user_args().has("--probe") and get_tree().current_scene == self
	if _probe:
		# Ringing a bell autosaves; point SaveGame at a throwaway slot so a probe never touches the real one.
		var save: Node = get_node_or_null(^"/root/SaveGame")
		if save != null:
			save.use_slot_path("user://probe_structures.json")


func _process(delta: float) -> void:
	if _probe:
		_frame += 1
		if _frame == PROBE_FRAME:
			_run_probe()
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
		var key: Key = (event as InputEventKey).keycode
		if key == KEY_ESCAPE:
			get_tree().quit()
		elif TELEPORTS.has(key):
			var mark: Node3D = get_node_or_null(TELEPORTS[key]) as Node3D
			if mark != null:
				_camera.global_position = mark.global_position


func _update_label() -> void:
	var c: Dictionary = scene_counts(_castle)
	var v: Dictionary = scene_counts(_village)
	var puzzle: BellPuzzle = _castle.get_node(^"BellPuzzle") as BellPuzzle
	var p: Vector3 = _camera.global_position
	_label.text = READOUT % [
		Engine.get_frames_per_second(), p.x, p.y, p.z,
		c["meshes"], c["multimeshes"], c["colliders"], c["verts"], c["bells"], c["interactables"],
		v["meshes"], v["multimeshes"], v["colliders"], v["verts"], _shack_count(), _prop_count(), v["interactables"],
		str(puzzle.progress), puzzle.resets, puzzle.is_solved(),
	]


## Walks a scene: drawn meshes, world-layer collision shapes, vertices (MultiMesh counted per instance),
## bells and interactables. Pure counting, so the test suite can trust it under the null renderer.
static func scene_counts(root: Node) -> Dictionary:
	var out: Dictionary = {"meshes": 0, "multimeshes": 0, "colliders": 0, "verts": 0, "bells": 0, "interactables": 0}
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		stack.append_array(node.get_children())
		if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
			out["meshes"] += 1
			out["verts"] += mesh_vertices((node as MeshInstance3D).mesh)
		elif node is MultiMeshInstance3D and (node as MultiMeshInstance3D).multimesh != null:
			var mm: MultiMesh = (node as MultiMeshInstance3D).multimesh
			out["multimeshes"] += 1
			out["verts"] += mesh_vertices(mm.mesh) * mm.instance_count
		elif node is CollisionShape3D and (node as CollisionShape3D).shape != null:
			var body: CollisionObject3D = node.get_parent() as CollisionObject3D
			if body != null and body is PhysicsBody3D and body.collision_layer & 1 != 0:
				out["colliders"] += 1
		if node is Bell:
			out["bells"] += 1
		if node is Interactable:
			out["interactables"] += 1
	return out


static func mesh_vertices(mesh: Mesh) -> int:
	if mesh == null:
		return 0
	var total: int = 0
	for s: int in range(mesh.get_surface_count()):
		var arrays: Array = mesh.surface_get_arrays(s)
		if arrays.size() > Mesh.ARRAY_VERTEX and arrays[Mesh.ARRAY_VERTEX] != null:
			total += (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	return total


static func plateau_radius(name: String) -> float:
	var json := JSON.new()
	if not FileAccess.file_exists(AREA_FILE) or json.parse(FileAccess.get_file_as_string(AREA_FILE)) != OK:
		return 0.0
	for p: Variant in (json.data as Dictionary).get("plateaus", []):
		if p is Dictionary and str(p.get("name", "")) == name:
			return float(p.get("radius", 0.0))
	return 0.0


func _shack_count() -> int:
	return (_village.get_node(^"Builder") as StructureBuilder).group_names("shack_").size()


func _prop_count() -> int:
	return _village.get_node(^"Props").get_child_count()


func _run_probe() -> void:
	var c: Dictionary = scene_counts(_castle)
	var v: Dictionary = scene_counts(_village)
	var cb: StructureBuilder = _castle.get_node(^"Builder") as StructureBuilder
	var vb: StructureBuilder = _village.get_node(^"Builder") as StructureBuilder
	# verts counts every drawn vertex including the photoscan props; kit_verts is the kit geometry alone.
	print("PROBE castle meshes=%d colliders=%d verts=%d bells=%d interactables=%d multimeshes=%d pieces=%d instances=%d kit_verts=%d" % [
		c["meshes"], c["colliders"], c["verts"], c["bells"], c["interactables"], c["multimeshes"],
		cb.stats()["pieces"], cb.stats()["instances"], cb.stats()["verts"]])
	print("PROBE village shacks=%d props=%d interactables=%d meshes=%d colliders=%d verts=%d multimeshes=%d kit_verts=%d" % [
		_shack_count(), _prop_count(), v["interactables"], v["meshes"], v["colliders"], v["verts"], v["multimeshes"], vb.stats()["verts"]])
	var cr: float = cb.footprint_radius()
	var vr: float = vb.footprint_radius()
	var cp: float = plateau_radius("castle")
	var vp: float = plateau_radius("village")
	print("PROBE fit castle_radius=%.1f castle_plateau=%.0f village_radius=%.1f village_plateau=%.0f fits=%s" % [
		cr, cp, vr, vp, cr <= cp and vr <= vp and cp > 0.0 and vp > 0.0])
	_probe_bells()
	var save: Node = get_node_or_null(^"/root/SaveGame")
	if save != null:
		save.delete()
	get_tree().quit()


# Through the real nodes: one wrong bell first (a reset), then the data order, then the order again.
func _probe_bells() -> void:
	var puzzle: BellPuzzle = _castle.get_node(^"BellPuzzle") as BellPuzzle
	var by_index: Dictionary = {}
	for bell: Bell in BellPuzzle.find_bells(_castle.get_node(^"Bells")):
		by_index[bell.index] = bell
	var wrong_first: bool = false
	if puzzle.is_configured():
		for idx: Variant in by_index:
			if int(idx) != puzzle.required[0]:
				(by_index[idx] as Bell).interact(self)
				wrong_first = puzzle.resets == 1 and puzzle.progress.is_empty()
				break
		for idx: int in puzzle.required:
			if by_index.has(idx):
				(by_index[idx] as Bell).interact(self)
	var resets_after_solve: int = puzzle.resets
	for idx: int in puzzle.required:
		if by_index.has(idx):
			(by_index[idx] as Bell).interact(self)
	var chapel: ChapelBell = _castle.get_node(^"ChapelBell") as ChapelBell
	print("PROBE bellpuzzle solved=%s resets=%d kindling_revealed=%s configured=%s order=%s wrong_first=%s repeat_changed=%s bell_fallen=%s" % [
		puzzle.is_solved(), puzzle.resets, puzzle.reward_revealed(), puzzle.is_configured(),
		",".join(PackedStringArray(puzzle.required.map(func(i: int) -> String: return str(i)))),
		wrong_first, puzzle.resets != resets_after_solve, chapel.is_fallen()])
