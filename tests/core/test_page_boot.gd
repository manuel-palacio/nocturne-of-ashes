# tests/core/test_page_boot.gd
extends GutTest
## What the page's parameters do to the boot; off the web there are none.

func test_off_the_web_every_parameter_reads_as_absent() -> void:
	assert_eq(PageParams.value("probe"), "")
	assert_false(PageParams.is_on("skirmish"))

func test_off_the_web_the_story_boots_as_set_up() -> void:
	var main: Main = preload("res://scenes/game.tscn").instantiate()
	PageBoot.configure(main)
	assert_eq(main.boot, Main.Boot.STORY)
	assert_null(main.state)
	assert_true(main.show_title)
	main.free()

func test_a_finished_haven_enters_the_vault_with_everyone() -> void:
	var state: GameState = PageBoot.haven_finished()
	assert_eq(state.room, &"vault")
	assert_eq(state.entry, &"from_haven")
	assert_eq(state.joined(), GameState.MEMBERS)
	assert_eq(state.known_gifts(&"alvar"), [&"iron_sinew", &"baleful_eye"] as Array[StringName])
	for flag: StringName in [&"met_malakor", &"zahra_joined", &"gonzalo_joined", &"captive_done", &"order_given"]:
		assert_true(state.has_flag(flag), String(flag))
	assert_eq(state.conscience, GameState.CONSCIENCE_START)

func _story_with_a_save() -> Main:
	var main: Main = preload("res://scenes/game.tscn").instantiate()
	main.store = SaveStore.new()
	main.store.path = "user://test_page_boot_%d.json" % randi()
	main.store.save(GameState.new_game())
	return main

func test_fresh_without_probe_clears_nothing() -> void:
	var main: Main = _story_with_a_save()
	PageBoot.configure(main, {"fresh": "1"})
	assert_true(main.store.has_save())
	main.store.clear()
	main.free()

func test_fresh_with_probe_clears_the_save() -> void:
	var main: Main = _story_with_a_save()
	PageBoot.configure(main, {"fresh": "1", "probe": "1"})
	assert_false(main.store.has_save())
	assert_null(main.state)
	main.free()

func test_skirmish_leaves_a_save_untouched_even_with_fresh_and_probe() -> void:
	var main: Main = _story_with_a_save()
	var store: SaveStore = main.store
	PageBoot.configure(main, {"skirmish": "1", "fresh": "1", "probe": "1"})
	assert_eq(main.boot, Main.Boot.SKIRMISH)
	assert_true(store.has_save())
	store.clear()
	main.free()

func test_at_vault_without_probe_does_nothing() -> void:
	var main: Main = _story_with_a_save()
	PageBoot.configure(main, {"at": "vault", "fresh": "1"})
	assert_null(main.state)
	assert_true(main.show_title)
	assert_true(main.opening_enabled)
	assert_true(main.store.has_save())
	main.store.clear()
	main.free()
