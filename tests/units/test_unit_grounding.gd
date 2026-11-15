# tests/units/test_unit_grounding.gd
extends GutTest
## Gravity keeps a unit's feet on the floor, wherever above it the unit starts.

const ROOM := preload("res://tests/fixtures/flat_room.tscn")
const ALVAR := preload("res://scenes/units/alvar.tscn")

## The top of the fixture floor.
const FLOOR_TOP: float = 0.0

var room: Node3D

func before_each() -> void:
	room = add_child_autofree(ROOM.instantiate())

func _unit_at(at: Vector3) -> Unit:
	var unit: Unit = ALVAR.instantiate()
	room.add_child(unit)
	unit.global_position = at
	return unit

func test_a_unit_placed_slightly_above_the_floor_comes_to_rest_on_it() -> void:
	var unit := _unit_at(Vector3(-3, 0.3, -3))
	await wait_seconds(1.0)
	assert_almost_eq(unit.global_position.y, FLOOR_TOP, 0.05)

func test_a_unit_placed_a_metre_up_comes_to_rest_on_the_floor() -> void:
	var unit := _unit_at(Vector3(-3, 1.0, 3))
	await wait_seconds(1.0)
	assert_almost_eq(unit.global_position.y, FLOOR_TOP, 0.05)

func test_a_walk_order_given_in_the_air_is_carried_out() -> void:
	var unit := _unit_at(Vector3(-3, 1.0, -3))
	await wait_physics_frames(3)
	assert_gt(unit.global_position.y, 0.5, "still in the air when ordered")
	unit.order_move(Vector3(-3, 0, 4))
	await wait_for_signal(unit.arrived, 5.0)
	assert_lt(Vector2(unit.global_position.x + 3, unit.global_position.z - 4).length(), 0.5)
	assert_almost_eq(unit.global_position.y, FLOOR_TOP, 0.05)
	assert_false(unit.is_moving())

func test_a_dead_unit_stays_on_the_floor() -> void:
	var unit := _unit_at(Vector3(-3, 0.3, 3))
	unit.stats.take_damage(999)
	await wait_seconds(1.0)
	assert_almost_eq(unit.global_position.y, FLOOR_TOP, 0.05)
