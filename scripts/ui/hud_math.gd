extends RefCounted
class_name HudMath
## The HUD's gauge arithmetic, kept static and tree-free so tests can pin the numbers. hud.gd only wires
## signals, nodes and tweens around these.

const LOW_HEALTH_THRESHOLD := 0.3
const LOW_HEALTH_CYCLE_SEC := 1.2
const LOW_HEALTH_DIM := 0.55
const VIGNETTE_MIN := 0.15
const VIGNETTE_MAX := 0.8
const VIGNETTE_GAIN := 2.0


## Hit-vignette strength for `amount` taken from a pool of `max_health`: proportional to the fraction lost,
## floored so a scratch still registers and capped so a near-kill never whites the screen out.
static func vignette_strength(amount: float, max_health: float) -> float:
	if max_health <= 0.0 or amount <= 0.0:
		return 0.0
	return clampf(amount / max_health * VIGNETTE_GAIN, VIGNETTE_MIN, VIGNETTE_MAX)


static func is_low(fraction: float, threshold: float = LOW_HEALTH_THRESHOLD) -> bool:
	return fraction < threshold


## Alpha of the health fill while low: a slow sine between 1.0 and LOW_HEALTH_DIM, one cycle per `cycle_sec`.
static func low_health_pulse(time_sec: float, cycle_sec: float = LOW_HEALTH_CYCLE_SEC) -> float:
	if cycle_sec <= 0.0:
		return 1.0
	var wave: float = 0.5 + 0.5 * sin(time_sec * TAU / cycle_sec)
	return lerpf(LOW_HEALTH_DIM, 1.0, wave)


## Pixel width of a bar fill for `fraction` of a trough `width` pixels wide.
static func fill_width(fraction: float, width: float) -> float:
	return clampf(fraction, 0.0, 1.0) * maxf(width, 0.0)


## Where the ghost trail sits the instant health changes: it never leads the real bar upward (a heal snaps
## it up), it only lingers above a drop so the lost slice shows before it catches up.
static func ghost_hold(ghost: float, fraction: float) -> float:
	return maxf(ghost, fraction)
