extends GutTest

var store: SaveStore

func before_each() -> void:
	store = SaveStore.new()
	store.path = "user://test_save_%d.json" % randi()
	store.clear()

func after_each() -> void:
	store.clear()

func _write(text: String) -> void:
	var file := FileAccess.open(store.path, FileAccess.WRITE)
	file.store_string(text)
	file.close()

func test_no_file_means_no_save() -> void:
	assert_false(store.has_save())
	assert_null(store.load_state())

func test_save_then_load() -> void:
	var state := GameState.new_game()
	state.change_conscience(-2)
	state.join(&"zahra")
	assert_true(store.save(state))
	assert_true(store.has_save())
	var back: GameState = store.load_state()
	assert_eq(back.to_dict(), state.to_dict())

func test_saving_again_replaces_the_save() -> void:
	var state := GameState.new_game()
	store.save(state)
	state.set_flag(&"met_malakor")
	store.save(state)
	assert_true(store.load_state().has_flag(&"met_malakor"))

func test_clear_removes_it() -> void:
	store.save(GameState.new_game())
	store.clear()
	assert_false(store.has_save())
	store.clear()  # clearing nothing is fine

func test_an_empty_file_is_unusable() -> void:
	_write("")
	assert_null(store.load_state())
	assert_push_warning("save")
	assert_false(store.has_save())

func test_a_file_that_is_not_json_is_unusable() -> void:
	_write("{ not json")
	assert_null(store.load_state())
	assert_push_warning("save")

func test_json_of_the_wrong_shape_is_unusable() -> void:
	_write("[1, 2, 3]")
	assert_null(store.load_state())
	assert_push_warning("save")

func test_a_save_from_another_version_is_unusable() -> void:
	var data: Dictionary = GameState.new_game().to_dict()
	data["version"] = GameState.VERSION + 1
	_write(JSON.stringify(data))
	assert_null(store.load_state())
	assert_push_warning("save")
