extends RefCounted
class_name Stamina
## Pure stamina pool: one-off spend, continuous drain, regen after a delay. No nodes, so unit-testable.

var max_value: float = 100.0
var current: float = 100.0
var regen_per_sec: float = 30.0
var regen_delay_sec: float = 0.6

var _delay_left: float = 0.0


func spend(amount: float) -> bool:
	if amount > current:
		return false
	current = clampf(current - amount, 0.0, max_value)
	_delay_left = regen_delay_sec
	return true


func drain(amount_per_sec: float, delta: float) -> bool:
	if is_empty():
		return false
	current = clampf(current - amount_per_sec * delta, 0.0, max_value)
	_delay_left = regen_delay_sec
	return true


func tick(delta: float) -> void:
	var regen_time: float = delta
	if _delay_left > 0.0:
		if delta <= _delay_left:
			_delay_left -= delta
			return
		regen_time = delta - _delay_left
		_delay_left = 0.0
	current = clampf(current + regen_per_sec * regen_time, 0.0, max_value)


func can_afford(amount: float) -> bool:
	return current >= amount


func is_empty() -> bool:
	return current <= 0.0


func fraction() -> float:
	if max_value <= 0.0:
		return 0.0
	return clampf(current / max_value, 0.0, 1.0)


func reset() -> void:
	current = max_value
	_delay_left = 0.0
