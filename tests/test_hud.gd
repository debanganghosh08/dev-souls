extends "res://tests/test_case.gd"
## HUD: scene structure (health bar, ghost trail, vignette and weapon slot wired under the Overlay so they
## hide with it), the signal binding to the player, and the pure HudMath numbers. No tree exists in the
## runner, so nothing is tweened here; the live run is covered by test_level_dressing.gd's child probe.

const HUD := "res://scenes/ui/hud.tscn"
const PLAYER := "res://scenes/player/player.tscn"

var _nodes: Array[Node] = []


func _spawn(path: String) -> Node:
	var node: Node = (load(path) as PackedScene).instantiate()
	_nodes.append(node)
	return node


func teardown() -> void:
	for node: Node in _nodes:
		node.free()
	_nodes.clear()


func test_hud_has_health_ghost_vignette_and_weapon_slot_under_the_overlay() -> void:
	var hud: Node = _spawn(HUD)
	var overlay: Control = hud.get_node_or_null("%Overlay") as Control
	assert_not_null(overlay, "HUD keeps its %Overlay")
	for name: String in ["%HealthTrough", "%HealthGhost", "%HealthBar", "%Vignette", "%WeaponLabel", "%StaminaBar"]:
		var node: Node = hud.get_node_or_null(name)
		assert_not_null(node, "HUD has %s" % name)
		if node != null:
			assert_true(node.get_parent() == overlay, "%s sits under the Overlay so it hides with Game.state" % name)
	var health: ProgressBar = hud.get_node_or_null("%HealthBar") as ProgressBar
	var ghost: ProgressBar = hud.get_node_or_null("%HealthGhost") as ProgressBar
	var trough: Control = hud.get_node_or_null("%HealthTrough") as Control
	var stamina: ProgressBar = hud.get_node_or_null("%StaminaBar") as ProgressBar
	assert_not_null(health, "health bar is a ProgressBar")
	assert_not_null(ghost, "ghost trail is a ProgressBar")
	if health != null and ghost != null and trough != null and stamina != null:
		assert_true(is_equal_approx(health.max_value, 1.0) and is_equal_approx(health.value, 1.0), "health bar runs 0..1 and starts full")
		assert_true(is_equal_approx(ghost.max_value, 1.0) and is_equal_approx(ghost.value, 1.0), "ghost runs 0..1 and starts full")
		assert_true(trough.get_index() < ghost.get_index() and ghost.get_index() < health.get_index(),
			"draw order is trough, then ghost, then the real fill on top")
		# No tree, so no layout pass: compare the anchored offsets, which is what the scene stores.
		var health_px: float = health.offset_bottom - health.offset_top
		var stamina_px: float = stamina.offset_bottom - stamina.offset_top
		assert_true(health_px > stamina_px * 2.0, "health is the thicker, primary gauge (%.0f px vs %.0f px)" % [health_px, stamina_px])
		assert_true(health.get_theme_stylebox("fill") is StyleBoxFlat, "health fill is a flat dark-red stylebox")
		var fill: StyleBoxFlat = health.get_theme_stylebox("fill") as StyleBoxFlat
		if fill != null:
			assert_true(fill.bg_color.r > fill.bg_color.g * 3.0 and fill.bg_color.r < 0.6, "fill is a dark red, not a bright one")
	var vignette: ColorRect = hud.get_node_or_null("%Vignette") as ColorRect
	assert_not_null(vignette, "vignette is a ColorRect")
	if vignette != null:
		assert_false(vignette.visible, "vignette starts hidden")
		var material: ShaderMaterial = vignette.material as ShaderMaterial
		assert_not_null(material, "vignette carries a ShaderMaterial")
		if material != null:
			assert_true("strength" in material.shader.code, "vignette shader exposes the strength the HUD drives")
			assert_true(is_zero_approx(float(material.get_shader_parameter(Hud.VIGNETTE_PARAM))), "vignette strength starts at 0")
	var weapon: Label = hud.get_node_or_null("%WeaponLabel") as Label
	assert_not_null(weapon, "weapon slot is a Label")
	if weapon != null:
		assert_true(weapon.anchor_left == 1.0 and weapon.anchor_top == 1.0, "weapon slot is anchored bottom-right")


func test_bind_player_connects_health_damage_and_fall_signals_and_rebinds_cleanly() -> void:
	var hud: Hud = _spawn(HUD) as Hud
	var first: Node = _spawn(PLAYER)
	var second: Node = _spawn(PLAYER)
	hud.bind_player(first)
	for signal_name: StringName in [&"health_changed", &"damaged", &"took_fall_damage"]:
		assert_true(first.is_connected(signal_name, Callable(hud, "_on_" + _handler_for(signal_name))),
			"bind_player connects %s" % signal_name)
	hud.bind_player(first)
	assert_true(first.is_connected(&"health_changed", hud._on_health_changed), "rebinding the same player keeps the connection")
	hud.bind_player(second)
	assert_false(first.is_connected(&"health_changed", hud._on_health_changed), "binding another player disconnects the old one")
	assert_false(first.is_connected(&"damaged", hud._on_damaged), "old damaged hook released")
	assert_true(second.is_connected(&"damaged", hud._on_damaged), "new player gets the damaged hook")


