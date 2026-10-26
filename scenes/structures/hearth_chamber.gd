extends Node3D
class_name HearthChamber
## The Hearth's chamber under the Mirror Pond, and the one piece of it that is state: the pond seal. The
## water in scenes/levels/vale.gd is a bare mesh with no collision, so the player can walk down into the
## basin long before it is drained, and the terrain hole over the stairwell would be a pit (D-014). The
## seal is the stone lid over the stair opening, built by the StructureBuilder as the layout piece named
## `seal_piece` so it wears the same stone and the same collision as the apron around it, and this script
## removes it when the pond drains. That makes it the real gate on the endgame: the Hearth's own
## `requires_flag` and the lid are keyed to the same flag, read from data/hearth.json, so they cannot
## disagree.
##
## A loaded save with the flag already set must come back with no lid from the first frame, so the state
## is applied once in _ready and then kept live through Flags.flag_set. The Flags autoload is looked up by
## path and injectable (`_inject`), because the test runner has none; with no Flags at all the lid stays,
## which is the safe failure.

@export var builder_path: NodePath = ^"Builder"
@export var seal_piece: String = "pond_seal"

var _flags: Node
var _builder: StructureBuilder
var _drained_flag: StringName = &""


func _ready() -> void:
	_builder = get_node_or_null(builder_path) as StructureBuilder
	if _flags == null:
		_flags = get_node_or_null(^"/root/Flags")
	bind()


func _inject(flags: Node) -> void:
	_flags = flags


## Reads the gate flag, applies the current state and listens for the live change. Public so a test can
## drive it without a tree (the builder is built here if _ready never ran for it).
func bind() -> void:
	if _builder == null:
		_builder = get_node_or_null(builder_path) as StructureBuilder
	if _builder != null and not _builder.is_built():
		_builder.build()
	_drained_flag = StringName(str(Hearth.load_from().get("requires_flag", "")))
	_apply()
	if _flags != null and _flags.has_signal(&"flag_set") and not _flags.flag_set.is_connected(_on_flag_set):
		_flags.flag_set.connect(_on_flag_set)


func drained_flag() -> StringName:
	return _drained_flag


func seal_node() -> Node:
	return _builder.get_node_or_null(seal_piece) if _builder != null else null


func is_sealed() -> bool:
	return seal_node() != null


func _on_flag_set(id: StringName) -> void:
	if id == _drained_flag:
		_apply()


# An empty gate flag means the Hearth is always reachable (a test level or debug run), so there is no lid
# to keep either. Removal is final: the water never comes back, and a freed node cannot be collided with.
func _apply() -> void:
	var drained: bool = _drained_flag == &"" or (_flags != null and _flags.has(_drained_flag))
	if not drained:
		return
	var seal: Node = seal_node()
	if seal == null:
		return
	seal.get_parent().remove_child(seal)
	if is_inside_tree():
		seal.queue_free()
	else:
		seal.free()
