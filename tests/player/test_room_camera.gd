# tests/player/test_room_camera.gd
extends GutTest
## A room sets how close the camera's focus may come to the wall at the top of the screen: the haven
## lets it come close to its north wall, so the horseshoe arches there are seen whole; the vault keeps
## the rig's own margin.

const MAIN: PackedScene = preload("res://scenes/main.tscn")
## Where Álvar stands against the haven's north wall, in front of its west arch.
const AT_THE_ARCHES: Vector3 = Vector3(-3.6, 0, -5.4)


func test_the_haven_lets_the_focus_come_close_to_its_north_wall() -> void:
	var main: Main = Story.boot(self)
	await wait_physics_frames(3)
	assert_eq(main.room.room_id, &"haven")
	assert_almost_eq(main.rig.far_fraction, main.room.camera_far_fraction, 0.0001)
	var wall: float = main.room.floor_bounds().position.y
	var focus: Vector3 = main.rig.focus_for(AT_THE_ARCHES)
	assert_lt(focus.z - wall, 1.5, "the focus comes within 1.5 m of the north wall, at %.2f" % focus.z)
	assert_gt(focus.z - wall, 1.0, "but not so near that the dark above the wall fills the screen's top")
	Story.finish(main)


func test_the_vault_keeps_the_rigs_own_margin() -> void:
	var main: Main = add_child_autofree(MAIN.instantiate())
	await wait_physics_frames(3)
	var fresh: CameraRig = autofree(CameraRig.new())
	assert_almost_eq(main.rig.far_fraction, fresh.far_fraction, 0.0001)
