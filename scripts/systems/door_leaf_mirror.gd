extends Node3D
class_name DoorLeafMirror
## The second leaf of a double door. Door only swings %Leaf, so this node copies that yaw, negated, every
## frame and both leaves open together without touching door.gd. Purely visual: %Blocker stays the only
## collider and nothing here is interactable.

@export var source: NodePath

var _source: Node3D


func _ready() -> void:
	_source = get_node_or_null(source) as Node3D
	set_process(_source != null)
	if _source != null:
		rotation.y = mirrored_yaw(_source.rotation.y)


func _process(_delta: float) -> void:
	rotation.y = mirrored_yaw(_source.rotation.y)


static func mirrored_yaw(leaf_yaw: float) -> float:
	return -leaf_yaw
