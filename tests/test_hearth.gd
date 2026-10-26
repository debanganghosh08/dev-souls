extends "res://tests/test_case.gd"
## The endgame decision (scripts/systems/hearth.gd). The game has exactly two endings and one question that
## picks between them, so every branch is worth pinning: an ending that fires early, or the true ending
## handed out without the Name, is the kind of bug a player only ever hits once.
##
## Everything here is pure -- plain dictionaries in, an enum out -- which is the point of keeping the rule
## out of the scene. Definitions come from the real data/items.json so the test fails if someone adds a
## Kindling without telling the Hearth, which is precisely the drift the design is meant to prevent.

const ITEMS := "res://data/items.json"

var _defs: Dictionary = {}
var _cfg: Dictionary = {}


func setup() -> void:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(ITEMS))
	if data is Dictionary:
		for key: Variant in (data as Dictionary):
			if (data as Dictionary)[key] is Dictionary:
				_defs[StringName(str(key))] = (data as Dictionary)[key]
	_cfg = Hearth.load_from()


func _held(ids: Array) -> Dictionary:
	var out: Dictionary = {}
	for id: Variant in ids:
		out[StringName(str(id))] = 1
	return out


func _all(kind: String) -> Array:
	var out: Array = []
	for id: StringName in Hearth.required_ids(_defs, kind):
		out.append(id)
	return out


func _drained() -> Array:
	return [StringName(str(_cfg["requires_flag"]))]


# --- config ----------------------------------------------------------------------------------------------

func test_the_real_data_file_parses_and_names_the_kinds() -> void:
	assert_eq(str(_cfg["kindling_kind"]), "kindling", "the Kindling requirement is an item kind")
	assert_eq(str(_cfg["name_kind"]), "fragment", "the Name requirement is an item kind")
	assert_ne(str(_cfg["requires_flag"]), "", "reaching the Hearth is gated by a flag")
	assert_ne(str(_cfg["rekindled_flag"]), str(_cfg["consumed_flag"]), "the two endings record differently")


func test_a_missing_or_malformed_file_falls_back_to_the_defaults() -> void:
	# Bad tuning data must never be able to stop the game from ending.
	var gone: Dictionary = Hearth.load_from("res://data/no_such_hearth.json", false)
	assert_eq(gone, Hearth.DEFAULTS, "a missing file yields the built-in defaults")
	var junk: Dictionary = Hearth.load_from(ITEMS, false)
	assert_eq(str(junk["kindling_kind"]), "kindling", "a file of the wrong shape still leaves usable config")


func test_a_comment_in_the_file_is_not_treated_as_configuration() -> void:
	assert_false(Hearth.load_from().has("_comment"), "only known keys are read")


# --- the requirement -------------------------------------------------------------------------------------

func test_the_requirement_is_derived_from_item_kind_in_declared_order() -> void:
	var kindling: Array = _all("kindling")
	assert_eq(kindling.size(), 3, "three Kindlings exist in data/items.json")
	assert_eq(kindling, [&"kindling_grey", &"kindling_green", &"kindling_red"], "in items.json's own order")
	var name_parts: Array = _all("fragment")
	assert_eq(name_parts.size(), 3, "the Name is in three fragments")
	assert_eq(name_parts[0], &"name_fragment_crypt", "ordered by the items file, not by id")


func test_the_hearth_and_the_inventory_panel_agree_on_the_kindling_count() -> void:
	# Two places derive this from item kind. If they ever disagree the player is told to find something the
	# Hearth does not want, or the other way round, and nothing else in the suite would notice.
	var held: Dictionary = _held([&"kindling_grey"])
	var rows: Array[Dictionary] = InventoryRows.build_rows(_defs, held)
	assert_eq(Hearth.progress(_defs, held, "kindling"), InventoryRows.kindling_progress(rows),
			"the Hearth and the inventory panel count the same Kindling")


func test_missing_reports_what_is_absent_in_requirement_order() -> void:
	var held: Dictionary = _held([&"kindling_green"])
	assert_eq(Hearth.missing(_defs, held, "kindling"), [&"kindling_grey", &"kindling_red"] as Array[StringName],
			"the two that are not held, in order")
	assert_true(Hearth.missing(_defs, _held(_all("kindling")), "kindling").is_empty(), "nothing missing when all held")
	var names: Array[String] = Hearth.missing_names(_defs, held, "kindling")
	assert_eq(names[0], "Grey Kindling", "a refusal can name the item the way the world does")


