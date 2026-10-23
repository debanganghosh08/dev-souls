extends "res://tests/test_case.gd"
## Pure Stamina tests: spend, drain, delayed regen, clamps, zero-max safety, reset.


func _fresh() -> Stamina:
	var s: Stamina = Stamina.new()
	s.max_value = 100.0
	s.current = 100.0
	s.regen_per_sec = 30.0
	s.regen_delay_sec = 0.6
	return s


func test_spend_fails_and_spends_nothing_when_short() -> void:
	var s: Stamina = _fresh()
	s.current = 10.0
	assert_false(s.spend(20.0), "spend above current fails")
	assert_eq(s.current, 10.0, "failed spend leaves current untouched")
	s.tick(1.0)
	assert_true(is_equal_approx(s.current, 40.0), "failed spend did not start the regen delay")


func test_spend_succeeds_and_reduces() -> void:
	var s: Stamina = _fresh()
	assert_true(s.spend(30.0), "spend within current succeeds")
	assert_eq(s.current, 70.0, "spend reduces current by amount")
	assert_true(s.spend(70.0), "spending exactly what is left succeeds")
	assert_eq(s.current, 0.0, "exact spend reaches zero")
	assert_true(s.is_empty(), "zero is empty")


func test_can_afford() -> void:
	var s: Stamina = _fresh()
	s.current = 25.0
	assert_true(s.can_afford(25.0), "exact amount is affordable")
	assert_false(s.can_afford(25.01), "slightly more is not affordable")


func test_drain_never_negative_and_false_when_empty() -> void:
	var s: Stamina = _fresh()
	s.current = 5.0
	assert_true(s.drain(100.0, 0.1), "drain with stamina left succeeds")
	assert_eq(s.current, 0.0, "drain clamps at zero instead of going negative")
	assert_false(s.drain(100.0, 0.1), "drain when empty fails")
	assert_eq(s.current, 0.0, "failed drain changes nothing")


func test_tick_waits_for_delay_then_regenerates() -> void:
	var s: Stamina = _fresh()
	s.spend(50.0)
	s.tick(0.3)
	assert_eq(s.current, 50.0, "no regen during the delay")
	s.tick(0.3)
	assert_eq(s.current, 50.0, "no regen when the delay ends exactly")
	s.tick(0.5)
	assert_true(is_equal_approx(s.current, 65.0), "regen at regen_per_sec after the delay")


func test_tick_regenerates_with_the_remainder_of_a_long_delta() -> void:
	var s: Stamina = _fresh()
	s.spend(50.0)
	s.tick(0.8)
	assert_true(is_equal_approx(s.current, 56.0), "only the time past the delay regenerates")


func test_drain_restarts_regen_delay() -> void:
	var s: Stamina = _fresh()
	s.current = 50.0
	s.drain(10.0, 0.1)
	s.tick(0.5)
	assert_true(is_equal_approx(s.current, 49.0), "draining restarts the delay so tick does not regen yet")


func test_regen_stops_exactly_at_max() -> void:
	var s: Stamina = _fresh()
	s.current = 95.0
	s.tick(1.0)
	assert_eq(s.current, 100.0, "regen clamps exactly at max_value")
	assert_eq(s.fraction(), 1.0, "fraction is 1 at max")


func test_fraction_is_safe_when_max_is_zero() -> void:
	var s: Stamina = _fresh()
	s.max_value = 0.0
	s.current = 0.0
	assert_eq(s.fraction(), 0.0, "fraction with zero max is 0, not NaN")
	s.tick(1.0)
	assert_eq(s.current, 0.0, "tick with zero max stays clamped at 0")


func test_fraction_normal() -> void:
	var s: Stamina = _fresh()
	s.current = 25.0
	assert_true(is_equal_approx(s.fraction(), 0.25), "fraction is current / max")


func test_reset_restores_and_clears_delay() -> void:
	var s: Stamina = _fresh()
	s.spend(90.0)
	s.reset()
	assert_eq(s.current, 100.0, "reset restores to max")
	s.current = 50.0
	s.tick(1.0)
	assert_true(is_equal_approx(s.current, 80.0), "reset cleared the regen delay")
