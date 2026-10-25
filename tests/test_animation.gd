extends "res://tests/test_case.gd"
## Live animation rig: a child headless Godot plays scenes/levels/anim_test.tscn with `--probe`, which builds
## the Wick's AnimationTree against the real glb, walks, rolls, swings and dies, printing PROBE lines. Same
## pattern and parser as tests/test_player.gd. Headless proves the clips resolved and the maths ran, not the look.

const ANIM_TEST := "res://scenes/levels/anim_test.tscn"
const PLAYER := "res://scenes/player/player.tscn"
const PROBE_FRAME_CAP := "900"

var _nodes: Array[Node] = []


func teardown() -> void:
	for node: Node in _nodes:
		node.free()
	_nodes.clear()


func test_player_scene_carries_the_wick_and_an_animator() -> void:
	var player: Node = (load(PLAYER) as PackedScene).instantiate()
	_nodes.append(player)
	assert_true(player is PlayerController, "player still runs PlayerController")
	assert_true(player.is_in_group(&"player"), "player keeps its group")
	assert_eq(player.collision_layer, 2, "player keeps collision layer 2")
	assert_eq(player.collision_mask, 1, "player keeps collision mask 1")
	var shape: CollisionShape3D = player.get_node_or_null("CollisionShape3D") as CollisionShape3D
	assert_not_null(shape, "player keeps its collision shape")
	if shape != null:
		assert_true(shape.shape is CapsuleShape3D, "collision stays a capsule")
	var animator: PlayerAnimator = player.get_node_or_null("%Animator") as PlayerAnimator
	assert_not_null(animator, "player has a unique Animator running PlayerAnimator")
	var body: Node3D = player.get_node_or_null("Body") as Node3D
	assert_not_null(body, "player has a Body holding the model")
	if body != null:
		assert_true(body.basis.z.z < 0.0 and body.basis.x.x < 0.0, "model is turned 180 degrees to face -Z like the capsule's nose did")
		assert_true(body.get_child_count() > 0, "Body holds the instanced model")
	assert_null(player.get_node_or_null("Body/Nose"), "the placeholder nose is gone")
	for unique: String in ["%CameraRig", "%SpringArm", "%Camera", "%Melee", "%InteractionDetector"]:
		assert_true(player.has_node(unique), "%s survives the character swap" % unique)


func test_headless_probe_resolves_every_clip_and_plays_the_one_shots() -> void:
	var output: Array = []
	var args: PackedStringArray = [
		"--headless", "--path", ProjectSettings.globalize_path("res://"),
		ANIM_TEST, "--quit-after", PROBE_FRAME_CAP, "--", "--probe",
	]
	var code: int = OS.execute(OS.get_executable_path(), args, output, true)
	var text: String = "\n".join(PackedStringArray(output))
	assert_eq(code, 0, "child headless run of anim_test exits cleanly")
	assert_false("SCRIPT ERROR" in text, "child run printed no script errors")
	var animator: Dictionary = _probe_line(text, "PROBE animator")
	assert_true(not animator.is_empty(), "probe printed the animator line")
	if not animator.is_empty():
		assert_eq(animator["missing"], "none", "every required clip resolved (missing=%s)" % animator["missing"])
		assert_true(int(animator["clips"]) >= 8, "the model carries at least the eight required clips")
		for key: String in ["idle", "walk", "run", "roll", "attack", "hit", "death", "rigged"]:
			assert_eq(animator[key], "true", "%s resolved" % key)
	var blends: Array[Dictionary] = _probe_lines(text, "PROBE blend")
	assert_true(blends.size() >= 4, "probe printed blend samples at several speeds")
	for blend: Dictionary in blends:
		var speed: float = float(blend["speed"])
		var value: float = float(blend["value"])
		if is_zero_approx(speed):
			assert_true(is_zero_approx(value), "rest blends to idle")
		elif is_equal_approx(speed, 4.2):
			assert_true(is_equal_approx(value, 1.0), "walk speed blends to the walk clip")
		elif speed >= 7.0:
			assert_true(is_equal_approx(value, 2.0), "sprint and beyond blend to the run clip (speed %s)" % blend["speed"])
	var live: Dictionary = _probe_line(text, "PROBE live")
	assert_true(not live.is_empty(), "probe printed the live locomotion line")
	if not live.is_empty():
		assert_true(float(live["speed"]) > 2.0, "the player was moving after a second of input (speed=%s)" % live["speed"])
		assert_true(float(live["blend"]) > 0.5, "the blend followed the speed (blend=%s)" % live["blend"])
		assert_true(float(live["rate"]) > 1.0, "the gait sped up to plant the feet (rate=%s)" % live["rate"])
		assert_eq(live["state"], "LOCOMOTION", "plain movement is the locomotion state")
	var roll: Dictionary = _probe_line(text, "PROBE roll")
	assert_true(not roll.is_empty(), "probe printed the roll line")
	if not roll.is_empty():
		assert_eq(roll["fired"], "true", "the dodge fired the roll one-shot")
		var frames: int = int(roll["active_frames"])
		assert_true(frames >= 15 and frames <= 60, "roll showed for about dodge_duration (%d frames)" % frames)
		assert_eq(roll["busy_after"], "false", "the animator is free again after the roll")
	var swing: Dictionary = _probe_line(text, "PROBE swing")
	assert_true(not swing.is_empty() and swing["started"] == "true", "a light swing started with the sword equipped")
	var attack: Dictionary = _probe_line(text, "PROBE attack")
	assert_true(not attack.is_empty(), "probe printed the attack line")
	if not attack.is_empty():
		assert_eq(attack["fired"], "true", "the swing fired the attack one-shot")
		var frames: int = int(attack["active_frames"])
		assert_true(frames >= 15 and frames <= 70, "light attack showed for about the swing length (%d frames)" % frames)
	var death: Dictionary = _probe_line(text, "PROBE death")
	assert_true(not death.is_empty(), "probe printed the death line")
	if not death.is_empty():
		assert_eq(death["state"], "DEATH", "Game.player_died put the animator in DEATH")
		assert_eq(death["busy"], "true", "a dead Wick is busy")


func _probe_lines(text: String, prefix: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for line: String in text.split("\n"):
		line = line.strip_edges()
		if line.begins_with(prefix):
			out.append(_parse(line.substr(prefix.length())))
	return out


func _probe_line(text: String, prefix: String) -> Dictionary:
	var lines: Array[Dictionary] = _probe_lines(text, prefix)
	return lines[0] if not lines.is_empty() else {}


func _parse(rest: String) -> Dictionary:
	var out: Dictionary = {}
	for token: String in rest.split(" ", false):
		var kv: PackedStringArray = token.split("=", true, 1)
		if kv.size() == 2:
			out[kv[0]] = kv[1]
	return out
