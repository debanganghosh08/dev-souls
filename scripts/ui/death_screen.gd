extends CanvasLayer
class_name DeathScreen
## Black veil with "YOU FADED" on Game.player_died: fade in, hold, Game.respawn(), fade out. The world keeps
## running underneath (nothing pauses the tree). A hard safety clears the veil if it ever outstays its welcome.

@export var fade_in_sec: float = 1.2
@export var veil_alpha: float = 0.85
@export var hold_sec: float = 1.5
@export var fade_out_sec: float = 0.8
@export var safety_sec: float = 6.0
@export var letter_spacing: int = 14

@onready var _veil: ColorRect = %Veil
@onready var _text: Label = %Text

var _game: Node
var _tween: Tween
var _shown_for: float = 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_game = get_node_or_null(^"/root/Game")
	_text.text = UiText.text("you_faded")
	_text.add_theme_font_override(&"font", UiUtil.spaced_font(letter_spacing))
	_veil.modulate.a = 0.0
	visible = false
	if _game != null:
		_game.player_died.connect(_on_player_died)
		_game.state_changed.connect(_on_state_changed)


func is_veil_visible() -> bool:
	return visible and _veil.modulate.a > 0.0


func _process(delta: float) -> void:
	if not visible:
		return
	_shown_for += delta
	if _shown_for > safety_sec:
		push_warning("DeathScreen: veil outstayed %.1f s, clearing it" % safety_sec)
		_clear()


func _on_player_died() -> void:
	_shown_for = 0.0
	visible = true
	_kill_tween()
	_tween = create_tween()
	_tween.tween_property(_veil, ^"modulate:a", veil_alpha, fade_in_sec).set_ease(Tween.EASE_IN_OUT)
	_tween.tween_interval(hold_sec)
	_tween.tween_callback(_respawn)
	_tween.tween_property(_veil, ^"modulate:a", 0.0, fade_out_sec).set_ease(Tween.EASE_IN_OUT)
	_tween.tween_callback(_clear)


# Leaving for the title while dead must not strand the veil over the menu.
func _on_state_changed(_old: int, new: int) -> void:
	if _game != null and new == _game.State.MENU and visible:
		_clear()


func _respawn() -> void:
	if _game != null:
		_game.respawn()


func _clear() -> void:
	_kill_tween()
	_veil.modulate.a = 0.0
	visible = false
	_shown_for = 0.0


func _kill_tween() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = null
