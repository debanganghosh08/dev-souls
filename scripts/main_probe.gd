extends RefCounted
class_name MainProbe
## Headless `--probe` driver for main.tscn (tests/test_ui.gd, tests/test_overlays.gd). Walks menu -> journey
## -> death, then respawns and exercises the inventory panel, the first-acquisition card and weapon switching
## by injecting real input actions. The first three lines are asserted byte-for-byte by test_ui.gd and must
## never change. This is Main's own test rig, so it reads Main's private members directly.

const SETTLE_FRAMES := 30
const DEATH_FRAMES := 5
const STEP_FRAMES := 6

var _main: Node
var _phase: int = 0
var _frames: int = 0


func _init(main: Node) -> void:
	_main = main


func step() -> void:
	_frames += 1
	var game: Node = _main._game
	match _phase:
		0:
			if _frames >= 2:
				print("PROBE menu continue_enabled=%s state=%s" % [_main._menu.continue_enabled(), _main._state_name()])
				_main._begin_level(_main.LEVEL_PATH, false)
				_next()
		1:
			if _main._level != null and _frames >= SETTLE_FRAMES:
				print("PROBE ingame level=%s hud=%s state=%s" % [
					_main._level.is_inside_tree(), _main._hud != null and _main._hud.is_inside_tree(), _main._state_name(),
				])
				if game != null:
					game.kill_player()
				_next()
		2:
			if _frames >= DEATH_FRAMES:
				print("PROBE death veil=%s state=%s" % [_main._death != null and _main._death.is_veil_visible(), _main._state_name()])
				# Back to PLAYING by the same call the death screen makes, so the overlays can be exercised.
				if game != null:
					game.respawn()
				_next()
		3:
			if _frames >= STEP_FRAMES:
				_press(&"inventory")
				_next()
		4:
			if _frames >= STEP_FRAMES:
				var panel: InventoryPanel = _main._inventory_panel
				print("PROBE inventory open=%s rows=%d unknown=%d state=%s" % [
					panel != null and panel.is_open(), panel.row_count() if panel != null else 0,
					panel.unknown_count() if panel != null else 0, _main._state_name(),
				])
				_press(&"inventory")
				_next()
		5:
			if _frames >= STEP_FRAMES:
				# Two first-time items at once: the hammer's card shows now, the torch's queues behind it.
				var inventory: Node = _main.get_node_or_null(^"/root/Inventory")
				if inventory != null:
					inventory.add(&"hammer")
					inventory.add(&"torch")
				_next()
		6:
			if _frames >= STEP_FRAMES:
				var card: ItemCard = _main._item_card
				print("PROBE itemcard shown=%s id=%s pending=%d state=%s" % [
					card != null and card.is_open(), card.shown_id() if card != null else &"",
					card.pending_count() if card != null else 0, _main._state_name(),
				])
				_press(&"interact")
				_next()
		7:
			if _frames >= STEP_FRAMES:
				_press(&"interact")
				_next()
		8:
			if _frames >= STEP_FRAMES:
				var panel: InventoryPanel = _main._inventory_panel
				var player: Node = _main._find_player()
				var ok: bool = panel != null and panel.request_equip(&"torch")
				var melee: Melee = player.get_melee() if player != null else null
				print("PROBE equip ok=%s weapon=%s state=%s" % [
					ok, melee.weapon_name() if melee != null else "", _main._state_name(),
				])
				_next()
		9:
			if _frames >= STEP_FRAMES:
				# The last screen of a run. end_journey only fires from PLAYING, which phase 8 just
				# confirmed the overlays had all released. The card is deliberately NOT dismissed: doing so
				# leaves for the title, and this run is about proving the card comes up and holds the screen.
				var card: EndingCard = _main._ending_card
				game.end_journey(Hearth.Ending.REKINDLE)
				print("PROBE ending shown=%s which=%d locked=%s title=%s state=%s over=%s" % [
					card != null and card.is_shown(), card.shown_ending() if card != null else -1,
					card != null and not card.accepts_input(),
					card != null and card.title_text() != "", _main._state_name(), game.journey_is_over(),
				])
				if _main._save != null:
					_main._save.delete()
				_next()
				_main.get_tree().quit()


func _next() -> void:
	_frames = 0
	_phase += 1


# A real action event through Input, so the overlays' _unhandled_input handlers are what gets exercised.
func _press(action: StringName) -> void:
	for pressed: bool in [true, false]:
		var event := InputEventAction.new()
		event.action = action
		event.pressed = pressed
		Input.parse_input_event(event)
