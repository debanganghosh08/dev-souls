extends CanvasLayer
class_name Hud
## In-world overlay: health bar with ghost trail and hit vignette, stamina bar, weapon slot, interaction
## prompt, refusal line, item toasts and the lore card. Nothing here knows which level is loaded; main.gd
## calls bind_player / bind_level, or the player is found by group. Gauge arithmetic lives in HudMath.

const PLAYER_GROUP := &"player"
const MELEE_IDLE := "IDLE"
const VIGNETTE_PARAM := &"strength"

@export var stamina_idle_fade_sec: float = 2.0
@export var stamina_idle_alpha: float = 0.12
@export var prompt_fade_sec: float = 0.12
@export var refusal_hold_sec: float = 2.5
@export var refusal_fade_sec: float = 0.5
@export var health_ease_sec: float = 0.25
@export var ghost_delay_sec: float = 0.5
@export var ghost_ease_sec: float = 0.3
@export var vignette_fade_sec: float = 0.35
@export var weapon_dim_alpha: float = 0.45
@export var weapon_dim_speed: float = 10.0

@onready var _overlay: Control = %Overlay
@onready var _health: ProgressBar = %HealthBar
@onready var _ghost: ProgressBar = %HealthGhost
@onready var _vignette: ColorRect = %Vignette
@onready var _stamina: ProgressBar = %StaminaBar
@onready var _weapon: Label = %WeaponLabel
@onready var _prompt: Label = %Prompt
@onready var _refusal: Label = %Refusal
@onready var _toasts: ItemToasts = %Toasts
@onready var _lore_card: LoreCard = %LoreCard

var _game: Node
var _inventory: Node
var _player: Node
var _melee: Melee
var _detector: InteractionDetector
var _interact_key: String = "E"
var _last_fraction: float = -1.0
var _stamina_idle: float = 0.0
var _health_fraction: float = 1.0
var _low_time: float = 0.0
var _weapon_id: StringName = &""
var _stamina_tween: Tween
var _health_tween: Tween
var _ghost_tween: Tween
var _vignette_tween: Tween
var _prompt_tween: Tween
var _refusal_tween: Tween
var _refusal_left: float = 0.0


func _ready() -> void:
	_game = get_node_or_null(^"/root/Game")
	_inventory = get_node_or_null(^"/root/Inventory")
	_interact_key = UiUtil.action_key_label(&"interact", "E")
	_prompt.modulate.a = 0.0
	_refusal.modulate.a = 0.0
	_set_vignette(0.0)
	_vignette.visible = false
	_weapon.text = UiText.text("unarmed")
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
		_sync_from_player()


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
	_melee = player.get_melee() if player.has_method(&"get_melee") else null
	_last_fraction = -1.0
	_weapon_id = &""
	if is_node_ready():
		_sync_from_player()


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
	_update_health_pulse(delta)
	_update_weapon(delta)
	if _refusal_left > 0.0:
		_refusal_left -= delta
		if _refusal_left <= 0.0:
			_refusal_tween = _fade(_refusal, _refusal_tween, 0.0, refusal_fade_sec)


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
	_melee = null


func _player_hooks() -> Array[Array]:
	return [
		[&"health_changed", _on_health_changed],
		[&"damaged", _on_damaged],
		[&"took_fall_damage", _on_fall_damage],
	]


## Snaps every gauge to the player's current numbers (on bind and respawn): no easing, no ghost trail.
func _sync_from_player() -> void:
	if _player == null or not is_instance_valid(_player) or _health == null:
		return
	if _player.has_method(&"health_fraction"):
		_health_fraction = clampf(_player.health_fraction(), 0.0, 1.0)
		_kill(_health_tween)
		_kill(_ghost_tween)
		_health.value = _health_fraction
		_ghost.value = _health_fraction
	_refresh_weapon()


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
		_kill(_stamina_tween)
		_stamina.modulate.a = 1.0


# The health bar never fades; below the threshold it breathes instead.
func _update_health_pulse(delta: float) -> void:
	if HudMath.is_low(_health_fraction):
		_low_time += delta
		_health.self_modulate.a = HudMath.low_health_pulse(_low_time)
	elif _low_time > 0.0 or _health.self_modulate.a < 1.0:
		_low_time = 0.0
		_health.self_modulate.a = 1.0


