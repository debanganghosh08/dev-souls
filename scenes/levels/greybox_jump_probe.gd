extends Node
class_name GreyboxJumpProbe
## Headless jump probe for greybox.tscn (user arg --probe-jump, run by tests/test_player.gd). Drives the real
## PlayerController through its input actions, one scenario after another, and prints one PROBE line each:
## a standing jump (apex, stamina, health, fall damage), a jump refused on short stamina, no double jump, the
## press buffer (honoured just before landing, expired from the apex), coyote time off the 2 m ledge (honoured
## at 3 frames, refused at 10), the three jump targets (0.6 m and 0.9 m blocks reached, the 2 m ledge not) and
## a walking control that proves the 0.6 m block cannot be stepped onto. Observed, not explained: the
## controller sees an action pressed here on the following physics frame and its release the frame after, so
## a press made on one frame and released on the next lands as a single one-frame press. Readings that depend
## on the jump having happened are therefore taken from the controller's signals, not on a fixed frame.

const SETTLE_FRAMES := 10
const FRAME_CAP := 300
const WAIT_FRAMES := 45
const WALK_FRAMES := 90
const FLAT_POINT := Vector3(-13.0, 0.0, 2.0)
const LEDGE_TOP_POINT := Vector3(-10.0, 2.0, -4.6)
const LANE_START_Z := -0.5
const BLOCK_EDGE_Z := -4.0
# Metres before a block's near edge at which the jump is pressed: at walk speed the body's axis crosses the
# edge about 0.31 s after take-off, at the apex.
const JUMP_LEAD := 1.3
const DOUBLE_PRESS_FRAME := 8
const BUFFER_PRESS_HEIGHT := 0.4
const COYOTE_PRESS_FRAME := 3
const LATE_PRESS_FRAME := 10
const LANES: Array[Dictionary] = [
	{"name": "jump_block_low", "x": -13.0, "height": 0.6, "jump": true},
	{"name": "jump_block_high", "x": -16.0, "height": 0.9, "jump": true},
	{"name": "jump_ledge_tall", "x": -10.0, "height": 2.0, "jump": true},
	{"name": "jump_walk_low", "x": -13.0, "height": 0.6, "jump": false},
]

var player: PlayerController

var _scenarios: Array[Callable] = []
var _index: int = 0
var _frames: int = 0
var _jumps: int = 0
var _falls: int = 0
var _last_drop: float = 0.0
var _peak: float = -INF
var _jumps_at_start: int = 0
var _falls_at_start: int = 0
var _pressed_action: StringName = &""
var _stamina_before: float = 0.0
var _stamina_after: float = 0.0
var _off_floor_frames: int = 0
var _second_pressed: bool = false
var _press_frame: int = 0
var _press_y: float = 0.0


func _ready() -> void:
	player.jumped.connect(_on_jumped)
	player.landed.connect(_on_landed)
	player.took_fall_damage.connect(_on_fall_damage)
	_scenarios = [_flat, _refused, _double, _buffer, _apex_press, _coyote, _late_press]
	for lane: Dictionary in LANES:
		_scenarios.append(_lane_run.bind(lane))


func _physics_process(_delta: float) -> void:
	if _pressed_action != &"":
		Input.action_release(_pressed_action)
		_pressed_action = &""
	if _index >= _scenarios.size():
		get_tree().quit()
		return
	if _frames >= 1:
		_peak = maxf(_peak, player.global_position.y)
	var done: bool = _scenarios[_index].call(_frames > FRAME_CAP)
	_frames += 1
	if done:
		_index += 1
		_frames = 0
		_peak = -INF
		_jumps_at_start = _jumps
		_falls_at_start = _falls
		_off_floor_frames = 0
		_second_pressed = false


func _flat(timed_out: bool) -> bool:
	if _frames == 0:
		_stand(FLAT_POINT)
		return false
	if _frames == SETTLE_FRAMES:
		player.get_stamina().reset()
		_stamina_before = player.get_stamina().current
		_press(&"jump")
		return false
	if not timed_out and not (_frames > SETTLE_FRAMES + 1 and _jumped() and player.is_on_floor()):
		return false
	print("PROBE jump_flat jumped=%s peak=%.3f target=%.2f land_y=%.3f floor=%s health=%.1f falls=%d stamina_before=%.1f stamina_after=%.1f cost=%.1f frames=%d" % [
		_jumped(), _peak, player.jump_height, player.global_position.y, player.is_on_floor(),
		player.health_fraction() * player.max_health, _falls - _falls_at_start,
		_stamina_before, _stamina_after, player.jump_cost, _frames,
	])
	return true


func _refused(timed_out: bool) -> bool:
	if _frames == 0:
		_stand(FLAT_POINT)
		return false
	if _frames == SETTLE_FRAMES:
		# Half the cost: regen adds 0.5 a frame, so a pool one short would reach the cost before the press lands.
		player.get_stamina().current = player.jump_cost * 0.5
		_stamina_before = player.get_stamina().current
		_press(&"jump")
		return false
	if not timed_out and _frames < SETTLE_FRAMES + WAIT_FRAMES:
		return false
	print("PROBE jump_refused stamina_at_press=%.1f cost=%.1f jumped=%s peak=%.3f" % [
		_stamina_before, player.jump_cost, _jumped(), _peak,
	])
	return true


