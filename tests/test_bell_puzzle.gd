extends "res://tests/test_case.gd"
## Bell puzzle tests. The sequence rule is BellPuzzle.advance, a pure static function, so most of this file
## needs no node at all. The node-level tests instance BellPuzzle outside any tree (no _ready, no autoloads)
## and inject the real Flags script, exactly as test_interactable.gd does for props.

const FLAGS_SCRIPT := "res://scripts/autoloads/flags.gd"
const PUZZLE_PATH := "res://data/puzzles/vale.json"
const ORDER: Array = [2, 0, 1]

var _nodes: Array[Node] = []


func teardown() -> void:
	for node: Node in _nodes:
		node.free()
	_nodes.clear()


func test_correct_sequence_completes_step_by_step() -> void:
	var r: Dictionary = BellPuzzle.advance([], ORDER, 2)
	assert_eq(r["progress"], [2], "first correct ring is credited")
	assert_false(r["completed"], "one ring of three does not complete")
	assert_false(r["reset"], "a correct ring is not a reset")
	r = BellPuzzle.advance(r["progress"], ORDER, 0)
	assert_eq(r["progress"], [2, 0], "second correct ring appends")
	assert_false(r["completed"], "two rings of three do not complete")
	r = BellPuzzle.advance(r["progress"], ORDER, 1)
	assert_eq(r["progress"], [2, 0, 1], "third ring fills the sequence")
	assert_true(r["completed"], "the full order completes")
	assert_false(r["reset"], "completion is not a reset")


func test_wrong_first_ring_resets_to_empty() -> void:
	var r: Dictionary = BellPuzzle.advance([], ORDER, 1)
	assert_eq(r["progress"], [], "a wrong first ring leaves nothing credited")
	assert_true(r["reset"], "a wrong ring reports a reset")
	assert_false(r["completed"], "a wrong ring never completes")


func test_wrong_ring_after_partial_progress_resets_rather_than_partially_credits() -> void:
	var r: Dictionary = BellPuzzle.advance([2, 0], ORDER, 0)
	assert_eq(r["progress"], [], "progress [2, 0] then a wrong bell is wiped, not kept at two")
	assert_true(r["reset"], "the wrong ring is reported as a reset")
	assert_false(r["completed"], "no completion on a wrong ring")


func test_wrong_ring_that_is_the_first_bell_restarts_the_attempt() -> void:
	# The reset rule still fires, but the ring that broke the sequence is judged as a fresh first ring.
	var r: Dictionary = BellPuzzle.advance([2, 0], ORDER, 2)
	assert_true(r["reset"], "ringing bell 2 at the third step resets")
	assert_eq(r["progress"], [2], "...and that same ring starts a new attempt, so 2,0,2,0,1 solves")
	r = BellPuzzle.advance(r["progress"], ORDER, 0)
	r = BellPuzzle.advance(r["progress"], ORDER, 1)
	assert_true(r["completed"], "the restarted attempt completes normally")


func test_same_bell_twice_in_a_row_resets_when_the_order_has_no_repeat() -> void:
	var r: Dictionary = BellPuzzle.advance([2], ORDER, 2)
	assert_true(r["reset"], "2 then 2 is a wrong ring for [2, 0, 1]")
	assert_eq(r["progress"], [2], "the second 2 restarts as a first ring (2,2,0,1 solves)")
	var twice: Dictionary = BellPuzzle.advance([0], [0, 0, 1], 0)
	assert_false(twice["reset"], "an order that repeats a bell accepts the repeat")
	assert_eq(twice["progress"], [0, 0], "the repeated bell is credited when the order asks for it")


func test_advance_never_mutates_its_inputs() -> void:
	var progress: Array = [2]
	var required: Array = ORDER.duplicate()
	BellPuzzle.advance(progress, required, 0)
	BellPuzzle.advance(progress, required, 1)
	assert_eq(progress, [2], "the caller's progress array is untouched")
	assert_eq(required, ORDER, "the required order is untouched")


func test_degenerate_inputs_do_not_crash() -> void:
	var empty: Dictionary = BellPuzzle.advance([], [], 0)
	assert_eq(empty["progress"], [], "empty required order credits nothing")
	assert_false(empty["completed"], "empty required order never completes")
	assert_false(empty["reset"], "empty required order never resets")
	var out_of_range: Dictionary = BellPuzzle.advance([2], ORDER, 99)
	assert_true(out_of_range["reset"], "an index no bell has is a wrong ring")
	assert_eq(out_of_range["progress"], [], "...and credits nothing")
	var negative: Dictionary = BellPuzzle.advance([], ORDER, -1)
	assert_true(negative["reset"], "a negative index is a wrong ring")
	var overfull: Dictionary = BellPuzzle.advance([2, 0, 1], ORDER, 2)
	assert_true(overfull["reset"], "ringing past a full sequence is judged as a new attempt")
	assert_eq(overfull["progress"], [2], "...starting over from the first bell")
	var single: Dictionary = BellPuzzle.advance([], [1], 1)
	assert_true(single["completed"], "a one-bell order completes on its bell")


