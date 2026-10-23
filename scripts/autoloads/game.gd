extends Node
## Run flow, death/respawn, clock. SaveGame is injectable (_inject) so tests run without autoloads.

enum State { BOOT, PLAYING, PAUSED, DEAD, MENU }

signal state_changed(old: State, new: State)
signal player_died()
signal respawned()
signal time_changed(hours: float)

const HOURS_PER_DAY := 24.0
const NIGHT_START := 20.0
const NIGHT_END := 6.0

var state: State = State.BOOT:
	set(value):
		if value == state:
			return
		var old: State = state
		state = value
		state_changed.emit(old, value)
var respawn_area: StringName = &"vale"
var respawn_point: Vector3 = Vector3.ZERO
var player_position: Vector3 = Vector3.ZERO
var time_of_day: float = 8.0:
	set(value):
		time_of_day = fposmod(value, HOURS_PER_DAY)
var playtime_seconds: float = 0.0

var _save: Node


func _ready() -> void:
	if _save == null:
		_inject(get_node_or_null("/root/SaveGame"))


func _inject(save: Node) -> void:
	_save = save


func _process(delta: float) -> void:
	if state == State.PLAYING:
		playtime_seconds += delta


func kill_player() -> void:
	if state != State.PLAYING:
		return
	state = State.DEAD
	player_died.emit()


func respawn() -> void:
	if state != State.DEAD:
		return
	player_position = respawn_point
	state = State.PLAYING
	respawned.emit()


func set_respawn(area: StringName, point: Vector3) -> void:
	respawn_area = area
	respawn_point = point
	if _save != null:
		_save.request_autosave()


func advance_time(delta_hours: float) -> void:
	time_of_day += delta_hours
	time_changed.emit(time_of_day)


func is_night() -> bool:
	return time_of_day < NIGHT_END or time_of_day >= NIGHT_START
