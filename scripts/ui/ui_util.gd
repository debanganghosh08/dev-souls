extends RefCounted
class_name UiUtil
## Small helpers shared by the UI scenes: headless-safe mouse capture, key labels and spaced title fonts.

const BONE := Color(0.85, 0.8, 0.7, 1.0)
const GOLD := Color(0.78, 0.65, 0.38, 1.0)
const ASH := Color(0.5, 0.47, 0.42, 1.0)


static func is_headless() -> bool:
	return DisplayServer.get_name() == "headless" or not DisplayServer.window_can_draw()


## Headless runs have no window to capture the mouse in, so the write is skipped there.
static func set_mouse_captured(captured: bool) -> void:
	if is_headless():
		return
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if captured else Input.MOUSE_MODE_VISIBLE


## "E" for the interact action, or the fallback when the action has no key bound.
static func action_key_label(action: StringName, fallback: String = "?") -> String:
	if not InputMap.has_action(action):
		return fallback
	for event: InputEvent in InputMap.action_get_events(action):
		var key: InputEventKey = event as InputEventKey
		if key == null:
			continue
		var code: Key = key.keycode
		if key.physical_keycode != KEY_NONE:
			# Physical keys name the US-layout position; map to the player's real layout when a window exists.
			code = key.physical_keycode if is_headless() \
				else DisplayServer.keyboard_get_keycode_from_physical(key.physical_keycode)
		var label: String = OS.get_keycode_string(code)
		if label != "":
			return label
	return fallback


## The default font with letter spacing; Godot has no serif bundled and no fonts are licensed yet.
static func spaced_font(glyph_spacing: int) -> FontVariation:
	var font := FontVariation.new()
	font.base_font = ThemeDB.fallback_font
	font.spacing_glyph = glyph_spacing
	return font
