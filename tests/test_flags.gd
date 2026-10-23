extends "res://tests/test_case.gd"

const FlagsScript := preload("res://scripts/autoloads/flags.gd")

var flags: Node
var set_count: int = 0
var cleared_count: int = 0


func setup() -> void:
	flags = FlagsScript.new()
	flags.flag_set.connect(func(_id: StringName) -> void: set_count += 1)
	flags.flag_cleared.connect(func(_id: StringName) -> void: cleared_count += 1)


func teardown() -> void:
	flags.free()


func test_set_twice_emits_once() -> void:
	set_count = 0
	flags.set_flag(&"kindling_grey_taken")
	flags.set_flag(&"kindling_grey_taken")
	assert_true(flags.has(&"kindling_grey_taken"), "flag should be set")
	assert_eq(set_count, 1, "flag_set should emit once")


func test_clear_emits_only_when_present() -> void:
	cleared_count = 0
	flags.set_flag(&"temp")
	flags.clear_flag(&"temp")
	flags.clear_flag(&"temp")
	assert_false(flags.has(&"temp"), "flag should be cleared")
	assert_eq(cleared_count, 1, "flag_cleared should emit once")


func test_has_all() -> void:
	flags.restore([&"a", &"b"])
	assert_true(flags.has_all([&"a", &"b"]), "both present")
	assert_false(flags.has_all([&"a", &"c"]), "c missing")
	assert_true(flags.has_all([]), "empty list is trivially satisfied")


func test_count_with_prefix() -> void:
	flags.restore([&"kindling_grey_taken", &"kindling_red_taken", &"castle_opened"])
	assert_eq(flags.count_with_prefix("kindling_"), 2, "two kindling flags")
	assert_eq(flags.count_with_prefix("nothing_"), 0, "no matches")


func test_all_flags_sorted() -> void:
	flags.restore([&"zeta", &"alpha", &"mid"])
	assert_eq(flags.all_flags(), [&"alpha", &"mid", &"zeta"], "sorted output")


func test_restore_replaces_state_silently() -> void:
	flags.set_flag(&"old")
	set_count = 0
	flags.restore(["new_one", &"new_two"])
	assert_false(flags.has(&"old"), "old flag gone")
	assert_true(flags.has(&"new_one"), "string ids become StringName")
	assert_true(flags.has(&"new_two"), "restored flag present")
	assert_eq(set_count, 0, "restore emits nothing")
