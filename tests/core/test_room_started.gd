# tests/core/test_room_started.gd
extends GutTest

const MAIN := preload("res://scenes/main.tscn")

var main: Main


func before_each() -> void:
	main = MAIN.instantiate()
	watch_signals(main)
	add_child_autoqfree(main)
	await wait_physics_frames(3)


func test_room_started_is_emitted_when_the_room_starts() -> void:
	assert_signal_emit_count(main, "room_started", 1)


func test_room_started_is_emitted_again_on_restart() -> void:
	main.player.stats.take_damage(999)
	await wait_physics_frames(2)
	await wait_until(func() -> bool: return main.hud.is_fallen_answerable(), Hud.FALLEN_DELAY + 1.0)
	Input.action_press("confirm")
	await wait_physics_frames(2)
	Input.action_release("confirm")
	await wait_physics_frames(3)
	assert_signal_emit_count(main, "room_started", 2)


func test_room_started_comes_after_the_units_are_spawned() -> void:
	var seen: Array[int] = []
	main.room_started.connect(func() -> void: seen.append(main.enemies_alive()))
	main.start_room()
	assert_eq(seen, [6])
