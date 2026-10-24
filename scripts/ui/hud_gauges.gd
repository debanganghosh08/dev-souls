extends Node
class_name HudGauges
## The HUD's gauges: health bar with ghost trail and low-health breath, hit vignette, stamina bar and the
## weapon slot. A child of the HUD scene; hud.gd forwards the player's signals here. Arithmetic is HudMath.

const MELEE_IDLE := "IDLE"
const VIGNETTE_PARAM := &"strength"

@export var stamina_idle_fade_sec: float = 2.0
@export var stamina_idle_alpha: float = 0.12
@export var health_ease_sec: float = 0.25
@export var ghost_delay_sec: float = 0.5
@export var ghost_ease_sec: float = 0.3
@export var vignette_fade_sec: float = 0.35
@export var weapon_dim_alpha: float = 0.45
@export var weapon_dim_speed: float = 10.0

@onready var _health: ProgressBar = %HealthBar
@onready var _ghost: ProgressBar = %HealthGhost
@onready var _vignette: ColorRect = %Vignette
@onready var _stamina: ProgressBar = %StaminaBar
@onready var _weapon: Label = %WeaponLabel

var _player: Node
var _melee: Melee
var _last_fraction: float = -1.0
var _stamina_idle: float = 0.0
var _health_fraction: float = 1.0
var _low_time: float = 0.0
var _weapon_id: StringName = &""
var _stamina_tween: Tween
var _health_tween: Tween
var _ghost_tween: Tween
var _vignette_tween: Tween


func _ready() -> void:
	set_vignette(0.0)
	_vignette.visible = false
	_weapon.text = UiText.text("unarmed")


func bind(player: Node, melee: Melee) -> void:
	_player = player
	_melee = melee
	_last_fraction = -1.0
	_weapon_id = &""


func _process(delta: float) -> void:
	_update_stamina(delta)
	_update_health_pulse(delta)
	_update_weapon(delta)


## Snaps every gauge to the player's current numbers (on bind and respawn): no easing, no ghost trail.
func sync_from_player() -> void:
	if _player == null or not is_instance_valid(_player) or _health == null:
		return
	if _player.has_method(&"health_fraction"):
		_health_fraction = clampf(_player.health_fraction(), 0.0, 1.0)
		_kill(_health_tween)
		_kill(_ghost_tween)
		_health.value = _health_fraction
		_ghost.value = _health_fraction
	refresh_weapon()


func on_health_changed(fraction: float) -> void:
	_health_fraction = clampf(fraction, 0.0, 1.0)
	_health_tween = _tween_value(_health, _health_tween, _health_fraction, health_ease_sec, 0.0)
	var hold: float = HudMath.ghost_hold(_ghost.value, _health_fraction)
	if hold <= _health_fraction:
		_kill(_ghost_tween)
		_ghost.value = hold
	else:
		_ghost_tween = _tween_value(_ghost, _ghost_tween, _health_fraction, ghost_ease_sec, ghost_delay_sec)


func on_damaged(amount: float) -> void:
	flash(HudMath.vignette_strength(amount, _max_health()))


# Fall damage also arrives through `damaged`; the flash takes the stronger of the two, never the sum.
func on_fall_damage(drop: float) -> void:
	var amount: float = drop
	if _player != null and is_instance_valid(_player) and _player.has_method(&"fall_damage_for"):
		amount = _player.fall_damage_for(drop)
	flash(HudMath.vignette_strength(amount, _max_health()))


func flash(strength: float) -> void:
	if strength <= 0.0 or _vignette == null:
		return
	_kill(_vignette_tween)
	var from: float = maxf(vignette_strength(), strength)
	_vignette.visible = true
	set_vignette(from)
	_vignette_tween = create_tween()
	_vignette_tween.tween_method(set_vignette, from, 0.0, vignette_fade_sec).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	_vignette_tween.tween_callback(_vignette.hide)


func set_vignette(value: float) -> void:
	var material: ShaderMaterial = _vignette.material as ShaderMaterial
	if material != null:
		material.set_shader_parameter(VIGNETTE_PARAM, value)


func vignette_strength() -> float:
	var material: ShaderMaterial = _vignette.material as ShaderMaterial
	return float(material.get_shader_parameter(VIGNETTE_PARAM)) if material != null else 0.0


func refresh_weapon() -> void:
	if _weapon == null:
		return
	if _melee == null or not is_instance_valid(_melee):
		_weapon_id = &""
		_weapon.text = UiText.text("unarmed")
		return
	_weapon_id = _melee.equipped()
	_weapon.text = UiText.text("unarmed") if _weapon_id == Melee.UNARMED else _melee.weapon_name()


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
		refresh_weapon()
	var target: float = 1.0 if _melee.state_name() == MELEE_IDLE else weapon_dim_alpha
	if not is_equal_approx(_weapon.modulate.a, target):
		_weapon.modulate.a = move_toward(_weapon.modulate.a, target, weapon_dim_speed * delta)


func _max_health() -> float:
	if _player == null or not is_instance_valid(_player):
		return 100.0
	var value: Variant = _player.get(&"max_health")
	return float(value) if value != null and float(value) > 0.0 else 100.0


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
