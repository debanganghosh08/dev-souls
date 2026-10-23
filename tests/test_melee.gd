extends "res://tests/test_case.gd"
## Melee tests without a scene: the pure in_arc test, the state machine stepped by hand, refusals, weapon
## multipliers from data/weapons.json, and the once-per-swing hit set fed with fake Damageable bodies.

const GAME_SCRIPT := "res://scripts/autoloads/game.gd"
const HALF_ARC := 55.0


class FakeInventory extends Node:
	var held: Array[StringName] = []

	func has(id: StringName) -> bool:
		return held.has(id)


class FakeBody extends Node3D:
	var is_dodging: bool = false


var _nodes: Array[Node] = []
var _melee: Melee
var _game: Node
var _inventory: FakeInventory
var _stamina: Stamina
var _body: FakeBody
var _started: Array[bool] = []
var _finished: int = 0
var _hits: Array[float] = []


func _fresh() -> void:
	_cleanup()
	_game = (load(GAME_SCRIPT) as GDScript).new()
	_game.state = _game.State.PLAYING
	_inventory = FakeInventory.new()
	_inventory.held = [&"sword", &"hammer", &"torch"]
	_stamina = Stamina.new()
	_stamina.reset()
	_body = FakeBody.new()
	_melee = Melee.new()
	_melee._inject(_game, _inventory, _stamina, _body)
	_melee.swing_started.connect(func(heavy: bool) -> void: _started.append(heavy))
	_melee.swing_finished.connect(func() -> void: _finished += 1)
	_melee.hit_landed.connect(func(_target: Node, amount: float) -> void: _hits.append(amount))
	_nodes.append_array([_game, _inventory, _body, _melee])


func _target(pos: Vector3, hp: float = 100.0) -> Damageable:
	var t: Damageable = Damageable.new()
	t.max_health = hp
	t.sync_health()
	t.position = pos
	_nodes.append(t)
	return t


func _cleanup() -> void:
	for node: Node in _nodes:
		node.free()
	_nodes.clear()
	_started.clear()
	_finished = 0
	_hits.clear()


func teardown() -> void:
	_cleanup()


func test_in_arc_accepts_dead_ahead_and_rejects_behind() -> void:
	var origin: Vector3 = Vector3.ZERO
	assert_true(Melee.in_arc(origin, Vector3.FORWARD, Vector3(0, 0, -1), 2.2, 110.0), "target 1 m dead ahead is hit")
	assert_false(Melee.in_arc(origin, Vector3.FORWARD, Vector3(0, 0, 1), 2.2, 110.0), "target 1 m behind is missed")
	assert_false(Melee.in_arc(origin, Vector3.FORWARD, Vector3(1, 0, 0), 2.2, 110.0), "target square to the side (90 deg) is outside a 110 deg arc")
	assert_true(Melee.in_arc(Vector3(5, 0, 5), Vector3.RIGHT, Vector3(6.5, 0, 5), 2.2, 110.0), "works away from the origin and facing +X")


func test_in_arc_reach_boundary_is_inclusive() -> void:
	var reach: float = 2.2
	assert_true(Melee.in_arc(Vector3.ZERO, Vector3.FORWARD, Vector3(0, 0, -reach), reach, 110.0), "exactly at reach is a hit")
	assert_false(Melee.in_arc(Vector3.ZERO, Vector3.FORWARD, Vector3(0, 0, -reach - 0.01), reach, 110.0), "1 cm past reach is a miss")
	assert_true(Melee.in_arc(Vector3.ZERO, Vector3.FORWARD, Vector3.ZERO, reach, 110.0), "standing inside the target still hits")
	assert_false(Melee.in_arc(Vector3.ZERO, Vector3.FORWARD, Vector3(0, 0, -1), -1.0, 110.0), "negative reach hits nothing")


func test_in_arc_angle_boundary_is_inclusive() -> void:
	var on_edge: Vector3 = Vector3(sin(deg_to_rad(HALF_ARC)), 0.0, -cos(deg_to_rad(HALF_ARC)))
	var past_edge: Vector3 = Vector3(sin(deg_to_rad(HALF_ARC + 1.0)), 0.0, -cos(deg_to_rad(HALF_ARC + 1.0)))
	assert_true(Melee.in_arc(Vector3.ZERO, Vector3.FORWARD, on_edge, 2.2, 110.0), "exactly on the 55 deg edge is a hit")
	assert_false(Melee.in_arc(Vector3.ZERO, Vector3.FORWARD, past_edge, 2.2, 110.0), "56 deg is a miss")
	assert_true(Melee.in_arc(Vector3.ZERO, Vector3.FORWARD, -on_edge, 2.2, 360.0), "a 360 deg arc hits behind")
	assert_false(Melee.in_arc(Vector3.ZERO, Vector3.ZERO, Vector3(0, 0, -1), 2.2, 110.0), "a zero facing cannot aim")


