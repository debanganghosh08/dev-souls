extends CharacterBody3D
class_name Damageable
## The contract everything attackable shares: a Health pool, take_damage, and died/damaged signals.
## Creatures and the Hollowed extend this. The player does NOT: PlayerController already extends
## CharacterBody3D with its own locomotion and GDScript has no multiple inheritance, so the player
## owns a Health of its own and exposes the same take_damage(amount, from) shape by convention.

signal damaged(amount: float, from: Node)
signal died(from: Node)

@export var max_health: float = 50.0

var health: Health = Health.new()


func _ready() -> void:
	sync_health()


# Exports are applied after _init, so the pool is sized here (and by tests that never enter a tree).
func sync_health() -> void:
	health.set_max(max_health, false)
	health.reset()


func take_damage(amount: float, from: Node) -> float:
	if health.is_dead():
		return 0.0
	var applied: float = health.damage(amount)
	if applied <= 0.0:
		return 0.0
	damaged.emit(applied, from)
	if health.is_dead():
		died.emit(from)
		_on_died(from)
	return applied


func is_dead() -> bool:
	return health.is_dead()


func health_fraction() -> float:
	return health.fraction()


func _on_died(_from: Node) -> void:
	pass
