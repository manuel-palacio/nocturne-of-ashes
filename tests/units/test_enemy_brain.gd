# tests/units/test_enemy_brain.gd
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
	room.add_child(alvar)
	room.add_child(foe)
	alvar.global_position = Vector3(-8, 0, -8)
	foe.global_position = Vector3(8, 0, 8)
	await wait_physics_frames(3)

func test_ignores_a_player_beyond_the_aggro_radius() -> void:
	await wait_seconds(0.6)
	assert_null(foe.attack_target())

func test_attacks_a_player_who_comes_within_the_radius() -> void:
	alvar.global_position = Vector3(3, 0, 8)
	await wait_seconds(0.6)
	assert_eq(foe.attack_target(), alvar)

func test_wounds_a_player_who_stands_still() -> void:
	alvar.global_position = Vector3(5, 0, 8)
	await wait_seconds(4.0)
	assert_lt(alvar.stats.health, 120)

func test_a_dead_enemy_does_nothing() -> void:
	foe.stats.take_damage(999)
	alvar.global_position = Vector3(6, 0, 8)
	await wait_seconds(0.6)
	assert_null(foe.attack_target())
