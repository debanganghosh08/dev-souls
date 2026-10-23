extends "res://tests/test_case.gd"
## Pure Interactable tests. No autoloads exist in the runner, so the real Flags and Inventory scripts are
## instanced directly and injected, SaveGame is a counting stub, and nothing enters a tree (tweens snap,
## %children are absent). Everything here is the gating/bookkeeping contract every prop relies on.

const FLAGS_SCRIPT := "res://scripts/autoloads/flags.gd"
const INVENTORY_SCRIPT := "res://scripts/autoloads/inventory.gd"
const ENGINE_WORDS: Array[String] = ["flag", "null", "nil", "res://", "stringname"]


class SaveStub extends Node:
	var autosaves: int = 0

	func request_autosave() -> void:
		autosaves += 1


var _flags: Node
var _inventory: Node
var _save: SaveStub
var _nodes: Array[Node] = []
var _refusals: Array[String] = []
var _interactions: int = 0


func _fresh() -> void:
	_cleanup()
	_flags = (load(FLAGS_SCRIPT) as GDScript).new()
	_inventory = (load(INVENTORY_SCRIPT) as GDScript).new()
	_inventory._load_definitions()
	_save = SaveStub.new()
	_nodes.append_array([_flags, _inventory, _save])
	_refusals.clear()
	_interactions = 0


func _wire(it: Interactable) -> Interactable:
	it._inject(_flags, _inventory, _save)
	it.refused.connect(func(reason: String) -> void: _refusals.append(reason))
	it.interacted.connect(func(_who: Node) -> void: _interactions += 1)
	_nodes.append(it)
	return it


func _cleanup() -> void:
	for node: Node in _nodes:
		node.free()
	_nodes.clear()


func teardown() -> void:
	_cleanup()


func test_plain_use_succeeds_sets_flags_and_autosaves() -> void:
	_fresh()
	var it: Interactable = _wire(Interactable.new())
	it.id = &"altar"
	it.sets_flag = &"altar_touched"
	it.once_flag = &"altar_done"
	assert_true(it.can_interact(), "a plain thing can be used")
	assert_eq(it.prompt_text(), "Examine", "default prompt is shown")
	assert_true(it.interact(null), "plain use succeeds")
	assert_true(_flags.has(&"altar_touched"), "sets_flag was set")
	assert_true(_flags.has(&"altar_done"), "once_flag was set")
	assert_eq(_interactions, 1, "interacted emitted once")
	assert_eq(_save.autosaves, 1, "one autosave requested")
	assert_eq(_refusals.size(), 0, "nothing refused")


func test_spent_reports_empty_prompt_and_refuses() -> void:
	_fresh()
	var it: Interactable = _wire(Interactable.new())
	it.once_flag = &"done"
	_flags.set_flag(&"done")
	assert_true(it.is_spent(), "once_flag set means spent")
	assert_eq(it.prompt_text(), "", "spent things offer no prompt")
	assert_false(it.can_interact(), "spent things cannot be used")
	assert_false(it.interact(null), "spent use fails")
	assert_eq(_refusals, ["It does not yield."], "refused with the default text")
	assert_eq(_interactions, 0, "no interaction")
	assert_eq(_save.autosaves, 0, "no autosave on refusal")


func test_required_item_missing_names_the_item_then_present_succeeds() -> void:
	_fresh()
	var it: Interactable = _wire(Interactable.new())
	it.required_item = &"hammer"
	assert_false(it.interact(null), "refused without the hammer")
	assert_eq(_refusals[0], "You need the Hammer.", "refusal names the item by its in-world name")
	_inventory.add(&"hammer")
	assert_true(it.interact(null), "succeeds with the hammer")
	assert_eq(_inventory.count(&"hammer"), 1, "non-consuming use leaves the item")


func test_consumes_item_removes_exactly_one() -> void:
	_fresh()
	var it: Interactable = _wire(Interactable.new())
	it.required_item = &"kindling_grey"
	it.consumes_item = true
	_inventory.add(&"kindling_grey", 2)
	assert_true(it.interact(null), "first use succeeds")
	assert_eq(_inventory.count(&"kindling_grey"), 1, "exactly one consumed")
	assert_true(it.interact(null), "second use succeeds")
	assert_eq(_inventory.count(&"kindling_grey"), 0, "second one consumed")
	assert_false(it.interact(null), "third use refused with none left")
	assert_eq(_refusals[0], "You need the Grey Kindling.", "refusal names the kindling")


