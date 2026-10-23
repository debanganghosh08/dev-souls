extends Control
class_name SettingsPanel
## Options panel shared by the title and the pause menu. Edits apply live through GameSettings.apply();
## Back saves the file and emits `closed`. `changed` lets main.gd push sensitivity onto the camera rig.

signal changed()
signal closed()

const FPS_CAPS: Array[int] = [30, 60, 120, 144, GameSettings.FPS_CAP_UNLIMITED]

@onready var _title: Label = %Title
@onready var _master: HSlider = %MasterSlider
@onready var _music: HSlider = %MusicSlider
@onready var _sfx: HSlider = %SfxSlider
@onready var _sensitivity: HSlider = %SensitivitySlider
@onready var _invert: CheckBox = %InvertCheck
@onready var _fullscreen: CheckBox = %FullscreenCheck
@onready var _vsync: CheckBox = %VsyncCheck
@onready var _fps: OptionButton = %FpsOption
@onready var _reset: Button = %Reset
@onready var _back: Button = %Back

var _settings: GameSettings
var _filling: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_title.text = UiText.text("settings_title")
	%MasterLabel.text = UiText.text("master_volume")
	%MusicLabel.text = UiText.text("music_volume")
	%SfxLabel.text = UiText.text("sfx_volume")
	%SensitivityLabel.text = UiText.text("mouse_sensitivity")
	%InvertLabel.text = UiText.text("invert_y")
	%FullscreenLabel.text = UiText.text("fullscreen")
	%VsyncLabel.text = UiText.text("vsync")
	%FpsLabel.text = UiText.text("fps_cap")
	_reset.text = UiText.text("reset_defaults")
	_back.text = UiText.text("back")
	_sensitivity.min_value = GameSettings.SENSITIVITY_MIN
	_sensitivity.max_value = GameSettings.SENSITIVITY_MAX
	_fps.clear()
	for cap: int in FPS_CAPS:
		_fps.add_item(UiText.text("fps_unlimited") if cap == GameSettings.FPS_CAP_UNLIMITED else str(cap))
	_master.value_changed.connect(_on_edited)
	_music.value_changed.connect(_on_edited)
	_sfx.value_changed.connect(_on_edited)
	_sensitivity.value_changed.connect(_on_edited)
	_invert.toggled.connect(_on_edited)
	_fullscreen.toggled.connect(_on_edited)
	_vsync.toggled.connect(_on_edited)
	_fps.item_selected.connect(_on_edited)
	_reset.pressed.connect(_on_reset_pressed)
	_back.pressed.connect(close)


func open(settings: GameSettings) -> void:
	_settings = settings
	_fill()
	visible = true
	_master.grab_focus()


func close() -> void:
	if _settings != null:
		_settings.save_settings()
	visible = false
	closed.emit()


func _fill() -> void:
	_filling = true
	_master.value = _settings.master_volume
	_music.value = _settings.music_volume
	_sfx.value = _settings.sfx_volume
	_sensitivity.value = _settings.mouse_sensitivity
	_invert.button_pressed = _settings.invert_y
	_fullscreen.button_pressed = _settings.fullscreen
	_vsync.button_pressed = _settings.vsync
	var index: int = FPS_CAPS.find(_settings.fps_cap)
	_fps.selected = index if index >= 0 else FPS_CAPS.find(60)
	_filling = false


# One handler for every control: the whole panel is read back, which keeps the mapping in one place.
func _on_edited(_value: Variant) -> void:
	if _filling or _settings == null:
		return
	_settings.master_volume = _master.value
	_settings.music_volume = _music.value
	_settings.sfx_volume = _sfx.value
	_settings.mouse_sensitivity = _sensitivity.value
	_settings.invert_y = _invert.button_pressed
	_settings.fullscreen = _fullscreen.button_pressed
	_settings.vsync = _vsync.button_pressed
	_settings.fps_cap = FPS_CAPS[_fps.selected] if _fps.selected >= 0 else 60
	_settings.apply()
	changed.emit()


func _on_reset_pressed() -> void:
	if _settings == null:
		return
	_settings.reset_to_defaults()
	_fill()
	_settings.apply()
	changed.emit()
