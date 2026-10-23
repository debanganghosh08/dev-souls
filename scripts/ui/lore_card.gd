extends Control
class_name LoreCard
## The "stop and read" panel. Opening pauses the game (Game.state = PAUSED) and frees the mouse; `interact`
## or `pause` closes it and restores PLAYING. Runs with process_mode ALWAYS so it still closes while paused.

signal opened()
signal closed()

@export var fade_in_sec: float = 0.25
@export var fade_out_sec: float = 0.15

@onready var _title: Label = %Title
@onready var _body: Label = %Body
@onready var _hint: Label = %Hint

var _game: Node
var _open: bool = false
var _tween: Tween


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_game = get_node_or_null(^"/root/Game")
	_hint.text = UiText.text("lore_dismiss") % UiUtil.action_key_label(&"interact", "E")
	modulate.a = 0.0
	visible = false


func is_open() -> bool:
	return _open


func open(title: String, body: String) -> void:
	_title.text = title
	_body.text = body
	if not _open:
		_open = true
		if _game != null and _game.state == _game.State.PLAYING:
			_game.state = _game.State.PAUSED
		UiUtil.set_mouse_captured(false)
		opened.emit()
	visible = true
	_fade_to(1.0, fade_in_sec)


func close() -> void:
	if not _open:
		return
	_open = false
	if _game != null and _game.state == _game.State.PAUSED:
		_game.state = _game.State.PLAYING
	UiUtil.set_mouse_captured(true)
	_fade_to(0.0, fade_out_sec)
	closed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if not _open:
		return
	if event.is_action_pressed(&"interact") or event.is_action_pressed(&"pause"):
		get_viewport().set_input_as_handled()
		close()


func _fade_to(alpha: float, seconds: float) -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(self, ^"modulate:a", alpha, seconds)
	if alpha <= 0.0:
		_tween.tween_callback(hide)
