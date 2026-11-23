# tests/rooms/test_doors.gd
extends GutTest

var main: Main

func after_each() -> void:
	Story.finish(main)

func _boot(state: GameState = null) -> void:
	main = Story.boot(self, state)
	await wait_physics_frames(3)

func _door(node_name: String) -> Door:
	return main.room.find_child(node_name) as Door

func test_the_stair_is_barred_until_the_order_is_given() -> void:
	await _boot()
	_door("StairDoor").use(main.player)
	await wait_physics_frames(2)
	assert_eq(main.room.room_id, &"haven")
	assert_eq(main.hud.notice(), "The stair is barred until Malakor says otherwise")

func test_with_the_order_the_stair_leads_to_the_vault() -> void:
	var state := GameState.new_game()
	state.set_flag(&"order_given")
	await _boot(state)
	main.player.order_interact(_door("StairDoor"))
	await wait_for_signal(main.room_started, 10.0)
	await wait_physics_frames(3)
	assert_eq(main.room.room_id, &"vault")
	assert_eq(main.state.entry, &"from_haven")
	assert_eq(main.enemies_alive(), 6)
	assert_eq(main.store.load_state().room, &"vault")

func test_no_leaving_while_a_fight_is_on() -> void:
	var state := GameState.skirmish()
	await _boot(state)
	main.enemies[0].order_attack(main.player)
	await wait_physics_frames(2)
	_door("WestDoor").use(main.player)
	await wait_physics_frames(2)
	assert_eq(main.room.room_id, &"vault")
	assert_eq(main.hud.notice(), "Not while they are upon you")

func test_the_way_back_to_the_haven_arrives_on_the_stairs_side_clear_of_it() -> void:
	var state := GameState.skirmish()
	await _boot(state)
	_door("WestDoor").use(main.player)
	await wait_physics_frames(3)
	assert_eq(main.room.room_id, &"haven")
	# Moved west of the stair so that, on arrival, nobody stands under the party panels.
	var from_stair: float = Arena.flat(main.player.global_position, _door("StairDoor").global_position)
	assert_lt(from_stair, 8.0)
	assert_gt(from_stair, 1.5, "far enough not to use the stair again")
	assert_gt(main.player.global_position.x, 0.0, "on the stair's side of the forge")

func test_the_last_lock_never_opens() -> void:
	var state := GameState.skirmish()
	await _boot(state)
	for enemy: Unit in main.enemies:
		enemy.take_hit(999)
	await wait_physics_frames(3)
	_door("LastLock").use(main.player)
	await wait_physics_frames(2)
	assert_eq(main.room.room_id, &"vault")
	assert_eq(main.hud.notice(), "The last lock does not yield. This is where the story rests, for now.")

func test_only_alvar_opens_doors() -> void:
	var state := GameState.skirmish()
	await _boot(state)
	assert_false(_door("WestDoor").can_be_used_by(main.party[1]))
	_door("WestDoor").use(main.party[1])
	await wait_physics_frames(2)
	assert_eq(main.room.room_id, &"vault")

func test_a_notice_fades() -> void:
	await _boot()
	main.hud.show_notice("The stair is barred until Malakor says otherwise")
	assert_eq(main.hud.notice(), "The stair is barred until Malakor says otherwise")
	await wait_seconds(2.8)
	assert_eq(main.hud.notice(), "")

func test_every_door_stands_within_reach_of_the_navmesh() -> void:
	await _boot()
	for room_id: StringName in Main.ROOMS:
		main.enter_room(room_id)
		await wait_physics_frames(3)
		var map := main.get_world_3d().navigation_map
		for door: Node in main.room.find_children("*", "Door", true, false):
			var at: Vector3 = (door as Door).global_position
			var on_mesh: Vector3 = NavigationServer3D.map_get_closest_point(map, at)
			assert_lt(Arena.flat(at, on_mesh), (door as Door).reach - 0.3, "%s/%s" % [room_id, door.name])

func test_doors_do_nothing_in_the_skirmish() -> void:
	main = add_child_autofree(load("res://scenes/main.tscn").instantiate())
	await wait_physics_frames(3)
	(main.room.find_child("WestDoor") as Door).use(main.player)
	await wait_physics_frames(2)
	assert_eq(main.room.room_id, &"vault")
	assert_eq(main.hud.notice(), "")

## The skirmish's state in the story, with the enemies' brains taken out, so no fight starts.
func _boot_in_a_calm_vault() -> void:
	await _boot(GameState.skirmish())
	for enemy: Unit in main.enemies:
		var brain: Node = enemy.get_node("Brain")
		enemy.remove_child(brain)
		brain.free()

