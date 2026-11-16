# tests/core/test_near_wall_clicks.gd
extends GutTest
## The wall nearest the camera is not drawn, so clicks in front of it must reach the floor and the units.

const MAIN := preload("res://scenes/main.tscn")

var main: Main
var foe: Unit

func before_each() -> void:
	main = add_child_autofree(MAIN.instantiate())
	await wait_physics_frames(3)
	# Every crusader stands still; the spare ones wait in the far west corners, out of the way.
	for enemy: Unit in main.enemies:
		enemy.get_node("Brain").free()
	foe = main.enemies[0]
	var corners: Array[Vector3] = [
		Vector3(-10, 0, -6), Vector3(-10, 0, 6), Vector3(-11, 0, -6), Vector3(-11, 0, 6), Vector3(-11, 0, -4.5),
	]
	for i: int in range(1, main.enemies.size()):
		main.enemies[i].global_position = corners[i - 1]
	foe.global_position = Vector3(-10, 0, -3)

func _flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()

func _place_player(at: Vector3) -> void:
	main.player.global_position = at
	main.rig.snap_to_target()
	await wait_physics_frames(3)

func _click(world: Vector3) -> void:
	main.input.click_at(main.rig.camera().unproject_position(world))

func _turn_camera_east() -> void:
	main.rig.rotate_by(PI / 2)
	main.rig.snap_to_target()

func test_a_floor_click_before_the_south_wall_reaches_the_floor() -> void:
	await _place_player(Vector3(0, 0, 4))
	_click(Vector3(0, 0, 5.5))
	await wait_for_signal(main.player.arrived, 4.0)
	assert_lt(_flat_distance(main.player.global_position, Vector3(0, 0, 5.5)), 0.5)

func test_a_click_on_a_crusader_before_the_south_wall_attacks_it() -> void:
	await _place_player(Vector3(0, 0, 4))
	foe.global_position = Vector3(0, 0, 6.8)
	await wait_physics_frames(3)
	_click(foe.global_position + Vector3(0, 0.9, 0))
	assert_eq(main.player.attack_target(), foe)

func test_a_floor_click_before_the_east_wall_reaches_the_floor() -> void:
	_turn_camera_east()
	await _place_player(Vector3(8, 0, 0))
	_click(Vector3(9.5, 0, 0))
	await wait_for_signal(main.player.arrived, 4.0)
	assert_lt(_flat_distance(main.player.global_position, Vector3(9.5, 0, 0)), 0.5)

func test_a_click_on_a_crusader_before_the_east_wall_attacks_it() -> void:
	_turn_camera_east()
	await _place_player(Vector3(8, 0, 0))
	foe.global_position = Vector3(10.8, 0, 0)
	await wait_physics_frames(3)
	_click(foe.global_position + Vector3(0, 0.9, 0))
	assert_eq(main.player.attack_target(), foe)

func test_the_walls_still_stop_units() -> void:
	await _place_player(Vector3(0, 0, 4))
	main.player.order_move(Vector3(0, 0, 14))
	await wait_for_signal(main.player.arrived, 4.0)
	assert_lt(main.player.global_position.z, 8.0)
	# Without an order the body keeps its velocity, so only the wall's collider can stop it.
	main.player.velocity = Vector3(0, 0, 4)
	await wait_seconds(1.5)
	assert_lt(main.player.global_position.z, 8.0)
