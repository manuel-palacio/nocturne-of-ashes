# tests/core/test_pause_and_selection_input.gd
extends GutTest

const MAIN := preload("res://scenes/main.tscn")

var main: Main

func before_each() -> void:
	main = add_child_autoqfree(MAIN.instantiate())
	await wait_physics_frames(3)

func _screen(world: Vector3) -> Vector2:
	return main.rig.camera().unproject_position(world)

func _tap(action: StringName) -> void:
	Input.action_press(action)
	await wait_physics_frames(2)
	Input.action_release(action)
	await wait_physics_frames(2)

func test_clicking_a_companion_selects_it() -> void:
	var zahra: Unit = main.party[1]
	main.input.click_at(_screen(zahra.global_position + Vector3(0, 0.9, 0)))
	assert_eq(main.selected, zahra)

func test_clicking_the_selected_unit_gives_no_order() -> void:
	main.input.click_at(_screen(main.player.global_position + Vector3(0, 0.9, 0)))
	assert_eq(main.player.current_order(), Unit.Order.NONE)
	assert_eq(main.selected, main.player)

func test_tab_selects_the_next_member() -> void:
	await _tap(&"select_next")
	assert_eq(main.selected, main.party[1])

func test_space_pauses_and_unpauses() -> void:
	watch_signals(main)
	await _tap(&"pause")
	assert_true(main.is_paused())
	assert_signal_emitted_with_parameters(main, "pause_changed", [true])
	await _tap(&"pause")
	assert_false(main.is_paused())

func test_space_no_longer_confirms() -> void:
	main.player.take_hit(999)
	await wait_physics_frames(2)
	await _tap(&"pause")
	assert_false(main.player.is_alive())
	assert_false(main.is_paused())

func test_nothing_moves_while_paused_and_orders_wait() -> void:
	main.set_paused(true)
	var from: Vector3 = main.player.global_position
	main.player.order_move(from + Vector3(4, 0, 0))
	await wait_seconds(0.5)
	assert_lt(Arena.flat(main.player.global_position, from), 0.05)
	main.set_paused(false)
	await wait_for_signal(main.player.arrived, 4.0)
	assert_lt(Arena.flat(main.player.global_position, from + Vector3(4, 0, 0)), 0.5)

func test_selection_and_camera_work_while_paused() -> void:
	main.set_paused(true)
	main.select(main.party[2])
	assert_eq(main.selected, main.party[2])
	var yaw: float = main.rig.rotation.y
	main.rig.rotate_by(0.5)
	assert_almost_eq(main.rig.rotation.y, yaw + 0.5, 0.001)

func test_effects_and_cooldowns_do_not_run_while_paused() -> void:
	var effect := StatusEffect.new()
	effect.id = &"test"
	effect.duration = 0.3
	main.player.add_effect(effect)
	main.set_paused(true)
	await wait_seconds(0.6)
	assert_true(main.player.has_effect(&"test"))

func test_restart_unpauses() -> void:
	main.set_paused(true)
	main.start_room()
	assert_false(main.is_paused())
	assert_eq(main.selected, main.player)

func test_no_selection_changes_while_alvar_is_down() -> void:
	main.player.take_hit(999)
	await wait_physics_frames(2)
	main.select(main.party[1])
	assert_eq(main.selected, main.player)
	main.select_next()
	assert_eq(main.selected, main.player)

func test_the_calm_timer_does_not_advance_while_paused() -> void:
	(main.party[1].get_node("Brain") as CombatBrain).uses_gifts = false
	main.calm_time = 0.5
	main.set_paused(true)
	main.party[1].take_hit(999)
	await wait_seconds(1.0)
	assert_false(main.party[1].is_alive(), "still down after the calm time, paused")
	main.set_paused(false)
	await wait_seconds(1.0)
	assert_true(main.party[1].is_alive())

func test_tab_does_nothing_while_input_is_off() -> void:
	main.input.enabled = false
	await _tap(&"select_next")
	assert_eq(main.selected, main.player)
