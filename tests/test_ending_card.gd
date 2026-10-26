extends "res://tests/test_case.gd"
## The run's last screen, and the Game hook that raises it. Only the pure parts are here: the runner never
## enters a scene tree, so an EndingCard's @onready labels do not exist and the live card is exercised by
## main.tscn's `--probe` run instead (PROBE ending, asserted in tests/test_overlays.gd).

const ENDING_SCENE := "res://scenes/ui/ending_card.tscn"
const PAUSE_SCENE := "res://scenes/ui/pause_menu.tscn"
const GameScript := preload("res://scripts/autoloads/game.gd")


func _game() -> Node:
	var game: Node = GameScript.new()
	game.state = game.State.PLAYING
	return game


# --- which card, if any -----------------------------------------------------------------------------------

func test_each_ending_has_its_own_two_text_keys() -> void:
	var rekindle: Array = EndingCard.text_keys(Hearth.Ending.REKINDLE)
	var become: Array = EndingCard.text_keys(Hearth.Ending.BECOME_FLAME)
	assert_eq(rekindle.size(), 2, "the true ending has a title and a body")
	assert_eq(become.size(), 2, "so does being consumed")
	assert_ne(rekindle, become, "the two endings do not share a card")
	for keys: Array in [rekindle, become]:
		for key: Variant in keys:
			assert_true(UiText.DEFAULTS.has(str(key)), "built-in fallback covers '%s'" % str(key))
			assert_ne(UiText.text(str(key)), str(key), "'%s' resolves to real words" % str(key))


func test_a_refusal_is_not_an_ending_and_raises_no_card() -> void:
	# UNREACHABLE and NOT_READY mean the Hearth turned the player away. Blacking the screen out for that
	# would end the game on a failed interaction.
	assert_true(EndingCard.text_keys(Hearth.Ending.UNREACHABLE).is_empty(), "an unreachable Hearth shows no card")
	assert_true(EndingCard.text_keys(Hearth.Ending.NOT_READY).is_empty(), "a refusal shows no card")
	assert_true(EndingCard.text_keys(-1).is_empty(), "an unknown outcome shows no card")
	for ending: int in [Hearth.Ending.REKINDLE, Hearth.Ending.BECOME_FLAME]:
		assert_true(Hearth.is_ending(ending), "the two with cards are the two that end the game")
	for ending: int in [Hearth.Ending.UNREACHABLE, Hearth.Ending.NOT_READY]:
		assert_false(Hearth.is_ending(ending), "the two without cards do not end the game")


# --- the Game hook ----------------------------------------------------------------------------------------

func test_ending_the_journey_announces_it_once() -> void:
	var game: Node = _game()
	var seen: Array[int] = []
	game.journey_ended.connect(func(e: int) -> void: seen.append(e))
	game.end_journey(Hearth.Ending.REKINDLE)
	game.end_journey(Hearth.Ending.BECOME_FLAME)
	assert_eq(seen, [Hearth.Ending.REKINDLE] as Array[int], "a second ending cannot overwrite the first")
	assert_true(game.journey_is_over(), "the run is recorded as over")
	game.free()


func test_only_a_run_in_progress_can_end() -> void:
	for state: int in [GameScript.State.BOOT, GameScript.State.PAUSED, GameScript.State.DEAD,
			GameScript.State.MENU]:
		var game: Node = GameScript.new()
		game.state = state
		var fired: Array[int] = []
		game.journey_ended.connect(func(e: int) -> void: fired.append(e))
		game.end_journey(Hearth.Ending.REKINDLE)
		assert_true(fired.is_empty(), "no ending from state %d" % state)
		assert_false(game.journey_is_over(), "and nothing is recorded")
		game.free()


func test_returning_to_the_title_frees_the_next_run_to_end() -> void:
	# Game outlives the level, so without this a second journey could never reach its own ending.
	var game: Node = _game()
	game.end_journey(Hearth.Ending.REKINDLE)
	assert_true(game.journey_is_over(), "the first run ended")
	game.state = game.State.MENU
	assert_false(game.journey_is_over(), "leaving for the title clears it")
	game.state = game.State.PLAYING
	var seen: Array[int] = []
	game.journey_ended.connect(func(e: int) -> void: seen.append(e))
	game.end_journey(Hearth.Ending.BECOME_FLAME)
	assert_eq(seen, [Hearth.Ending.BECOME_FLAME] as Array[int], "the next run can end differently")
	game.free()


func test_death_and_the_ending_stay_separate() -> void:
	# Dying mid-journey must not consume the ending, and ending must not read as death.
	var game: Node = _game()
	var died: Array[bool] = []
	game.player_died.connect(func() -> void: died.append(true))
	game.kill_player()
	assert_eq(died.size(), 1, "the player died")
	assert_false(game.journey_is_over(), "death is not an ending")
	game.respawn()
	game.end_journey(Hearth.Ending.REKINDLE)
	assert_true(game.journey_is_over(), "and the run can still end after a death")
	game.free()


# --- where it draws ---------------------------------------------------------------------------------------

func test_the_card_draws_over_every_other_overlay() -> void:
	# It is the last thing anyone sees; a pause menu or a death veil on top of it would be a soft-lock.
	var card: CanvasLayer = (load(ENDING_SCENE) as PackedScene).instantiate() as CanvasLayer
	assert_false(card.visible, "it starts hidden")
	assert_eq(card.process_mode, Node.PROCESS_MODE_ALWAYS, "it keeps running while the game is paused")
	for path: String in [PAUSE_SCENE, "res://scenes/ui/inventory_panel.tscn",
			"res://scenes/ui/death_screen.tscn"]:
		var other: CanvasLayer = (load(path) as PackedScene).instantiate() as CanvasLayer
		assert_true(card.layer > other.layer, "the ending card draws above %s (%d > %d)"
				% [path.get_file(), card.layer, other.layer])
		other.free()
	# Above the acquisition-card layer too, and under the loading veil, which covers it on the way out.
	var main: Node = (load("res://scenes/main/main.tscn") as PackedScene).instantiate()
	var item_layer: CanvasLayer = main.get_node_or_null("%ItemCardLayer") as CanvasLayer
	var loading: CanvasLayer = main.get_node_or_null("%Loading") as CanvasLayer
	assert_true(item_layer != null and card.layer > item_layer.layer, "above the acquisition card")
	assert_true(loading != null and card.layer < loading.layer, "under the veil that takes us to the title")
	main.free()
	card.free()
