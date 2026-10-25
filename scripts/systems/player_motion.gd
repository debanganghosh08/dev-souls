extends RefCounted
class_name PlayerMotion
## Pure locomotion maths for PlayerController: camera-relative wish direction, accelerate-or-brake steering
## and the yaw a moving body should face. No node access, so every rule here is unit-testable.

const INPUT_DEADZONE_SQ := 0.0001


static func wish_direction(input: Vector2, camera_yaw: float) -> Vector3:
	return Vector3(input.x, 0.0, input.y).rotated(Vector3.UP, camera_yaw)


static func has_input(wish_dir: Vector3) -> bool:
	return wish_dir.length_squared() > INPUT_DEADZONE_SQ


# Accelerates toward the wished velocity while speeding up and brakes with friction otherwise, so letting go
# stops faster than setting off (the souls-like weight). Returns the new horizontal velocity.
static func steer(
	horizontal: Vector3,
	wish_dir: Vector3,
	target_speed: float,
	acceleration: float,
	friction: float,
	delta: float,
) -> Vector3:
	var moving: bool = has_input(wish_dir)
	var target: Vector3 = wish_dir * target_speed if moving else Vector3.ZERO
	var speeding_up: bool = moving and target.length_squared() >= horizontal.length_squared()
	var rate: float = acceleration if speeding_up else friction
	return horizontal.move_toward(target, rate * delta)


# -Z is forward for both the body and the model, so a body moving along -Z has yaw 0.
static func facing_yaw(horizontal: Vector3) -> float:
	return atan2(-horizontal.x, -horizontal.z)


# Eases the body's yaw toward its direction of travel; a near-stationary body keeps facing where it was.
static func turn_toward(current_yaw: float, horizontal: Vector3, rotation_speed: float, delta: float) -> float:
	if horizontal.length_squared() < 0.01:
		return current_yaw
	return lerp_angle(current_yaw, facing_yaw(horizontal), minf(rotation_speed * delta, 1.0))
