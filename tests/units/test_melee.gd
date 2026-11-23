# tests/units/test_melee.gd
extends GutTest

const ROOM := preload("res://tests/fixtures/flat_room.tscn")
const ALVAR := preload("res://scenes/units/alvar.tscn")
const CRUSADER := preload("res://scenes/units/crusader.tscn")

var room: Node3D
var alvar: Unit
var foe: Unit

func before_each() -> void:
	room = add_child_autofree(ROOM.instantiate())
	alvar = ALVAR.instantiate()
	foe = CRUSADER.instantiate()
	foe.get_node("Brain").queue_free()  # a passive target for these tests
	room.add_child(alvar)
	room.add_child(foe)
	alvar.global_position = Vector3.ZERO
	foe.global_position = Vector3(0, 0, 1.2)
	await wait_physics_frames(3)

func test_a_hit_in_range_does_the_weapon_damage() -> void:
	assert_true(alvar.get_node("Melee").try_hit(foe))
	assert_eq(foe.stats.health, foe.stats.max_health - 15)

func test_no_second_hit_inside_the_cooldown() -> void:
	var melee: MeleeAttack = alvar.get_node("Melee")
	melee.try_hit(foe)
	assert_false(melee.try_hit(foe))
	assert_eq(foe.stats.health, foe.stats.max_health - 15)

func test_out_of_range_misses() -> void:
	foe.global_position = Vector3(0, 0, 3.0)
	assert_false(alvar.get_node("Melee").try_hit(foe))
	assert_eq(foe.stats.health, foe.stats.max_health)

func test_an_attack_order_closes_the_distance_and_kills() -> void:
	foe.global_position = Vector3(0, 0, 7.0)
	# Down to a few blows, so the fight is short: this is about the order, not the numbers.
	foe.stats.take_damage(foe.stats.max_health - 60)
	alvar.order_attack(foe)
	await wait_for_signal(foe.died, 10.0)
	assert_false(foe.is_alive())
	await wait_physics_frames(5)
	assert_null(alvar.attack_target())
	assert_false(alvar.is_moving())

func test_a_target_freed_mid_fight_ends_the_attack_without_error() -> void:
	watch_signals(alvar)
	alvar.order_attack(foe)
	await wait_physics_frames(5)
	foe.free()
	await wait_physics_frames(10)
	assert_null(alvar.attack_target())
	assert_signal_emitted(alvar, "attack_ended")

func test_orders_against_friends_and_the_dead_are_ignored() -> void:
	var friend: Unit = ALVAR.instantiate()
	room.add_child(friend)
	alvar.order_attack(friend)
	assert_null(alvar.attack_target())
	foe.stats.take_damage(999)
	alvar.order_attack(foe)
	assert_null(alvar.attack_target())

func test_a_move_order_breaks_off_the_attack() -> void:
	alvar.order_attack(foe)
	alvar.order_move(Vector3(-5, 0, 0))
	assert_null(alvar.attack_target())
