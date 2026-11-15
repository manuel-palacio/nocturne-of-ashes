# tests/core/test_main.gd
extends GutTest

const MAIN := preload("res://scenes/main.tscn")

var main: Main

func before_each() -> void:
	main = add_child_autofree(MAIN.instantiate())
	await wait_physics_frames(3)

func test_the_room_starts_with_one_player_and_three_enemies() -> void:
	assert_true(main.player.is_alive())
	assert_eq(main.enemies_alive(), 3)
	assert_true(main.input.enabled)

func test_falling_holds_input_and_shows_the_prompt() -> void:
	main.player.stats.take_damage(999)
	await wait_physics_frames(2)
	assert_false(main.input.enabled)
	assert_true(main.hud.is_fallen_shown())

func test_confirm_after_falling_restarts_the_room() -> void:
	main.player.stats.take_damage(999)
	await wait_physics_frames(2)
	Input.action_press("confirm")
	await wait_physics_frames(2)
	Input.action_release("confirm")
	await wait_physics_frames(3)
	assert_true(main.player.is_alive())
	assert_eq(main.player.stats.health, 120)
	assert_eq(main.enemies_alive(), 3)
	assert_false(main.hud.is_fallen_shown())
	assert_true(main.input.enabled)

func test_confirm_while_alive_does_not_restart() -> void:
	main.player.stats.take_damage(20)
	Input.action_press("confirm")
	await wait_physics_frames(2)
	Input.action_release("confirm")
	assert_eq(main.player.stats.health, 100)

func test_every_spawn_point_is_on_the_navmesh() -> void:
	var map := main.get_world_3d().navigation_map
	for marker_name in ["PlayerSpawn", "EnemySpawn1", "EnemySpawn2", "EnemySpawn3"]:
		var at: Vector3 = main.find_child(marker_name).global_position
		assert_lt(at.distance_to(NavigationServer3D.map_get_closest_point(map, at)), 0.3, marker_name)
