extends CanvasLayer
class_name InventoryPanel
## Tab while PLAYING: the quiet "what am I carrying" screen. Every known item is listed by kind, held ones by
## name, the rest as a dimmed withheld mark, with the selected item's lore on an embedded ItemCard. Opening
## sets Game.state = PAUSED and frees the mouse; closing (Tab or Esc) restores PLAYING and recaptures it.
## Ownership rule shared by every overlay: only whoever moved PLAYING -> PAUSED moves it back, and an
## overlay may only open while the state is PLAYING, so no two of them ever hold the screen at once.
## Rows are built by the pure InventoryRows statics; this file is only the scene glue.

signal opened()
signal closed()

@export var fade_in_sec: float = 0.2
@export var fade_out_sec: float = 0.12
@export var unknown_alpha: float = 0.4
@export var heading_font_size: int = 14
@export var row_font_size: int = 19

var _root: Control
var _title: Label
var _progress: Label
var _kindling: Label
var _rows_box: VBoxContainer
var _card: ItemCard
var _equip: Button
var _hint: Label
var _game: Node
var _inventory: Node
var _player: Node
var _open: bool = false
var _rows: Array[Dictionary] = []
var _buttons: Array[Button] = []
var _selected: int = -1
var _tween: Tween


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_resolve_nodes()
	if _game == null:
		_inject(get_node_or_null(^"/root/Game"), get_node_or_null(^"/root/Inventory"))
	_title.text = UiText.text("inventory_title")
	_hint.text = UiText.text("inventory_hint") % [
		UiUtil.action_key_label(&"inventory", "Tab"), UiUtil.action_key_label(&"ui_accept", "Enter"),
	]
	_equip.pressed.connect(_on_equip_pressed)
	_root.visible = false
	_root.modulate.a = 0.0


func _inject(game: Node, inventory: Node) -> void:
	_resolve_nodes()
	_game = game
	_inventory = inventory


func bind_player(player: Node) -> void:
	_player = player


func is_open() -> bool:
	return _open


func row_count() -> int:
	return _rows.size()


func unknown_count() -> int:
	return InventoryRows.unknown_count(_rows)


func open() -> void:
	if _open or _game == null or _game.state != _game.State.PLAYING:
		return
	_open = true
	_game.state = _game.State.PAUSED
	UiUtil.set_mouse_captured(false)
	_rebuild()
	_root.visible = true
	_fade_to(1.0, fade_in_sec)
	if not _buttons.is_empty():
		_focus(0)
	opened.emit()


func close() -> void:
	if not _open:
		return
	_open = false
	# Only the overlay that took PLAYING->PAUSED gives it back, and the mouse follows that decision. If
	# something else moved the state on (death, quit to title), recapturing here would trap the cursor on a
	# screen that needs it free.
	var restored: bool = _game != null and _game.state == _game.State.PAUSED
	if restored:
		_game.state = _game.State.PLAYING
	UiUtil.set_mouse_captured(restored)
	_fade_to(0.0, fade_out_sec)
	closed.emit()


## Equips through the player's real Melee; false (and nothing else) when Melee refuses or there is no player.
func request_equip(id: StringName) -> bool:
	var melee: Melee = _melee()
	if melee == null:
		return false
	var ok: bool = melee.equip(id)
	if ok and _selected >= 0:
		_select(_selected)
	return ok


func _unhandled_input(event: InputEvent) -> void:
	if not _open and event.is_action_pressed(&"inventory") and _game != null and _game.state == _game.State.PLAYING:
		get_viewport().set_input_as_handled()
		open()


# Closing and list navigation run in _input: with a row focused, the GUI would otherwise swallow Tab as
# ui_focus_next before _unhandled_input ever saw it, and the panel could not be closed by the key that opened it.
func _input(event: InputEvent) -> void:
	if not _open:
		return
	if event.is_action_pressed(&"inventory") or event.is_action_pressed(&"pause"):
		close()
	elif event.is_action_pressed(&"move_forward"):
		_focus(_selected - 1)
	elif event.is_action_pressed(&"move_back"):
		_focus(_selected + 1)
	else:
		return
	get_viewport().set_input_as_handled()


