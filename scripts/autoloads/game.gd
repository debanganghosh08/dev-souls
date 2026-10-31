extends Node
## Run flow, death/respawn, clock. SaveGame is injectable (_inject) so tests run without autoloads.

enum State { BOOT, PLAYING, PAUSED, DEAD, MENU }

signal state_changed(old: State, new: State)
signal player_died()
signal respawned()
signal time_changed(hours: float)
## The journey is over: the Hearth was reached and one of the two endings happened. The value is a
## Hearth.Ending. EndingCard listens for this the way DeathScreen listens for player_died, so the Hearth
## never has to reach into the interface.
signal journey_ended(ending: int)

const HOURS_PER_DAY := 24.0
const NIGHT_START := 20.0
const NIGHT_END := 6.0

var state: State = State.BOOT:
	set(value):
		if value == state:
			return
		var old: State = state
		state = value
		# Returning to the title is the end of a run, and this autoload outlives the level, so the next run
		# must be allowed to reach its own ending.
		if value == State.MENU:
			_ended = false
		state_changed.emit(old, value)
var respawn_area: StringName = &"vale"
## Where death returns the player. NEVER leave this at the origin: the Vale has a terrain hole there
## for the Hearth chamber, and the owner found it the hard way -- drowned in the river, respawned at
## (0, 0, 0), fell through the world. A level sets this to its spawn as soon as it loads (see
## vale.gd), and a Hearth moves it on.
var respawn_point: Vector3 = Vector3.ZERO
var player_position: Vector3 = Vector3.ZERO
var time_of_day: float = 8.0:
	set(value):
		time_of_day = fposmod(value, HOURS_PER_DAY)
var playtime_seconds: float = 0.0

var _ended: bool = false
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


## Ends the run. Deliberately does not touch `state`: EndingCard takes the screen the way the pause menu
## does (PLAYING -> PAUSED, mouse freed) and Main leaves for the title when the card is dismissed, so no new
## state has to be threaded through every `match state` in the game. Fires at most once per run: two endings
## cannot happen, and a second Hearth use must not replay the card.
func end_journey(ending: int) -> void:
	if _ended or state != State.PLAYING:
		return
	_ended = true
	journey_ended.emit(ending)


func journey_is_over() -> bool:
	return _ended


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