func test_an_item_counted_under_either_key_type_still_counts() -> void:
	# items.json parses to String keys; Inventory.add uses StringName. Both reach this code.
	assert_eq(Hearth.progress(_defs, {"kindling_grey": 1}, "kindling"), Vector2i(1, 3), "String key counts")
	assert_eq(Hearth.progress(_defs, {&"kindling_grey": 1}, "kindling"), Vector2i(1, 3), "StringName key counts")
	assert_eq(Hearth.progress(_defs, {&"kindling_grey": 0}, "kindling"), Vector2i(0, 3), "a zero count is not held")


# --- reaching it -----------------------------------------------------------------------------------------

func test_the_hearth_is_out_of_reach_until_the_pond_is_drained() -> void:
	var everything: Dictionary = _held(_all("kindling") + _all("fragment"))
	assert_false(Hearth.is_reachable([], _cfg), "the pond still covers the way down")
	assert_eq(Hearth.ending_for(_defs, everything, [], _cfg), Hearth.Ending.UNREACHABLE,
			"carrying everything does not open the basin")
	assert_true(Hearth.is_reachable(_drained(), _cfg), "the drained flag opens it")


func test_an_empty_gate_flag_means_always_reachable() -> void:
	# How a test level or a debug run gets to the Hearth without draining anything.
	var cfg: Dictionary = _cfg.duplicate()
	cfg["requires_flag"] = ""
	assert_true(Hearth.is_reachable([], cfg), "no gate flag, no gate")


# --- the decision ----------------------------------------------------------------------------------------

func test_every_kindling_is_needed_before_either_ending() -> void:
	var two: Dictionary = _held([&"kindling_grey", &"kindling_red"] + _all("fragment"))
	assert_eq(Hearth.ending_for(_defs, two, _drained(), _cfg), Hearth.Ending.NOT_READY,
			"the whole Name does not substitute for the fuel")
	assert_false(Hearth.is_ending(Hearth.Ending.NOT_READY), "NOT_READY does not end the game")


func test_the_name_decides_which_ending() -> void:
	var fuel_only: Dictionary = _held(_all("kindling"))
	assert_eq(Hearth.ending_for(_defs, fuel_only, _drained(), _cfg), Hearth.Ending.BECOME_FLAME,
			"all the Kindling and no Name: the Hearth takes the Wick")
	var partial: Dictionary = _held(_all("kindling") + [&"name_fragment_crypt", &"name_fragment_shrine"])
	assert_eq(Hearth.ending_for(_defs, partial, _drained(), _cfg), Hearth.Ending.BECOME_FLAME,
			"two syllables of three is not the Name")
	var whole: Dictionary = _held(_all("kindling") + _all("fragment"))
	assert_eq(Hearth.ending_for(_defs, whole, _drained(), _cfg), Hearth.Ending.REKINDLE,
			"all the Kindling and the whole Name: the true ending")


func test_each_ending_leaves_its_own_flag_and_the_others_leave_none() -> void:
	assert_eq(Hearth.ending_flag(Hearth.Ending.REKINDLE, _cfg), StringName(str(_cfg["rekindled_flag"])),
			"rekindling is recorded")
	assert_eq(Hearth.ending_flag(Hearth.Ending.BECOME_FLAME, _cfg), StringName(str(_cfg["consumed_flag"])),
			"being consumed is recorded too")
	assert_eq(Hearth.ending_flag(Hearth.Ending.NOT_READY, _cfg), &"", "a refusal records nothing")
	assert_eq(Hearth.ending_flag(Hearth.Ending.UNREACHABLE, _cfg), &"", "an unreachable Hearth records nothing")
	assert_true(Hearth.is_ending(Hearth.Ending.REKINDLE) and Hearth.is_ending(Hearth.Ending.BECOME_FLAME),
			"both outcomes end the game")


func test_a_finished_journey_stays_finished() -> void:
	assert_false(Hearth.is_finished([], _cfg), "an untouched Hearth is not finished")
	assert_true(Hearth.is_finished([StringName(str(_cfg["rekindled_flag"]))], _cfg), "rekindled is finished")
	assert_true(Hearth.is_finished([StringName(str(_cfg["consumed_flag"]))], _cfg), "consumed is finished")
	assert_false(Hearth.is_finished(_drained(), _cfg), "draining the pond is not an ending")