func test_required_order_comes_from_data() -> void:
	var config: Dictionary = BellPuzzle.load_config(PUZZLE_PATH, "bells")
	var required: Array[int] = BellPuzzle.parse_required(config)
	assert_eq(required.size(), 3, "vale.json names three bells")
	assert_eq(required, [2, 0, 1], "vale.json order is sluice, gate, watch (years 3, 7, 11 on the headstones)")
	for i: int in required:
		assert_true(i >= 0 and i <= 2, "every index is one of the three castle bells (got %d)" % i)
	var lore_keys: Array[String] = ["grave_sluice_keeper", "grave_gatekeeper", "grave_watch", "chapel_inscription"]
	for key: String in lore_keys:
		assert_ne(LoreStone.lore_entry(key).get("title", ""), "", "lore entry '%s' that discloses the order exists" % key)


func test_missing_or_malformed_data_falls_back_without_crashing() -> void:
	assert_eq(BellPuzzle.load_config("res://data/puzzles/does_not_exist.json", "bells"), {}, "missing file gives {}")
	assert_eq(BellPuzzle.load_config("res://AGENTS.md", "bells"), {}, "non-JSON file gives {}")
	assert_eq(BellPuzzle.load_config(PUZZLE_PATH, "no_such_puzzle"), {}, "unknown puzzle key gives {}")
	assert_eq(BellPuzzle.parse_required({}), [], "no required_order gives an empty order")
	assert_eq(BellPuzzle.parse_required({"required_order": "2,0,1"}), [], "a string order is rejected")
	assert_eq(BellPuzzle.parse_required({"required_order": [2, "x", 1]}), [], "a non-numeric entry rejects the whole order")
	assert_eq(BellPuzzle.parse_required({"required_order": [2.0, 0.0, 1.0]}), [2, 0, 1], "JSON whole floats are accepted as indices")
	assert_eq(BellPuzzle.parse_required({"required_order": [1.5]}), [], "a fractional index is rejected")
	var puzzle: BellPuzzle = _puzzle({})
	puzzle.on_bell_rung(2)
	puzzle.on_bell_rung(0)
	puzzle.on_bell_rung(1)
	assert_false(puzzle.is_solved(), "an unconfigured puzzle cannot be solved by any sequence")
	assert_false(puzzle.is_configured(), "an unconfigured puzzle says so")


func test_node_solves_sets_flag_reveals_reward_and_does_not_regrant() -> void:
	var puzzle: BellPuzzle = _puzzle(BellPuzzle.load_config(PUZZLE_PATH, "bells"))
	var flags: Node = puzzle.get_meta(&"flags")
	var solved_count: Array[int] = [0]
	var resets_seen: Array[int] = []
	puzzle.solved.connect(func() -> void: solved_count[0] += 1)
	puzzle.sequence_reset.connect(func(rung: int) -> void: resets_seen.append(rung))
	var prize: Area3D = puzzle.get_node(^"Prize") as Area3D
	assert_false(prize.visible, "the reward starts hidden")
	puzzle.on_bell_rung(0)
	assert_eq(puzzle.resets, 1, "a wrong first bell counts one reset")
	assert_eq(resets_seen, [0], "the reset signal names the offending bell")
	puzzle.on_bell_rung(2)
	puzzle.on_bell_rung(0)
	assert_false(puzzle.is_solved(), "two of three is not solved")
	puzzle.on_bell_rung(1)
	assert_true(puzzle.is_solved(), "the data order solves the puzzle")
	assert_true(flags.has(&"vale_bells_rung"), "solving sets the flag from vale.json")
	assert_true(prize.visible and prize.monitorable, "solving reveals the reward in the bell-bed")
	assert_true((puzzle.get_node(^"Chapel") as ChapelBell).is_fallen(), "solving drops the chapel bell")
	assert_eq(solved_count[0], 1, "solved emitted once")
	for i: int in [2, 0, 1, 2, 0, 1, 0, 0]:
		puzzle.on_bell_rung(i)
	assert_eq(solved_count[0], 1, "repeating the order (or anything) after solving does not re-grant")
	assert_eq(puzzle.resets, 1, "rings after solving are ignored, not counted as resets")


func test_node_restores_solved_state_from_flag() -> void:
	var puzzle: BellPuzzle = _puzzle(BellPuzzle.load_config(PUZZLE_PATH, "bells"))
	var flags: Node = puzzle.get_meta(&"flags")
	flags.set_flag(&"vale_bells_rung")
	puzzle._ready()
	assert_true(puzzle.is_solved(), "a saved flag restores the solved state on load")
	assert_true((puzzle.get_node(^"Prize") as Area3D).visible, "...and the reward is already revealed")


# A detached BellPuzzle with the real Flags script injected, a hidden Area3D reward and a ChapelBell child.
func _puzzle(config: Dictionary) -> BellPuzzle:
	var puzzle := BellPuzzle.new()
	var flags: Node = (load(FLAGS_SCRIPT) as GDScript).new()
	var prize := Area3D.new()
	prize.name = "Prize"
	prize.visible = false
	prize.monitorable = false
	puzzle.add_child(prize)
	var chapel := ChapelBell.new()
	chapel.name = "Chapel"
	puzzle.add_child(chapel)
	puzzle.reward = NodePath("Prize")
	puzzle.chapel_bell = NodePath("Chapel")
	puzzle._inject(flags)
	puzzle.configure(config)
	puzzle.set_meta(&"flags", flags)
	_nodes.append_array([puzzle, flags])
	return puzzle
