# tests/player/test_picker.gd
extends GutTest

var arena: Arena
var alvar: Unit
var foe: Unit
var cam: Camera3D

func before_each() -> void:
	arena = Arena.new(self)
	alvar = arena.spawn(Arena.ALVAR, Vector3.ZERO)
	foe = arena.spawn(Arena.CRUSADER, Vector3(0, 0, -4))
	var rig := CameraRig.new()
	cam = Camera3D.new()
	cam.name = "Camera"
	rig.add_child(cam)
	arena.room.add_child(rig)
	rig.target = alvar
	rig.snap_to_target()
	cam.current = true
	await wait_physics_frames(3)

func _screen(world: Vector3) -> Vector2:
	return cam.unproject_position(world)

func test_finds_the_unit_under_the_point() -> void:
	assert_eq(Picker.unit_at(cam, _screen(foe.global_position + Vector3(0, 0.9, 0))), foe)

func test_finds_no_unit_over_bare_floor() -> void:
	assert_null(Picker.unit_at(cam, _screen(Vector3(4, 0, 2))))

func test_a_fallen_unit_is_not_picked() -> void:
	foe.take_hit(Arena.LETHAL)
	await wait_physics_frames(3)
	assert_null(Picker.unit_at(cam, _screen(foe.global_position + Vector3(0, 0.3, 0))))

func test_ground_under_a_unit_is_still_ground() -> void:
	var point: Vector3 = Picker.ground_at(cam, _screen(foe.global_position + Vector3(0, 0.9, 0)))
	assert_almost_eq(point.y, 0.0, 0.05)

func test_ground_beyond_the_floor_falls_back_to_the_plane() -> void:
	var point: Variant = Picker.ground_at(cam, Vector2(640, 2))
	assert_not_null(point)
	assert_almost_eq((point as Vector3).y, 0.0, 0.01)
