extends "res://tests/test_case.gd"
## The art swap and the set dressing. In-process: every prop scene still carries its script, collider and
## %-unique nodes with the real meshes wired (and the hidden duplicate parts actually hidden); the creature
## scenes wear the real models; the dressing JSON and LevelDressing's pure helpers; a full build() placing
## nothing in the pit or on the probe routes. Live: a child greybox.tscn --probe run must print the nine
## original PROBE lines in their original order plus the new perf and dressing lines.

const GREYBOX := "res://scenes/levels/greybox.tscn"
const DRESSING := "res://data/dressing/greybox.json"
const PROBE_FRAME_CAP := "900"
const ORIGINAL_PROBES: Array[String] = [
	"PROBE landed", "PROBE stairs", "PROBE focus", "PROBE chest", "PROBE door", "PROBE combat",
	"PROBE creature kind=deer", "PROBE creature kind=wolf", "PROBE pit",
]
const PROPS: Dictionary = {
	"chest": ["%Lid", "%Glow"], "pickup": ["%Glow"], "lore_stone": ["%Glow"],
	"lever": ["%Handle", "%Glow"], "door": ["%Leaf", "%Blocker", "%Glow"],
}
const PIT := {"min": [19, -4], "max": [27, 4]}
const SPAWN_AND_STAIRS := {"min": [-3, -3], "max": [3, 14]}
const CHEST_RAY := {"min": [1, -5], "max": [3, -1]}
const MEADOW := {"min": [-31, 6], "max": [-4, 31]}

var _nodes: Array[Node] = []


func _spawn(path: String) -> Node:
	var node: Node = (load(path) as PackedScene).instantiate()
	_nodes.append(node)
	return node


func teardown() -> void:
	for node: Node in _nodes:
		node.free()
	_nodes.clear()


func test_prop_scenes_keep_nodes_scripts_colliders_and_wear_real_meshes() -> void:
	for name: String in PROPS:
		var root: Node = _spawn("res://scenes/props/%s.tscn" % name)
		var it: Interactable = root as Interactable
		assert_not_null(it, "%s root is still an Interactable" % name)
		if it == null:
			continue
		assert_true(it.get_script().resource_path.ends_with("/interactables/%s.gd" % name), "%s keeps its own script" % name)
		assert_eq(it.collision_layer, 4, "%s stays on the interactable layer" % name)
		assert_eq(it.collision_mask, 0, "%s still detects nothing itself" % name)
		var shape: CollisionShape3D = root.get_node_or_null("CollisionShape3D") as CollisionShape3D
		assert_not_null(shape, "%s keeps its CollisionShape3D" % name)
		if shape != null:
			assert_not_null(shape.shape, "%s collider still has a shape" % name)
		for part: String in PROPS[name]:
			assert_not_null(root.get_node_or_null(part), "%s still has %s" % [name, part])
		var glow: MeshInstance3D = root.get_node_or_null("%Glow") as MeshInstance3D
		assert_not_null(glow, "%s %%Glow is a MeshInstance3D" % name)
		if glow != null:
			assert_true(glow.material_override is StandardMaterial3D, "%s %%Glow keeps a StandardMaterial3D the base can brighten" % name)
		assert_true(_visible_array_meshes(root, root) > 0, "%s shows at least one real (imported) mesh" % name)
	var chest: Node = _spawn("res://scenes/props/chest.tscn")
	assert_eq(_visible_array_meshes(chest, chest), 5, "chest shows exactly bottom, two handles, lock and lid (duplicates hidden)")
	assert_eq(_visible_array_meshes(chest.get_node("%Lid"), chest), 1, "only the lid mesh swings with %Lid")
	assert_true((chest.get_node("%Lid") as Node3D).position.is_equal_approx(Vector3(0, 0.5, -0.3)), "chest %Lid pivot untouched")
	var door: Node = _spawn("res://scenes/props/door.tscn")
	assert_eq(_visible_array_meshes(door, door), 3, "door shows exactly frame, left leaf and right leaf")
	assert_eq(_visible_array_meshes(door.get_node("%Leaf"), door), 1, "one leaf swings with %Leaf")
	var mirror: DoorLeafMirror = door.get_node_or_null("LeafRight") as DoorLeafMirror
	assert_not_null(mirror, "door has a mirrored second leaf")
	if mirror != null:
		assert_true(mirror.get_node(mirror.source) == door.get_node("%Leaf"), "the second leaf follows %Leaf")
		assert_eq(_visible_array_meshes(mirror, door), 1, "the second leaf shows exactly one mesh")
		assert_true(is_equal_approx(DoorLeafMirror.mirrored_yaw(1.3), -1.3), "the second leaf swings the opposite way")
	var blocker: StaticBody3D = door.get_node_or_null("%Blocker") as StaticBody3D
	assert_not_null(blocker, "door %Blocker survived")
	if blocker != null:
		var box: BoxShape3D = (blocker.get_node("BlockerShape") as CollisionShape3D).shape as BoxShape3D
		assert_true(box != null and box.size.is_equal_approx(Vector3(1.4, 2.4, 0.2)), "blocker size unchanged")
		assert_eq(blocker.collision_layer, 1, "blocker still blocks on the world layer")
	var lever: Node = _spawn("res://scenes/props/lever.tscn")
	assert_eq(_visible_array_meshes(lever, lever), 1, "lever shows one rock from the moss set")
	assert_not_null(lever.get_node_or_null("%Handle/HandleMesh"), "lever keeps its shaft under %Handle")


