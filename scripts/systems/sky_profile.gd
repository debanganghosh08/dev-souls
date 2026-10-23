class_name SkyProfile
extends RefCounted
## An ordered list of hour-keyed palette keyframes and a wrap-around sampler. Pure data: no nodes,
## no singletons, so tests build it directly. The palettes themselves live in data/daynight.json.

const HOURS_PER_DAY := 24.0
const COLOR_KEYS: Array[String] = ["sun_color", "sky_top", "sky_horizon", "ground_color", "fog_color"]
const FLOAT_KEYS: Array[String] = ["fog_density", "sun_energy", "ambient_energy", "star_alpha"]
## Flat grey dusk used when a file is missing or a keyframe omits a key: never pretty, never a crash.
const DEFAULTS: Dictionary = {
	"sun_color": Color(0.8, 0.78, 0.74),
	"sky_top": Color(0.28, 0.32, 0.38),
	"sky_horizon": Color(0.5, 0.5, 0.52),
	"ground_color": Color(0.2, 0.2, 0.22),
	"fog_color": Color(0.5, 0.5, 0.52),
	"fog_density": 0.02,
	"sun_energy": 0.6,
	"ambient_energy": 0.4,
	"star_alpha": 0.0,
}

var _keyframes: Array[Dictionary] = []


static func from_dict(data: Dictionary) -> SkyProfile:
	var profile: SkyProfile = SkyProfile.new()
	var raw: Variant = data.get("keyframes", [])
	if raw is Array:
		for entry: Variant in raw:
			if entry is Dictionary:
				profile.add_keyframe(float(entry.get("hour", 0.0)), entry)
	return profile


func add_keyframe(hour: float, values: Dictionary) -> void:
	var frame: Dictionary = {"hour": fposmod(hour, HOURS_PER_DAY)}
	for key: String in COLOR_KEYS:
		frame[key] = _parse_color(values.get(key), DEFAULTS[key])
	for key: String in FLOAT_KEYS:
		frame[key] = _parse_float(values.get(key), DEFAULTS[key])
	_keyframes.append(frame)
	_keyframes.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["hour"] < b["hour"])


func keyframe_count() -> int:
	return _keyframes.size()


func keyframe_hours() -> Array[float]:
	var out: Array[float] = []
	for frame: Dictionary in _keyframes:
		out.append(frame["hour"])
	return out


func sample(hour: float) -> Dictionary:
	var n: int = _keyframes.size()
	if n == 0:
		return DEFAULTS.duplicate()
	if n == 1:
		return _values_of(_keyframes[0])
	var h: float = fposmod(hour, HOURS_PER_DAY)
	var first: Dictionary = _keyframes[0]
	var last: Dictionary = _keyframes[n - 1]
	var a: Dictionary
	var b: Dictionary
	var t: float
	if h < first["hour"] or h >= last["hour"]:
		# Midnight wrap: the segment from the last keyframe to the first one crosses 24 -> 0, so its span
		# is measured the short way round the clock, not back across the whole day. Between 22:00 and 02:00,
		# 00:00 is the halfway point.
		a = last
		b = first
		var span: float = fposmod(first["hour"] - last["hour"], HOURS_PER_DAY)
		t = 0.0 if span <= 0.0 else fposmod(h - last["hour"], HOURS_PER_DAY) / span
	else:
		var i: int = 0
		while i < n - 2 and h >= _keyframes[i + 1]["hour"]:
			i += 1
		a = _keyframes[i]
		b = _keyframes[i + 1]
		var span: float = b["hour"] - a["hour"]
		t = 0.0 if span <= 0.0 else (h - a["hour"]) / span
	return _blend(a, b, clampf(t, 0.0, 1.0))


func _blend(a: Dictionary, b: Dictionary, t: float) -> Dictionary:
	var out: Dictionary = {}
	for key: String in COLOR_KEYS:
		out[key] = (a[key] as Color).lerp(b[key], t)
	for key: String in FLOAT_KEYS:
		out[key] = lerpf(a[key], b[key], t)
	return out


func _values_of(frame: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for key: String in COLOR_KEYS:
		out[key] = frame[key]
	for key: String in FLOAT_KEYS:
		out[key] = frame[key]
	return out


static func _parse_color(value: Variant, fallback: Color) -> Color:
	if value is Color:
		return value
	if value is String and Color.html_is_valid(value):
		return Color.html(value)
	return fallback


static func _parse_float(value: Variant, fallback: float) -> float:
	if value is float or value is int:
		return float(value)
	return fallback
