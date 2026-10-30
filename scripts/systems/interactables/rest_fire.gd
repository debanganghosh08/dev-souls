extends Interactable
class_name RestFire
## Sit at a fire and let the day move (W10-R). The owner asked for "a place or a fire campsite where I can
## actually rest and change day to night, night to day, evening and early morning". Pressing E moves the
## clock to the next stop in `stops` -- dawn, noon, dusk, midnight by default -- so four uses walk the whole
## day round, and the sky, the fog and every fire in the valley follow because they all read Game.time_of_day.
##
## Unlike most interactables this one never spends: a campfire you could only rest at once would be a trap.
## The arithmetic is next_stop(), a pure static function, because "what comes after 23:30" is exactly the
## kind of thing that is wrong at the wrap and right everywhere else.

const DEFAULT_STOPS: Array[float] = [6.0, 12.0, 18.0, 0.0]
const HOURS := 24.0

## Hours of the day this fire rests to, in the order they occur. Any list works; they are sorted on use.
@export var stops: Array[float] = DEFAULT_STOPS
## Smallest jump, so resting at 05:59 goes to noon rather than nudging one minute to dawn.
@export var min_jump_hours: float = 0.5

var _game_override: Node = null


func _ready() -> void:
	if prompt == "":
		prompt = UiText.text("rest_prompt")
	super()


## Tests hand in a stand-in for the Game autoload, as the melee and wardrobe tests do.
func _inject_game(game: Node) -> void:
	_game_override = game


## The next stop strictly after `now`, wrapping past midnight. Returns the hours to ADD, never negative and
## never zero: resting always moves the clock somewhere.
static func next_stop(now: float, at: Array, min_jump: float = 0.5) -> float:
	var hours: Array[float] = []
	for raw: Variant in at:
		if raw is float or raw is int:
			hours.append(fposmod(float(raw), HOURS))
	if hours.is_empty():
		return HOURS
	hours.sort()
	var from: float = fposmod(now, HOURS)
	var best: float = HOURS
	for h: float in hours:
		var ahead: float = fposmod(h - from, HOURS)
		if ahead < min_jump:
			# Already there, or as good as: that stop is a whole day away, not a moment.
			ahead += HOURS
		best = minf(best, ahead)
	return best


func hours_until_next() -> float:
	return next_stop(_clock(), stops, min_jump_hours)


func _on_interact(_who: Node) -> void:
	var game: Node = _game_override if _game_override != null else _game
	if game == null:
		return
	game.advance_time(next_stop(_clock(), stops, min_jump_hours))


func _clock() -> float:
	var game: Node = _game_override if _game_override != null else _game
	return float(game.time_of_day) if game != null else 0.0
