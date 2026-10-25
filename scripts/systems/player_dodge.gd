extends RefCounted
class_name PlayerDodge
## The dodge roll's clock: a fixed-length dash along one flat direction with i-frames for its first part.
## PlayerController owns the public is_dodging / is_invulnerable flags and copies this state into them.

var direction: Vector3 = Vector3.FORWARD
var time_left: float = 0.0


func start(dir: Vector3, duration: float) -> void:
	direction = Vector3(dir.x, 0.0, dir.z).normalized()
	time_left = duration


func active() -> bool:
	return time_left > 0.0


# Advances the clock; returns true while the roll still grants invulnerability.
func tick(delta: float, duration: float, invulnerable_fraction: float) -> bool:
	time_left -= delta
	var elapsed_fraction: float = 1.0 - time_left / maxf(duration, 0.001)
	return elapsed_fraction < invulnerable_fraction
