# tests/player/test_gift_input.gd
extends GutTest

const MAIN := preload("res://scenes/main.tscn")

var main: Main
var foe: Unit

func before_each() -> void:
	main = add_child_autoqfree(MAIN.instantiate())
	await wait_physics_frames(3)
	for enemy: Unit in main.enemies:
		var brain: Node = enemy.get_node("Brain")
		enemy.remove_child(brain)
		brain.free()
	foe = main.enemies[0]
	foe.global_position = main.player.global_position + Vector3(4, 0, 0)
	await wait_physics_frames(2)

func _screen(world: Vector3) -> Vector2:
	return main.rig.camera().unproject_position(world)

func _click(unit: Unit) -> void:
	main.input.click_at(_screen(unit.global_position + Vector3(0, 0.9, 0)))

func test_a_self_gift_fires_on_its_key() -> void:
	main.input.press_gift(0)
	assert_true(main.player.has_effect(&"iron_sinew"))
	assert_eq(main.input.targeting_gift(), -1)

func test_a_targeted_gift_waits_for_a_click_on_a_valid_target() -> void:
	watch_signals(main.input)
	main.input.press_gift(1)
	assert_eq(main.input.targeting_gift(), 1)
	assert_signal_emitted_with_parameters(main.input, "targeting_changed", [1])
	_click(foe)
	assert_true(foe.is_stunned())
	assert_eq(main.input.targeting_gift(), -1)
	assert_eq(main.player.current_order(), Unit.Order.NONE)

func test_a_click_elsewhere_keeps_targeting_and_gives_no_order() -> void:
	main.input.press_gift(1)
	main.input.click_at(_screen(main.player.global_position + Vector3(2, 0, 2)))
	assert_eq(main.input.targeting_gift(), 1)
	assert_eq(main.player.current_order(), Unit.Order.NONE)
	assert_eq(main.player.stats.blood, 60)

func test_the_same_key_or_cancel_closes_targeting() -> void:
	main.input.press_gift(1)
	main.input.press_gift(1)
	assert_eq(main.input.targeting_gift(), -1)
	main.input.press_gift(1)
	main.input.cancel_targeting()
	assert_eq(main.input.targeting_gift(), -1)

func test_a_gift_that_cannot_be_paid_for_does_not_open_targeting() -> void:
	# Baleful Eye costs as much as the Fury's line: Blood that cannot pay for it is spent into the
	# Fury, which is ended here, leaving Álvar free to act with 8 Blood.
	main.player.stats.spend_blood(52)
	main.player.remove_effect(&"fury")
	assert_true(main.player.can_act())
	main.input.press_gift(1)
	assert_eq(main.input.targeting_gift(), -1)

func test_the_target_dying_before_the_click_spends_nothing() -> void:
	main.input.press_gift(1)
	var at: Vector2 = _screen(foe.global_position + Vector3(0, 0.9, 0))
	foe.take_hit(Arena.LETHAL)
	await wait_physics_frames(3)
	main.input.click_at(at)
	assert_eq(main.player.stats.blood, 60)
	assert_eq(main.input.targeting_gift(), 1)

func test_changing_selection_closes_targeting() -> void:
	main.input.press_gift(1)
	main.select(main.party[1])
	assert_eq(main.input.targeting_gift(), -1)

func test_an_ally_gift_can_be_cast_on_a_companion_by_clicking_them() -> void:
	main.select(main.party[1])
	main.party[2].take_hit(60)
	main.input.press_gift(0)
	_click(main.party[2])
	assert_eq(main.party[2].stats.health, 140)
	assert_eq(main.selected, main.party[1])

func test_gifts_can_be_used_while_paused() -> void:
	main.set_paused(true)
	main.input.press_gift(0)
	assert_true(main.player.has_effect(&"iron_sinew"))
	assert_eq(main.player.stats.blood, 40)

func test_restart_and_falling_close_targeting() -> void:
	main.input.press_gift(1)
	main.player.take_hit(Arena.LETHAL)
	await wait_physics_frames(2)
	assert_eq(main.input.targeting_gift(), -1)
	main.input.press_gift(0)
	assert_false(main.player.has_effect(&"iron_sinew"))

func test_a_click_on_a_weakened_enemy_feeds_while_short_of_blood() -> void:
	Arena.weaken(foe, 0.15)  # within the feed threshold
	_click(foe)
	assert_eq(main.player.current_order(), Unit.Order.FEED)

func test_a_click_on_a_weakened_enemy_attacks_at_full_blood() -> void:
	main.player.stats.gain_blood(100)
	Arena.weaken(foe, 0.15)
	_click(foe)
	assert_eq(main.player.current_order(), Unit.Order.ATTACK)
	assert_eq(main.player.attack_target(), foe)

func test_targeting_closes_when_the_unit_is_stunned() -> void:
	main.input.press_gift(1)
	var stun := StatusEffect.new()
	stun.id = &"stun"
	stun.duration = 0.3
	stun.stuns = true
	main.player.add_effect(stun)
	await wait_physics_frames(2)
	assert_eq(main.input.targeting_gift(), -1)
	await wait_seconds(0.5)
	main.input.click_at(_screen(main.player.global_position + Vector3(2, 0, 2)))
	assert_eq(main.player.current_order(), Unit.Order.MOVE)

func test_starting_the_room_closes_targeting() -> void:
	main.input.press_gift(1)
	main.start_room()
	assert_eq(main.input.targeting_gift(), -1)

func _tap(action: StringName) -> void:
	Input.action_press(action)
	await wait_physics_frames(2)
	Input.action_release(action)
	await wait_physics_frames(2)

func test_the_gift_keys_and_cancel_do_what_the_buttons_do() -> void:
	await _tap(&"gift_1")
	assert_true(main.player.has_effect(&"iron_sinew"), "gift_1 uses the first Gift")
	await _tap(&"gift_2")
	assert_eq(main.input.targeting_gift(), 1, "gift_2 opens targeting for the second")
	await _tap(&"cancel")
	assert_eq(main.input.targeting_gift(), -1, "cancel closes it")

func test_a_right_click_in_the_world_cancels_targeting() -> void:
	main.input.press_gift(1)
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_RIGHT
	click.position = _screen(main.player.global_position + Vector3(2, 0, 2))
	click.pressed = true
	# Handed to the input node as the world gets it: the test runner's own window lies over the
	# middle of the screen and would take a click sent through the viewport.
	main.input._unhandled_input(click)
	assert_eq(main.input.targeting_gift(), -1)
	assert_eq(main.player.current_order(), Unit.Order.NONE)
