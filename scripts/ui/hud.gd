extends CanvasLayer
class_name Hud
## In-world overlay coordinator. Binds the player and level to its three parts — HudGauges (health, stamina,
## vignette, weapon slot), HudPrompt (prompt and refusal line) and ItemToasts — and owns the lore card.
## Nothing here knows which level is loaded; main.gd calls bind_player / bind_level, or the player is found
## by group. The whole %Overlay hides whenever Game.state is not PLAYING.

const PLAYER_GROUP := &"player"
const VIGNETTE_PARAM := HudGauges.VIGNETTE_PARAM

@onready var _overlay: Control = %Overlay
@onready var _gauges: HudGauges = %Gauges
@onready var _prompt: HudPrompt = %PromptLine
@onready var _toasts: ItemToasts = %Toasts
@onready var _lore_card: LoreCard = %LoreCard

var _game: Node
var _inventory: Node
var _player: Node
var _detector: InteractionDetector


func _ready() -> void:
	_game = get_node_or_null(^"/root/Game")
	_inventory = get_node_or_null(^"/root/Inventory")
	if _game != null:
		_game.state_changed.connect(_on_state_changed)
		_game.respawned.connect(_sync_from_player)
		_overlay.visible = _game.state == _game.State.PLAYING
	if _inventory != null:
		_inventory.item_added.connect(_on_item_added)
	if _player == null:
		var found: Node = get_tree().get_first_node_in_group(PLAYER_GROUP)
		if found != null:
			bind_player(found)
	else:
		_bind_gauges()


func bind_player(player: Node) -> void:
	_unbind_player()
	_player = player
	_detector = _find_detector(player)
	if _detector != null:
		_detector.focus_changed.connect(_on_focus_changed)
		_detector.interaction_refused.connect(_on_interaction_refused)
	for hook: Array in _player_hooks():
		if player.has_signal(hook[0]) and not player.is_connected(hook[0], hook[1]):
			player.connect(hook[0], hook[1])
	if is_node_ready():
		_bind_gauges()


## Connects every LoreStone under `root` to the lore card. Call again after loading another area.
func bind_level(root: Node) -> void:
	for stone: LoreStone in _collect_stones(root, []):
		if not stone.reading_requested.is_connected(_on_reading_requested):
			stone.reading_requested.connect(_on_reading_requested)


func lore_card() -> LoreCard:
	return _lore_card


func is_lore_open() -> bool:
	return _lore_card != null and _lore_card.is_open()


func _unbind_player() -> void:
	if _detector != null and is_instance_valid(_detector):
		_detector.focus_changed.disconnect(_on_focus_changed)
		_detector.interaction_refused.disconnect(_on_interaction_refused)
	_detector = null
	if _player != null and is_instance_valid(_player):
		for hook: Array in _player_hooks():
			if _player.has_signal(hook[0]) and _player.is_connected(hook[0], hook[1]):
				_player.disconnect(hook[0], hook[1])
	_player = null
	if _gauges != null:
		_gauges.bind(null, null)


func _player_hooks() -> Array[Array]:
	return [
		[&"health_changed", _on_health_changed],
		[&"damaged", _on_damaged],
		[&"took_fall_damage", _on_fall_damage],
	]


# Gauges exist only once the scene is ready; a bind before that (tests) is completed here from _ready.
func _bind_gauges() -> void:
	var melee: Melee = _player.get_melee() if _player != null and _player.has_method(&"get_melee") else null
	_gauges.bind(_player, melee)
	_sync_from_player()


func _sync_from_player() -> void:
	if _gauges != null:
		_gauges.sync_from_player()


func _on_health_changed(fraction: float) -> void:
	_gauges.on_health_changed(fraction)


func _on_damaged(amount: float, _from: Node) -> void:
	_gauges.on_damaged(amount)


func _on_fall_damage(drop: float) -> void:
	_gauges.on_fall_damage(drop)


func _on_state_changed(_old: int, new: int) -> void:
	if _game == null:
		return
	_overlay.visible = new == _game.State.PLAYING


func _on_focus_changed(target: Interactable) -> void:
	_prompt.on_focus_changed(target)


func _on_interaction_refused(reason: String) -> void:
	_prompt.on_interaction_refused(reason)


func _on_item_added(id: StringName, amount: int) -> void:
	var item_name: String = String(id)
	if _inventory != null:
		var definition: Dictionary = _inventory.definition(id)
		if definition.has("name"):
			item_name = str(definition["name"])
	if amount > 1:
		item_name = UiText.text("acquired_amount") % [item_name, amount]
	_toasts.push(UiText.text("acquired") % item_name)
	# Deferred: the player's auto-equip listens to the same signal and may run after this handler.
	_gauges.refresh_weapon.call_deferred()


func _on_reading_requested(title: String, body: String) -> void:
	_lore_card.open(title, body)


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
