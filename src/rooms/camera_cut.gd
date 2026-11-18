class_name CameraCut
extends Node3D
## A run of a room's inner structure (an arcade) that stands between the camera and the floor when
## the camera looks at its outer side: then it is not drawn, as the wall nearest the camera is not, so
## the floor and the units behind it stay in sight. It still blocks what it blocks; only drawing stops.

## The side it shows away from the middle of the room, along the floor (y is ignored), in world space:
## rooms are placed without turning, so this is also the room's own direction.
@export var outward: Vector3 = Vector3.BACK
## It is cut while the camera looks within this many degrees of straight at its outer side.
@export var cut_within_degrees: float = 60.0


func _process(_delta: float) -> void:
	var camera: Camera3D = get_viewport().get_camera_3d()
	if camera != null:
		visible = not cuts_for(-camera.global_basis.z)


## Whether a camera looking along `look` sees its outer side squarely enough to cut it.
func cuts_for(look: Vector3) -> bool:
	var flat_look := Vector2(look.x, look.z)
	var flat_out := Vector2(outward.x, outward.z)
	if flat_look.is_zero_approx() or flat_out.is_zero_approx():
		return false
	return flat_look.normalized().dot(flat_out.normalized()) < -cos(deg_to_rad(cut_within_degrees))
