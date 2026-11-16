# tests/ui/test_title_screen.gd
extends GutTest

const GAME := preload("res://scenes/game.tscn")

var main: Main

func after_each() -> void:
	Story.finish(main)

func _boot_with_title(saved: GameState) -> void:
	main = GAME.instantiate()
	main.store = SaveStore.new()
	main.store.path = "user://test_title_%d.json" % randi()
	main.store.clear()
	if saved != null:
		main.store.save(saved)
	add_child_autofree(main)
	await wait_physics_frames(3)

func _title() -> TitleScreen:
	return main.find_child("TitleScreen") as TitleScreen

func test_without_a_save_only_new_game_is_offered() -> void:
	await _boot_with_title(null)
	assert_true(_title().is_open())
	assert_false(_title().find_child("ContinueButton").visible)
	assert_true(_title().find_child("NewGameButton").visible)
	assert_null(main.room)
	assert_false(main.input.enabled)

func test_new_game_enters_the_haven() -> void:
	await _boot_with_title(null)
	_title().new_game_chosen.emit()
	await wait_physics_frames(3)
	assert_false(_title().is_open())
	assert_eq(main.room.room_id, &"haven")
	assert_true(main.input.enabled)

func test_continue_restores_the_save() -> void:
	var saved := GameState.skirmish()
	saved.change_conscience(-4)
	await _boot_with_title(saved)
	assert_true(_title().find_child("ContinueButton").visible)
	_title().continue_chosen.emit()
	await wait_physics_frames(3)
	assert_eq(main.room.room_id, &"vault")
	assert_eq(main.state.conscience, 3)
	assert_eq(main.party.size(), 3)

func test_enter_continues_when_it_can_and_starts_anew_when_it_cannot() -> void:
	var saved := GameState.skirmish()
	await _boot_with_title(saved)
	Input.action_press("confirm")
	await wait_physics_frames(2)
	Input.action_release("confirm")
	await wait_physics_frames(3)
	assert_eq(main.room.room_id, &"vault")

func test_an_unusable_save_offers_only_new_game() -> void:
	main = GAME.instantiate()
	main.store = SaveStore.new()
	main.store.path = "user://test_title_%d.json" % randi()
	var file := FileAccess.open(main.store.path, FileAccess.WRITE)
	file.store_string("garbage")
	file.close()
	add_child_autofree(main)
	await wait_physics_frames(3)
	assert_false(_title().find_child("ContinueButton").visible)
