extends "res://tests/test_case.gd"
## Pure Health tests: damage clamps, invulnerability, healing cap, set_max, zero-max safety, kill, reset.


func _fresh(max_value: float = 100.0) -> Health:
	var h: Health = Health.new()
	h.max_value = max_value
	h.current = max_value
	h.invulnerable = false
	return h


func test_damage_reduces_and_returns_applied() -> void:
	var h: Health = _fresh()
	assert_eq(h.damage(30.0), 30.0, "full damage applies when there is room")
	assert_eq(h.current, 70.0, "current drops by the amount")
	assert_false(h.is_dead(), "70 is alive")


func test_damage_clamps_at_zero_and_never_negative() -> void:
	var h: Health = _fresh()
	h.current = 20.0
	assert_eq(h.damage(50.0), 20.0, "only the remaining 20 is applied")
	assert_eq(h.current, 0.0, "current clamps at zero")
	assert_true(h.is_dead(), "zero is dead")
	assert_eq(h.damage(10.0), 0.0, "damage on a dead pool applies nothing")
	assert_eq(h.current, 0.0, "current never goes negative")


func test_damage_ignores_non_positive_amounts() -> void:
	var h: Health = _fresh()
	assert_eq(h.damage(0.0), 0.0, "zero damage applies nothing")
	assert_eq(h.damage(-15.0), 0.0, "negative damage applies nothing")
	assert_eq(h.current, 100.0, "current untouched by non-positive damage")


func test_damage_while_invulnerable_applies_nothing() -> void:
	var h: Health = _fresh()
	h.invulnerable = true
	assert_eq(h.damage(40.0), 0.0, "invulnerable returns zero applied")
	assert_eq(h.current, 100.0, "invulnerable leaves current untouched")
	h.invulnerable = false
	assert_eq(h.damage(40.0), 40.0, "damage applies again once vulnerable")


func test_heal_never_exceeds_max() -> void:
	var h: Health = _fresh()
	h.current = 80.0
	assert_eq(h.heal(50.0), 20.0, "only the missing 20 is restored")
	assert_eq(h.current, 100.0, "healing caps at max")
	assert_eq(h.heal(10.0), 0.0, "healing a full pool restores nothing")
	assert_eq(h.heal(-5.0), 0.0, "negative heal restores nothing")
	assert_eq(h.current, 100.0, "current unchanged by a negative heal")


func test_heal_from_dead_revives_the_pool() -> void:
	var h: Health = _fresh()
	h.kill()
	assert_eq(h.heal(25.0), 25.0, "healing a dead pool restores the amount")
	assert_false(h.is_dead(), "healed pool is alive again")


func test_set_max_keeping_ratio_scales_current() -> void:
	var h: Health = _fresh()
	h.current = 50.0
	h.set_max(200.0, true)
	assert_eq(h.max_value, 200.0, "max updated")
	assert_true(is_equal_approx(h.current, 100.0), "half stays half of the new max")
	h.set_max(40.0, true)
	assert_true(is_equal_approx(h.current, 20.0), "shrinking keeps the ratio too")


func test_set_max_without_ratio_only_clamps() -> void:
	var h: Health = _fresh()
	h.current = 50.0
	h.set_max(200.0, false)
	assert_eq(h.current, 50.0, "raising max leaves current as is")
	h.set_max(30.0, false)
	assert_eq(h.current, 30.0, "lowering max below current clamps current down")


func test_set_max_guards_non_positive_values() -> void:
	var h: Health = _fresh()
	h.set_max(0.0, true)
	assert_eq(h.max_value, 100.0, "zero max is refused")
	h.set_max(-10.0, false)
	assert_eq(h.max_value, 100.0, "negative max is refused")
	assert_eq(h.current, 100.0, "current untouched by refused set_max")


func test_fraction_is_safe_when_max_is_zero() -> void:
	var h: Health = _fresh()
	h.max_value = 0.0
	h.current = 0.0
	assert_eq(h.fraction(), 0.0, "zero max gives fraction 0 instead of dividing by zero")
	h.current = 5.0
	assert_eq(h.fraction(), 0.0, "zero max still gives 0 with stray current")


func test_fraction_and_reset() -> void:
	var h: Health = _fresh()
	h.current = 25.0
	assert_true(is_equal_approx(h.fraction(), 0.25), "fraction is current over max")
	h.current = 150.0
	assert_eq(h.fraction(), 1.0, "fraction clamps to 1 when current overshoots")
	h.reset()
	assert_eq(h.current, 100.0, "reset refills to max")


func test_kill_empties_the_pool() -> void:
	var h: Health = _fresh()
	h.invulnerable = true
	h.kill()
	assert_eq(h.current, 0.0, "kill sets current to zero even while invulnerable")
	assert_true(h.is_dead(), "killed is dead")
	assert_eq(h.fraction(), 0.0, "killed fraction is zero")
