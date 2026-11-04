extends "res://tests/test_case.gd"
## SkyProfile is pure (no nodes, no autoloads), so everything here runs in-process.

const EPS := 0.001


func _kf(hour: float, fog: float, fog_color: String, sun: float = 0.5) -> Dictionary:
	return {"hour": hour, "fog_density": fog, "fog_color": fog_color, "sun_energy": sun}


func _profile(frames: Array) -> SkyProfile:
	return SkyProfile.from_dict({"keyframes": frames})


func _near(a: float, b: float) -> bool:
	return absf(a - b) < EPS


func test_sample_on_a_keyframe_returns_its_values() -> void:
	var p: SkyProfile = _profile([_kf(6.0, 0.1, "#102030", 0.2), _kf(12.0, 0.5, "#ffffff", 0.9), _kf(18.0, 0.3, "#000000", 0.1)])
	var s: Dictionary = p.sample(12.0)
	assert_true(_near(s["fog_density"], 0.5), "fog at the 12:00 keyframe is exact")
	assert_true(_near(s["sun_energy"], 0.9), "sun energy at the 12:00 keyframe is exact")
	assert_true((s["fog_color"] as Color).is_equal_approx(Color.WHITE), "fog colour at the 12:00 keyframe is exact")
	var first: Dictionary = p.sample(6.0)
	assert_true(_near(first["fog_density"], 0.1), "the first keyframe samples exactly")
	var last: Dictionary = p.sample(18.0)
	assert_true(_near(last["fog_density"], 0.3), "the last keyframe samples exactly")


func test_sample_midway_interpolates_halfway() -> void:
	var p: SkyProfile = _profile([_kf(6.0, 0.2, "#000000", 0.0), _kf(12.0, 0.6, "#ffffff", 1.0)])
	var s: Dictionary = p.sample(9.0)
	assert_true(_near(s["fog_density"], 0.4), "fog halfway between 0.2 and 0.6 is 0.4 (got %s)" % s["fog_density"])
	assert_true(_near(s["sun_energy"], 0.5), "sun energy halfway is 0.5")
	assert_true((s["fog_color"] as Color).is_equal_approx(Color(0.5, 0.5, 0.5)), "colour lerps to mid grey")
	var q: Dictionary = p.sample(7.5)
	assert_true(_near(q["fog_density"], 0.3), "a quarter of the way is 0.3")


func test_midnight_wrap_interpolates_the_short_way() -> void:
	var p: SkyProfile = _profile([_kf(2.0, 0.4, "#ffffff", 1.0), _kf(22.0, 0.2, "#000000", 0.0)])
	var midnight: Dictionary = p.sample(0.0)
	assert_true(_near(midnight["fog_density"], 0.3), "00:00 is halfway between 22:00 and 02:00 (got %s)" % midnight["fog_density"])
	assert_true(_near(midnight["sun_energy"], 0.5), "00:00 sun energy is halfway")
	assert_true((midnight["fog_color"] as Color).is_equal_approx(Color(0.5, 0.5, 0.5)), "00:00 colour is mid grey")
	var late: Dictionary = p.sample(23.0)
	assert_true(_near(late["fog_density"], 0.25), "23:00 is a quarter of the way from 22:00 to 02:00 (got %s)" % late["fog_density"])
	var early: Dictionary = p.sample(1.0)
	assert_true(_near(early["fog_density"], 0.35), "01:00 is three quarters of the way (got %s)" % early["fog_density"])
	var noon: Dictionary = p.sample(12.0)
	assert_true(_near(noon["fog_density"], 0.3), "12:00 is halfway on the long daytime segment from 02:00 to 22:00")


