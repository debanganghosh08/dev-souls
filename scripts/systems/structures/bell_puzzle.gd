class_name BellPuzzle
extends Node
## Ring the castle bells in the order the keepers were laid down (data/puzzles/vale.json) and the chapel bell
## falls, baring the reward in its bell-bed. The sequence rule is the pure static advance() so it can be
## tested without a scene; this node only wires Bells to it, keeps score and drives the drop.
## Reset-on-wrong-ring rule: any ring that is not the next expected bell wipes progress (no partial credit),
## but that same ring is then judged as a fresh first ring, so 2,2,0,1 still solves [2,0,1] without the
## player having to "unring" anything. Repeating the order after solving does nothing.

signal progress_changed(progress: Array)
signal sequence_reset(rung: int)
signal solved()

const DEFAULT_PATH := "res://data/puzzles/vale.json"
const DROP_SECONDS := 1.4

@export_file("*.json") var puzzle_path: String = DEFAULT_PATH
@export var puzzle_key: String = "bells"
@export var bells_root: NodePath
@export var chapel_bell: NodePath
@export var reward: NodePath
@export var solved_flag: StringName = &"vale_bells_rung"
## Sound hook for a wrong ring: assign a stream and give this node an AudioStreamPlayer3D child "ResetCue".
@export var reset_cue: AudioStream

var required: Array[int] = []
var progress: Array[int] = []
var resets: int = 0

var _solved: bool = false
var _flags: Node
var _cue: AudioStreamPlayer3D


func _ready() -> void:
	if _flags == null:
		_flags = get_node_or_null(^"/root/Flags")
	configure(load_config(puzzle_path, puzzle_key))
	_cue = get_node_or_null(^"ResetCue") as AudioStreamPlayer3D
	var root: Node = get_node_or_null(bells_root)
	if root != null:
		for bell: Bell in find_bells(root):
			bell.rung.connect(on_bell_rung)
	if _flags != null and _flags.has(solved_flag):
		_apply_solved(0.0)


func _inject(flags: Node) -> void:
	_flags = flags


## Takes the puzzle's sub-dictionary from data; an empty or malformed one leaves the puzzle unsolvable
## (required stays empty) instead of crashing or inventing an order.
func configure(config: Dictionary) -> void:
	required = parse_required(config)
	if config.has("solved_flag") and str(config["solved_flag"]) != "":
		solved_flag = StringName(str(config["solved_flag"]))
	progress.clear()


func is_configured() -> bool:
	return not required.is_empty()


func is_solved() -> bool:
	return _solved


func reward_revealed() -> bool:
	var node: Node = get_node_or_null(reward)
	return node != null and node is Node3D and (node as Node3D).visible


func on_bell_rung(index: int) -> void:
	if _solved:
		return
	var result: Dictionary = advance(progress, required, index)
	progress.assign(result["progress"])
	if result["reset"]:
		resets += 1
		sequence_reset.emit(index)
		_play_reset_cue()
	progress_changed.emit(progress.duplicate())
	if result["completed"]:
		_solve()


## Pure sequence rule. Returns {"progress": Array, "completed": bool, "reset": bool}. Never mutates its inputs.
static func advance(progress_in: Array, required_in: Array, rung: int) -> Dictionary:
	var out: Dictionary = {"progress": [], "completed": false, "reset": false}
	if required_in.is_empty():
		return out
	var expected: int = int(required_in[progress_in.size()]) if progress_in.size() < required_in.size() else -1
	if rung == expected:
		var next: Array = progress_in.duplicate()
		next.append(rung)
		out["progress"] = next
		out["completed"] = next.size() == required_in.size()
		return out
	out["reset"] = true
	if rung == int(required_in[0]):
		out["progress"] = [rung]
		out["completed"] = required_in.size() == 1
	return out


## The `required_order` list of a puzzle entry, kept only if every element is a whole number.
static func parse_required(config: Dictionary) -> Array[int]:
	var out: Array[int] = []
	var raw: Variant = config.get("required_order", null)
	if not raw is Array:
		return out
	for v: Variant in raw:
		if (v is int) or (v is float and is_equal_approx(float(v), roundf(float(v)))):
			out.append(int(v))
		else:
			return []
	return out


## Reads one puzzle's entry from a puzzles file. Missing file, bad JSON or a missing key give {} (warned, no crash).
static func load_config(path: String, key: String) -> Dictionary:
	if path == "" or not FileAccess.file_exists(path):
		push_warning("BellPuzzle: %s missing; the bells will not solve" % path)
		return {}
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(path)) != OK or not json.data is Dictionary:
		push_warning("BellPuzzle: %s is not a JSON object; the bells will not solve" % path)
		return {}
	var data: Dictionary = json.data
	return data[key] if data.has(key) and data[key] is Dictionary else {}


static func find_bells(root: Node) -> Array[Bell]:
	var out: Array[Bell] = []
	if root is Bell:
		out.append(root)
	for child: Node in root.get_children():
		out.append_array(find_bells(child))
	return out


func _solve() -> void:
	_solved = true
	if _flags != null:
		_flags.set_flag(solved_flag)
	_apply_solved(DROP_SECONDS)
	solved.emit()


func _apply_solved(seconds: float) -> void:
	_solved = true
	var bell: Node = get_node_or_null(chapel_bell)
	if bell != null and bell.has_method("drop"):
		bell.call("drop", seconds)
	var prize: Node = get_node_or_null(reward)
	if prize is Node3D:
		(prize as Node3D).visible = true
	if prize is Area3D:
		(prize as Area3D).monitorable = true


func _play_reset_cue() -> void:
	if _cue != null and reset_cue != null and is_inside_tree():
		_cue.stream = reset_cue
		_cue.play()
