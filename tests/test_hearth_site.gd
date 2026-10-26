extends "res://tests/test_case.gd"
## The Hearth as a prop (scripts/systems/interactables/hearth_site.gd): the four outcomes of using it, with
## the real Flags, Inventory and Game scripts instanced and injected the way tests/test_interactable.gd
## does. Nothing enters a tree, so the light and ember are absent and the flare snaps; what is proven is
## the branching -- that a refusal sets no flag and ends no run, that each ending records its own flag and
## reaches Game.end_journey, and that a finished Hearth refuses on load.

const FLAGS_SCRIPT := "res://scripts/autoloads/flags.gd"
const INVENTORY_SCRIPT := "res://scripts/autoloads/inventory.gd"
const GameScript := preload("res://scripts/autoloads/game.gd")
const CHAMBER_SCENE := "res://scenes/structures/hearth_chamber.tscn"
const LAYOUT := "res://data/structures/hearth_chamber.json"
const ENGINE_WORDS: Array[String] = ["flag", "null", "nil", "res://", "stringname", "%s"]


class SaveStub extends Node:
	var autosaves: int = 0

	func request_autosave() -> void:
		autosaves += 1


var _flags: Node
var _inventory: Node
var _save: SaveStub
var _game: Node
var _nodes: Array[Node] = []
var _refusals: Array[String] = []
var _endings: Array[int] = []
var _defs: Dictionary = {}


func setup() -> void:
	var inv: Node = (load(INVENTORY_SCRIPT) as GDScript).new()
	inv._load_definitions()
	_defs = inv.all_definitions().duplicate()
	inv.free()


func _fresh() -> void:
	_cleanup()
	_flags = (load(FLAGS_SCRIPT) as GDScript).new()
	_inventory = (load(INVENTORY_SCRIPT) as GDScript).new()
	_inventory._load_definitions()
	_save = SaveStub.new()
	_game = GameScript.new()
	_game.state = _game.State.PLAYING
	_game.journey_ended.connect(func(e: int) -> void: _endings.append(e))
	_nodes.append_array([_flags, _inventory, _save, _game])
	_refusals.clear()
	_endings.clear()


func _hearth() -> HearthSite:
	var site := HearthSite.new()
	site._inject(_flags, _inventory, _save)
	site._inject_game(_game)
	site.refused.connect(func(reason: String) -> void: _refusals.append(reason))
	_nodes.append(site)
	return site


func _give(kind: String) -> void:
	for id: StringName in Hearth.required_ids(_defs, kind):
		_inventory.add(id)


func _cleanup() -> void:
	for node: Node in _nodes:
		node.free()
	_nodes.clear()


func teardown() -> void:
	_cleanup()


# --- refusals ---------------------------------------------------------------------------------------------

func test_a_sealed_hearth_refuses_and_sets_nothing() -> void:
	_fresh()
	_give("kindling")
	_give("fragment")
	var site: HearthSite = _hearth()
	assert_eq(site.decide(), Hearth.Ending.UNREACHABLE, "carrying everything does not open the basin")
	assert_false(site.can_interact(), "the Hearth cannot be used while the pond covers it")
	assert_false(site.interact(null), "use is refused")
	assert_eq(_refusals, [UiText.text("hearth_sealed")], "the refusal is the sealed line from data/ui_text.json")
	assert_eq(_flags.all_flags(), [], "a refusal sets no flag")
	assert_false(_game.journey_is_over(), "a refusal does not end the run")
	assert_eq(_endings.size(), 0, "no ending was announced")
	assert_eq(_save.autosaves, 0, "no autosave on a refusal")
	assert_false(site.is_spent(), "the Hearth is not spent by refusing")
	assert_eq(site.prompt_text(), UiText.text("hearth_prompt"), "the prompt stays, so the Hearth stays usable")


func test_a_drained_but_unfed_hearth_names_what_is_still_wanting() -> void:
	_fresh()
	_flags.set_flag(&"pond_drained")
	_inventory.add(&"kindling_grey")
	var site: HearthSite = _hearth()
	assert_eq(site.decide(), Hearth.Ending.NOT_READY, "one Kindling of three is not ready")
	assert_false(site.interact(null), "use is refused")
	assert_eq(_refusals.size(), 1, "one refusal")
	var line: String = _refusals[0] if not _refusals.is_empty() else ""
	assert_true(line.contains("Green Kindling") and line.contains("Red Kindling"), "the two missing Kindlings are named: '%s'" % line)
	assert_false(line.contains("Grey Kindling"), "the one carried is not asked for: '%s'" % line)
	assert_true(line.find("Green") < line.find("Red"), "named in requirement order")
	assert_eq(_flags.all_flags(), [&"pond_drained"], "no new flag")
	assert_false(_game.journey_is_over(), "the run goes on")
	assert_eq(_inventory.count(&"kindling_grey"), 1, "nothing was consumed by a refusal")
	assert_eq(site.prompt_text(), UiText.text("hearth_prompt"), "still usable")


# --- endings ----------------------------------------------------------------------------------------------