func test_zero_keyframes_returns_defaults() -> void:
	var p: SkyProfile = SkyProfile.new()
	assert_eq(p.keyframe_count(), 0, "fresh profile has no keyframes")
	var s: Dictionary = p.sample(13.0)
	assert_true(_near(s["fog_density"], SkyProfile.DEFAULTS["fog_density"]), "fog falls back to the default")
	assert_eq(s["sun_color"], SkyProfile.DEFAULTS["sun_color"], "sun colour falls back to the default")
	for key: String in SkyProfile.COLOR_KEYS + SkyProfile.FLOAT_KEYS:
		assert_true(s.has(key), "default sample has key %s" % key)


func test_one_keyframe_is_returned_for_every_hour() -> void:
	var p: SkyProfile = _profile([_kf(15.0, 0.33, "#123456", 0.7)])
	assert_eq(p.keyframe_count(), 1, "one keyframe")
	for hour: float in [0.0, 3.0, 15.0, 23.9]:
		var s: Dictionary = p.sample(hour)
		assert_true(_near(s["fog_density"], 0.33), "fog at %s equals the only keyframe" % hour)
		assert_true((s["fog_color"] as Color).is_equal_approx(Color.html("#123456")), "colour at %s equals the only keyframe" % hour)


func test_unsorted_input_is_sorted_on_construction() -> void:
	var p: SkyProfile = _profile([_kf(12.0, 0.9, "#ffffff"), _kf(0.0, 0.1, "#000000"), _kf(6.0, 0.5, "#808080")])
	assert_eq(p.keyframe_hours(), [0.0, 6.0, 12.0] as Array[float], "keyframes are sorted by hour")
	var s: Dictionary = p.sample(3.0)
	assert_true(_near(s["fog_density"], 0.3), "03:00 interpolates between the 00:00 and 06:00 keyframes (got %s)" % s["fog_density"])
	var t: Dictionary = p.sample(9.0)
	assert_true(_near(t["fog_density"], 0.7), "09:00 interpolates between the 06:00 and 12:00 keyframes")


func test_hours_outside_the_day_wrap() -> void:
	var p: SkyProfile = _profile([_kf(1.0, 0.1, "#000000"), _kf(11.0, 0.5, "#808080"), _kf(23.0, 0.9, "#ffffff")])
	assert_true(_near(p.sample(-1.0)["fog_density"], p.sample(23.0)["fog_density"]), "-1 wraps to 23")
	assert_true(_near(p.sample(-1.0)["fog_density"], 0.9), "-1 lands on the 23:00 keyframe")
	assert_true(_near(p.sample(25.0)["fog_density"], p.sample(1.0)["fog_density"]), "25 wraps to 1")
	assert_true(_near(p.sample(25.0)["fog_density"], 0.1), "25 lands on the 01:00 keyframe")
	assert_true(_near(p.sample(24.0)["fog_density"], p.sample(0.0)["fog_density"]), "24 wraps to 0")
	var q: SkyProfile = _profile([_kf(24.0, 0.7, "#ffffff"), _kf(12.0, 0.1, "#000000")])
	assert_eq(q.keyframe_hours(), [0.0, 12.0] as Array[float], "a keyframe at hour 24 is stored at hour 0")


func test_from_dict_survives_missing_keys_and_bad_colours() -> void:
	var p: SkyProfile = SkyProfile.from_dict({"keyframes": [
		{"hour": 5.0, "sun_color": "not a colour", "fog_density": "thick", "sky_top": "#zzzzzz"},
		{"hour": 17.0},
		"garbage",
		{"fog_density": 0.25},
	]})
	assert_eq(p.keyframe_count(), 3, "dictionary entries are kept, non-dictionary entries are skipped")
	var s: Dictionary = p.sample(5.0)
	assert_eq(s["sun_color"], SkyProfile.DEFAULTS["sun_color"], "a malformed colour string falls back to the default")
	assert_eq(s["sky_top"], SkyProfile.DEFAULTS["sky_top"], "a malformed hex falls back to the default")
	assert_true(_near(s["fog_density"], SkyProfile.DEFAULTS["fog_density"]), "a non-numeric float falls back to the default")
	var t: Dictionary = p.sample(17.0)
	for key: String in SkyProfile.COLOR_KEYS + SkyProfile.FLOAT_KEYS:
		assert_true(t.has(key), "a bare keyframe still samples key %s" % key)
	var noh: Dictionary = p.sample(0.0)
	assert_true(_near(noh["fog_density"], 0.25), "a keyframe without an hour defaults to 00:00")
	assert_eq(SkyProfile.from_dict({}).keyframe_count(), 0, "no keyframes key gives an empty profile")
	assert_eq(SkyProfile.from_dict({"keyframes": "junk"}).keyframe_count(), 0, "a non-array keyframes value gives an empty profile")
	assert_true(SkyProfile.from_dict({}).sample(3.0).has("fog_density"), "an empty profile still samples")