func _rebuild() -> void:
	for child: Node in _rows_box.get_children():
		_rows_box.remove_child(child)
		child.free()  # detached and never mid-signal here, so no queue (the runner has no SceneTree anyway)
	_buttons.clear()
	_selected = -1
	_rows = InventoryRows.build_rows(_inventory.all_definitions(), _inventory.items()) if _inventory != null else []
	var found: Vector2i = InventoryRows.progress(_rows)
	var kindling: Vector2i = InventoryRows.kindling_progress(_rows)
	_progress.text = UiText.text("inventory_progress") % [found.x, found.y]
	_kindling.text = UiText.text("kindling_progress") % [kindling.x, kindling.y]
	var index: int = 0
	for group: Dictionary in InventoryRows.group_rows(_rows):
		_rows_box.add_child(_heading(InventoryRows.kind_label(str(group["kind"]))))
		for row: Dictionary in group["rows"]:
			_rows_box.add_child(_row_button(row, index))
			index += 1
	if _rows.is_empty():
		_card.fill("", "", "", "")
		_equip.visible = false


func _heading(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override(&"font_size", heading_font_size)
	label.add_theme_color_override(&"font_color", UiUtil.ASH)
	return label


func _row_button(row: Dictionary, index: int) -> Button:
	var button := Button.new()
	button.text = InventoryRows.title_for(row)
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.add_theme_font_size_override(&"font_size", row_font_size)
	if not row["held"]:
		button.modulate.a = unknown_alpha
	button.focus_entered.connect(_select.bind(index))
	button.mouse_entered.connect(_focus.bind(index))
	button.pressed.connect(_on_row_pressed.bind(index))
	_buttons.append(button)
	return button


func _focus(index: int) -> void:
	if _buttons.is_empty():
		return
	index = clampi(index, 0, _buttons.size() - 1)
	if _buttons[index].is_inside_tree():
		_buttons[index].grab_focus()
	else:
		_select(index)


func _select(index: int) -> void:
	if index < 0 or index >= _rows.size():
		return
	_selected = index
	var row: Dictionary = _rows[index]
	var count_line: String = UiText.text("count_line") % int(row["count"]) if row["held"] else ""
	var kind: String = InventoryRows.kind_label(str(row["kind"])) if row["held"] else ""
	_card.fill(InventoryRows.title_for(row), kind, count_line, InventoryRows.body_for(row))
	_card.modulate.a = 1.0 if row["held"] else unknown_alpha
	var melee: Melee = _melee()
	var weapon: bool = InventoryRows.is_weapon(row) and row["held"] and melee != null
	_equip.visible = weapon
	if weapon:
		var is_equipped: bool = melee.equipped() == row["id"]
		_equip.text = UiText.text("equipped") if is_equipped else UiText.text("equip")
		_equip.disabled = is_equipped


func _on_row_pressed(index: int) -> void:
	_select(index)
	var row: Dictionary = _rows[index]
	if InventoryRows.is_weapon(row) and row["held"]:
		request_equip(row["id"])


func _on_equip_pressed() -> void:
	if _selected >= 0:
		request_equip(_rows[_selected]["id"])
		_focus(_selected)


func _melee() -> Melee:
	if _player == null or not is_instance_valid(_player) or not _player.has_method(&"get_melee"):
		return null
	return _player.get_melee()


# Outside a tree (the test runner) there is nothing to tween, so the alpha is set directly.
func _fade_to(alpha: float, seconds: float) -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	if not is_inside_tree():
		_root.modulate.a = alpha
		_root.visible = alpha > 0.0
		return
	_tween = create_tween()
	_tween.tween_property(_root, ^"modulate:a", alpha, seconds)
	if alpha <= 0.0:
		_tween.tween_callback(_root.hide)


func _resolve_nodes() -> void:
	if _root != null:
		return
	_root = %Root
	_title = %Title
	_progress = %Progress
	_kindling = %Kindling
	_rows_box = %Rows
	_card = %Card
	_equip = %Equip
	_hint = %Hint
