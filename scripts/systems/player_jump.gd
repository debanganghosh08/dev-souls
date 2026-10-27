extends RefCounted
class_name PlayerJump
## The jump's two clocks, pure state like PlayerDodge: coyote time (the floor still counts for a moment after
## walking off it) and a press buffer (a press just before landing fires on the landing frame). A press is
## consumed by the first frame that could jump, whether or not the jump then happens, so a refused press
## never lingers and fires later. Launching clears the coyote clock, which is what rules out a double jump.

var coyote_left: float = 0.0
var buffer_left: float = 0.0


func reset() -> void:
	coyote_left = 0.0
	buffer_left = 0.0


# Once per physics frame, before take(): `pressed` is this frame's fresh press.
func update(on_floor: bool, pressed: bool, delta: float, coyote_time: float, buffer_time: float) -> void:
	coyote_left = coyote_time if on_floor else maxf(coyote_left - delta, 0.0)
	buffer_left = buffer_time if pressed else maxf(buffer_left - delta, 0.0)


# True once when a live press meets a floor (or its coyote grace); both clocks are spent by it. A press with
# no floor under it stays buffered until its time runs out.
func take() -> bool:
	if buffer_left <= 0.0 or coyote_left <= 0.0:
		return false
	buffer_left = 0.0
	coyote_left = 0.0
	return true


func can_jump() -> bool:
	return coyote_left > 0.0


func wants_jump() -> bool:
	return buffer_left > 0.0


# Take-off speed that peaks at `height` under constant gravity: v = sqrt(2 g h).
static func launch_speed(gravity: float, height: float) -> float:
	return sqrt(2.0 * maxf(gravity, 0.0) * maxf(height, 0.0))


# The apex a take-off speed reaches under constant gravity: h = v^2 / (2 g).
static func apex_height(launch: float, gravity: float) -> float:
	if gravity <= 0.0:
		return 0.0
	return launch * launch / (2.0 * gravity)
