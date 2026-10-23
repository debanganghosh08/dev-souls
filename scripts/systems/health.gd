extends RefCounted
class_name Health
## Pure health pool: damage with invulnerability, healing, max changes, death. No nodes, no signals, so
## unit-testable; the owning node decides what to emit.

var max_value: float = 100.0
var current: float = 100.0
var invulnerable: bool = false


func damage(amount: float) -> float:
	if invulnerable or is_dead() or amount <= 0.0:
		return 0.0
	var applied: float = minf(amount, current)
	current = clampf(current - applied, 0.0, max_value)
	return applied


func heal(amount: float) -> float:
	if amount <= 0.0:
		return 0.0
	var restored: float = minf(amount, max_value - current)
	current = clampf(current + restored, 0.0, max_value)
	return restored


func set_max(value: float, keep_ratio: bool) -> void:
	if value <= 0.0:
		return
	var ratio: float = fraction()
	max_value = value
	if keep_ratio:
		current = max_value * ratio
	current = clampf(current, 0.0, max_value)


func is_dead() -> bool:
	return current <= 0.0


func fraction() -> float:
	if max_value <= 0.0:
		return 0.0
	return clampf(current / max_value, 0.0, 1.0)


func reset() -> void:
	current = max_value


func kill() -> void:
	current = 0.0
