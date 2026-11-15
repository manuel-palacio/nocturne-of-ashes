# tests/units/test_chase.gd
extends GutTest
## How a chasing unit behaves when its way is blocked or its path ends short of the target.

const ROOM := preload("res://tests/fixtures/flat_room.tscn")
const ALVAR := preload("res://scenes/units/alvar.tscn")
const CRUSADER := preload("res://scenes/units/crusader.tscn")

var room: Node3D
var alvar: Unit

func before_each() -> void:
	room = add_child_autofree(ROOM.instantiate())
	alvar = ALVAR.instantiate()
	room.add_child(alvar)
	alvar.global_position = Vector3(-4, 0, 0)

func _add_crusader(at: Vector3) -> Unit:
	var crusader: Unit = CRUSADER.instantiate()
	room.add_child(crusader)
	crusader.global_position = at
	return crusader

func test_a_chaser_blocked_by_another_keeps_its_target_quietly() -> void:
	var front: Unit = _add_crusader(Vector3(-4, 0, 4))
	var behind: Unit = _add_crusader(Vector3(-4, 0, 5))
	await wait_seconds(3.0)
	assert_push_warning_count(0)
	assert_eq(front.attack_target(), alvar)
	assert_eq(behind.attack_target(), alvar)

func test_a_chase_whose_path_ends_out_of_range_neither_arrives_nor_repaths() -> void:
	# Hovering past the floor's edge: the nearest navmesh point lies about 2 m short of it.
	var foe: Unit = _add_crusader(Vector3(-4, 0, 11.5))
	foe.get_node("Brain").queue_free()
	await wait_physics_frames(3)
	watch_signals(alvar)
	alvar.order_attack(foe)
	await wait_seconds(4.0)
	assert_signal_not_emitted(alvar, "arrived")
	assert_eq(alvar.attack_target(), foe)
	assert_false(alvar.is_moving())
	assert_push_warning_count(0)
