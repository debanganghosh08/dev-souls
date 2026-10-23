extends "res://tests/test_case.gd"
## Pure Creature.decide tests: every disposition at every distance band, inclusive sight/attack boundaries,
## the strict leash boundary, and DEAD winning over everything. Plus the Damageable contract outside a tree.

const SIGHT := 14.0
const BITE := 1.8
const LEASH := 25.0

var _nodes: Array[Node] = []


func _decide(kind: int, to_player: float, to_home: float = 0.0, dead: bool = false) -> int:
	return Creature.decide(kind, to_player, to_home, SIGHT, BITE, LEASH, dead)


func teardown() -> void:
	for node: Node in _nodes:
		node.free()
	_nodes.clear()


func test_passive_wanders_whatever_the_player_does() -> void:
	for distance: float in [0.0, 1.0, BITE, 5.0, SIGHT, 13.9, 14.1, 100.0, INF]:
		assert_eq(_decide(Creature.Disposition.PASSIVE, distance), Creature.State.WANDER, "passive wanders at %s m" % distance)


func test_skittish_flees_within_sight_and_wanders_beyond() -> void:
	assert_eq(_decide(Creature.Disposition.SKITTISH, 0.0), Creature.State.FLEE, "flees with the player on top of it")
	assert_eq(_decide(Creature.Disposition.SKITTISH, 5.0), Creature.State.FLEE, "flees at 5 m")
	assert_eq(_decide(Creature.Disposition.SKITTISH, SIGHT), Creature.State.FLEE, "exactly at sight range still flees")
	assert_eq(_decide(Creature.Disposition.SKITTISH, SIGHT + 0.01), Creature.State.WANDER, "just past sight range wanders")
	assert_eq(_decide(Creature.Disposition.SKITTISH, 100.0), Creature.State.WANDER, "far away wanders")
	assert_eq(_decide(Creature.Disposition.SKITTISH, INF), Creature.State.WANDER, "no player at all wanders")
	assert_ne(_decide(Creature.Disposition.SKITTISH, 1.0), Creature.State.ATTACK, "skittish never attacks")


func test_hostile_attacks_in_range_chases_in_sight_wanders_beyond() -> void:
	assert_eq(_decide(Creature.Disposition.HOSTILE, 0.0), Creature.State.ATTACK, "attacks with the player on top of it")
	assert_eq(_decide(Creature.Disposition.HOSTILE, BITE), Creature.State.ATTACK, "exactly at attack range attacks")
	assert_eq(_decide(Creature.Disposition.HOSTILE, BITE + 0.01), Creature.State.CHASE, "just past attack range chases")
	assert_eq(_decide(Creature.Disposition.HOSTILE, 8.0), Creature.State.CHASE, "chases at 8 m")
	assert_eq(_decide(Creature.Disposition.HOSTILE, SIGHT), Creature.State.CHASE, "exactly at sight range chases")
	assert_eq(_decide(Creature.Disposition.HOSTILE, SIGHT + 0.01), Creature.State.WANDER, "just past sight range wanders")
	assert_eq(_decide(Creature.Disposition.HOSTILE, INF), Creature.State.WANDER, "no player at all wanders")
	assert_ne(_decide(Creature.Disposition.HOSTILE, 1.0), Creature.State.FLEE, "hostile never flees")


func test_leash_overrides_every_disposition_but_is_strict() -> void:
	for kind: int in [Creature.Disposition.PASSIVE, Creature.Disposition.SKITTISH, Creature.Disposition.HOSTILE]:
		assert_eq(_decide(kind, 1.0, LEASH + 0.01), Creature.State.RETURN_HOME, "disposition %d returns home just past the leash" % kind)
		assert_eq(_decide(kind, 1.0, 100.0), Creature.State.RETURN_HOME, "disposition %d returns home far from home" % kind)
	assert_eq(_decide(Creature.Disposition.HOSTILE, 1.0, LEASH), Creature.State.ATTACK, "exactly on the leash a wolf still attacks")
	assert_eq(_decide(Creature.Disposition.SKITTISH, 1.0, LEASH), Creature.State.FLEE, "exactly on the leash a deer still flees")
	assert_eq(_decide(Creature.Disposition.PASSIVE, 1.0, LEASH), Creature.State.WANDER, "exactly on the leash a passive animal wanders")
	assert_eq(_decide(Creature.Disposition.HOSTILE, 0.5, LEASH * 0.5), Creature.State.ATTACK, "inside the leash the leash does nothing")


func test_dead_decides_dead_regardless_of_distance() -> void:
	for kind: int in [Creature.Disposition.PASSIVE, Creature.Disposition.SKITTISH, Creature.Disposition.HOSTILE]:
		for to_player: float in [0.0, BITE, SIGHT, 100.0]:
			for to_home: float in [0.0, LEASH, 100.0]:
				assert_eq(_decide(kind, to_player, to_home, true), Creature.State.DEAD, "dead %d at %s/%s decides DEAD" % [kind, to_player, to_home])


func test_damageable_contract_signals_and_clamps() -> void:
	var d: Damageable = Damageable.new()
	_nodes.append(d)
	d.max_health = 30.0
	d.sync_health()
	var damaged: Array[float] = []
	var died: Array[Node] = []
	d.damaged.connect(func(amount: float, _from: Node) -> void: damaged.append(amount))
	d.died.connect(func(from: Node) -> void: died.append(from))
	assert_eq(d.take_damage(10.0, null), 10.0, "damage applied is returned")
	assert_eq(d.take_damage(-1.0, null), 0.0, "non-positive damage applies nothing")
	assert_eq(d.take_damage(50.0, null), 20.0, "overkill applies only what was left")
	assert_true(d.is_dead(), "dead after overkill")
	assert_eq(d.take_damage(5.0, null), 0.0, "a dead body takes no more damage")
	assert_eq(damaged, [10.0, 20.0], "damaged emitted once per applied hit")
	assert_eq(died.size(), 1, "died emitted exactly once")
	assert_eq(d.health_fraction(), 0.0, "dead fraction is zero")


func test_creature_defaults_and_state_name() -> void:
	var c: Creature = Creature.new()
	_nodes.append(c)
	assert_eq(c.state_name(), "IDLE", "a fresh creature is IDLE")
	assert_eq(c.disposition, Creature.Disposition.PASSIVE, "default disposition is PASSIVE")
	assert_false(c.is_dead(), "fresh creature is alive")
	assert_false(c.is_dissolving(), "fresh creature is not dissolving")
	assert_false(c.motes_active(), "no motes without a Motes node")
	assert_true(c.sight_range > c.attack_range, "sight range exceeds attack range by default")
	assert_true(c.home_leash > c.wander_radius, "leash exceeds the wander radius by default")