# Melee has no equip signal, so the equipped id is compared each frame (one StringName compare); the slot
# dims while a swing is committed and brightens back as soon as Melee is IDLE again.
func _update_weapon(delta: float) -> void:
	if _melee == null or not is_instance_valid(_melee):
		return
	if _melee.equipped() != _weapon_id:
		_refresh_weapon()
	var target: float = 1.0 if _melee.state_name() == MELEE_IDLE else weapon_dim_alpha
	if not is_equal_approx(_weapon.modulate.a, target):
		_weapon.modulate.a = move_toward(_weapon.modulate.a, target, weapon_dim_speed * delta)


func _refresh_weapon() -> void:
	if _weapon == null:
		return
	if _melee == null or not is_instance_valid(_melee):
		_weapon_id = &""
		_weapon.text = UiText.text("unarmed")
		return
	_weapon_id = _melee.equipped()
	_weapon.text = UiText.text("unarmed") if _weapon_id == Melee.UNARMED else _melee.weapon_name()


func _on_health_changed(fraction: float) -> void:
	_health_fraction = clampf(fraction, 0.0, 1.0)
	_health_tween = _tween_value(_health, _health_tween, _health_fraction, health_ease_sec, 0.0)
	var hold: float = HudMath.ghost_hold(_ghost.value, _health_fraction)
	if hold <= _health_fraction:
		_kill(_ghost_tween)
		_ghost.value = hold
	else:
		_ghost_tween = _tween_value(_ghost, _ghost_tween, _health_fraction, ghost_ease_sec, ghost_delay_sec)


func _on_damaged(amount: float, _from: Node) -> void:
	_flash(HudMath.vignette_strength(amount, _max_health()))


# Fall damage also arrives through `damaged`; the flash takes the stronger of the two, never the sum.
func _on_fall_damage(drop: float) -> void:
	var amount: float = drop
	if _player != null and is_instance_valid(_player) and _player.has_method(&"fall_damage_for"):
		amount = _player.fall_damage_for(drop)
	_flash(HudMath.vignette_strength(amount, _max_health()))


func _flash(strength: float) -> void:
	if strength <= 0.0 or _vignette == null:
		return
	_kill(_vignette_tween)
	var from: float = maxf(_vignette_strength(), strength)
	_vignette.visible = true
	_set_vignette(from)
	_vignette_tween = create_tween()
	_vignette_tween.tween_method(_set_vignette, from, 0.0, vignette_fade_sec).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	_vignette_tween.tween_callback(_vignette.hide)


func _set_vignette(value: float) -> void:
	var material: ShaderMaterial = _vignette.material as ShaderMaterial
	if material != null:
		material.set_shader_parameter(VIGNETTE_PARAM, value)


func _vignette_strength() -> float:
	var material: ShaderMaterial = _vignette.material as ShaderMaterial
	return float(material.get_shader_parameter(VIGNETTE_PARAM)) if material != null else 0.0


func _max_health() -> float:
	if _player == null or not is_instance_valid(_player):
		return 100.0
	var value: Variant = _player.get(&"max_health")
	return float(value) if value != null and float(value) > 0.0 else 100.0


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
	# Deferred: the player's auto-equip listens to the same signal and may run after this handler.
	_refresh_weapon.call_deferred()


func _on_reading_requested(title: String, body: String) -> void:
	_lore_card.open(title, body)


func _fade(node: CanvasItem, current: Tween, alpha: float, seconds: float) -> Tween:
	_kill(current)
	var tween: Tween = create_tween()
	tween.tween_property(node, ^"modulate:a", alpha, seconds)
	return tween


func _tween_value(bar: Range, current: Tween, target: float, seconds: float, delay: float) -> Tween:
	_kill(current)
	var tween: Tween = create_tween()
	if delay > 0.0:
		tween.tween_interval(delay)
	tween.tween_property(bar, ^"value", target, seconds).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	return tween


func _kill(tween: Tween) -> void:
	if tween != null and tween.is_valid():
		tween.kill()


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
