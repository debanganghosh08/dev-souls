extends CanvasLayer
class_name EndingCard
## The last screen of a run. Listens for Game.journey_ended the way DeathScreen listens for player_died, so
## the Hearth sets a flag and emits, and never has to know an interface exists.
##
## It takes the screen the way the pause menu does -- PLAYING -> PAUSED with the mouse freed -- rather than
## through a new Game.State, which would have to be handled by every `match state` in the game. Unlike the
## pause menu it never gives the screen back: the journey is over, so dismissing it emits `finished` and Main
## leaves for the title (the same path as "Save and Quit to Title").

signal finished()

## Hearth.Ending -> the two UiText keys for that ending.
const TEXTS: Dictionary = {
	Hearth.Ending.REKINDLE: ["ending_rekindle_title", "ending_rekindle_body"],
	Hearth.Ending.BECOME_FLAME: ["ending_become_title", "ending_become_body"],
}

@export var fade_in_sec: float = 3.0
@export var veil_alpha: float = 0.96
@export var letter_spacing: int = 10
## The card refuses input for this long so the last beat is not skipped by a key still held from the Hearth.
@export var input_lockout_sec: float = 1.6

@onready var _veil: ColorRect = %Veil
@onready var _title: Label = %Title
@onready var _body: Label = %Body
@onready var _hint: Label = %Hint

var _game: Node
var _shown: bool = false
var _elapsed: float = 0.0
var _ending: int = -1


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_game = get_node_or_null(^"/root/Game")
	_veil.modulate.a = 0.0
	visible = false
	set_process(false)
	set_process_unhandled_input(false)
	if _game != null and _game.has_signal(&"journey_ended"):
		_game.journey_ended.connect(show_ending)


## The two UiText keys for an ending. Static and pure so the mapping is testable without a tree (the test
## runner never enters one, so a node's @onready labels do not exist there). An outcome with no card of its
## own -- UNREACHABLE and NOT_READY are refusals, not endings -- yields nothing, and show_ending ignores it:
## a refused Hearth must never black the screen out.
static func text_keys(ending: int) -> Array:
	return TEXTS.get(ending, []) as Array


func is_shown() -> bool:
	return _shown


func shown_ending() -> int:
	return _ending


func title_text() -> String:
	return _title.text if _title != null else ""


## Public so a test can drive it without the autoload; also the signal handler.
func show_ending(ending: int) -> void:
	var keys: Array = text_keys(ending)
	if _shown or keys.is_empty():
		return
	_shown = true
	_ending = ending
	_elapsed = 0.0
	_title.text = UiText.text(str(keys[0]))
	_body.text = UiText.text(str(keys[1]))
	_hint.text = UiText.text("ending_dismiss") % UiUtil.action_key_label(&"interact")
	_hint.visible = false
	_title.add_theme_font_override(&"font", UiUtil.spaced_font(letter_spacing))
	visible = true
	# PAUSED stops the world responding while the card is up; the mouse is freed so the player is not still
	# steering a camera they can no longer see.
	if _game != null and _game.state == _game.State.PLAYING:
		_game.state = _game.State.PAUSED
	UiUtil.set_mouse_captured(false)
	set_process(true)
	set_process_unhandled_input(true)
	if is_inside_tree():
		create_tween().tween_property(_veil, ^"modulate:a", veil_alpha, fade_in_sec).set_ease(Tween.EASE_IN_OUT)
	else:
		_veil.modulate.a = veil_alpha


func accepts_input() -> bool:
	return _shown and _elapsed >= input_lockout_sec


func _process(delta: float) -> void:
	_elapsed += delta
	if not _hint.visible and accepts_input():
		_hint.visible = true


func _unhandled_input(event: InputEvent) -> void:
	if not accepts_input():
		return
	if event.is_action_pressed(&"interact") or event.is_action_pressed(&"ui_accept") \
			or event.is_action_pressed(&"ui_cancel"):
		dismiss()


func dismiss() -> void:
	if not _shown:
		return
	set_process(false)
	set_process_unhandled_input(false)
	# Main frees this node on the way to the title, so there is nothing to tidy here beyond stopping work.
	finished.emit()