func _double(timed_out: bool) -> bool:
	if _frames == 0:
		_stand(FLAT_POINT)
		return false
	if _frames == SETTLE_FRAMES:
		player.get_stamina().reset()
		_press(&"jump")
		return false
	if _frames == SETTLE_FRAMES + DOUBLE_PRESS_FRAME:
		_press_y = player.global_position.y
		_press(&"jump")
		return false
	if not timed_out and not (_frames > SETTLE_FRAMES + DOUBLE_PRESS_FRAME + 1 and player.is_on_floor()):
		return false
	print("PROBE jump_double jumps=%d second_press_y=%.3f rising=%s peak=%.3f" % [
		_jumps - _jumps_at_start, _press_y, _press_y > 0.3, _peak,
	])
	return true


func _buffer(timed_out: bool) -> bool:
	return _second_press_while_falling("jump_buffer", timed_out, BUFFER_PRESS_HEIGHT)


func _apex_press(timed_out: bool) -> bool:
	return _second_press_while_falling("jump_apex_press", timed_out, INF)


# One jump, then a second press on the way down once below `height`: the buffer honours it only when the
# landing comes within jump_buffer_time of the press.
func _second_press_while_falling(label: String, timed_out: bool, height: float) -> bool:
	if _frames == 0:
		_stand(FLAT_POINT)
		return false
	if _frames == SETTLE_FRAMES:
		player.get_stamina().reset()
		_press(&"jump")
		return false
	if not _second_pressed and _frames > SETTLE_FRAMES + 1 and player.velocity.y < 0.0 and player.global_position.y < height:
		_second_pressed = true
		_press_frame = _frames
		_press_y = player.global_position.y
		_press(&"jump")
		return false
	if not timed_out and not (_second_pressed and _frames >= _press_frame + WAIT_FRAMES):
		return false
	print("PROBE %s jumps=%d press_y=%.3f peak=%.3f floor=%s" % [
		label, _jumps - _jumps_at_start, _press_y, _peak, player.is_on_floor(),
	])
	return true


func _coyote(timed_out: bool) -> bool:
	return _press_after_walking_off("jump_coyote", timed_out, COYOTE_PRESS_FRAME)


func _late_press(timed_out: bool) -> bool:
	return _press_after_walking_off("jump_late_press", timed_out, LATE_PRESS_FRAME)


# Walks off the 2 m ledge's far edge and presses jump a fixed number of frames after the floor is gone.
func _press_after_walking_off(label: String, timed_out: bool, press_frame: int) -> bool:
	if _frames == 0:
		_stand(LEDGE_TOP_POINT)
		player.get_stamina().reset()
		Input.action_press(&"move_forward")
		return false
	if not player.is_on_floor():
		_off_floor_frames += 1
	if not _second_pressed and _off_floor_frames == press_frame:
		_second_pressed = true
		_press_frame = _frames
		_press_y = player.global_position.y
		_press(&"jump")
		return false
	if not timed_out and not (_second_pressed and _frames > _press_frame + 1 and player.is_on_floor()):
		return false
	Input.action_release(&"move_forward")
	print("PROBE %s press_frame_off_floor=%d press_y=%.3f jumped=%s peak=%.3f land_y=%.3f drop=%.2f falls=%d" % [
		label, press_frame, _press_y, _jumped(), _peak, player.global_position.y, _last_drop, _falls - _falls_at_start,
	])
	return true


# Walks a lane straight at a block and jumps JUMP_LEAD metres before its edge (or never, for the control).
func _lane_run(timed_out: bool, lane: Dictionary) -> bool:
	var wants_jump: bool = bool(lane["jump"])
	if _frames == 0:
		_stand(Vector3(float(lane["x"]), 0.0, LANE_START_Z))
		player.get_stamina().reset()
		Input.action_press(&"move_forward")
		return false
	if wants_jump and not _second_pressed and player.global_position.z <= BLOCK_EDGE_Z + JUMP_LEAD:
		_second_pressed = true
		_press_frame = _frames
		_press(&"jump")
		return false
	var finished: bool
	if wants_jump:
		finished = _second_pressed and _frames > _press_frame + 1 and _jumped() and player.is_on_floor()
	else:
		finished = _frames >= WALK_FRAMES
	if not timed_out and not finished:
		return false
	Input.action_release(&"move_forward")
	var height: float = float(lane["height"])
	var y: float = player.global_position.y
	print("PROBE %s height=%.2f jumped=%s land_y=%.3f peak=%.3f reached=%s z=%.2f frames=%d" % [
		lane["name"], height, _jumped(), y, _peak, y > height - 0.1 and player.is_on_floor(), player.global_position.z, _frames,
	])
	return true


func _stand(point: Vector3) -> void:
	player.global_position = point
	player.velocity = Vector3.ZERO
	player.rotation.y = 0.0
	var rig: CameraRig = player.get_camera_rig() as CameraRig
	if rig != null:
		rig.snap_to_target()


func _press(action: StringName) -> void:
	Input.action_press(action)
	_pressed_action = action


func _jumped() -> bool:
	return _jumps > _jumps_at_start


func _on_jumped() -> void:
	_jumps += 1
	# Emitted right after the stamina is paid, inside the controller's own frame.
	_stamina_after = player.get_stamina().current


func _on_landed(drop: float) -> void:
	_last_drop = drop


func _on_fall_damage(_drop: float) -> void:
	_falls += 1
