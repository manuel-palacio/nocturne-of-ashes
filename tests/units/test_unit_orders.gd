# tests/units/test_unit_orders.gd
extends GutTest

var arena: Arena
var alvar: Unit
var foe: Unit

func before_each() -> void:
	arena = Arena.new(self)
	alvar = arena.spawn(Arena.ALVAR, Vector3.ZERO)
	foe = arena.spawn(Arena.CRUSADER, Vector3(0, 0, 6))
	await wait_physics_frames(3)

func test_a_new_unit_has_no_order() -> void:
	assert_eq(alvar.current_order(), Unit.Order.NONE)

func test_a_move_order_shows_until_arrival() -> void:
	alvar.order_move(Vector3(3, 0, 0))
	assert_eq(alvar.current_order(), Unit.Order.MOVE)
	await wait_for_signal(alvar.arrived, 4.0)
	assert_eq(alvar.current_order(), Unit.Order.NONE)

func test_an_attack_order_shows_until_the_target_dies() -> void:
	alvar.order_attack(foe)
	assert_eq(alvar.current_order(), Unit.Order.ATTACK)
	await wait_for_signal(foe.died, 12.0)
	await wait_physics_frames(3)
	assert_eq(alvar.current_order(), Unit.Order.NONE)

func test_stop_clears_the_order() -> void:
	alvar.order_attack(foe)
	alvar.stop()
	assert_eq(alvar.current_order(), Unit.Order.NONE)
	assert_null(alvar.attack_target())

func test_every_unit_scene_has_a_mover() -> void:
	assert_not_null(alvar.get_node_or_null(^"Mover") as Mover)
	assert_not_null(foe.get_node_or_null(^"Mover") as Mover)
