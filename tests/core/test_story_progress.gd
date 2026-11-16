# tests/core/test_story_progress.gd
extends GutTest

var main: Main

func after_each() -> void:
	Story.finish(main)

func before_each() -> void:
	main = Story.boot(self)
	await wait_physics_frames(3)

func _label() -> Label:
	return main.hud.find_child("ConscienceLabel") as Label

func test_conscience_is_shown_and_follows_changes() -> void:
	assert_true(_label().visible)
	assert_eq(_label().text, "Conscience 7/10")
	main.state.change_conscience(-2)
	assert_eq(_label().text, "Conscience 5/10")

func test_it_is_hidden_in_a_skirmish() -> void:
	var skirmish: Main = add_child_autofree(load("res://scenes/main.tscn").instantiate())
	await wait_physics_frames(3)
	assert_false((skirmish.hud.find_child("ConscienceLabel") as Label).visible)

func test_it_follows_the_state_after_a_reload() -> void:
	main.state.change_conscience(-3)
	main.checkpoint()
	main.state.change_conscience(-3)
	main.reload_checkpoint()
	await wait_physics_frames(3)
	assert_eq(_label().text, "Conscience 4/10")
	main.state.change_conscience(1)
	assert_eq(_label().text, "Conscience 5/10")

func test_a_learned_gift_appears_at_once() -> void:
	assert_eq(main.hud.gift_buttons().size(), 0)
	main.state.learn(&"alvar", &"baleful_eye")
	await wait_physics_frames(2)
	assert_eq(main.hud.gift_buttons().map(func(b: GiftButton) -> String: return b.text), ["1 Baleful Eye (15)"])
	main.state.learn(&"alvar", &"iron_sinew")
	await wait_physics_frames(2)
	assert_eq(main.hud.gift_buttons().map(func(b: GiftButton) -> String: return b.text), ["1 Iron Sinew (20)", "2 Baleful Eye (15)"])

func test_learning_keeps_a_running_cooldown() -> void:
	main.state.learn(&"alvar", &"iron_sinew")
	await wait_physics_frames(2)
	main.input.press_gift(0)
	await wait_physics_frames(2)
	main.state.learn(&"alvar", &"baleful_eye")
	await wait_physics_frames(2)
	var gifts := main.player.get_node("Gifts") as GiftUser
	assert_gt(gifts.cooldown_left(0), 10.0)
	assert_eq(gifts.cooldown_left(1), 0.0)

func test_a_companion_who_joins_appears_and_follows() -> void:
	main.state.join(&"gonzalo")
	await wait_physics_frames(3)
	assert_eq(main.party.map(func(u: Unit) -> StringName: return u.member_id), [&"alvar", &"gonzalo"])
	assert_eq(main.hud.panels().size(), 2)
	assert_eq(main.selected, main.player)
	var brain := main.party[1].get_node("Brain") as CombatBrain
	assert_true(brain.enabled)
	assert_eq(brain.leader, main.player)
	assert_eq(main.party[1].stats.health, 160)

func test_members_keep_their_order_whoever_joins_first() -> void:
	main.state.join(&"gonzalo")
	main.state.join(&"zahra")
	await wait_physics_frames(3)
	assert_eq(main.party.map(func(u: Unit) -> StringName: return u.member_id), [&"alvar", &"zahra", &"gonzalo"])
	assert_eq(main.hud.panels()[1].find_child("NameLabel").text, "Zahra")

func test_a_joined_companion_is_saved_and_returns_after_reload() -> void:
	main.state.join(&"zahra")
	await wait_physics_frames(3)
	main.checkpoint()
	main.reload_checkpoint()
	await wait_physics_frames(3)
	assert_eq(main.party.size(), 2)

func test_a_join_closes_targeting() -> void:
	main.state.learn(&"alvar", &"baleful_eye")
	await wait_physics_frames(2)
	main.input.press_gift(0)
	assert_eq(main.input.targeting_gift(), 0)
	main.state.join(&"zahra")
	await wait_physics_frames(2)
	assert_eq(main.input.targeting_gift(), -1)
	assert_false(main.hud.gift_buttons()[0].is_targeting())
