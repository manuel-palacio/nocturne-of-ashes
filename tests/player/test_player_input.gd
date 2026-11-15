# tests/player/test_player_input.gd
extends GutTest

const ROOM := preload("res://tests/fixtures/flat_room.tscn")
const ALVAR := preload("res://scenes/units/alvar.tscn")
const CRUSADER := preload("res://scenes/units/crusader.tscn")

var room: Node3D
var alvar: Unit
var foe: Unit
var rig: CameraRig
var input: PlayerInput

func before_each() -> void:
	room = add_child_autofree(ROOM.instantiate())
	alvar = ALVAR.instantiate()
	foe = CRUSADER.instantiate()
	foe.get_node("Brain").queue_free()
	room.add_child(alvar)
	room.add_child(foe)
	alvar.global_position = Vector3.ZERO
	foe.global_position = Vector3(0, 0, -4)
	rig = CameraRig.new()
	var cam := Camera3D.new()
	cam.name = "Camera"
	rig.add_child(cam)
	room.add_child(rig)
	rig.target = alvar
	rig.snap_to_target()
	cam.current = true
	input = PlayerInput.new()
	room.add_child(input)
	input.unit = alvar
	input.rig = rig
	await wait_physics_frames(3)

func _screen(world: Vector3) -> Vector2:
	return rig.camera().unproject_position(world)

func test_a_click_on_the_floor_sends_the_unit_there() -> void:
	input.click_at(_screen(Vector3(3, 0, 2)))
	await wait_for_signal(alvar.arrived, 4.0)
	assert_almost_eq(alvar.global_position.x, 3.0, 0.5)
	assert_almost_eq(alvar.global_position.z, 2.0, 0.5)

func test_a_click_on_an_enemy_orders_an_attack() -> void:
	input.click_at(_screen(foe.global_position + Vector3(0, 0.9, 0)))
	assert_eq(alvar.attack_target(), foe)

func test_a_click_on_the_sky_still_moves_along_the_ground() -> void:
	input.click_at(Vector2(640, 2))
	assert_true(alvar.is_moving())

func test_disabled_input_gives_no_orders() -> void:
	input.enabled = false
	input.click_at(_screen(Vector3(3, 0, 2)))
	assert_false(alvar.is_moving())

func test_a_dead_unit_takes_no_clicks() -> void:
	alvar.stats.take_damage(999)
	input.click_at(_screen(Vector3(3, 0, 2)))
	assert_false(alvar.is_moving())
