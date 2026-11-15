# tests/units/test_unit_movement.gd
extends GutTest

const ROOM := preload("res://tests/fixtures/flat_room.tscn")
const ALVAR := preload("res://scenes/units/alvar.tscn")

var room: Node3D
var unit: Unit

func before_each() -> void:
	room = add_child_autofree(ROOM.instantiate())
	unit = ALVAR.instantiate()
	room.add_child(unit)
	unit.global_position = Vector3.ZERO
	await wait_physics_frames(3)  # the navigation map needs a frame to sync

func _flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()

func test_walks_to_an_ordered_point() -> void:
	unit.order_move(Vector3(0, 0, 6))
	await wait_for_signal(unit.arrived, 4.0)
	assert_lt(_flat_distance(unit.global_position, Vector3(0, 0, 6)), 0.5)
	assert_false(unit.is_moving())

func test_walks_around_an_obstacle() -> void:
	unit.order_move(Vector3(8, 0, 0))
	await wait_for_signal(unit.arrived, 6.0)
	assert_lt(_flat_distance(unit.global_position, Vector3(8, 0, 0)), 0.5)

func test_a_point_off_the_floor_resolves_to_the_nearest_reachable_point() -> void:
	unit.order_move(Vector3(40, 0, 0))
	await wait_for_signal(unit.arrived, 6.0)
	assert_almost_eq(unit.global_position.x, 10.0, 1.0)
	assert_false(unit.is_moving())

func test_stop_halts_the_walk() -> void:
	unit.order_move(Vector3(0, 0, 9))
	await wait_physics_frames(10)
	unit.stop()
	var at := unit.global_position
	await wait_physics_frames(20)
	assert_lt(_flat_distance(unit.global_position, at), 0.05)

func test_a_dead_unit_ignores_orders_and_reports_death_once() -> void:
	watch_signals(unit)
	unit.stats.take_damage(999)
	unit.order_move(Vector3(0, 0, 6))
	await wait_physics_frames(20)
	assert_lt(_flat_distance(unit.global_position, Vector3.ZERO), 0.05)
	assert_false(unit.is_alive())
	assert_signal_emit_count(unit, "died", 1)

func test_instances_do_not_share_stats() -> void:
	var second: Unit = ALVAR.instantiate()
	room.add_child(second)
	unit.stats.take_damage(10)
	assert_eq(second.stats.health, 120)
