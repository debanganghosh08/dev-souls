extends Interactable
class_name Bell
## A ringable bell. Never spent (no once_flag): it swings its %BellBody pivot and reports its index to
## whoever listens (BellPuzzle). The bronze mesh is built by the kit at load so the scene holds no binary.

signal rung(index: int)

const SWING_DEG := 26.0
const SWING_SEC := 0.32
const SWINGS := 3

@export var index: int = 0
@export var radius: float = 0.32
@export var height: float = 0.48

var _body: Node3D


func _ready() -> void:
	if prompt == "Examine":
		prompt = "Ring"
	super()
	_body = get_node_or_null(^"%BellBody") as Node3D
	var holder: MeshInstance3D = get_node_or_null(^"%BellMesh") as MeshInstance3D
	if holder != null and holder.mesh == null:
		holder.mesh = StructureKit.bell(radius, height, "bronze")["mesh"]
		# The pivot is the crown; the kit's bell stands on its mouth, so hang it below the pivot.
		holder.position = Vector3(0.0, -height * 1.06, 0.0)


func _on_interact(_who: Node) -> void:
	_swing()
	rung.emit(index)


func _swing() -> void:
	if _body == null or not is_inside_tree():
		return
	var tween: Tween = create_tween()
	for i: int in range(SWINGS):
		var amp: float = SWING_DEG * (1.0 - float(i) / float(SWINGS))
		tween.tween_property(_body, ^"rotation_degrees:z", amp, SWING_SEC).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		tween.tween_property(_body, ^"rotation_degrees:z", -amp, SWING_SEC * 2.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(_body, ^"rotation_degrees:z", 0.0, SWING_SEC).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
