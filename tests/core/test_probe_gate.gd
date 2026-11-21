# tests/core/test_probe_gate.gd
extends GutTest
## Whether the page may use the probe and its test parameters: only with `probe=1`, and never in the
## public build (the `public` feature).

## A feature lookup as in the public build.
func _public(feature: String) -> bool:
	return feature == ProbeGate.PUBLIC_FEATURE

## A feature lookup as in the test build.
func _test_build(_feature: String) -> bool:
	return false

func test_the_test_build_allows_the_probe_with_probe_1() -> void:
	assert_true(ProbeGate.allows({"probe": "1"}, _test_build))

func test_the_test_build_refuses_it_without_probe_1() -> void:
	assert_false(ProbeGate.allows({}, _test_build))
	assert_false(ProbeGate.allows({"probe": "0"}, _test_build))
	assert_false(ProbeGate.allows({"fresh": "1", "calm": "1"}, _test_build))

func test_the_public_build_refuses_it_whatever_the_parameters_say() -> void:
	for params: Dictionary in [
		{}, {"probe": "1"}, {"probe": "1", "fresh": "1", "title": "1"},
		{"probe": "1", "calm": "1", "frail": "1", "at": "vault"},
	]:
		assert_false(ProbeGate.allows(params, _public), str(params))

func test_off_the_web_there_is_no_probe() -> void:
	assert_false(ProbeGate.allows())

func _story_with_a_save() -> Main:
	var main: Main = preload("res://scenes/game.tscn").instantiate()
	main.store = SaveStore.new()
	main.store.path = "user://test_probe_gate_%d.json" % randi()
	main.store.save(GameState.new_game())
	return main

func test_the_public_build_ignores_fresh_title_and_at() -> void:
	var main: Main = _story_with_a_save()
	PageBoot.configure(main, {"probe": "1", "fresh": "1", "at": "vault", "title": "0"}, _public)
	assert_true(main.store.has_save(), "the save is kept")
	assert_eq(main.boot, Main.Boot.STORY)
	assert_null(main.state)
	assert_true(main.show_title, "the title shows as for a visitor")
	assert_true(main.opening_enabled)
	main.store.clear()
	main.free()

func test_the_public_build_does_not_skip_the_title() -> void:
	var main: Main = _story_with_a_save()
	PageBoot.configure(main, {"probe": "1", "calm": "1", "frail": "1"}, _public)
	assert_true(main.show_title)
	assert_null(main.state, "nothing is loaded before the title")
	main.store.clear()
	main.free()

func test_the_public_build_still_plays_the_skirmish() -> void:
	var main: Main = _story_with_a_save()
	var store: SaveStore = main.store
	PageBoot.configure(main, {"skirmish": "1", "probe": "1", "fresh": "1"}, _public)
	assert_eq(main.boot, Main.Boot.SKIRMISH)
	assert_null(main.store)
	assert_true(store.has_save())
	store.clear()
	main.free()

func test_the_public_build_still_reads_the_language_from_the_page() -> void:
	assert_eq(Language.requested_from_page({"lang": "es", "probe": "1"}), "es")
