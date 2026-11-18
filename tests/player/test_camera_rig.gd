# tests/player/test_camera_rig.gd
extends GutTest

var rig: CameraRig
var target: Node3D

func before_each() -> void:
	target = add_child_autofree(Node3D.new())
	rig = CameraRig.new()
	rig.add_child(Camera3D.new())
	rig.get_child(0).name = "Camera"
	add_child_autofree(rig)
	rig.target = target
	rig.snap_to_target()

func test_camera_sits_at_the_set_distance_and_pitch() -> void:
	var offset := rig.camera().global_position - rig.global_position
	assert_almost_eq(offset.length(), 12.0, 0.01)
	assert_almost_eq(rad_to_deg(asin(offset.y / offset.length())), 50.0, 0.1)

func test_zoom_is_clamped() -> void:
	rig.zoom_by(50)
	assert_almost_eq(rig.distance, 18.0, 0.001)
	rig.zoom_by(-50)
	assert_almost_eq(rig.distance, 8.0, 0.001)

func test_rotation_keeps_the_distance() -> void:
	rig.rotate_by(PI / 2)
	var offset := rig.camera().global_position - rig.global_position
	assert_almost_eq(offset.length(), 12.0, 0.01)
	assert_almost_eq(rig.rotation.y, PI / 2, 0.001)

func test_snap_follows_the_target() -> void:
	target.global_position = Vector3(7, 0, -3)
	rig.snap_to_target()
	assert_almost_eq(rig.global_position, Vector3(7, 0, -3), Vector3.ONE * 0.001)

## The four margins: to the walls at -x, +x, -z and +z.
func _margins() -> Array[float]:
	return [rig.margin_toward(Vector2.LEFT), rig.margin_toward(Vector2.RIGHT), rig.margin_toward(Vector2.UP), rig.margin_toward(Vector2.DOWN)]

func _inside(floor_rect: Rect2, at: Vector3) -> bool:
	var m: Array[float] = _margins()
	var inner := Rect2(floor_rect.position + Vector2(m[0], m[2]), floor_rect.size - Vector2(m[0] + m[1], m[2] + m[3]))
	return inner.grow(0.001).has_point(Vector2(at.x, at.z))

func test_at_a_room_corner_the_focus_stays_inside_the_room() -> void:
	rig.camera().fov = 25.0
	var floor_rect := Rect2(-12, -8, 24, 16)
	rig.set_bounds(floor_rect)
	for corner: Vector3 in [Vector3(-12, 0, -8), Vector3(12, 0, 8), Vector3(-15, 0, 9)]:
		rig.rotate_by(PI / 3)
		target.global_position = corner
		rig.snap_to_target()
		assert_gt(_margins().min(), 0.5, "the focus keeps away from the walls")
		assert_true(_inside(floor_rect, rig.global_position), "focus %s for a target at %s" % [rig.global_position, corner])
		# It also stays there while following.
		await wait_process_frames(10)
		assert_true(_inside(floor_rect, rig.global_position), "following, focus %s for a target at %s" % [rig.global_position, corner])

func test_in_the_middle_of_a_room_the_focus_is_the_target() -> void:
	rig.camera().fov = 25.0
	rig.set_bounds(Rect2(-12, -8, 24, 16))
	target.global_position = Vector3(1.5, 0, -2)
	for turn: int in 4:
		rig.rotate_by(PI / 2)
		rig.snap_to_target()
		assert_almost_eq(rig.global_position, target.global_position, Vector3.ONE * 0.001)

func test_the_margins_follow_the_view_as_it_turns_and_zooms() -> void:
	# Unturned the camera looks toward -z: the wall at -z is ahead, the one at +z behind it.
	var unturned: Array[float] = _margins()
	assert_almost_eq(unturned[0], unturned[1], 0.001, "the side walls alike")
	assert_gt(unturned[0], unturned[3], "the screen is wider than it is deep")
	assert_gt(unturned[3], unturned[2], "the wall ahead is held less far off than the one behind")
	rig.rotate_by(PI / 2)
	var turned: Array[float] = _margins()
	assert_almost_eq(turned[2], unturned[0], 0.001, "a quarter turn makes -z a side wall")
	assert_almost_eq(turned[0], unturned[2], 0.001, "and -x the wall ahead")
	rig.zoom_by(3)
	assert_gt(rig.margin_toward(Vector2.UP), turned[2], "zoomed out, the walls are held further off")