func test_attack_refused_without_stamina() -> void:
	_fresh()
	_stamina.current = 5.0
	assert_false(_melee.try_attack(false), "light attack refused below its cost")
	assert_eq(_stamina.current, 5.0, "refused attack spends nothing")
	assert_eq(_melee.state_name(), "IDLE", "refused attack stays IDLE")
	assert_eq(_started.size(), 0, "no swing_started on refusal")


func test_attack_refused_while_dodging() -> void:
	_fresh()
	_body.is_dodging = true
	assert_false(_melee.can_attack(), "cannot attack mid-dodge")
	assert_false(_melee.try_attack(false), "attack refused while dodging")
	assert_eq(_stamina.current, 100.0, "nothing spent while dodging")
	_body.is_dodging = false
	assert_true(_melee.try_attack(false), "attack accepted once the dodge ends")


func test_attack_refused_when_not_playing() -> void:
	_fresh()
	for state: int in [_game.State.PAUSED, _game.State.DEAD, _game.State.MENU, _game.State.BOOT]:
		_game.state = state
		assert_false(_melee.try_attack(true), "attack refused in state %d" % state)
	assert_eq(_stamina.current, 100.0, "nothing spent outside PLAYING")
	_game.state = _game.State.PLAYING
	assert_true(_melee.try_attack(true), "attack accepted while PLAYING")


func test_no_buffering_outside_idle() -> void:
	_fresh()
	var light_cost: float = _melee.stamina_cost(false)
	assert_true(_melee.try_attack(false), "first press starts a swing")
	assert_eq(_melee.state_name(), "WINDUP", "swing begins in WINDUP")
	assert_false(_melee.try_attack(false), "second press during WINDUP is dropped")
	assert_false(_melee.try_attack(true), "heavy press during WINDUP is dropped too")
	assert_eq(_started.size(), 1, "only one swing started")
	assert_true(is_equal_approx(_stamina.current, 100.0 - light_cost), "only one light cost was paid")


func test_state_machine_cycles_back_to_idle() -> void:
	_fresh()
	_melee.step(1.0)
	assert_eq(_melee.state_name(), "IDLE", "stepping while idle does nothing")
	_melee.try_attack(false)
	_melee.step(_melee.light_windup)
	assert_eq(_melee.state_name(), "ACTIVE", "windup elapsed -> ACTIVE")
	_melee.step(_melee.active_time)
	assert_eq(_melee.state_name(), "RECOVERY", "active window elapsed -> RECOVERY")
	_melee.step(_melee.light_recovery * 0.5)
	assert_eq(_melee.state_name(), "RECOVERY", "half the recovery is still RECOVERY")
	assert_false(_melee.can_attack(), "cannot attack during recovery")
	_melee.step(_melee.light_recovery * 0.5)
	assert_eq(_melee.state_name(), "IDLE", "recovery elapsed -> IDLE")
	assert_eq(_finished, 1, "swing_finished emitted once")
	assert_true(_melee.can_attack(), "ready for the next swing")


func test_heavy_costs_more_and_hits_harder() -> void:
	_fresh()
	assert_true(_melee.equip(&"sword"), "sword equipped")
	assert_true(_melee.stamina_cost(true) > _melee.stamina_cost(false), "heavy stamina cost exceeds light")
	assert_true(_melee.damage_for(true) > _melee.damage_for(false), "heavy damage exceeds light")
	assert_true(_melee.try_attack(true), "heavy swing starts")
	assert_true(is_equal_approx(_stamina.current, 100.0 - _melee.heavy_stamina), "heavy cost paid up front")
	assert_true(_melee.is_heavy_swing(), "swing is flagged heavy")
	assert_eq(_started, [true], "swing_started carries heavy=true")
	var t: Damageable = _target(Vector3(0, 0, -1))
	_melee.apply_hits([t], Vector3.ZERO, Vector3.FORWARD)
	assert_true(is_equal_approx(t.health.current, 100.0 - _melee.heavy_damage), "heavy swing dealt heavy_damage with the sword")