func test_required_flag_gates_both_ways() -> void:
	_fresh()
	var it: Interactable = _wire(Interactable.new())
	it.required_flag = &"gate_open"
	it.refusal_text = "The way is shut."
	assert_false(it.can_interact(), "blocked while the flag is missing")
	assert_false(it.interact(null), "refused while the flag is missing")
	assert_eq(_refusals[0], "The way is shut.", "configured refusal text is used")
	_flags.set_flag(&"gate_open")
	assert_true(it.can_interact(), "open once the flag is set")
	assert_true(it.interact(null), "succeeds once the flag is set")


func test_missing_autoloads_degrade_without_crashing() -> void:
	_fresh()
	var it := Interactable.new()
	_nodes.append(it)
	assert_true(it.interact(null), "a plain thing still works with no autoloads")
	it.once_flag = &"x"
	assert_false(it.is_spent(), "no Flags means never spent")
	it.required_item = &"hammer"
	assert_false(it.can_interact(), "no Inventory means the item is not held")
	assert_eq(it.refusal_reason(), it.refusal_text, "falls back to refusal_text without item names")


func test_chest_gives_contents_once() -> void:
	_fresh()
	var chest: Chest = _wire(Chest.new()) as Chest
	chest.once_flag = &"chest_done"
	chest.contents = {"kindling_grey": 1, "torch": 2}
	assert_true(chest.interact(null), "chest opens")
	assert_eq(_inventory.count(&"kindling_grey"), 1, "kindling granted")
	assert_eq(_inventory.count(&"torch"), 2, "torches granted with their count")
	assert_false(chest.interact(null), "an opened chest refuses")
	assert_eq(_inventory.count(&"kindling_grey"), 1, "never granted twice")
	assert_eq(_inventory.count(&"torch"), 2, "never granted twice")
	assert_eq(chest.prompt_text(), "", "an opened chest offers no prompt")


func test_pickup_hides_itself_and_gives_item() -> void:
	_fresh()
	var pickup: Pickup = _wire(Pickup.new()) as Pickup
	pickup.item = &"hammer"
	pickup.once_flag = &"hammer_taken"
	assert_true(pickup.visible, "visible before being taken")
	assert_true(pickup.interact(null), "pickup is taken")
	assert_false(pickup.visible, "hidden once taken")
	assert_eq(_inventory.count(&"hammer"), 1, "hammer in inventory")
	assert_true(pickup.is_spent(), "taken pickup is spent")
	assert_false(pickup.interact(null), "cannot be taken twice")


func test_lever_toggles_on_and_off() -> void:
	_fresh()
	var lever: Lever = _wire(Lever.new()) as Lever
	lever.sets_flag = &"sluice_open"
	assert_false(lever.is_on(), "starts off")
	assert_true(lever.interact(null), "first pull")
	assert_true(lever.is_on(), "on after one pull")
	assert_true(_flags.has(&"sluice_open"), "flag set when on")
	assert_true(lever.interact(null), "second pull")
	assert_false(lever.is_on(), "off after two pulls")
	assert_false(_flags.has(&"sluice_open"), "flag cleared when off")
	assert_true(lever.interact(null), "third pull")
	assert_true(lever.is_on(), "on again")
	assert_true(_flags.has(&"sluice_open"), "flag set again")
	assert_eq(lever.prompt_text(), "Examine", "a lever is never spent")


func test_door_opens_only_after_successful_interact() -> void:
	_fresh()
	var door: Door = _wire(Door.new()) as Door
	door.required_flag = &"lever_pulled"
	door.required_item = &"castle_key"
	door.refusal_text = "Barred."
	assert_false(door.is_open(), "closed at start")
	assert_false(door.interact(null), "refused while barred")
	assert_false(door.is_open(), "still closed after a refusal")
	assert_eq(_refusals[0], "Barred.", "flag refusal comes first")
	_flags.set_flag(&"lever_pulled")
	assert_false(door.interact(null), "refused without the key")
	assert_eq(_refusals[1], "You need the Castle Key.", "then the key is asked for by name")
	assert_false(door.is_open(), "still closed without the key")
	_inventory.add(&"castle_key")
	assert_true(door.interact(null), "opens with lever pulled and key held")
	assert_true(door.is_open(), "reports open after success")
	assert_eq(_inventory.count(&"castle_key"), 1, "the key is not consumed")


