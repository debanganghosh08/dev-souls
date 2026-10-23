extends "res://tests/test_case.gd"
## Combat wiring: the Melee child in player.tscn, player health and fall damage with an injected Game, the
## creature scenes and their greybox placement, then a child headless run of greybox.tscn --probe for the
## live swing, the deer's flight and the wolf's death dissolve (same pattern as tests/test_player.gd).

const GREYBOX := "res://scenes/levels/greybox.tscn"
const DEER := "res://scenes/creatures/deer.tscn"
const WOLF := "res://scenes/creatures/wolf.tscn"
const GAME_SCRIPT := "res://scripts/autoloads/game.gd"
const PROBE_FRAME_CAP := "900"
const ANIMAL_LAYER := 16
const PIT_X := 23.0
const ORIGINAL_PROBES := ["PROBE landed", "PROBE stairs", "PROBE focus", "PROBE chest", "PROBE door", "PROBE pit"]

var _scene: Node
var _player: PlayerController
var _game: Node
var _nodes: Array[Node] = []


func _fresh() -> void:
	_cleanup()
	_scene = (load(GREYBOX) as PackedScene).instantiate()
	_player = _scene.get_node("Player") as PlayerController
	_game = (load(GAME_SCRIPT) as GDScript).new()
	_game.state = _game.State.PLAYING
	_player._inject(_game)
	_nodes.append_array([_scene, _game])


func _cleanup() -> void:
	for node: Node in _nodes:
		node.free()
	_nodes.clear()
	_scene = null
	_player = null
	_game = null


func teardown() -> void:
	_cleanup()


func test_player_scene_carries_a_melee_child() -> void:
	_fresh()
	var melee: Node = _player.get_node_or_null("Melee")
	assert_not_null(melee, "player has a Melee child")
	assert_true(melee is Melee, "Melee child runs the Melee script")
	assert_true(_player.has_node("%Melee"), "Melee is a unique name")


func test_player_takes_damage_and_dies_at_zero() -> void:
	_fresh()
	var fractions: Array[float] = []
	var hits: Array[float] = []
	_player.health_changed.connect(func(f: float) -> void: fractions.append(f))
	_player.damaged.connect(func(amount: float, _from: Node) -> void: hits.append(amount))
	assert_true(is_equal_approx(_player.health_fraction(), 1.0), "health starts full")
	assert_eq(_player.take_damage(40.0, null), 40.0, "damage applies while PLAYING")
	assert_true(is_equal_approx(_player.health_fraction(), 0.6), "fraction reflects the hit")
	assert_eq(hits, [40.0], "damaged emitted with the applied amount")
	assert_eq(fractions.size(), 1, "health_changed emitted once")
	assert_eq(_game.state, _game.State.PLAYING, "still alive at 60 %")
	assert_eq(_player.take_damage(100.0, null), 60.0, "overkill applies the remainder")
	assert_eq(_game.state, _game.State.DEAD, "reaching zero health kills via Game")
	assert_eq(_player.take_damage(10.0, null), 0.0, "no damage while DEAD")


func test_player_ignores_damage_while_invulnerable_or_not_playing() -> void:
	_fresh()
	_player.is_invulnerable = true
	assert_eq(_player.take_damage(50.0, null), 0.0, "dodge i-frames swallow damage")
	_player.is_invulnerable = false
	_game.state = _game.State.PAUSED
	assert_eq(_player.take_damage(50.0, null), 0.0, "no damage while paused")
	_game.state = _game.State.PLAYING
	assert_true(is_equal_approx(_player.health_fraction(), 1.0), "health untouched by swallowed hits")
	assert_eq(_player.take_damage(-5.0, null), 0.0, "negative damage applies nothing")


func test_fall_damage_scales_with_the_drop() -> void:
	_fresh()
	assert_eq(_player.fall_damage_for(_player.fall_damage_height), 0.0, "no damage at the threshold")
	assert_true(is_equal_approx(_player.fall_damage_for(10.0), 2.0 * _player.fall_damage_per_metre), "two metres past the threshold scale linearly")
	_player._update_fall_tracking(false, 10.0)
	_player._update_fall_tracking(true, 0.0)
	assert_true(is_equal_approx(_player.health_fraction(), 1.0 - 2.0 * _player.fall_damage_per_metre / _player.max_health), "a 10 m drop costs health")
	assert_eq(_game.state, _game.State.PLAYING, "a 10 m drop is survivable")
	_player._update_fall_tracking(false, 0.0)
	_player._update_fall_tracking(true, -20.0)
	assert_eq(_game.state, _game.State.DEAD, "a 20 m drop still kills outright")


func test_repeated_falls_wear_health_down_to_death() -> void:
	_fresh()
	var falls: int = 0
	while _game.state == _game.State.PLAYING and falls < 20:
		_player._update_fall_tracking(false, 12.0)
		_player._update_fall_tracking(true, 0.0)
		falls += 1
	assert_eq(_game.state, _game.State.DEAD, "enough sub-lethal drops kill through health")
	assert_true(falls > 1, "it took more than one 12 m drop (%d)" % falls)
	assert_eq(_player.health_fraction(), 0.0, "health is empty on death")


