class_name PlayerInput
extends Node
## Turns mouse clicks and keys into orders for the controlled unit, selection requests, and moves for
## the camera rig. It never calls `Main`; selection goes out through its signals.

## A click landed on a living friend of the controlled unit.
signal select_requested(unit: Unit)
## The `select_next` action was pressed.
signal select_next_requested

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
	# Polled rather than read from events, so presses made with Input.action_press count too.
	if enabled and Input.is_action_just_pressed(&"select_next"):
		select_next_requested.emit()
	if rig == null:
		return
	var turn: float = Input.get_action_strength(&"camera_right") - Input.get_action_strength(&"camera_left")
	if turn != 0.0:
		rig.rotate_by(turn * rig.rotate_speed * delta)


## Asks to select a living friend under the point, attacks a living hostile there, else walks to the
## ground under it. A click on the controlled unit itself does nothing.
func click_at(screen_position: Vector2) -> void:
	if not enabled or unit == null or not unit.is_alive():
		return
	var cam: Camera3D = rig.camera()
	var other: Unit = Picker.unit_at(cam, screen_position)
	if other == unit:
		return
	if other != null and other.is_alive():
		if unit.is_hostile_to(other):
			unit.order_attack(other)
		else:
			select_requested.emit(other)
		return
	var on_ground: Variant = Picker.ground_at(cam, screen_position)
	if on_ground != null:
		unit.order_move(on_ground)
