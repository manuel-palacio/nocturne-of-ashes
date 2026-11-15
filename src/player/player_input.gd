class_name PlayerInput
extends Node
## Turns mouse clicks and camera keys into orders for the player's unit and moves for the camera rig.

## Length of the click ray, in metres.
const _RAY_LENGTH: float = 100.0
## The click ray tests the "world" (1) and "units" (2) physics layers. It skips "walls" (3):
## the wall nearest the camera is not drawn, and its collider must not catch clicks meant for the floor.
const _RAY_MASK: int = 0b11

var unit: Unit
var rig: CameraRig
var enabled: bool = true


func _unhandled_input(event: InputEvent) -> void:
	var button := event as InputEventMouseButton
	if button == null or not button.pressed:
		return
	match button.button_index:
		MOUSE_BUTTON_LEFT:
			click_at(button.position)
		MOUSE_BUTTON_WHEEL_UP:
			rig.zoom_by(-1)
		MOUSE_BUTTON_WHEEL_DOWN:
			rig.zoom_by(1)


func _process(delta: float) -> void:
	if rig == null:
		return
	var turn: float = Input.get_action_strength(&"camera_right") - Input.get_action_strength(&"camera_left")
	if turn != 0.0:
		rig.rotate_by(turn * rig.rotate_speed * delta)


## Attacks a living hostile unit under the point, else walks to the ground under it.
func click_at(screen_position: Vector2) -> void:
	if not enabled or unit == null or not unit.is_alive():
		return
	var cam: Camera3D = rig.camera()
	var origin: Vector3 = cam.project_ray_origin(screen_position)
	var direction: Vector3 = cam.project_ray_normal(screen_position)
	var query := PhysicsRayQueryParameters3D.create(origin, origin + direction * _RAY_LENGTH, _RAY_MASK)
	var hit: Dictionary = cam.get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		var other := hit.collider as Unit
		if other != null and other.is_alive() and unit.is_hostile_to(other):
			unit.order_attack(other)
		else:
			unit.order_move(hit.position)
		return
	# Past the walls nothing is hit; the ground plane still gives a point to walk towards.
	var on_ground: Variant = Plane(Vector3.UP, 0.0).intersects_ray(origin, direction)
	if on_ground != null:
		unit.order_move(on_ground)
