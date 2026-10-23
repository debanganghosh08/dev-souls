extends "res://tests/test_case.gd"

const InventoryScript := preload("res://scripts/autoloads/inventory.gd")

var inv: Node
var added: Array = []
var removed: Array = []


func setup() -> void:
	inv = InventoryScript.new()
	inv._load_definitions()
	inv.item_added.connect(func(id: StringName, n: int) -> void: added.append([id, n]))
	inv.item_removed.connect(func(id: StringName, n: int) -> void: removed.append([id, n]))


func teardown() -> void:
	inv.free()


func test_definitions_loaded() -> void:
	assert_eq(inv.all_definitions().size(), 13, "items.json has 13 ids")
	assert_eq(inv.definition(&"torch")["kind"], "tool", "torch is a tool")
	assert_eq(inv.definition(&"nope"), {}, "unknown definition is empty")


func test_add_and_count() -> void:
	inv.restore({})
	added.clear()
	inv.add(&"torch")
	inv.add(&"torch", 2)
	assert_eq(inv.count(&"torch"), 3, "count accumulates")
	assert_true(inv.has(&"torch"), "has after add")
	assert_eq(added, [[&"torch", 1], [&"torch", 2]], "item_added per call")


func test_add_clamps_amount() -> void:
	inv.restore({})
	inv.add(&"hammer", 0)
	inv.add(&"hammer", -5)
	assert_eq(inv.count(&"hammer"), 2, "amount <= 0 counts as 1")


func test_unknown_id_ignored() -> void:
	inv.restore({})
	added.clear()
	inv.add(&"dragon_egg")
	assert_eq(inv.count(&"dragon_egg"), 0, "unknown item never stored")
	assert_false(inv.has(&"dragon_egg"), "has is false")
	assert_eq(added.size(), 0, "no signal for unknown item")


func test_remove_more_than_held_fails() -> void:
	inv.restore({"torch": 2})
	removed.clear()
	assert_false(inv.remove(&"torch", 3), "cannot remove 3 of 2")
	assert_eq(inv.count(&"torch"), 2, "nothing removed on failure")
	assert_false(inv.remove(&"sword"), "cannot remove unheld item")
	assert_eq(removed.size(), 0, "no signal on failure")


func test_remove_to_zero_erases_key() -> void:
	inv.restore({"torch": 2})
	assert_true(inv.remove(&"torch", 2), "exact removal succeeds")
	assert_eq(inv.count(&"torch"), 0, "count never negative")
	assert_false(inv.items().has(&"torch"), "key erased at zero")
	assert_eq(removed, [[&"torch", 2]], "item_removed emitted")


func test_remove_partial() -> void:
	inv.restore({"kindling_grey": 3})
	assert_true(inv.remove(&"kindling_grey", -1), "amount clamps to 1")
	assert_eq(inv.count(&"kindling_grey"), 2, "one removed")


func test_items_is_copy() -> void:
	inv.restore({"sword": 1})
	var copy: Dictionary = inv.items()
	copy[&"sword"] = 99
	assert_eq(inv.count(&"sword"), 1, "mutating the copy does not touch state")


func test_to_dict_and_restore_round_trip() -> void:
	inv.restore({})
	inv.add(&"castle_key")
	inv.add(&"torch", 4)
	var data: Dictionary = inv.to_dict()
	assert_eq(data, {"castle_key": 1, "torch": 4}, "to_dict uses String keys")
	inv.restore({"sword": 1, "torch": 0, "bell_rope": -2})
	assert_eq(inv.items(), {&"sword": 1}, "restore drops zero/negative and replaces state")
