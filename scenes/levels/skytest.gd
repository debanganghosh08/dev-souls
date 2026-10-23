extends Node3D
## Day/night inspection level: a floor, boxes and a tall pillar under scenes/environment/sky.tscn, with a
## readout. Keys: hold T to fast-forward, H jumps +1 h, P cycles the area palette, Esc quits.
## With the user arg `--probe` (used by tests/test_daynight.gd) it steps the clock through the day,
## prints machine-readable PROBE lines and quits. Launch by path; greybox stays the main scene.

const FAST_MINUTES_PER_DAY := 0.5
const PROBE_HOURS: Array[float] = [0.0, 3.0, 6.0, 9.0, 12.0, 15.0, 18.0, 20.0, 22.0]
const PROBE_AREAS: Array[StringName] = [&"vale", &"wood", &"barrens"]
const READOUT := "hour  %05.2f   night %s\narea  %s   fog %.3f\nsun_energy %.2f   sun_up %s   ambient %.2f\n\nT hold: fast-forward   H: +1 hour   P: cycle area   Esc: quit"

@onready var _sky: DayNightCycle = %Sky
@onready var _label: Label = %DebugLabel

var _game: Node
var _normal_minutes_per_day: float = 20.0
var _probe: bool = false
var _probe_step: int = 0


func _ready() -> void:
	_game = get_node_or_null(^"/root/Game")
	_normal_minutes_per_day = _sky.minutes_per_day
	if _game != null:
		_game.state = _game.State.PLAYING
	_probe = OS.get_cmdline_user_args().has("--probe")
	if _probe:
		_sky.paused = true


func _process(_delta: float) -> void:
	if _game == null:
		return
	if _probe:
		_probe_frame()
		return
	_sky.minutes_per_day = FAST_MINUTES_PER_DAY if Input.is_key_pressed(KEY_T) else _normal_minutes_per_day
	var c: Dictionary = _sky.current()
	_label.text = READOUT % [
		_game.time_of_day,
		"yes" if _game.is_night() else "no",
		_sky.area,
		float(c.get("fog_density", 0.0)),
		float(c.get("sun_energy", 0.0)),
		"yes" if _sky.sun_is_up() else "no",
		float(c.get("ambient_energy", 0.0)),
	]


func _unhandled_input(event: InputEvent) -> void:
	if _game == null or not (event is InputEventKey) or not event.is_pressed() or event.is_echo():
		return
	var key: InputEventKey = event as InputEventKey
	match key.keycode:
		KEY_H:
			_game.advance_time(1.0)
		KEY_P:
			_cycle_area()
		KEY_ESCAPE:
			get_tree().quit()


func _cycle_area() -> void:
	var ids: Array[StringName] = _sky.area_ids()
	if ids.is_empty():
		return
	var i: int = ids.find(_sky.area)
	_sky.set_area(ids[(i + 1) % ids.size()])


# One probe line per frame keeps the loop alive so the engine and Game.time_changed behave as in play.
func _probe_frame() -> void:
	if _probe_step < PROBE_HOURS.size():
		_jump_to(PROBE_HOURS[_probe_step])
		var c: Dictionary = _sky.current()
		print("PROBE hour=%.2f night=%s fog=%.4f sun_energy=%.3f sun_up=%s ambient=%.3f area=%s" % [
			_game.time_of_day, _game.is_night(), float(c["fog_density"]), float(c["sun_energy"]),
			_sky.sun_is_up(), float(c["ambient_energy"]), _sky.area,
		])
	elif _probe_step < PROBE_HOURS.size() + PROBE_AREAS.size():
		var id: StringName = PROBE_AREAS[_probe_step - PROBE_HOURS.size()]
		_jump_to(12.0)
		_sky.set_area(id)
		var c: Dictionary = _sky.current()
		print("PROBE area id=%s hour=%.2f fog=%.4f sun_energy=%.3f" % [
			id, _game.time_of_day, float(c["fog_density"]), float(c["sun_energy"]),
		])
	else:
		get_tree().quit()
	_probe_step += 1


func _jump_to(hours: float) -> void:
	_game.advance_time(fposmod(hours - _game.time_of_day, 24.0))
