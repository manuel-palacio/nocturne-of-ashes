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
	main.opening_enabled = false
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

func test_a_checkpoint_while_the_title_is_open_keeps_the_save() -> void:
	var saved := GameState.skirmish()
	saved.change_conscience(-4)
	await _boot_with_title(saved)
	watch_signals(main)
	main.checkpoint()
	assert_signal_not_emitted(main, "checkpoint_saved")
	assert_eq(main.store.load_state().conscience, 3)
	assert_eq(main.store.load_state().room, &"vault")

func test_pause_does_nothing_while_the_title_is_open() -> void:
	await _boot_with_title(null)
	Input.action_press("pause")
	await wait_physics_frames(2)
	Input.action_release("pause")
	await wait_physics_frames(2)
	assert_false(main.is_paused())
	assert_true(_title().is_open())

func test_a_reload_closes_the_title_and_turns_input_on() -> void:
	await _boot_with_title(GameState.skirmish())
	main.reload_checkpoint()
	await wait_physics_frames(3)
	assert_false(_title().is_open())
	assert_true(main.input.enabled)
	assert_eq(main.room.room_id, &"vault")

func test_a_reload_from_the_title_over_an_unusable_save_warns_once_and_starts_a_new_game() -> void:
	main = GAME.instantiate()
	main.store = SaveStore.new()
	main.store.path = "user://test_title_%d.json" % randi()
	var file := FileAccess.open(main.store.path, FileAccess.WRITE)
	file.store_string("garbage")
	file.close()
	add_child_autofree(main)
	await wait_physics_frames(3)
	assert_push_warning_count(0)  # finding a save at boot does not read it
	main.reload_checkpoint()  # nothing in memory yet: the store is read
	await wait_physics_frames(3)
	assert_push_warning("save")
	assert_push_warning_count(1)
	assert_eq(main.room.room_id, &"haven")
	assert_eq(main.state.conscience, 7)
	assert_true(main.store.has_save())

## The saves line in Spanish, the longest of the title's texts, wraps inside the screen at 1280 × 720
## and at 800 × 500, clear of the preparing line below it and of the buttons above.
func test_the_saves_line_fits_in_spanish_wide_and_small() -> void:
	await _boot_with_title(null)
	var window_size: Vector2i = get_tree().root.size
	Language.apply("es")
	var title: TitleScreen = _title()
	title.show_storage_warning(true)
	var line := title.find_child("StorageLabel") as Label
	var preparing := title.find_child("PreparingLabel") as Label
	var controls := title.find_child("ControlsButton") as Control
	for size: Vector2i in [Vector2i(1280, 720), Vector2i(800, 500)]:
		get_tree().root.size = size
		await wait_physics_frames(2)
		var what: String = str(size)
		assert_eq(line.text, "Este navegador no guarda las partidas: el progreso dura hasta que se cierre la página.")
		assert_eq(line.autowrap_mode, TextServer.AUTOWRAP_WORD_SMART)
		assert_lte(line.get_line_count(), 2, what)
		var view: Vector2 = line.get_viewport_rect().size
		var drawn: Rect2 = line.get_global_rect()
		assert_gte(drawn.position.x, 0.0, what)
		assert_lte(drawn.end.x, view.x, what)
		assert_lte(drawn.end.y, preparing.get_global_rect().position.y + 0.5, what)
		var text_top: float = drawn.end.y - line.get_line_count() * line.get_line_height()
		assert_gte(text_top, controls.get_global_rect().end.y, what)
	TranslationServer.set_locale("en")
	get_tree().root.size = window_size
	await wait_physics_frames(2)
