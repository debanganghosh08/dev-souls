extends RefCounted
class_name PlayerFallTracker
## Tracks the highest point of an airborne arc and reports the drop on landing. Pure state, no node access,
## so PlayerController stays a thin owner of the rule "a drop past the threshold hurts, past the kill height kills".

const NO_LANDING := -1.0

var _airborne: bool = false
var _peak_y: float = 0.0


func reset() -> void:
	_airborne = false


# Returns the drop in metres on the frame the body lands; NO_LANDING while airborne or already grounded.
func update(on_floor: bool, y: float) -> float:
	if not on_floor:
		if not _airborne:
			_airborne = true
			_peak_y = y
		elif y > _peak_y:
			_peak_y = y
		return NO_LANDING
	if not _airborne:
		return NO_LANDING
	_airborne = false
	return _peak_y - y


# Damage grows linearly with every metre past the threshold; the hard kill above the killing height stays
# with the caller so a lethal drop never depends on these numbers.
static func damage_for(drop: float, threshold: float, per_metre: float) -> float:
	return maxf(drop - threshold, 0.0) * per_metre
