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