func test_no_leaving_while_alvar_is_in_the_fury() -> void:
	await _boot_in_a_calm_vault()
	main.player.stats.spend_blood(main.player.stats.blood - 5)
	assert_true(main.player.is_in_fury())
	_door("WestDoor").use(main.player)
	await wait_physics_frames(3)
	assert_eq(main.room.room_id, &"vault")
	assert_eq(main.hud.notice(), "Not while they are upon you")

func test_no_leaving_while_a_member_walks_to_a_feed() -> void:
	await _boot_in_a_calm_vault()
	var meal: Unit = main.enemies[0]
	meal.take_hit(40)
	main.party[1].order_feed(meal)
	assert_eq(main.party[1].feed_target(), meal)
	_door("WestDoor").use(main.player)
	await wait_physics_frames(3)
	assert_eq(main.room.room_id, &"vault")
	assert_eq(main.hud.notice(), "Not while they are upon you")

func test_no_leaving_while_a_member_feeds() -> void:
	await _boot_in_a_calm_vault()
	var meal: Unit = main.enemies[0]
	meal.take_hit(40)
	meal.global_position = main.party[1].global_position + Vector3(1.2, 0, 0)
	main.party[1].order_feed(meal)
	await wait_until(func() -> bool: return main.party[1].is_feeding(), 3.0)
	assert_true(main.party[1].is_feeding())
	_door("WestDoor").use(main.player)
	await wait_physics_frames(3)
	assert_eq(main.room.room_id, &"vault")
	assert_eq(main.hud.notice(), "Not while they are upon you")

func test_a_door_is_inert_during_a_conversation() -> void:
	await _boot(GameState.skirmish())
	main.talk(preload("res://tests/fixtures/test_talk.dialogue"), "start")
	await wait_physics_frames(2)
	assert_true(main.is_talking())
	watch_signals(_door("WestDoor"))
	assert_false(_door("WestDoor").use(main.player))
	await wait_physics_frames(3)
	assert_eq(main.room.room_id, &"vault")
	assert_eq(main.hud.notice(), "")
	assert_signal_not_emitted(_door("WestDoor"), "travel_requested")

func test_a_door_is_inert_while_the_title_shows() -> void:
	main = preload("res://scenes/game.tscn").instantiate()
	main.store = SaveStore.new()
	main.store.path = "user://test_doors_%d.json" % randi()
	main.store.clear()
	add_child_autoqfree(main)
	await wait_physics_frames(3)
	assert_true(main.is_title_open())
	# There is no room on the title, so a room's doors are handed to the travel by hand.
	var vault: Room = add_child_autoqfree(Main.ROOMS[&"vault"].instantiate())
	(main.get_node("Travel") as Travel).begin_room(vault, main.state)
	var door: Door = vault.find_child("WestDoor")
	var alvar: Unit = autofree(Party.SCENES[&"alvar"].instantiate())
	watch_signals(door)
	assert_false(door.use(alvar))
	await wait_physics_frames(3)
	assert_null(main.room)
	assert_eq(main.hud.notice(), "")
	assert_signal_not_emitted(door, "travel_requested")

func test_a_door_used_just_before_the_fight_starts_does_not_travel() -> void:
	await _boot_in_a_calm_vault()
	assert_true(_door("WestDoor").use(main.player))
	# In the same frame, before the party would go through at its end.
	main.enemies[0].order_attack(main.player)
	await wait_physics_frames(3)
	assert_eq(main.room.room_id, &"vault")

func test_a_click_on_a_door_with_a_companion_selected_sends_alvar() -> void:
	var state := GameState.new_game()
	state.join(&"zahra")
	state.set_flag(&"order_given")
	await _boot(state)
	var zahra: Unit = main.party[1]
	main.select(zahra)
	main.rig.snap_to_target()
	await wait_physics_frames(3)
	var door: Door = _door("StairDoor")
	var cam: Camera3D = main.rig.camera()
	var at: Vector2 = cam.unproject_position(door.global_position + Vector3(0, 1.0, 0))
	assert_eq(Picker.interactable_at(cam, at), door)
	main.input.click_at(at)
	assert_eq(main.player.current_order(), Unit.Order.INTERACT)
	assert_ne(zahra.current_order(), Unit.Order.INTERACT)
	await wait_physics_frames(5)
	assert_eq(main.selected, zahra)
	assert_eq(main.rig.target, zahra)
	await wait_for_signal(main.room_started, 10.0)
	await wait_physics_frames(3)
	assert_eq(main.room.room_id, &"vault")
	assert_eq(main.selected, main.player)