func test_creature_scenes_wear_the_real_models_turned_to_face_forward() -> void:
	for path: String in ["res://scenes/creatures/wolf.tscn", "res://scenes/creatures/deer.tscn"]:
		var creature: Node = _spawn(path)
		var body: GeometryInstance3D = creature.get_node_or_null("Body") as GeometryInstance3D
		assert_not_null(body, "%s Body is still a GeometryInstance3D (creature.gd fades it)" % path)
		assert_not_null(creature.get_node_or_null("Body/Nose"), "%s keeps the Nose marker" % path)
		var model: Node3D = creature.get_node_or_null("Body/Model") as Node3D
		assert_not_null(model, "%s has the real model under Body" % path)
		if model == null:
			continue
		assert_true(model.find_children("*", "Skeleton3D", true, false).size() == 1, "%s model is the rigged glb" % path)
		assert_true(_visible_array_meshes(model, creature) >= 1, "%s model has a visible mesh" % path)
		var scale: Vector3 = model.transform.basis.get_scale()
		assert_true(scale.y > 0.2 and scale.y < 0.5, "%s model is scaled to animal size (%.2f)" % [path, scale.y])
		assert_true(model.transform.basis.z.z < 0.0, "%s model is turned so its head points along -Z like the Nose" % path)
		var anim: AnimationPlayer = model.get_node_or_null("AnimationPlayer") as AnimationPlayer
		assert_not_null(anim, "%s model keeps its AnimationPlayer" % path)
		if anim != null:
			assert_eq(anim.autoplay, "Idle", "%s idles instead of standing in the rest pose" % path)
			assert_true(anim.has_animation("Idle"), "%s has an Idle clip" % path)
		var motes: GPUParticles3D = creature.get_node_or_null("Motes") as GPUParticles3D
		assert_true(motes != null and motes.one_shot and not motes.emitting, "%s Motes untouched" % path)


func test_dressing_data_lists_real_models_and_fences_the_pit() -> void:
	var data: Dictionary = LevelDressing.load_data(DRESSING)
	assert_false(data.is_empty(), "dressing JSON parses")
	var fenced: bool = false
	for rect: Variant in data.get("keep_out", []):
		if rect is Dictionary and float(rect["min"][0]) <= 20.0 and float(rect["max"][0]) >= 26.0 \
				and float(rect["min"][1]) <= -3.0 and float(rect["max"][1]) >= 3.0:
			fenced = true
	assert_true(fenced, "a keep_out rectangle covers the whole pit")
	var sets: Array = data.get("sets", [])
	assert_true(sets.size() >= 10, "there are enough sets to dress the level (%d)" % sets.size())
	for set: Dictionary in sets:
		assert_true(ResourceLoader.exists(str(set.get("model", ""))), "%s model exists on disk" % set.get("name"))
		for placed: Dictionary in set.get("place", []):
			var p := Vector3(float(placed["at"][0]), 0.0, float(placed["at"][1]))
			assert_false(LevelDressing.in_rect(p, PIT), "%s placement %s stays out of the pit" % [set.get("name"), p])
			assert_false(LevelDressing.in_rect(p, SPAWN_AND_STAIRS), "%s placement %s stays off spawn and stairs" % [set.get("name"), p])
			if bool(set.get("collide", false)):
				assert_false(LevelDressing.in_rect(p, MEADOW), "%s collider %s stays out of the creature meadow" % [set.get("name"), p])


