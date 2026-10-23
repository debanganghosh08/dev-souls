extends Control
class_name MainMenu
## Title screen. Emits what the player chose; main.gd does the loading. Continue is greyed without a save,
## and New Journey over an existing save asks once, inline, before anything is unmade.

signal continue_requested()
signal new_journey_requested()
signal quit_requested()

@export var breath_sec: float = 9.0
@export var breath_alpha: float = 0.3
@export var title_spacing: int = 10

@onready var _breath: TextureRect = %Breath
@onready var _title: Label = %Title
@onready var _subtitle: Label = %Subtitle
@onready var _buttons: VBoxContainer = %Buttons
@onready var _continue: Button = %Continue
@onready var _new_journey: Button = %NewJourney
@onready var _settings_button: Button = %SettingsButton
@onready var _quit: Button = %Quit
@onready var _confirm: VBoxContainer = %Confirm
@onready var _confirm_text: Label = %ConfirmText
@onready var _begin_anew: Button = %BeginAnew
@onready var _keep: Button = %Keep
@onready var _settings_panel: SettingsPanel = %SettingsPanel

var settings: GameSettings

var _save: Node
var _breath_tween: Tween


func _ready() -> void:
	_save = get_node_or_null(^"/root/SaveGame")
	_title.text = UiText.text("title")
	_title.add_theme_font_override(&"font", UiUtil.spaced_font(title_spacing))
	_subtitle.text = UiText.text("subtitle")
	_continue.text = UiText.text("continue")
	_new_journey.text = UiText.text("new_journey")
	_settings_button.text = UiText.text("settings")
	_quit.text = UiText.text("quit")
	_confirm_text.text = UiText.text("confirm_unmake")
	_begin_anew.text = UiText.text("begin_anew")
	_keep.text = UiText.text("keep")
	_continue.pressed.connect(func() -> void: continue_requested.emit())
	_new_journey.pressed.connect(_on_new_journey_pressed)
	_settings_button.pressed.connect(_on_settings_pressed)
	_quit.pressed.connect(func() -> void: quit_requested.emit())
	_begin_anew.pressed.connect(_on_begin_anew_pressed)
	_keep.pressed.connect(_show_buttons)
	_settings_panel.closed.connect(_show_buttons)
	_confirm.visible = false
	_settings_panel.visible = false
	_start_breath()


func open() -> void:
	visible = true
	refresh()
	_show_buttons()


func refresh() -> void:
	_continue.disabled = _save == null or not _save.has_save()


func continue_enabled() -> bool:
	return not _continue.disabled


func _show_buttons() -> void:
	_confirm.visible = false
	_settings_panel.visible = false
	_buttons.visible = true
	_first_enabled_button().grab_focus()


func _first_enabled_button() -> Button:
	return _new_journey if _continue.disabled else _continue


func _on_new_journey_pressed() -> void:
	if _save != null and _save.has_save():
		_buttons.visible = false
		_confirm.visible = true
		_keep.grab_focus()
		return
	new_journey_requested.emit()


func _on_begin_anew_pressed() -> void:
	if _save != null:
		_save.delete()
	_confirm.visible = false
	refresh()
	new_journey_requested.emit()


func _on_settings_pressed() -> void:
	if settings == null:
		settings = GameSettings.load_settings()
	_buttons.visible = false
	_settings_panel.open(settings)


# A second gradient breathing in and out over the backdrop: the "barely moving" dark, no shader.
func _start_breath() -> void:
	_breath.modulate.a = 0.0
	_breath_tween = create_tween().set_loops()
	_breath_tween.tween_property(_breath, ^"modulate:a", breath_alpha, breath_sec).set_trans(Tween.TRANS_SINE)
	_breath_tween.tween_property(_breath, ^"modulate:a", 0.0, breath_sec).set_trans(Tween.TRANS_SINE)
