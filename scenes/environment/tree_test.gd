extends Node3D
## One tree of every TreeGen archetype in a row, for side-by-side shape comparison under sky.tscn.

const SPACING := 12.0
const SEED_BASE := 7


func _ready() -> void:
	var names: PackedStringArray = TreeGen.archetypes()
	var x: float = -SPACING * float(names.size() - 1) * 0.5
	for i: int in names.size():
		var archetype: String = names[i]
		var tree: Dictionary = TreeGen.build(TreeGen.params_for(archetype), SEED_BASE + i)
		var root := Node3D.new()
		root.name = archetype.capitalize()
		root.position = Vector3(x + SPACING * float(i), 0.0, 0.0)
		add_child(root)
		_add_part(root, "Trunk", tree["trunk"], TreeMaterials.bark_for(archetype))
		_add_part(root, "Cards", tree["cards"], TreeMaterials.cards_for(archetype))


func _add_part(parent: Node3D, part_name: String, mesh: ArrayMesh, material: Material) -> void:
	if mesh.get_surface_count() == 0:
		return
	mesh.surface_set_material(0, material)
	var mi := MeshInstance3D.new()
	mi.name = part_name
	mi.mesh = mesh
	parent.add_child(mi)