func test_scatter_is_deterministic_and_respects_keep_out_and_gap() -> void:
	var zone := {"min": [-10, -10], "max": [10, 10]}
	var hole := {"min": [-2, -2], "max": [2, 2]}
	var a: RandomNumberGenerator = RandomNumberGenerator.new()
	a.seed = 42
	var b: RandomNumberGenerator = RandomNumberGenerator.new()
	b.seed = 42
	var first: Array[Vector3] = LevelDressing.scatter_points(zone, 12, 1.5, [hole], a)
	var second: Array[Vector3] = LevelDressing.scatter_points(zone, 12, 1.5, [hole], b)
	assert_eq(first.size(), 12, "a roomy zone yields every requested point")
	assert_eq(first, second, "the same seed scatters identically")
	for p: Vector3 in first:
		assert_true(LevelDressing.in_rect(p, zone), "point %s is inside the zone" % p)
		assert_false(LevelDressing.in_rect(p, hole), "point %s avoids the keep_out" % p)
		assert_true(is_zero_approx(p.y), "scatter points sit on y = 0")
	for i: int in first.size():
		for j: int in range(i + 1, first.size()):
			assert_true(Vector2(first[i].x - first[j].x, first[i].z - first[j].z).length() >= 1.5, "points keep the minimum gap")
	var crowded: Array[Vector3] = LevelDressing.scatter_points({"min": [0, 0], "max": [1, 1]}, 50, 0.9, [], a)
	assert_true(crowded.size() < 50, "a zone with no room yields fewer points instead of hanging (%d)" % crowded.size())


func test_in_rect_and_chunk_key() -> void:
	var rect := {"min": [20, -3], "max": [26, 3]}
	assert_true(LevelDressing.in_rect(Vector3(23, 5, 0), rect), "inside ignores y")
	assert_true(LevelDressing.in_rect(Vector3(20, 0, -3), rect), "edges are inclusive")
	assert_false(LevelDressing.in_rect(Vector3(19.9, 0, 0), rect), "just outside in x")
	assert_false(LevelDressing.in_rect(Vector3(23, 0, 3.1), rect), "just outside in z")
	assert_eq(LevelDressing.chunk_key(Vector3(0, 0, 0), 24.0), Vector2i(0, 0), "origin is cell 0,0")
	assert_eq(LevelDressing.chunk_key(Vector3(-0.1, 0, 23.9), 24.0), Vector2i(-1, 0), "cells floor, so negatives go to -1")
	assert_eq(LevelDressing.chunk_key(Vector3(48, 0, -24), 24.0), Vector2i(2, -1), "cell edges belong to the next cell")


