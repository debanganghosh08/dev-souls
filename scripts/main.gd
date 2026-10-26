extends Node
## Entry point. Composes title screen, level and overlays; owns the GameSettings instance.
## To ship a real area, change LEVEL_PATH (or pass another path to _begin_level): nothing else here cares.
## `--probe` hands the frame loop to MainProbe, which prints PROBE lines on a throwaway save slot.
##
## Overlay ownership: an overlay (pause menu, lore card, inventory panel, item card) may take the screen only
## while Game.state == PLAYING; it alone moves the state to PAUSED, frees the mouse, and on close moves it
## back and recaptures. So at most one holds the screen, and none can open over DEAD or MENU. The death
## screen and HUD never touch the mouse or the state; Main owns the MENU <-> PLAYING transitions.

const LEVEL_PATH := "res://scenes/levels/vale.tscn"
const PROBE_SLOT := "user://probe_ui_slot.json"
const HUD_SCENE := preload("res://scenes/ui/hud.tscn")
const DEATH_SCENE := preload("res://scenes/ui/death_screen.tscn")
const PAUSE_SCENE := preload("res://scenes/ui/pause_menu.tscn")
const INVENTORY_SCENE := preload("res://scenes/ui/inventory_panel.tscn")
const ITEM_CARD_SCENE := preload("res://scenes/ui/item_card.tscn")
const ENDING_SCENE := preload("res://scenes/ui/ending_card.tscn")

@onready var _menu: MainMenu = %MainMenu
@onready var _loading: CanvasLayer = %Loading
@onready var _loading_label: Label = %LoadingLabel
@onready var _level_root: Node3D = %LevelRoot
@onready var _overlays: Node = %Overlays
@onready var _item_card_layer: CanvasLayer = %ItemCardLayer

var _settings: GameSettings
var _game: Node
var _save: Node
var _level: Node
var _hud: Hud
var _death: DeathScreen
var _pause: PauseMenu
var _inventory_panel: InventoryPanel
var _item_card: ItemCard
var _ending_card: EndingCard
var _loading_path: String = ""
var _continue_after_load: bool = false
var _probe: MainProbe


func _ready() -> void:
	_game = get_node_or_null(^"/root/Game")
	_save = get_node_or_null(^"/root/SaveGame")
	if OS.get_cmdline_user_args().has("--probe"):
		_probe = MainProbe.new(self)
	if _probe != null and _save != null:
		# Before anything can write: a probe must never read, overwrite or delete the real save.
		_save.use_slot_path(PROBE_SLOT)
		_save.delete()
	_settings = GameSettings.load_settings()
	_settings.apply()
	_loading_label.text = UiText.text("loading")
	_loading.visible = false
	_menu.settings = _settings
	_menu.continue_requested.connect(func() -> void: _begin_level(LEVEL_PATH, true))
	_menu.new_journey_requested.connect(func() -> void: _begin_level(LEVEL_PATH, false))
	_menu.quit_requested.connect(func() -> void: get_tree().quit())
	_menu.get_node(^"%SettingsPanel").changed.connect(_push_settings_to_player)
	_show_title()


func _process(_delta: float) -> void:
	if _loading_path != "":
		_poll_level_load()
	if _probe != null:
		_probe.step()


# --- flow ------------------------------------------------------------------------------------------------

func _show_title() -> void:
	if _game != null:
		_game.state = _game.State.MENU
	UiUtil.set_mouse_captured(false)
	_menu.open()


## The one place a level is loaded. Threaded so a large area shows "Awakening..." instead of a hang.
func _begin_level(path: String, continue_save: bool) -> void:
	if _loading_path != "":
		return
	_continue_after_load = continue_save
	_menu.visible = false
	_loading.visible = true
	var err: Error = ResourceLoader.load_threaded_request(path)
	if err != OK:
		push_error("Main: cannot load %s (%s)" % [path, error_string(err)])
		_loading.visible = false
		_show_title()
		return
	_loading_path = path


func _poll_level_load() -> void:
	var status: ResourceLoader.ThreadLoadStatus = ResourceLoader.load_threaded_get_status(_loading_path)
	if status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
		return
	var path: String = _loading_path
	_loading_path = ""
	if status != ResourceLoader.THREAD_LOAD_LOADED:
		push_error("Main: loading %s failed (status %d)" % [path, status])
		_loading.visible = false
		_show_title()
		return
	_enter_level(ResourceLoader.load_threaded_get(path) as PackedScene)


func _enter_level(scene: PackedScene) -> void:
	_level = scene.instantiate()
	_level_root.add_child(_level)
	_hud = HUD_SCENE.instantiate()
	_death = DEATH_SCENE.instantiate()
	_pause = PAUSE_SCENE.instantiate()
	_pause.settings = _settings
	_pause.quit_to_title_requested.connect(_leave_level)
	_pause.get_node(^"%SettingsPanel").changed.connect(_push_settings_to_player)
	_inventory_panel = INVENTORY_SCENE.instantiate()
	_item_card = ITEM_CARD_SCENE.instantiate()
	# The journey's last screen never hands the game back, so it leaves for the title like the pause menu's
	# "Save and Quit" does. It listens to Game.journey_ended itself; Main only owns the way out.
	_ending_card = ENDING_SCENE.instantiate()
	_ending_card.finished.connect(_leave_level)
	_overlays.add_child(_hud)
	_overlays.add_child(_death)
	_overlays.add_child(_inventory_panel)
	_overlays.add_child(_pause)
	_overlays.add_child(_ending_card)
	_item_card_layer.add_child(_item_card)
	var player: Node = _find_player()
	if player != null:
		_hud.bind_player(player)
		_inventory_panel.bind_player(player)
	_hud.bind_level(_level)
	_loading.visible = false
	if _game != null:
		_game.state = _game.State.PLAYING
	# load_slot only after the level is in the tree, so restored state lands on live nodes.
	if _continue_after_load and _save != null and _save.load_slot() and player is Node3D and _game != null:
		(player as Node3D).global_position = _game.player_position
		if player.has_method(&"get_camera_rig") and player.get_camera_rig() != null:
			player.get_camera_rig().snap_to_target()
	_push_settings_to_player()
	UiUtil.set_mouse_captured(true)


func _leave_level() -> void:
	for overlay: Node in [_hud, _death, _pause, _inventory_panel, _item_card, _ending_card]:
		if overlay != null:
			overlay.queue_free()
	_hud = null
	_death = null
	_pause = null
	_inventory_panel = null
	_item_card = null
	_ending_card = null
	if _level != null:
		_level.queue_free()
		_level = null
	_show_title()


func _find_player() -> Node:
	return get_tree().get_first_node_in_group(&"player")


func _push_settings_to_player() -> void:
	var player: Node = _find_player()
	if player == null or not player.has_method(&"get_camera_rig"):
		return
	var rig: Node3D = player.get_camera_rig()
	if rig == null:
		return
	rig.set(&"mouse_sensitivity", _settings.mouse_sensitivity)
	rig.set(&"invert_y", _settings.invert_y)


func _state_name() -> String:
	if _game == null:
		return "NO GAME"
	return str(_game.State.keys()[_game.state])