func _handler_for(signal_name: StringName) -> String:
	match signal_name:
		&"health_changed":
			return "health_changed"
		&"damaged":
			return "damaged"
	return "fall_damage"


func test_vignette_strength_scales_with_fraction_lost_floored_and_capped() -> void:
	assert_true(is_zero_approx(HudMath.vignette_strength(0.0, 100.0)), "no damage, no flash")
	assert_true(is_zero_approx(HudMath.vignette_strength(10.0, 0.0)), "a zero pool never divides")
	assert_true(is_equal_approx(HudMath.vignette_strength(1.0, 100.0), HudMath.VIGNETTE_MIN), "a scratch still registers at the floor")
	assert_true(is_equal_approx(HudMath.vignette_strength(12.0, 100.0), 0.24), "a wolf bite (12 %) reads 0.24")
	assert_true(is_equal_approx(HudMath.vignette_strength(30.0, 100.0), 0.6), "30 % lost reads 0.6")
	assert_true(is_equal_approx(HudMath.vignette_strength(90.0, 100.0), HudMath.VIGNETTE_MAX), "a near-kill caps out")
	assert_true(HudMath.vignette_strength(12.0, 200.0) < HudMath.vignette_strength(12.0, 100.0), "a bigger pool makes the same hit read lighter")


func test_low_health_threshold_and_pulse_shape() -> void:
	assert_true(HudMath.is_low(0.29), "29 % is low")
	assert_false(HudMath.is_low(0.3), "30 % is the threshold, not below it")
	assert_false(HudMath.is_low(1.0), "full is not low")
	var cycle: float = HudMath.LOW_HEALTH_CYCLE_SEC
	assert_true(is_equal_approx(cycle, 1.2), "pulse cycle is 1.2 s")
	assert_true(is_equal_approx(HudMath.low_health_pulse(0.0), lerpf(HudMath.LOW_HEALTH_DIM, 1.0, 0.5)), "pulse starts mid-way")
	assert_true(is_equal_approx(HudMath.low_health_pulse(cycle * 0.25), 1.0), "pulse peaks at full alpha")
	assert_true(is_equal_approx(HudMath.low_health_pulse(cycle * 0.75), HudMath.LOW_HEALTH_DIM), "pulse bottoms at the dim alpha, never invisible")
	assert_true(is_equal_approx(HudMath.low_health_pulse(cycle), HudMath.low_health_pulse(0.0)), "pulse repeats every cycle")
	assert_true(is_equal_approx(HudMath.low_health_pulse(0.7, 0.0), 1.0), "a zero cycle disables the pulse")
	assert_true(HudMath.LOW_HEALTH_DIM >= 0.5, "the dim phase keeps the bar clearly visible")


func test_fill_width_and_ghost_hold() -> void:
	assert_true(is_equal_approx(HudMath.fill_width(0.5, 360.0), 180.0), "half health is half the trough")
	assert_true(is_zero_approx(HudMath.fill_width(-0.2, 360.0)), "negative fractions clamp to empty")
	assert_true(is_equal_approx(HudMath.fill_width(1.5, 360.0), 360.0), "over-full clamps to the trough")
	assert_true(is_zero_approx(HudMath.fill_width(0.5, -10.0)), "a negative width is treated as zero")
	assert_true(is_equal_approx(HudMath.ghost_hold(1.0, 0.52), 1.0), "after a hit the ghost holds at the old value")
	assert_true(is_equal_approx(HudMath.ghost_hold(0.52, 0.9), 0.9), "after a heal the ghost snaps up to the new value")
	assert_true(is_equal_approx(HudMath.ghost_hold(0.6, 0.6), 0.6), "no change leaves the ghost where it is")


func test_ui_text_has_the_weapon_slot_fallback() -> void:
	var json := JSON.new()
	assert_eq(json.parse(FileAccess.get_file_as_string(UiText.PATH)), OK, "data/ui_text.json parses")
	var table: Dictionary = json.data if json.data is Dictionary else {}
	assert_true(table.has("unarmed") and table["unarmed"] is String and table["unarmed"] != "", "ui_text.json has 'unarmed'")
	assert_true(UiText.DEFAULTS.has("unarmed"), "built-in fallback covers 'unarmed'")
	assert_eq(UiText.text("unarmed"), "Unarmed", "weapon slot reads Unarmed when nothing is equipped")
