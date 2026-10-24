extends "res://tests/test_case.gd"
## Item card: fires once per id on Inventory.item_added, remembers that in a Flags flag, queues while the
## state is not PLAYING, and never acts when embedded. Real Game / Flags / Inventory scripts are injected;
## no tree exists, so nothing is tweened and deferred calls are driven by hand.

const InventoryScript := preload("res://scripts/autoloads/inventory.gd")
const FlagsScript := preload("res://scripts/autoloads/flags.gd")
const GameScript := preload("res://scripts/autoloads/game.gd")
const CARD := "res://scenes/ui/item_card.tscn"

var _inv: Node
var _flags: Node
var _game: Node
var _nodes: Array[Node] = []


func setup() -> void:
	_inv = InventoryScript.new()
	_inv._load_definitions()
	_flags = FlagsScript.new()
	_game = GameScript.new()
	_game.state = _game.State.PLAYING


func teardown() -> void:
	for node: Node in _nodes:
		node.free()
	_nodes.clear()
	_inv.free()
	_flags.free()
	_game.free()


# setup() runs once per file, so each test starts from a clean state and frees the cards before it: a
# card left alive would still listen to the shared Inventory and take the next test's acquisition.
func _card(embedded: bool = false) -> ItemCard:
	for node: Node in _nodes:
		node.free()
	_nodes.clear()
	_inv.restore({})
	_flags.restore([])
	_game.state = _game.State.PLAYING
	var card: ItemCard = (load(CARD) as PackedScene).instantiate() as ItemCard
	card.embedded = embedded
	card._inject(_game, _flags, _inv)
	_nodes.append(card)
	return card


func test_scene_structure_and_flag_name() -> void:
	var card: ItemCard = _card()
	assert_true(card.process_mode == Node.PROCESS_MODE_ALWAYS, "card runs while paused so it can close")
	for name: String in ["%Dim", "%Card", "%Kind", "%Title", "%Count", "%Body", "%Hint"]:
		assert_not_null(card.get_node_or_null(name), "card has %s" % name)
	assert_eq(ItemCard.seen_flag(&"torch"), &"seen_item_torch", "seen flag is seen_item_<id>")
	assert_false(card.is_open(), "starts closed")


func test_first_acquisition_shows_once_sets_the_flag_and_pauses() -> void:
	var card: ItemCard = _card()
	_inv.add(&"torch")
	assert_true(card.is_open(), "the first torch opens the card")
	assert_eq(card.shown_id(), &"torch", "the card shows the torch")
	assert_eq(_game.state, _game.State.PAUSED, "the card holds the game paused")
	assert_true(_flags.has(&"seen_item_torch"), "the seen flag is set when the card shows")
	assert_eq((card.get_node("%Title") as Label).text, "Torch", "title is the item name")
	assert_eq((card.get_node("%Body") as Label).text, _inv.definition(&"torch")["lore"], "body is the lore")
	card.close()
	assert_false(card.is_open(), "closed")
	assert_eq(_game.state, _game.State.PLAYING, "closing restores PLAYING")
	_inv.add(&"torch")
	assert_false(card.is_open(), "a second torch only toasts, never interrupts")
	assert_eq(card.pending_count(), 0, "nothing queued for a known item")


func test_an_item_flagged_seen_before_never_shows() -> void:
	var card: ItemCard = _card()
	_flags.set_flag(&"seen_item_hammer")
	_inv.add(&"hammer")
	assert_false(card.is_open(), "a flag from an earlier session suppresses the card")
	assert_eq(card.pending_count(), 0, "and queues nothing")
	assert_eq(_game.state, _game.State.PLAYING, "state untouched")


func test_queues_while_not_playing_and_shows_when_the_screen_clears() -> void:
	var card: ItemCard = _card()
	_game.state = _game.State.PAUSED
	_inv.add(&"sword")
	assert_false(card.is_open(), "nothing opens over another overlay")
	assert_eq(card.pending_count(), 1, "the sword waits")
	assert_false(_flags.has(&"seen_item_sword"), "not flagged until actually shown")
	_game.state = _game.State.DEAD
	card._try_present()
	assert_false(card.is_open(), "nothing opens while DEAD")
	_game.state = _game.State.PLAYING
	card._try_present()
	assert_true(card.is_open() and card.shown_id() == &"sword", "the queued sword shows once PLAYING again")
	assert_eq(card.pending_count(), 0, "queue drained")
	assert_true(_flags.has(&"seen_item_sword"), "flagged on show")


func test_two_new_items_show_one_after_the_other_without_duplicates() -> void:
	var card: ItemCard = _card()
	_inv.add(&"hammer")
	_inv.add(&"torch")
	_inv.add(&"torch")
	assert_eq(card.shown_id(), &"hammer", "the first item shows first")
	assert_eq(card.pending_count(), 1, "the torch queues once, not twice")
	card.close()
	card._try_present()
	assert_true(card.is_open() and card.shown_id() == &"torch", "the torch follows after the hammer is dismissed")
	card.close()
	assert_eq(_game.state, _game.State.PLAYING, "all cards dismissed leaves PLAYING")


func test_embedded_card_only_displays() -> void:
	var card: ItemCard = _card(true)
	_inv.add(&"castle_key")
	assert_false(card.is_open(), "an embedded card ignores acquisitions")
	assert_eq(_game.state, _game.State.PLAYING, "and never touches the state")
	card.fill("Name", "Keys", "Carried  ×1", "Lore")
	assert_eq((card.get_node("%Title") as Label).text, "Name", "fill sets the title")
	assert_eq((card.get_node("%Kind") as Label).text, "Keys", "fill sets the kind line")
	assert_true((card.get_node("%Count") as Label).visible, "a count line shows when given")
	card.fill("Name", "", "", "Lore")
	assert_false((card.get_node("%Count") as Label).visible, "an empty count line hides")
