extends RefCounted
class_name PlayerStepUp
## CharacterBody3D cannot climb steps: a 0.25 m stair tread reads as a wall, so the player sticks. When the
## way ahead is blocked at foot level but clear one step higher, lift the body onto the step and settle it.
## Teleporting is safe here only because test_move proved the raised volume is free.


# Returns true when the body was lifted onto a step this frame.
static func try_step_up(body: CharacterBody3D, wish_dir: Vector3, max_step_height: float, probe_distance: float) -> bool:
	if not body.is_on_floor() or not body.is_on_wall():
		return false
	var flat: Vector3 = Vector3(wish_dir.x, 0.0, wish_dir.z)
	if flat.length_squared() < 0.0001:
		return false
	var ahead: Vector3 = flat.normalized() * probe_distance
	if not body.test_move(body.global_transform, ahead):
		return false
	var lifted: Transform3D = body.global_transform.translated(Vector3.UP * max_step_height)
	if body.test_move(lifted, ahead):
		return false
	body.global_transform = lifted.translated(ahead)
	body.move_and_collide(Vector3.DOWN * (max_step_height + 0.05))
	return true
