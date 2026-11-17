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

## Puts a character labelled `label` at `at` in the room; hidden unless `shown`. The room's own Zahra,
## the member these tests have join, is taken out first, so only the test's character can place her.
func _character(label: String, at: Vector3, shown: bool = true) -> Npc:
	for resident: Npc in main.room.npcs():
		if resident.label == "Zahra":
			main.room.remove_child(resident)
			resident.free()
	var npc: Npc = load("res://scenes/rooms/npc.tscn").instantiate()
	npc.label = label
	if not shown:
		npc.shown_if = &"never_set"
	main.room.add_child(npc)
	npc.global_position = at
	await wait_physics_frames(2)
	return npc

func _flat(point: Vector3) -> Vector2:
	return Vector2(point.x, point.z)

func _on_navmesh(point: Vector3) -> bool:
	var map := main.get_world_3d().navigation_map
	return point.distance_to(NavigationServer3D.map_get_closest_point(map, point)) < 0.3

func _companion_marker() -> Vector3:
	return (main.room.find_child("Entry_start").get_node("Companion1") as Node3D).global_position

func test_a_joiner_appears_beside_their_character_toward_the_centre() -> void:
	var npc: Npc = await _character("Zahra", Vector3(6, 0.3, 0))
	main.state.join(&"zahra")
	await wait_physics_frames(3)
	var at: Vector3 = main.party[1].global_position
	assert_almost_eq(_flat(at).distance_to(_flat(npc.global_position)), Room.BESIDE_NPC, 0.1)
	assert_lt(_flat(at).length(), _flat(npc.global_position).length())
	assert_true(_on_navmesh(at))

func test_with_no_matching_character_a_joiner_appears_at_the_companion_marker() -> void:
	await _character("Someone else", Vector3(6, 0.3, 0))
	main.state.join(&"zahra")
	await wait_physics_frames(3)
	assert_almost_eq(_flat(main.party[1].global_position).distance_to(_flat(_companion_marker())), 0.0, 0.1)

func test_a_hidden_character_is_ignored() -> void:
	var npc: Npc = await _character("Zahra", Vector3(6, 0.3, 0), false)
	assert_false(npc.visible)
	main.state.join(&"zahra")
	await wait_physics_frames(3)
	assert_almost_eq(_flat(main.party[1].global_position).distance_to(_flat(_companion_marker())), 0.0, 0.1)

func test_a_character_at_the_centre_still_gives_a_point_on_the_navmesh() -> void:
	var npc: Npc = await _character("Zahra", Vector3(0, 0.3, 0))
	main.state.join(&"zahra")
	await wait_physics_frames(3)
	var at: Vector3 = main.party[1].global_position
	assert_true(_on_navmesh(at))
	assert_almost_eq(_flat(at).distance_to(_flat(npc.global_position)), Room.BESIDE_NPC, 0.1)
