# tests/core/test_party.gd
extends GutTest

const MAIN := preload("res://scenes/main.tscn")

var main: Main

func before_each() -> void:
	main = add_child_autoqfree(MAIN.instantiate())
	await wait_physics_frames(3)

func _brain(unit: Unit) -> CombatBrain:
	return unit.get_node("Brain") as CombatBrain

func _kill_enemies() -> void:
	for enemy: Unit in main.enemies:
		enemy.take_hit(Arena.LETHAL)

func test_the_party_is_alvar_zahra_and_gonzalo_with_alvar_selected() -> void:
	assert_eq(main.party.map(func(u: Unit) -> String: return u.display_name), ["Brother Álvar", "Zahra", "Gonzalo"])
	assert_eq(main.selected, main.player)
	assert_eq(main.player.stats.blood, 60)

func test_selecting_hands_over_camera_input_and_brains() -> void:
	watch_signals(main)
	var zahra: Unit = main.party[1]
	main.select(zahra)
	assert_eq(main.selected, zahra)
	assert_eq(main.rig.target, zahra)
	assert_eq(main.input.unit, zahra)
	assert_false(_brain(zahra).enabled)
	assert_true(_brain(main.player).enabled)
	assert_eq(_brain(main.player).leader, zahra)
	assert_signal_emitted_with_parameters(main, "selection_changed", [zahra])

func test_select_next_cycles_and_skips_the_fallen() -> void:
	main.party[1].take_hit(Arena.LETHAL)
	main.select_next()
	assert_eq(main.selected, main.party[2])
	main.select_next()
	assert_eq(main.selected, main.party[0])

func test_an_enemy_or_a_fallen_member_cannot_be_selected() -> void:
	main.select(main.enemies[0])
	assert_eq(main.selected, main.player)
	main.party[2].take_hit(Arena.LETHAL)
	main.select(main.party[2])
	assert_eq(main.selected, main.player)

func test_selection_returns_to_alvar_when_the_selected_companion_falls() -> void:
	main.select(main.party[1])
	main.party[1].take_hit(Arena.LETHAL)
	await wait_physics_frames(2)
	assert_eq(main.selected, main.player)
	assert_eq(main.rig.target, main.player)

func test_companions_follow_the_selected_member() -> void:
	_kill_enemies()  # nothing to fight, so following is all they do
	main.player.order_move(Vector3(-2, 0, 0))
	await wait_seconds(4.0)
	for companion: Unit in [main.party[1], main.party[2]]:
		assert_lt(Arena.flat(companion.global_position, main.player.global_position), 5.0, companion.display_name)
		assert_gt(companion.global_position.x, -8.0, companion.display_name)

func test_a_fallen_companion_rises_when_the_fight_has_been_calm() -> void:
	(main.party[1].get_node("Brain") as CombatBrain).uses_gifts = false
	main.calm_time = 0.5
	main.party[1].take_hit(Arena.LETHAL)
	await wait_seconds(1.0)
	assert_true(main.party[1].is_alive())
	assert_eq(main.party[1].stats.health, 24)  # 30% of 80

func test_clearing_the_room_signals_once_and_raises_the_fallen() -> void:
	watch_signals(main)
	main.party[2].take_hit(Arena.LETHAL)
	_kill_enemies()
	await wait_physics_frames(3)
	assert_signal_emit_count(main, "room_cleared", 1)
	assert_true(main.party[2].is_alive())

func test_alvar_falling_ends_the_round_and_restart_rebuilds_the_party() -> void:
	main.select(main.party[1])
	main.party[2].take_hit(Arena.LETHAL)
	main.player.take_hit(Arena.LETHAL)
	await wait_physics_frames(2)
	assert_true(main.hud.is_fallen_shown())
	await wait_until(func() -> bool: return main.hud.is_fallen_answerable(), Hud.FALLEN_DELAY + 1.0)
	Input.action_press("confirm")
	await wait_physics_frames(2)
	Input.action_release("confirm")
	await wait_physics_frames(3)
	assert_eq(main.party.size(), 3)
	for member: Unit in main.party:
		assert_true(member.is_alive())
		assert_eq(member.stats.health, member.stats.max_health)
	assert_eq(main.selected, main.player)
	assert_eq(main.enemies_alive(), 6)
