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

func test_the_way_back_to_the_haven_arrives_at_the_stair() -> void:
	var state := GameState.skirmish()
	await _boot(state)
	_door("WestDoor").use(main.player)
	await wait_physics_frames(3)
	assert_eq(main.room.room_id, &"haven")
	assert_lt(Arena.flat(main.player.global_position, _door("StairDoor").global_position), 4.0)

func test_the_last_lock_never_opens() -> void:
	var state := GameState.skirmish()
	await _boot(state)
	for enemy: Unit in main.enemies:
		enemy.take_hit(999)
	await wait_physics_frames(3)
	_door("LastLock").use(main.player)
	await wait_physics_frames(2)
	assert_eq(main.room.room_id, &"vault")
	assert_eq(main.hud.notice(), "The last lock does not yield. Not yet.")

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
