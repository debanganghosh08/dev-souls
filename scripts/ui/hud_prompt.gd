extends Node
class_name HudPrompt
## The HUD's interaction prompt ("[E]  Open") and the refusal line above it. A child of the HUD scene;
## hud.gd connects the player's InteractionDetector to the two handlers here.

@export var prompt_fade_sec: float = 0.12
@export var refusal_hold_sec: float = 2.5
@export var refusal_fade_sec: float = 0.5

@onready var _prompt: Label = %Prompt
@onready var _refusal: Label = %Refusal

var _interact_key: String = "E"
var _prompt_tween: Tween
var _refusal_tween: Tween
var _refusal_left: float = 0.0


func _ready() -> void:
	_interact_key = UiUtil.action_key_label(&"interact", "E")
	_prompt.modulate.a = 0.0
	_refusal.modulate.a = 0.0


func _process(delta: float) -> void:
	if _refusal_left > 0.0:
		_refusal_left -= delta
		if _refusal_left <= 0.0:
			_refusal_tween = _fade(_refusal, _refusal_tween, 0.0, refusal_fade_sec)


func on_focus_changed(target: Interactable) -> void:
	if target == null or not is_instance_valid(target):
		_prompt_tween = _fade(_prompt, _prompt_tween, 0.0, prompt_fade_sec)
		return
	_prompt.text = UiText.text("prompt_format") % [_interact_key, target.prompt_text()]
	_prompt_tween = _fade(_prompt, _prompt_tween, 1.0, prompt_fade_sec)


func on_interaction_refused(reason: String) -> void:
	_refusal.text = reason
	_refusal_left = refusal_hold_sec
	_refusal_tween = _fade(_refusal, _refusal_tween, 1.0, prompt_fade_sec)


func _fade(node: CanvasItem, current: Tween, alpha: float, seconds: float) -> Tween:
	if current != null and current.is_valid():
		current.kill()
	var tween: Tween = create_tween()
	tween.tween_property(node, ^"modulate:a", alpha, seconds)
	return tween
