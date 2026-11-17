# tests/core/test_loose_ends.gd
extends GutTest
## Small fixes carried from earlier milestones, one or two tests each.

const MAIN := preload("res://scenes/main.tscn")

var main: Main

func after_each() -> void:
	Story.finish(main)

func _skirmish() -> void:
	main = add_child_autoqfree(MAIN.instantiate())
	await wait_physics_frames(3)

## Presses and releases mouse `button` over the middle of `control`.
func _click(control: Control, button: MouseButton = MOUSE_BUTTON_LEFT) -> void:
	var click := InputEventMouseButton.new()
	click.button_index = button
	click.position = control.get_global_rect().get_center()
	click.global_position = click.position
	click.pressed = true
	# In the viewport's own coordinates, as the test window is stretched.
	control.get_viewport().push_input(click, true)
	var release: InputEventMouseButton = click.duplicate()
	release.pressed = false
	control.get_viewport().push_input(release, true)
	await wait_physics_frames(2)

# 1. A fallen companion never stays selected.

func test_a_fallen_companion_hands_selection_to_the_next_living_member_while_alvar_is_down() -> void:
	await _skirmish()
	main.select(main.party[1])
	main.player.take_hit(999)
	main.party[1].take_hit(999)
	assert_eq(main.selected, main.party[2])
	assert_eq(main.rig.target, main.party[2])

func test_selection_stays_on_alvar_when_nobody_lives() -> void:
	await _skirmish()
	main.select(main.party[1])
	main.player.take_hit(999)
	main.party[2].take_hit(999)
	main.party[1].take_hit(999)
	assert_eq(main.selected, main.player)

# 2. Effects are not added to the fallen.

func test_effects_are_not_added_to_the_fallen() -> void:
	await _skirmish()
	var zahra: Unit = main.party[1]
	zahra.take_hit(999)
	var stun := StatusEffect.new()
	stun.id = &"stun"
	stun.duration = 1.0
	stun.stuns = true
	zahra.add_effect(stun)
	assert_false(zahra.has_effect(&"stun"))
	assert_eq(zahra.effect_ids(), [] as Array[StringName])

# 3. `was_hit` before `died` on a killing blow.

func test_a_killing_blow_is_heard_as_a_hit_before_the_death() -> void:
	var arena := Arena.new(self)
	var foe: Unit = arena.spawn(Arena.CRUSADER, Vector3.ZERO)
	await wait_physics_frames(2)
	var heard: Array[String] = []
	foe.was_hit.connect(func(_amount: int, _source: Unit) -> void: heard.append("was_hit"))
	foe.died.connect(func(_unit: Unit) -> void: heard.append("died"))
	foe.take_hit(999)
	assert_eq(heard, ["was_hit", "died"] as Array[String])

# 4. An order on a map that never becomes ready warns once and is dropped.

func test_an_order_on_a_map_that_never_becomes_ready_warns_once_and_is_dropped() -> void:
	var arena := Arena.new(self)
	# The room's only region holds no navmesh, so no point is ever on the map.
	(arena.room.get_node("NavigationRegion3D") as NavigationRegion3D).navigation_mesh = null
	var alvar: Unit = arena.spawn(Arena.ALVAR, Vector3.ZERO)
	await wait_physics_frames(3)
	alvar.order_move(Vector3(3, 0, 0))
	await wait_seconds(4.5)
	assert_eq(alvar.current_order(), Unit.Order.MOVE, "still waiting before 5 s")
	assert_push_warning_count(0)
	await wait_seconds(1.0)
	assert_eq(alvar.current_order(), Unit.Order.NONE)
	assert_false(alvar.is_moving())
	assert_push_warning("could not plan its move order")
	await wait_seconds(1.0)
	assert_push_warning_count(1)

# 5. Right click and the wheel pass through HUD panels and Gift buttons; only the left button is consumed.

func test_a_right_click_on_a_party_panel_cancels_targeting() -> void:
	await _skirmish()
	main.input.press_gift(1)  # Baleful Eye waits for a target
	assert_eq(main.input.targeting_gift(), 1)
	await _click(main.hud.panels()[1], MOUSE_BUTTON_RIGHT)
	assert_eq(main.input.targeting_gift(), -1)
	assert_eq(main.selected, main.player)

func test_a_right_click_on_a_gift_button_cancels_targeting() -> void:
	await _skirmish()
	main.input.press_gift(1)
	await _click(main.hud.gift_buttons()[0], MOUSE_BUTTON_RIGHT)
	assert_eq(main.input.targeting_gift(), -1)
	assert_false(main.player.has_effect(&"iron_sinew"))

func test_the_wheel_zooms_over_panels_and_gift_buttons() -> void:
	await _skirmish()
	var start: float = main.rig.distance
	await _click(main.hud.panels()[0], MOUSE_BUTTON_WHEEL_UP)
	assert_lt(main.rig.distance, start)
	var closer: float = main.rig.distance
	await _click(main.hud.gift_buttons()[1], MOUSE_BUTTON_WHEEL_DOWN)
	assert_gt(main.rig.distance, closer)

func test_the_left_button_on_panels_and_buttons_gives_no_order_in_the_world() -> void:
	await _skirmish()
	await _click(main.hud.panels()[1])
	assert_eq(main.selected, main.party[1])
	assert_ne(main.party[1].order_issuer(), Unit.Issuer.PLAYER, "the panel's click gave no order")
	main.select(main.player)
	await wait_physics_frames(2)
	await _click(main.hud.gift_buttons()[0])
	assert_true(main.player.has_effect(&"iron_sinew"))
	assert_eq(main.player.current_order(), Unit.Order.NONE, "the button's click gave no order")
	# Now cooling down, so disabled.
	assert_true(main.hud.gift_buttons()[0].disabled)
	await _click(main.hud.gift_buttons()[0])
	assert_eq(main.player.current_order(), Unit.Order.NONE, "the disabled button's click gave no order")

# 6. A click on the fallen prompt does what Enter does.

func test_a_click_on_the_fallen_prompt_restarts_the_skirmish_once() -> void:
	await _skirmish()
	main.player.take_hit(999)
	await wait_physics_frames(2)
	assert_true(main.hud.is_fallen_shown())
	watch_signals(main)
	await _click(main.hud.find_child("FallenLabel") as Control)
	assert_signal_emit_count(main, "room_started", 1)
	assert_true(main.player.is_alive())
	assert_false(main.hud.is_fallen_shown())

func test_a_click_on_the_fallen_prompt_reloads_the_story_checkpoint_once() -> void:
	var state := GameState.skirmish()
	state.change_conscience(-2)
	main = Story.boot(self, state)
	await wait_physics_frames(3)
	main.state.change_conscience(-3)
	main.player.take_hit(999)
	await wait_physics_frames(2)
	watch_signals(main)
	await _click(main.hud.find_child("FallenLabel") as Control)
	assert_signal_emit_count(main, "room_started", 1)
	assert_true(main.player.is_alive())
	assert_eq(main.state.conscience, GameState.CONSCIENCE_START - 2, "the checkpoint's Conscience")