func test_every_kindling_without_the_name_consumes_the_wick() -> void:
	_fresh()
	_flags.set_flag(&"pond_drained")
	_give("kindling")
	_inventory.add(&"name_fragment_crypt")
	var site: HearthSite = _hearth()
	assert_eq(site.decide(), Hearth.Ending.BECOME_FLAME, "fuel without the whole Name")
	assert_true(site.can_interact(), "an ending is a successful use")
	assert_true(site.interact(null), "use succeeds")
	assert_true(_flags.has(&"wick_consumed"), "being consumed is recorded")
	assert_false(_flags.has(&"hearth_rekindled"), "rekindling is not")
	assert_eq(_endings, [Hearth.Ending.BECOME_FLAME] as Array[int], "Game announced the consumed ending once")
	assert_true(_game.journey_is_over(), "the run is over")
	assert_eq(site.lit_ending(), Hearth.Ending.BECOME_FLAME, "the Hearth remembers which ending it gave")
	assert_eq(_save.autosaves, 1, "the ending is autosaved, so a finished journey stays finished")
	assert_eq(_refusals.size(), 0, "nothing was refused")


func test_every_kindling_and_the_whole_name_rekindles() -> void:
	_fresh()
	_flags.set_flag(&"pond_drained")
	_give("kindling")
	_give("fragment")
	var site: HearthSite = _hearth()
	assert_eq(site.decide(), Hearth.Ending.REKINDLE, "fuel and the whole Name")
	assert_true(site.interact(null), "use succeeds")
	assert_true(_flags.has(&"hearth_rekindled"), "rekindling is recorded")
	assert_false(_flags.has(&"wick_consumed"), "the Wick was not consumed")
	assert_eq(_endings, [Hearth.Ending.REKINDLE] as Array[int], "Game announced the true ending once")
	assert_true(_game.journey_is_over(), "the run is over")


func test_a_finished_hearth_is_spent_and_refuses_for_good() -> void:
	_fresh()
	_flags.set_flag(&"pond_drained")
	_give("kindling")
	_give("fragment")
	var site: HearthSite = _hearth()
	assert_true(site.interact(null), "the first use ends the journey")
	assert_true(site.is_spent(), "the Hearth is spent afterwards")
	assert_eq(site.prompt_text(), "", "a spent Hearth offers no prompt")
	assert_false(site.interact(null), "a second use is refused")
	assert_eq(_refusals, [UiText.text("hearth_spent")], "with the spent line")
	assert_eq(_endings.size(), 1, "the ending was not replayed")
	assert_eq(_save.autosaves, 1, "nothing more to save")


func test_a_finished_hearth_refuses_on_a_loaded_save() -> void:
	# The save holds the ending flag; this session's Hearth must find the fire already out.
	_fresh()
	_flags.restore([&"pond_drained", &"wick_consumed"])
	_give("kindling")
	_give("fragment")
	var site: HearthSite = _hearth()
	assert_true(site.is_spent(), "the recorded ending makes it spent before any use")
	assert_false(site.interact(null), "it refuses")
	assert_eq(_refusals, [UiText.text("hearth_spent")], "with the spent line")
	assert_false(_game.journey_is_over(), "end_journey was never called again")
	assert_eq(_flags.all_flags(), [&"pond_drained", &"wick_consumed"], "and the flags are untouched")


# --- robustness ---------------------------------------------------------------------------------------------

func test_refusal_lines_come_from_data_and_leak_no_engine_words() -> void:
	_fresh()
	var lines: Array[String] = []
	var sealed: HearthSite = _hearth()
	lines.append(sealed.refusal_reason())
	_flags.set_flag(&"pond_drained")
	lines.append(sealed.refusal_reason())
	_flags.set_flag(&"hearth_rekindled")
	lines.append(sealed.refusal_reason())
	for line: String in lines:
		assert_true(line.length() > 0, "every refusal says something")
		for word: String in ENGINE_WORDS:
			assert_false(line.to_lower().contains(word), "'%s' leaks the engine word '%s'" % [line, word])


func test_a_hearth_with_no_autoloads_refuses_without_crashing() -> void:
	_fresh()
	var site := HearthSite.new()
	_nodes.append(site)
	assert_eq(site.decide(), Hearth.Ending.UNREACHABLE, "nothing held and nothing set reads as sealed")
	assert_false(site.interact(null), "refused, never a free ending")
	assert_false(site.is_spent(), "and not spent")
	assert_ne(site.refusal_reason(), "", "a refusal still says something")
	assert_eq(site.config()["requires_flag"], "pond_drained", "the gate flag came from data/hearth.json")


# --- the scene ----------------------------------------------------------------------------------------------

func test_the_chamber_scene_seats_the_hearth_on_its_bowl() -> void:
	var root: Node = (load(CHAMBER_SCENE) as PackedScene).instantiate()
	_nodes.append(root)
	var site: HearthSite = root.get_node_or_null(^"Hearth") as HearthSite
	assert_not_null(site, "the chamber carries a HearthSite")
	if site == null:
		return
	assert_eq(site.id, &"the_hearth", "the Hearth has its id")
	assert_eq(site.collision_layer, Interactable.INTERACTABLE_LAYER, "it is on the interactable layer")
	assert_not_null(site.get_node_or_null(^"Light"), "it carries its own light")
	assert_not_null(site.get_node_or_null(^"Ember"), "and a visible ember")
	var layout: Dictionary = StructureBuilder.load_layout(LAYOUT)
	var bowl: Dictionary = {}
	for raw: Variant in layout.get("pieces", []):
		if str(raw.get("name", "")) == "hearth_bowl":
			bowl = raw
	assert_false(bowl.is_empty(), "the layout has the fire bowl")
	if bowl.is_empty():
		return
	var rim := Vector3(float(bowl["at"][0]), float(bowl["at"][1]) + float(bowl["params"]["h"]), float(bowl["at"][2]))
	assert_true(site.position.is_equal_approx(rim), "the Hearth sits on the bowl's rim (%s vs %s)" % [site.position, rim])
