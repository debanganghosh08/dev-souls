extends Control
class_name ItemCard
## One item's name, kind, count and lore on a dark card. Two lives: `embedded` inside the inventory panel's
## detail pane (no dim, no input, never touches Game.state), or standalone as the "item acquired" beat: the
## first time an id lands in the Inventory the card pauses the game, holds until `interact` or `pause`, and
## never returns for that id. It only takes the screen while Game.state == PLAYING; anything that arrives
## while another overlay holds PAUSED (or while DEAD / MENU) queues and shows once the state is PLAYING again.

signal opened()
signal closed()

# "Seen" lives in Flags, not a runtime set: Flags is what SaveGame serialises, so a journey continued on
# another day still knows which cards it has shown, and New Journey (fresh flags) shows them all again.
const SEEN_FLAG_PREFIX := "seen_item_"

@export var embedded: bool = false
@export var fade_in_sec: float = 0.25
@export var fade_out_sec: float = 0.15

var _dim: ColorRect
var _card: PanelContainer
var _kind: Label
var _title: Label
var _count: Label
var _body: Label
var _hint: Label
var _game: Node
var _flags: Node
var _inventory: Node
var _open: bool = false
var _shown_id: StringName = &""
var _pending: Array[StringName] = []
var _tween: Tween


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_resolve_nodes()
	_hint.text = UiText.text("item_card_hint") % UiUtil.action_key_label(&"interact", "E")
	if embedded:
		_dim.visible = false
		_hint.visible = false
		_card.custom_minimum_size = Vector2.ZERO
		_card.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_card.add_theme_stylebox_override(&"panel", StyleBoxEmpty.new())
		return
	if _game == null:
		_inject(get_node_or_null(^"/root/Game"), get_node_or_null(^"/root/Flags"), get_node_or_null(^"/root/Inventory"))
	modulate.a = 0.0
	visible = false


## Tests (and main.gd, should it ever want to) hand in the autoloads before any exist in the tree.
func _inject(game: Node, flags: Node, inventory: Node) -> void:
	_resolve_nodes()
	_game = game
	_flags = flags
	_inventory = inventory
	if _game != null and not _game.is_connected(&"state_changed", _on_state_changed):
		_game.state_changed.connect(_on_state_changed)
	if _inventory != null and not _inventory.is_connected(&"item_added", _on_item_added):
		_inventory.item_added.connect(_on_item_added)


static func seen_flag(id: StringName) -> StringName:
	return StringName(SEEN_FLAG_PREFIX + String(id))


func fill(title: String, kind: String, count_line: String, body: String) -> void:
	_resolve_nodes()
	_title.text = title
	_kind.text = kind
	_count.text = count_line
	_count.visible = count_line != ""
	_body.text = body


func is_open() -> bool:
	return _open


func shown_id() -> StringName:
	return _shown_id


func pending_count() -> int:
	return _pending.size()


## Queues `id` for its first-acquisition card unless it was shown before; shows it now if the screen is free.
func present(id: StringName) -> void:
	if embedded or (_flags != null and _flags.has(seen_flag(id))):
		return
	if _pending.has(id) or (_open and _shown_id == id):
		return
	_pending.append(id)
	_try_present()


func close() -> void:
	if not _open:
		return
	_open = false
	if _game != null and _game.state == _game.State.PAUSED:
		_game.state = _game.State.PLAYING
	UiUtil.set_mouse_captured(true)
	_fade_to(0.0, fade_out_sec)
	closed.emit()
	_try_present.call_deferred()


func _unhandled_input(event: InputEvent) -> void:
	if not _open:
		return
	if event.is_action_pressed(&"interact") or event.is_action_pressed(&"pause"):
		get_viewport().set_input_as_handled()
		close()


func _on_item_added(id: StringName, _amount: int) -> void:
	present(id)


func _on_state_changed(_old: int, new: int) -> void:
	if _game != null and new == _game.State.PLAYING and not _pending.is_empty():
		_try_present.call_deferred()


func _try_present() -> void:
	if _open or _pending.is_empty() or _game == null or _game.state != _game.State.PLAYING:
		return
	var id: StringName = _pending.pop_front()
	if _flags != null:
		if _flags.has(seen_flag(id)):
			_try_present()
			return
		_flags.set_flag(seen_flag(id))
	var definition: Dictionary = _inventory.definition(id) if _inventory != null else {}
	fill(
		str(definition.get("name", String(id))),
		InventoryRows.kind_label(str(definition.get("kind", ""))),
		"",
		str(definition.get("lore", "")),
	)
	_shown_id = id
	_open = true
	_game.state = _game.State.PAUSED
	UiUtil.set_mouse_captured(false)
	visible = true
	_fade_to(1.0, fade_in_sec)
	opened.emit()


# Outside a tree (the test runner) there is nothing to tween, so the alpha is set directly.
func _fade_to(alpha: float, seconds: float) -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	if not is_inside_tree():
		modulate.a = alpha
		visible = alpha > 0.0
		return
	_tween = create_tween()
	_tween.tween_property(self, ^"modulate:a", alpha, seconds)
	if alpha <= 0.0:
		_tween.tween_callback(hide)


func _resolve_nodes() -> void:
	if _title != null:
		return
	_dim = %Dim
	_card = %Card
	_kind = %Kind
	_title = %Title
	_count = %Count
	_body = %Body
	_hint = %Hint
