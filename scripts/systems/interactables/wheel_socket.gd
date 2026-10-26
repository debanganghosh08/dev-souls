extends Interactable
class_name WheelSocket
## A pair of uprights with an empty axle between them, waiting for a wheel. Fitting the Sluice Wheel here is
## how the Mirror Pond is drained (docs/GAME_DESIGN.md), which is the one thing that opens the way down to
## the Hearth.
##
## The base class already does all the gating -- it refuses without `required_item`, consumes the item, sets
## `sets_flag` and refuses a second use through `once_flag` -- so this adds only what can be seen: the wheel
## appears on the axle and turns once. Loading a save where the flag is already set shows the wheel in place
## and unturned, because the water left long before this session started.

const TURN_DEG := 300.0
const TURN_SEC := 2.2

var _wheel: Node3D
var _fitted: bool = false


func _ready() -> void:
	super()
	_wheel = get_node_or_null(^"%Wheel") as Node3D
	_fitted = sets_flag != &"" and _has_flag(sets_flag)
	if _wheel != null:
		_wheel.visible = _fitted


func is_fitted() -> bool:
	return _fitted


func _on_interact(_who: Node) -> void:
	_fitted = true
	if _wheel == null:
		return
	_wheel.visible = true
	# The uprights stand either side of the axle, so the axle runs along Z and the wheel turns about it.
	# _pose animates in a live tree and snaps when there is none, which is what tests and a spent-on-load
	# socket both need.
	_pose(_wheel, &"rotation_degrees", Vector3(0.0, 0.0, TURN_DEG), TURN_SEC)
