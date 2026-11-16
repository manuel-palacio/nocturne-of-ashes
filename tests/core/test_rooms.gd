# tests/core/test_rooms.gd
extends GutTest

var main: Main

func after_each() -> void:
	Story.finish(main)

func _boot(state: GameState = null) -> void:
	main = Story.boot(self, state)
	await wait_physics_frames(3)

func test_a_new_story_starts_in_the_haven_with_alvar_alone() -> void:
	await _boot()
	assert_eq(main.room.room_id, &"haven")
	assert_eq(main.party.size(), 1)
	assert_eq(main.player.member_id, &"alvar")
	assert_eq(main.selected, main.player)
	assert_eq(main.enemies.size(), 0)
	assert_eq((main.player.get_node("Gifts") as GiftUser).count(), 0)

func test_the_skirmish_scene_is_unchanged() -> void:
	main = add_child_autofree(load("res://scenes/main.tscn").instantiate())
	await wait_physics_frames(3)
	assert_eq(main.room.room_id, &"vault")
	assert_eq(main.party.size(), 3)
	assert_eq(main.enemies_alive(), 6)
	assert_null(main.store)

func test_entering_a_room_spawns_the_joined_members_with_their_known_gifts() -> void:
	var state := GameState.new_game()
	state.join(&"zahra")
	state.learn(&"alvar", &"iron_sinew")
	await _boot(state)
	main.enter_room(&"vault", &"from_haven")
	await wait_physics_frames(3)
	assert_eq(main.room.room_id, &"vault")
	assert_eq(main.party.map(func(u: Unit) -> StringName: return u.member_id), [&"alvar", &"zahra"])
	assert_eq((main.player.get_node("Gifts") as GiftUser).count(), 1)
	assert_eq(main.enemies_alive(), 6)
	assert_eq(main.state.room, &"vault")
	assert_eq(main.state.entry, &"from_haven")
	assert_eq(main.hud.panels().size(), 2)

func test_health_and_blood_travel_between_rooms() -> void:
	var state := GameState.new_game()
	state.join(&"gonzalo")
	await _boot(state)
	main.player.take_hit(50)
	main.player.stats.spend_blood(20)
	main.enter_room(&"vault")
	await wait_physics_frames(3)
	assert_eq(main.player.stats.health, 70)
	assert_eq(main.player.stats.blood, 40)
	assert_eq(main.party[1].stats.health, 160)

func test_a_fallen_companion_arrives_risen_at_thirty_percent() -> void:
	var state := GameState.new_game()
	state.join(&"zahra")
	await _boot(state)
	main.party[1].take_hit(999)
	main.enter_room(&"vault")
	await wait_physics_frames(3)
	assert_true(main.party[1].is_alive())
	assert_eq(main.party[1].stats.health, 24)

func test_arrival_is_unpaused_with_alvar_selected_and_no_targeting() -> void:
	var state := GameState.skirmish()
	state.room = &"haven"
	await _boot(state)
	main.select(main.party[1])
	main.input.press_gift(0)
	main.set_paused(true)
	main.enter_room(&"vault")
	await wait_physics_frames(3)
	assert_false(main.is_paused())
	assert_eq(main.selected, main.player)
	assert_eq(main.input.targeting_gift(), -1)
	assert_true(main.input.enabled)

func test_a_cleared_room_stays_cleared() -> void:
	var state := GameState.skirmish()
	await _boot(state)
	for enemy: Unit in main.enemies:
		enemy.take_hit(999)
	await wait_physics_frames(3)
	assert_true(main.state.has_flag(&"vault_cleared"))
	main.enter_room(&"haven")
	await wait_physics_frames(3)
	main.enter_room(&"vault")
	await wait_physics_frames(3)
	assert_eq(main.enemies.size(), 0)
	assert_true(main.is_cleared())

func test_an_unknown_room_is_refused() -> void:
	await _boot()
	main.enter_room(&"nowhere")
	assert_push_warning("nowhere")
	assert_eq(main.room.room_id, &"haven")

func test_a_missing_entry_falls_back_to_start() -> void:
	await _boot()
	main.enter_room(&"vault", &"no_such_entry")
	await wait_physics_frames(3)
	assert_push_warning("no_such_entry")
	assert_eq(main.room.room_id, &"vault")
	assert_true(main.player.is_alive())

func test_every_entry_and_spawn_of_every_room_is_on_its_navmesh() -> void:
	await _boot()
	for room_id: StringName in Main.ROOMS:
		main.enter_room(room_id)
		await wait_physics_frames(3)
		var map := main.get_world_3d().navigation_map
		var markers: Array[Node] = main.room.find_children("Entry_*", "Marker3D", false)
		markers.append_array(main.room.find_children("Companion?", "Marker3D", true))
		markers.append_array(main.room.enemy_markers())
		assert_gt(markers.size(), 2, room_id)
		for marker: Node3D in markers:
			var at: Vector3 = marker.global_position
			assert_lt(at.distance_to(NavigationServer3D.map_get_closest_point(map, at)), 0.3, "%s/%s" % [room_id, marker.name])

func test_restart_in_a_story_returns_to_how_the_room_was_entered() -> void:
	var state := GameState.skirmish()
	await _boot(state)
	main.player.stats.spend_blood(20)
	main.enter_room(&"vault")
	await wait_physics_frames(3)
	main.player.take_hit(999)
	await wait_physics_frames(2)
	main.start_room()
	await wait_physics_frames(3)
	assert_true(main.player.is_alive())
	assert_eq(main.player.stats.blood, 40)
	assert_eq(main.enemies_alive(), 6)
