extends CanvasLayer
class_name PauseMenu
## Esc while PLAYING: dim veil with Resume / Settings / Save and Quit to Title. Never opens while DEAD or
## while a lore card is open (the card holds PAUSED itself, so only PLAYING counts as "can open").

signal quit_to_title_requested()

@onready var _root: Control = %Root
@onready var _menu: VBoxContainer = %Menu
@onready var _resume: Button = %Resume
@onready var _settings_button: Button = %SettingsButton
@onready var _save_quit: Button = %SaveQuit
@onready var _settings_panel: SettingsPanel = %SettingsPanel

var settings: GameSettings

var _game: Node
var _save: Node
var _open: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_game = get_node_or_null(^"/root/Game")
	_save = get_node_or_null(^"/root/SaveGame")
	_resume.text = UiText.text("resume")
	_settings_button.text = UiText.text("settings")
	_save_quit.text = UiText.text("save_and_quit")
	_resume.pressed.connect(close)
	_settings_button.pressed.connect(_on_settings_pressed)
	_save_quit.pressed.connect(_on_save_quit_pressed)
	_settings_panel.closed.connect(_on_settings_closed)
	_root.visible = false


func is_open() -> bool:
	return _open


func open() -> void:
	if _open or _game == null or _game.state != _game.State.PLAYING:
		return
	_open = true
	_game.state = _game.State.PAUSED
	UiUtil.set_mouse_captured(false)
	_root.visible = true
	_menu.visible = true
	_settings_panel.visible = false
	_resume.grab_focus()


func close() -> void:
	if not _open:
		return
	_open = false
	_root.visible = false
	if _settings_panel.visible:
		_settings_panel.close()
	if _game != null and _game.state == _game.State.PAUSED:
		_game.state = _game.State.PLAYING
	UiUtil.set_mouse_captured(true)


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed(&"pause"):
		return
	if _open:
		get_viewport().set_input_as_handled()
		if _settings_panel.visible:
			_settings_panel.close()
		else:
			close()
	elif _game != null and _game.state == _game.State.PLAYING:
		get_viewport().set_input_as_handled()
		open()


func _on_settings_pressed() -> void:
	if settings == null:
		settings = GameSettings.load_settings()
	_menu.visible = false
	_settings_panel.open(settings)


func _on_settings_closed() -> void:
	if not _open:
		return
	_menu.visible = true
	_resume.grab_focus()


func _on_save_quit_pressed() -> void:
	if _save != null:
		_save.save()
	_open = false
	_root.visible = false
	quit_to_title_requested.emit()