func test_build_places_everything_outside_the_pit_in_chunked_multimeshes() -> void:
	var dressing: LevelDressing = LevelDressing.new()
	_nodes.append(dressing)
	dressing.chunk_size = 24.0
	dressing.build(LevelDressing.load_data(DRESSING))
	var stats: Dictionary = dressing.stats()
	assert_true(stats["instances"] >= 80, "the level gets a real amount of dressing (%d instances)" % stats["instances"])
	assert_true(stats["multimeshes"] >= 1 and stats["multimeshes"] < stats["instances"], "repeated pieces are batched (%d multimeshes for %d instances)" % [stats["multimeshes"], stats["instances"]])
	assert_true(stats["colliders"] >= 5, "the big rocks, trunks and stumps are solid (%d colliders)" % stats["colliders"])
	assert_true(stats["triangles"] > 100000, "triangle estimate counts the photoscan density (%d)" % stats["triangles"])
	# The runner's dummy renderer drops MultiMesh buffers (transforms read back as identity), so placement is
	# checked against the CPU-side record LevelDressing keeps, and the multimeshes only for shape.
	var origins: PackedVector3Array = dressing.origins()
	assert_eq(origins.size(), int(stats["instances"]), "every placed instance is recorded")
	for p: Vector3 in origins:
		assert_false(LevelDressing.in_rect(p, PIT), "instance at %s is not in the pit" % p)
		assert_false(LevelDressing.in_rect(p, SPAWN_AND_STAIRS), "instance at %s is off the spawn and stairs" % p)
		assert_false(LevelDressing.in_rect(p, CHEST_RAY), "instance at %s is out of the chest focus line" % p)
		assert_true(absf(p.x) <= 31.0 and absf(p.z) <= 31.0, "instance at %s is on the floor slab" % p)
	var seen: int = 0
	for child: Node in dressing.get_children():
		if child is MultiMeshInstance3D:
			var mmi: MultiMeshInstance3D = child
			assert_true(mmi.visibility_range_end > 0.0, "%s has a visibility range" % mmi.name)
			assert_true(mmi.multimesh.instance_count > 0, "%s is not empty" % mmi.name)
			seen += mmi.multimesh.instance_count
		elif child is StaticBody3D:
			var p: Vector3 = (child as StaticBody3D).position
			assert_false(LevelDressing.in_rect(p, PIT), "collider at %s is not in the pit" % p)
			assert_false(LevelDressing.in_rect(p, MEADOW), "collider at %s stays out of the creature meadow" % p)
			assert_eq((child as StaticBody3D).collision_layer, 1, "dressing colliders are world geometry")
	assert_true(seen >= stats["instances"], "every placed instance is in some multimesh (%d seen)" % seen)


func test_headless_probe_keeps_the_nine_lines_in_order_and_adds_perf() -> void:
	var output: Array = []
	var args: PackedStringArray = [
		"--headless", "--path", ProjectSettings.globalize_path("res://"),
		GREYBOX, "--quit-after", PROBE_FRAME_CAP, "--", "--probe",
	]
	var code: int = OS.execute(OS.get_executable_path(), args, output, true)
	var text: String = "\n".join(PackedStringArray(output))
	assert_eq(code, 0, "child headless run of the dressed greybox exits cleanly")
	assert_false("SCRIPT ERROR" in text, "child run printed no script errors")
	var last: int = -1
	for prefix: String in ORIGINAL_PROBES:
		var at: int = text.find(prefix)
		assert_true(at >= 0, "%s still printed" % prefix)
		assert_true(at > last, "%s keeps its place in the order" % prefix)
		last = maxi(last, at)
	var perf: Dictionary = _probe_line(text, "PROBE perf")
	assert_true(not perf.is_empty(), "probe printed the perf line")
	if not perf.is_empty():
		assert_true(perf.has("draw_calls") and perf.has("primitives"), "perf line carries draw_calls and primitives")
		assert_true(perf["draw_calls"].is_valid_int() and perf["primitives"].is_valid_int(), "perf counters are integers")
	var dressing: Dictionary = _probe_line(text, "PROBE dressing")
	assert_true(not dressing.is_empty(), "probe printed the dressing line")
	if not dressing.is_empty():
		assert_true(int(dressing["instances"]) >= 80, "the live level built its dressing (%s instances)" % dressing["instances"])


# Counts MeshInstance3Ds under `node` whose mesh is imported (ArrayMesh, not a primitive) and that are
# visible all the way up to `root`. No tree exists, so visibility is walked by hand.
func _visible_array_meshes(node: Node, root: Node) -> int:
	var count: int = 0
	if node is MeshInstance3D and (node as MeshInstance3D).mesh is ArrayMesh and _visible_up_to(node, root):
		count += 1
	for child: Node in node.get_children():
		count += _visible_array_meshes(child, root)
	return count


func _visible_up_to(node: Node, root: Node) -> bool:
	var cursor: Node = node
	while cursor != null:
		if cursor is Node3D and not (cursor as Node3D).visible:
			return false
		if cursor == root:
			return true
		cursor = cursor.get_parent()
	return true


func _probe_line(text: String, prefix: String) -> Dictionary:
	var out: Dictionary = {}
	for line: String in text.split("\n"):
		line = line.strip_edges()
		if not line.begins_with(prefix):
			continue
		for token: String in line.substr(prefix.length()).split(" ", false):
			var kv: PackedStringArray = token.split("=", true, 1)
			if kv.size() == 2:
				out[kv[0]] = kv[1]
		return out
	return out
