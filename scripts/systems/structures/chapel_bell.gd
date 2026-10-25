class_name ChapelBell
extends Node3D
## The hero bell hanging in the chapel tower. Not interactable: BellPuzzle calls drop() and it falls from its
## beam onto the bell-bed below, tipping aside so the reward hidden there is reachable. The kit builds its
## bronze mesh and collider at load, both hung from the %BellBody pivot (the crown) so the fall is one tween.

@export var radius: float = 0.7
@export var height: float = 0.95
## Where the pivot comes to rest, local to this node, and how far the bell rolls onto its side.
@export var landing: Vector3 = Vector3(1.1, 0.55, 0.0)
@export var landing_tilt_deg: float = 78.0

var _fallen: bool = false
var _body: Node3D


func _ready() -> void:
	_body = get_node_or_null(^"%BellBody") as Node3D
	if _body != null and _body.get_child_count() == 0:
		var mesh: Node3D = StructureKit.make_node(StructureKit.bell(radius, height, "bronze"), "BellMesh")
		mesh.position = Vector3(0.0, -height * 1.06, 0.0)
		_body.add_child(mesh)


func is_fallen() -> bool:
	return _fallen


func drop(seconds: float) -> void:
	_fallen = true
	if _body == null:
		return
	var target_rot := Vector3(0.0, 0.0, landing_tilt_deg)
	if seconds <= 0.0 or not is_inside_tree():
		_body.position = landing
		_body.rotation_degrees = target_rot
		return
	var tween: Tween = create_tween().set_parallel(true)
	tween.tween_property(_body, ^"position", landing, seconds).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_property(_body, ^"rotation_degrees", target_rot, seconds).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
