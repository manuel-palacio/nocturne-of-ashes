# tests/units/test_unit_navigation_setup.gd
extends GutTest
## How a unit copes with the navigation setup around it: map timing, navmesh height, blocked orders.

const ROOM := preload("res://tests/fixtures/flat_room.tscn")
const ALVAR := preload("res://scenes/units/alvar.tscn")

var room: Node3D
var unit: Unit

func before_each() -> void:
	room = add_child_autofree(ROOM.instantiate())
	unit = ALVAR.instantiate()
	room.add_child(unit)
	unit.global_position = Vector3.ZERO

func _flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()

func test_an_order_given_before_the_map_has_synced_is_carried_out() -> void:
	unit.order_move(Vector3(0, 0, 6))
	await wait_for_signal(unit.arrived, 4.0)
	assert_lt(_flat_distance(unit.global_position, Vector3(0, 0, 6)), 0.5)
	assert_false(unit.is_moving())

func test_arrives_whatever_the_height_between_its_feet_and_the_navmesh() -> void:
	await wait_physics_frames(3)
	unit.global_position = Vector3(0, 1, 0)
	unit.order_move(Vector3(0, 0, 6))
	await wait_for_signal(unit.arrived, 4.0)
	assert_lt(_flat_distance(unit.global_position, Vector3(0, 0, 6)), 0.5)
	assert_false(unit.is_moving())

func test_an_order_that_makes_no_progress_stops_with_a_warning() -> void:
	await wait_physics_frames(3)
	unit.move_speed = 0.0
	unit.order_move(Vector3(0, 0, 6))
	await wait_seconds(1.5)
	assert_false(unit.is_moving())
	assert_push_warning("no progress")