func test_one_swing_cannot_hit_the_same_target_twice() -> void:
	_fresh()
	_melee.equip(&"sword")
	var t: Damageable = _target(Vector3(0, 0, -1))
	_melee.try_attack(false)
	assert_eq(_melee.apply_hits([t, t], Vector3.ZERO, Vector3.FORWARD), 1, "duplicate candidates hit once")
	assert_eq(_melee.apply_hits([t], Vector3.ZERO, Vector3.FORWARD), 0, "a later pass in the same swing hits nothing")
	assert_true(is_equal_approx(t.health.current, 100.0 - _melee.light_damage), "exactly one light hit was applied")
	assert_eq(_hits.size(), 1, "hit_landed emitted once")
	_melee.step(10.0)
	_melee.step(10.0)
	_melee.step(10.0)
	assert_true(_melee.try_attack(false), "next swing starts")
	assert_eq(_melee.apply_hits([t], Vector3.ZERO, Vector3.FORWARD), 1, "a new swing can hit the same target again")


func test_apply_hits_respects_arc_reach_and_death() -> void:
	_fresh()
	_melee.equip(&"sword")
	var ahead: Damageable = _target(Vector3(0, 0, -1.5))
	var behind: Damageable = _target(Vector3(0, 0, 1.5))
	var far: Damageable = _target(Vector3(0, 0, -5.0))
	var dead: Damageable = _target(Vector3(0.2, 0, -1.0))
	dead.health.kill()
	_melee.try_attack(false)
	var hits: int = _melee.apply_hits([ahead, behind, far, dead, Node.new()], Vector3.ZERO, Vector3.FORWARD)
	assert_eq(hits, 1, "only the live target ahead within reach is hit")
	assert_true(ahead.health.current < 100.0, "target ahead took damage")
	assert_eq(behind.health.current, 100.0, "target behind untouched")
	assert_eq(far.health.current, 100.0, "target out of reach untouched")


func test_weapon_multipliers_change_damage_and_equip_needs_inventory() -> void:
	_fresh()
	_melee._weapons = WeaponTable.load_from()
	assert_eq(_melee.equipped(), &"unarmed", "starts unarmed")
	var unarmed: float = _melee.damage_for(false)
	assert_true(_melee.equip(&"torch"), "torch equips")
	var torch: float = _melee.damage_for(false)
	assert_true(_melee.equip(&"sword"), "sword equips")
	var sword: float = _melee.damage_for(false)
	var sword_cost: float = _melee.stamina_cost(false)
	assert_true(_melee.equip(&"hammer"), "hammer equips")
	var hammer: float = _melee.damage_for(false)
	assert_true(unarmed < torch and torch < sword and sword < hammer, "damage orders unarmed < torch < sword < hammer")
	assert_true(_melee.stamina_cost(false) > sword_cost, "hammer costs more stamina than the sword")
	assert_true(_melee.effective_reach() > _melee.reach, "hammer adds reach")
	_inventory.held = []
	assert_false(_melee.equip(&"sword"), "cannot equip a weapon not in the inventory")
	assert_eq(_melee.equipped(), &"hammer", "failed equip keeps the current weapon")
	assert_false(_melee.equip(&"castle_key"), "non-weapon ids are refused")
	_melee.unequip()
	assert_eq(_melee.equipped(), &"unarmed", "unequip returns to bare hands")
	assert_true(_melee.equip(&"unarmed"), "unarmed can always be equipped")


func test_missing_weapons_file_falls_back_to_defaults() -> void:
	var loaded: Dictionary = WeaponTable.load_from("res://data/does_not_exist.json", false)
	assert_eq(loaded.size(), WeaponTable.DEFAULTS.size(), "fallback has every default entry")
	for id: StringName in [&"unarmed", &"torch", &"sword", &"hammer"]:
		assert_true(loaded.has(id), "fallback has %s" % id)
		assert_eq(loaded[id], WeaponTable.DEFAULTS[id], "fallback %s matches the built-in default" % id)
	var real: Dictionary = WeaponTable.load_from()
	for id: StringName in [&"unarmed", &"torch", &"sword", &"hammer"]:
		assert_true(real.has(id), "data/weapons.json defines %s" % id)
		for field: String in ["name", "damage_multiplier", "stamina_multiplier", "reach_bonus"]:
			assert_true(real[id].has(field), "%s has %s" % [id, field])