func test_cloud_keys_fall_back_and_blend() -> void:
	# wood and barrens omit most of the newer keys and rely on this path; a keyframe without cloud keys must
	# still sample all three, and at the default values. Breaking it: drop "cloud_cover" from FLOAT_KEYS
	# (sample() stops returning it) or from DEFAULTS (add_keyframe indexes a missing key).
	var bare: SkyProfile = _profile([_kf(6.0, 0.1, "#102030")])
	var s: Dictionary = bare.sample(6.0)
	assert_true(_near(s["cloud_cover"], SkyProfile.DEFAULTS["cloud_cover"]), "cloud_cover falls back to the default")
	assert_eq(s["cloud_color"], SkyProfile.DEFAULTS["cloud_color"], "cloud_color falls back to the default")
	assert_eq(s["cloud_shade"], SkyProfile.DEFAULTS["cloud_shade"], "cloud_shade falls back to the default")
	assert_true((SkyProfile.DEFAULTS["cloud_color"] as Color).get_luminance() <= (SkyProfile.DEFAULTS["sky_horizon"] as Color).get_luminance() + EPS,
		"a defaulted cloud is no brighter than the defaulted horizon, so a bare keyframe cannot grow a glowing slab")
	assert_true((SkyProfile.DEFAULTS["cloud_shade"] as Color).get_luminance() < (SkyProfile.DEFAULTS["cloud_color"] as Color).get_luminance(),
		"a cloud's core is darker than its lit edge")
	# And the keys interpolate like every other key: a keyframe that sets them, halfway to one that does not.
	var p: SkyProfile = SkyProfile.from_dict({"keyframes": [
		{"hour": 0.0, "cloud_cover": 1.0, "cloud_color": "#ffffff", "cloud_shade": "#000000"},
		{"hour": 12.0, "cloud_cover": 0.0, "cloud_color": "#000000", "cloud_shade": "#ffffff"},
	]})
	var mid: Dictionary = p.sample(6.0)
	assert_true(_near(mid["cloud_cover"], 0.5), "cloud_cover lerps (got %s)" % mid["cloud_cover"])
	assert_true((mid["cloud_color"] as Color).is_equal_approx(Color(0.5, 0.5, 0.5)), "cloud_color lerps to mid grey")
	assert_true((mid["cloud_shade"] as Color).is_equal_approx(Color(0.5, 0.5, 0.5)), "cloud_shade lerps to mid grey")
	assert_true(_near(p.sample(0.0)["cloud_cover"], 1.0) and _near(p.sample(12.0)["cloud_cover"], 0.0), "the keyframes sample exactly")


func test_colour_values_can_be_colors_or_hex_strings() -> void:
	var p: SkyProfile = SkyProfile.from_dict({"keyframes": [
		{"hour": 0.0, "fog_color": Color.RED}, {"hour": 12.0, "fog_color": "#0000ff"},
	]})
	assert_true((p.sample(0.0)["fog_color"] as Color).is_equal_approx(Color.RED), "Color values pass straight through")
	assert_true((p.sample(12.0)["fog_color"] as Color).is_equal_approx(Color.BLUE), "hex strings are parsed")
	assert_true((p.sample(6.0)["fog_color"] as Color).is_equal_approx(Color(0.5, 0.0, 0.5)), "the two blend")
