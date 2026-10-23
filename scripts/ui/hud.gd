extends CanvasLayer
class_name Hud
## In-world overlay: stamina bar, interaction prompt, refusal line, item toasts and the lore card. Nothing here
## knows which level is loaded; main.gd calls bind_player / bind_level, or the player is found by group.

const PLAYER_GROUP := &"player"

@export var stamina_idle_fade_sec: float = 2.0
@export var stamina_idle_alpha: float = 0.12
@export var prompt_fade_sec: float = 0.12
@export var refusal_hold_sec: float = 2.5
@export var refusal_fade_sec: float = 0.5

@onready var _overlay: Control = %Overlay
@onready var _stamina: ProgressBar = %StaminaBar
@onready var _prompt: Label = %Prompt
@onready var _refusal: Label = %Refusal
@onready var _toasts: ItemToasts = %Toasts
@onready var _lore_card: LoreCard = %LoreCard

var _game: Node
var _inventory: Node
var _player: Node
var _detector: InteractionDetector
var _interact_key: String = "E"
var _last_fraction: float = -1.0
var _stamina_idle: float = 0.0
var _stamina_tween: Tween
var _prompt_tween: Tween
var _refusal_tween: Tween
var _refusal_left: float = 0.0


func _ready() -> void:
	_game = get_node_or_null(^"/root/Game")
	_inventory = get_node_or_null(^"/root/Inventory")
	_interact_key = UiUtil.action_key_label(&"interact", "E")
	_prompt.modulate.a = 0.0
	_refusal.modulate.a = 0.0
	if _game != null:
		_game.state_changed.connect(_on_state_changed)
		_overlay.visible = _game.state == _game.State.PLAYING
	if _inventory != null:
		_inventory.item_added.connect(_on_item_added)
	if _player == null:
		var found: Node = get_tree().get_first_node_in_group(PLAYER_GROUP)
		if found != null:
			bind_player(found)


func bind_player(player: Node) -> void:
	if _detector != null and is_instance_valid(_detector):
		_detector.focus_changed.disconnect(_on_focus_changed)
		_detector.interaction_refused.disconnect(_on_interaction_refused)
	_player = player
	_detector = _find_detector(player)
	if _detector != null:
		_detector.focus_changed.connect(_on_focus_changed)
		_detector.interaction_refused.connect(_on_interaction_refused)
	_last_fraction = -1.0


## Connects every LoreStone under `root` to the lore card. Call again after loading another area.
func bind_level(root: Node) -> void:
	for stone: LoreStone in _collect_stones(root, []):
		if not stone.reading_requested.is_connected(_on_reading_requested):
			stone.reading_requested.connect(_on_reading_requested)


func lore_card() -> LoreCard:
	return _lore_card


func is_lore_open() -> bool:
	return _lore_card != null and _lore_card.is_open()


func _process(delta: float) -> void:
	_update_stamina(delta)
	if _refusal_left > 0.0:
		_refusal_left -= delta
		if _refusal_left <= 0.0:
			_refusal_tween = _fade(_refusal, _refusal_tween, 0.0, refusal_fade_sec)


func _update_stamina(delta: float) -> void:
	if _player == null or not is_instance_valid(_player) or not _player.has_method(&"stamina_fraction"):
		return
	var fraction: float = _player.stamina_fraction()
	if is_equal_approx(fraction, _last_fraction):
		if fraction >= 1.0 and _stamina_idle < stamina_idle_fade_sec:
			_stamina_idle += delta
			if _stamina_idle >= stamina_idle_fade_sec:
				_stamina_tween = _fade(_stamina, _stamina_tween, stamina_idle_alpha, 0.8)
		return
	_last_fraction = fraction
	_stamina.value = fraction * _stamina.max_value
	_stamina_idle = 0.0
	if _stamina.modulate.a < 1.0:
		if _stamina_tween != null and _stamina_tween.is_valid():
			_stamina_tween.kill()
		_stamina.modulate.a = 1.0


func _on_state_changed(_old: int, new: int) -> void:
	if _game == null:
		return
	_overlay.visible = new == _game.State.PLAYING


func _on_focus_changed(target: Interactable) -> void:
	if target == null or not is_instance_valid(target):
		_prompt_tween = _fade(_prompt, _prompt_tween, 0.0, prompt_fade_sec)
		return
	_prompt.text = UiText.text("prompt_format") % [_interact_key, target.prompt_text()]
	_prompt_tween = _fade(_prompt, _prompt_tween, 1.0, prompt_fade_sec)


func _on_interaction_refused(reason: String) -> void:
	_refusal.text = reason
	_refusal_left = refusal_hold_sec
	_refusal_tween = _fade(_refusal, _refusal_tween, 1.0, prompt_fade_sec)


func _on_item_added(id: StringName, amount: int) -> void:
	var item_name: String = String(id)
	if _inventory != null:
		var definition: Dictionary = _inventory.definition(id)
		if definition.has("name"):
			item_name = str(definition["name"])
	if amount > 1:
		item_name = UiText.text("acquired_amount") % [item_name, amount]
	_toasts.push(UiText.text("acquired") % item_name)


func _on_reading_requested(title: String, body: String) -> void:
	_lore_card.open(title, body)


func _fade(node: CanvasItem, current: Tween, alpha: float, seconds: float) -> Tween:
	if current != null and current.is_valid():
		current.kill()
	var tween: Tween = create_tween()
	tween.tween_property(node, ^"modulate:a", alpha, seconds)
	return tween


func _find_detector(player: Node) -> InteractionDetector:
	for child: Node in player.get_children():
		if child is InteractionDetector:
			return child
	return null


func _collect_stones(node: Node, out: Array[LoreStone]) -> Array[LoreStone]:
	if node is LoreStone:
		out.append(node)
	for child: Node in node.get_children():
		_collect_stones(child, out)
	return out