func test_lore_stone_emits_text_from_data_and_is_repeatable() -> void:
	_fresh()
	var stone: LoreStone = _wire(LoreStone.new()) as LoreStone
	stone.lore_key = "grave_marker"
	var readings: Array[Array] = []
	stone.reading_requested.connect(func(title: String, body: String) -> void: readings.append([title, body]))
	assert_true(stone.interact(null), "first reading")
	assert_true(stone.interact(null), "a stone can be read again")
	assert_eq(readings.size(), 2, "one reading per use")
	assert_eq(readings[0][0], "Grave Marker", "title comes from data/lore.json")
	assert_true(readings[0][1].length() > 40, "body comes from data/lore.json")
	stone.lore_key = "no_such_key"
	stone.interact(null)
	assert_eq(readings[2][0], "Worn Stone", "an unknown key reads as a worn stone, not a crash")
	for key: String in ["grave_marker", "chapel_inscription", "sluice_notice", "shrine_verse", "windmill_verse", "crypt_verse"]:
		var entry: Dictionary = LoreStone.lore_entry(key)
		assert_true(entry.has("title") and entry.has("body"), "lore entry '%s' has a title and body" % key)


func test_refusal_reason_never_leaks_engine_words() -> void:
	_fresh()
	var reasons: Array[String] = []
	var spent: Interactable = _wire(Interactable.new())
	spent.once_flag = &"used"
	_flags.set_flag(&"used")
	reasons.append(spent.refusal_reason())
	var gated: Interactable = _wire(Interactable.new())
	gated.required_flag = &"never_set"
	reasons.append(gated.refusal_reason())
	var needs_known: Interactable = _wire(Interactable.new())
	needs_known.required_item = &"sword"
	reasons.append(needs_known.refusal_reason())
	var needs_unknown: Interactable = _wire(Interactable.new())
	needs_unknown.required_item = &"no_such_item"
	reasons.append(needs_unknown.refusal_reason())
	for reason: String in reasons:
		assert_true(reason.length() > 0, "every refusal says something")
		for word: String in ENGINE_WORDS:
			assert_false(reason.to_lower().contains(word), "'%s' leaks the engine word '%s'" % [reason, word])


func test_detector_scoring_prefers_centre_then_distance() -> void:
	var centred: float = InteractionDetector.score(0.0, 1.0, 75.0, 3.2)
	var off_centre: float = InteractionDetector.score(10.0, 1.0, 75.0, 3.2)
	assert_true(centred > off_centre, "more centred wins at equal distance")
	var near: float = InteractionDetector.score(10.0, 1.0, 75.0, 3.2)
	var far: float = InteractionDetector.score(10.0, 2.5, 75.0, 3.2)
	assert_true(near > far, "closer wins at equal angle")
	assert_true(InteractionDetector.score(5.0, 3.0, 75.0, 3.2) > InteractionDetector.score(40.0, 0.5, 75.0, 3.2),
		"centring dominates distance")
	assert_true(InteractionDetector.score(12.0, 1.0, 75.0, 3.2) > InteractionDetector.score(10.0, 2.5, 75.0, 3.2),
		"a hair less centred but a stride closer still wins")
	assert_eq(InteractionDetector.score(0.0, 3.3, 75.0, 3.2), -1.0, "beyond reach is rejected")
	assert_eq(InteractionDetector.score(80.0, 1.0, 75.0, 3.2), -1.0, "outside the view cone is rejected")
	assert_true(is_equal_approx(InteractionDetector.score(0.0, 0.0, 75.0, 3.2), 1.0), "dead centre and touching scores 1")
	assert_true(is_zero_approx(InteractionDetector.score(75.0, 3.2, 75.0, 3.2)), "the edge of both limits scores 0, still eligible")
	assert_eq(InteractionDetector.score(0.0, 1.0, 0.0, 3.2), -1.0, "a zero view cone rejects everything")
