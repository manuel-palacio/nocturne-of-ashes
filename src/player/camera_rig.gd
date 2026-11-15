class_name CameraRig
extends Node3D
## Follows `target` across the floor with a pitched camera that can be rotated and zoomed.

@export var pitch_degrees: float = 50.0
@export var distance: float = 12.0
@export var min_distance: float = 8.0
@export var max_distance: float = 18.0
@export var zoom_step: float = 1.0
## Radians per second while a rotate key is held.
@export var rotate_speed: float = 1.6
@export var follow_sharpness: float = 8.0

var target: Node3D


func _ready() -> void:
	_place_camera()


func _process(delta: float) -> void:
	if not is_instance_valid(target):
		return
	var weight: float = 1.0 - exp(-follow_sharpness * delta)
	global_position = global_position.lerp(target.global_position, weight)


func rotate_by(radians: float) -> void:
	rotation.y += radians


## Positive steps zoom out.
func zoom_by(steps: int) -> void:
	distance = clampf(distance + steps * zoom_step, min_distance, max_distance)
	_place_camera()


func snap_to_target() -> void:
	if is_instance_valid(target):
		global_position = target.global_position
	_place_camera()


func camera() -> Camera3D:
	return $Camera


## Places the camera `distance` back along the pitched arm, looking at the rig origin.
func _place_camera() -> void:
	var pitch: float = deg_to_rad(pitch_degrees)
	var offset := Vector3(0.0, sin(pitch), cos(pitch)) * distance
	camera().transform = Transform3D(Basis.looking_at(-offset, Vector3.UP), offset)
