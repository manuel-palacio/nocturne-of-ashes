# tests/core/test_checkpoints.gd
extends GutTest

var main: Main

func after_each() -> void:
	Story.finish(main)

func _boot(state: GameState = null) -> void:
	main = Story.boot(self, state)
	await wait_physics_frames(3)

func test_entering_a_room_saves() -> void:
	await _boot()
	assert_true(main.store.has_save())
	assert_eq(main.store.load_state().room, &"haven")

func test_a_skirmish_never_saves() -> void:
	main = add_child_autofree(load("res://scenes/main.tscn").instantiate())
	await wait_physics_frames(3)
	main.checkpoint()  # must not error
	assert_null(main.store)

func test_a_checkpoint_keeps_vitals_and_progress() -> void:
	await _boot()
	main.player.take_hit(30)
	main.state.change_conscience(-2)
	main.state.set_flag(&"met_malakor")
	watch_signals(main)
	main.checkpoint()
	assert_signal_emitted(main, "checkpoint_saved")
	var saved: GameState = main.store.load_state()
	assert_eq(saved.vitals(&"alvar").x, 90)
	assert_eq(saved.conscience, 5)
	assert_true(saved.has_flag(&"met_malakor"))

func test_a_fall_reloads_the_last_checkpoint() -> void:
	var state := GameState.skirmish()
	await _boot(state)
	main.state.change_conscience(-3)  # after the checkpoint: must be undone
	main.player.take_hit(999)
	await wait_physics_frames(2)
	assert_true(main.hud.is_fallen_shown())
	Input.action_press("confirm")
	await wait_physics_frames(2)
	Input.action_release("confirm")
	await wait_physics_frames(3)
	assert_true(main.player.is_alive())
	assert_eq(main.state.conscience, 7)
	assert_eq(main.enemies_alive(), 6)
	assert_false(main.hud.is_fallen_shown())
	assert_eq(main.party.size(), 3)

func test_reload_restores_the_room_the_save_names() -> void:
	var state := GameState.skirmish()
	await _boot(state)
	main.enter_room(&"haven", &"from_vault")
	await wait_physics_frames(3)
	main.reload_checkpoint()
	await wait_physics_frames(3)
	assert_eq(main.room.room_id, &"haven")
	assert_eq(main.state.entry, &"from_vault")

func test_reload_with_an_unusable_save_starts_a_new_game() -> void:
	await _boot()
	var file := FileAccess.open(main.store.path, FileAccess.WRITE)
	file.store_string("garbage")
	file.close()
	main.reload_checkpoint()
	await wait_physics_frames(3)
	assert_push_warning("save")
	assert_eq(main.room.room_id, &"haven")
	assert_eq(main.state.conscience, 7)
	assert_true(main.store.has_save())

func test_new_game_wipes_progress() -> void:
	var state := GameState.skirmish()
	state.change_conscience(-5)
	await _boot(state)
	main.new_game()
	await wait_physics_frames(3)
	assert_eq(main.room.room_id, &"haven")
	assert_eq(main.party.size(), 1)
	assert_eq(main.state.conscience, 7)
	assert_eq(main.store.load_state().joined(), [&"alvar"] as Array[StringName])

func test_the_cleared_flag_is_saved_at_once() -> void:
	var state := GameState.skirmish()
	await _boot(state)
	for enemy: Unit in main.enemies:
		enemy.take_hit(999)
	await wait_physics_frames(3)
	assert_true(main.store.load_state().has_flag(&"vault_cleared"))

func test_reload_closes_pause_and_targeting() -> void:
	var state := GameState.skirmish()
	await _boot(state)
	main.input.press_gift(1)
	main.set_paused(true)
	main.reload_checkpoint()
	await wait_physics_frames(3)
	assert_false(main.is_paused())
	assert_eq(main.input.targeting_gift(), -1)

func _unwritable_path() -> String:
	return "user://no_such_folder_%d/save.json" % randi()

func test_a_fall_reloads_the_checkpoint_kept_in_memory_when_the_store_cannot_write() -> void:
	var state := GameState.skirmish()
	await _boot(state)
	main.state.change_conscience(-2)
	main.state.set_flag(&"met_malakor")
	main.checkpoint()
	main.store.clear()
	main.store.path = _unwritable_path()
	main.state.change_conscience(-3)  # after the checkpoint: must be undone
	main.player.take_hit(999)
	await wait_physics_frames(2)
	Input.action_press("confirm")
	await wait_physics_frames(2)
	Input.action_release("confirm")
	await wait_physics_frames(3)
	assert_push_warning("Could not write")
	assert_eq(main.room.room_id, &"vault")
	assert_true(main.player.is_alive())
	assert_eq(main.state.conscience, 5)
	assert_true(main.state.has_flag(&"met_malakor"))
	assert_eq(main.party.size(), 3)

func test_a_reload_from_memory_is_independent_of_the_live_state() -> void:
	await _boot()
	main.store.clear()
	main.store.path = _unwritable_path()
	main.reload_checkpoint()
	await wait_physics_frames(3)
	main.state.change_conscience(-4)
	main.reload_checkpoint()
	await wait_physics_frames(3)
	assert_push_warning_count(2)
	assert_eq(main.state.conscience, 7)

func test_new_game_forgets_the_checkpoint_in_memory() -> void:
	var state := GameState.skirmish()
	await _boot(state)
	main.new_game()
	await wait_physics_frames(3)
	main.store.clear()
	main.reload_checkpoint()
	await wait_physics_frames(3)
	assert_eq(main.room.room_id, &"haven")
	assert_eq(main.party.size(), 1)