func test_creature_scenes_are_animals_with_motes() -> void:
	for path: String in [DEER, WOLF]:
		var creature: Creature = (load(path) as PackedScene).instantiate() as Creature
		_nodes.append(creature)
		assert_not_null(creature, "%s runs the Creature script" % path)
		assert_eq(creature.collision_layer, ANIMAL_LAYER, "%s sits on the animal layer" % path)
		assert_true(creature.is_in_group(&"animal"), "%s is in the animal group" % path)
		assert_not_null(creature.get_node_or_null("CollisionShape3D"), "%s has a collider" % path)
		assert_not_null(creature.get_node_or_null("Body"), "%s has a body mesh" % path)
		assert_not_null(creature.get_node_or_null("Body/Nose"), "%s has a nose marker" % path)
		var motes: GPUParticles3D = creature.get_node_or_null("Motes") as GPUParticles3D
		assert_not_null(motes, "%s has a Motes emitter" % path)
		if motes != null:
			assert_false(motes.emitting, "%s motes start idle" % path)
			assert_true(motes.one_shot, "%s motes are a one-shot burst" % path)
	var deer: Creature = _nodes[-2] as Creature
	var wolf: Creature = _nodes[-1] as Creature
	assert_eq(deer.disposition, Creature.Disposition.SKITTISH, "deer is skittish")
	assert_eq(wolf.disposition, Creature.Disposition.HOSTILE, "wolf is hostile")
	assert_true(wolf.attack_damage > 0.0, "wolf bites for damage")


func test_greybox_places_two_deer_and_a_wolf_away_from_the_pit() -> void:
	_fresh()
	var names: Array[String] = ["DeerA", "DeerB", "Wolf"]
	for name: String in names:
		var creature: Creature = _scene.get_node_or_null("Creatures/" + name) as Creature
		assert_not_null(creature, "greybox has %s" % name)
		if creature == null:
			continue
		assert_true(absf(creature.position.x - PIT_X) > 20.0, "%s is well away from the pit" % name)
		assert_true(creature.position.length() > creature.sight_range, "%s cannot see the spawn point" % name)
	var wolf: Creature = _scene.get_node("Creatures/Wolf") as Creature
	assert_eq(wolf.disposition, Creature.Disposition.HOSTILE, "greybox wolf is hostile")
	assert_eq(wolf.death_flag, &"greybox_wolf_slain", "greybox wolf sets a flag on death")
	assert_eq((_scene.get_node("Creatures/DeerA") as Creature).disposition, Creature.Disposition.SKITTISH, "DeerA is skittish")
	assert_eq((_scene.get_node("Creatures/DeerB") as Creature).disposition, Creature.Disposition.SKITTISH, "DeerB is skittish")


func test_headless_probe_swings_and_dissolves() -> void:
	var output: Array = []
	var args: PackedStringArray = [
		"--headless", "--path", ProjectSettings.globalize_path("res://"),
		GREYBOX, "--quit-after", PROBE_FRAME_CAP, "--", "--probe",
	]
	var code: int = OS.execute(OS.get_executable_path(), args, output, true)
	var text: String = "\n".join(PackedStringArray(output))
	assert_eq(code, 0, "child headless run of greybox exits cleanly")
	assert_false("SCRIPT ERROR" in text, "child run printed no script errors")
	var combat: Dictionary = _probe_line(text, "PROBE combat")
	assert_true(not combat.is_empty(), "probe printed the combat line")
	if not combat.is_empty():
		assert_eq(combat["equipped"], "sword", "the sword from the live Inventory was auto-equipped")
		assert_eq(combat["state"], "IDLE", "the swing finished and returned to IDLE")
		assert_eq(combat["hit"], "true", "the light swing hit the wolf in front of the player")
		assert_true(is_equal_approx(float(combat["dmg"]), 18.0), "sword light damage is 18 (dmg=%s)" % combat["dmg"])
		assert_true(is_equal_approx(float(combat["wolf_hp"]), 42.0), "wolf lost exactly one light hit (hp=%s)" % combat["wolf_hp"])
	var deer: Dictionary = _probe_line(text, "PROBE creature kind=deer")
	assert_true(not deer.is_empty(), "probe printed the deer line")
	if not deer.is_empty():
		assert_eq(deer["state"], "FLEE", "the deer dropped beside the player fled")
		assert_eq(deer["dead"], "false", "the deer is alive")
		assert_eq(deer["motes"], "false", "no motes on a living deer")
	var wolf: Dictionary = _probe_line(text, "PROBE creature kind=wolf")
	assert_true(not wolf.is_empty(), "probe printed the wolf line")
	if not wolf.is_empty():
		assert_eq(wolf["state"], "DEAD", "the killed wolf is DEAD")
		assert_eq(wolf["dead"], "true", "the wolf reports dead")
		assert_eq(wolf["motes"], "true", "the golden motes burst on death")
		assert_eq(wolf["dissolving"], "true", "the dissolve started")
	var last_index: int = -1
	for prefix: String in ORIGINAL_PROBES:
		var index: int = text.find(prefix)
		assert_true(index >= 0, "%s line still printed" % prefix)
		assert_true(index > last_index, "%s keeps its original order" % prefix)
		last_index = index


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
