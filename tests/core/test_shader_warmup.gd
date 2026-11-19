# tests/core/test_shader_warmup.gd
extends GutTest
## The rooms are drawn off screen behind the title, a few kinds of thing a frame, and nothing of them
## is left once the game starts.

const GAME := preload("res://scenes/game.tscn")
const HAVEN := preload("res://scenes/rooms/forge_haven.tscn")
const VAULT := preload("res://scenes/rooms/vault_room.tscn")

var main: Main


func after_each() -> void:
	if main != null:
		Story.finish(main)
	main = null


## What the off-screen view shows now: its room, whether it has a world of its own, its rings beside
## the room, and how many of the room's drawn things and shadows are showing; "" for no view.
func _describe(warmup: ShaderWarmup) -> String:
	var view: SubViewport = warmup.view()
	if view == null:
		return ""
	var room := view.get_child(0) as Room
	var showing: int = room.find_children("*", "GeometryInstance3D", true, false).filter(
			func(node: Node) -> bool: return (node as GeometryInstance3D).visible).size()
	var shadows: int = room.find_children("*", "Light3D", true, false).filter(
			func(node: Node) -> bool: return (node as Light3D).shadow_enabled).size()
	var rings: int = view.get_children().filter(func(node: Node) -> bool: return node is FloorRing).size()
	return "%s own=%s rings=%d showing=%s shadows=%d" % [room.room_id, view.own_world_3d, rings,
			"none" if showing == 0 else "some", shadows]


func test_each_room_is_shown_a_kind_at_a_time_in_its_own_world_then_freed() -> void:
	var warmup: ShaderWarmup = add_child_autofree(ShaderWarmup.new())
	watch_signals(warmup)
	warmup.start([HAVEN, VAULT])
	assert_true(warmup.is_warming())
	assert_null(warmup.view(), "the title is drawn first")
	# Frame by frame, what the last frame drew: the tree's `process_frame` comes before any node's
	# `_process`.
	var frames: Array[String] = []
	var record := func() -> void:
		var now: String = _describe(warmup)
		if now != "":
			frames.append(now)
	get_tree().process_frame.connect(record)
	await wait_until(func() -> bool: return not warmup.is_warming(), 3.0)
	get_tree().process_frame.disconnect(record)
	var haven: Array[String] = frames.filter(func(line: String) -> bool: return line.begins_with("haven"))
	var vault: Array[String] = frames.filter(func(line: String) -> bool: return line.begins_with("vault"))
	assert_eq(haven.size(), 6, "the haven over six frames: %s" % [haven])
	assert_eq(vault.size(), 6, "the vault over six frames: %s" % [vault])
	assert_eq(frames.size(), 12, "nothing else drawn")
	assert_eq(haven.front(), "haven own=true rings=1 showing=none shadows=0", "first only the ring")
	assert_eq(haven.back(), "haven own=true rings=1 showing=some shadows=1", "at last all of it")
	assert_eq(vault.front(), "vault own=true rings=1 showing=none shadows=0")
	assert_eq(vault.back(), "vault own=true rings=1 showing=some shadows=2")
	assert_false(warmup.is_warming())
	assert_signal_emit_count(warmup, "finished", 1)
	assert_null(warmup.view())
	assert_eq(warmup.get_child_count(), 0)


func test_stop_frees_the_room_being_drawn() -> void:
	var warmup: ShaderWarmup = add_child_autofree(ShaderWarmup.new())
	warmup.start([HAVEN, VAULT])
	await wait_until(func() -> bool: return warmup.view() != null, 2.0)
	assert_not_null(warmup.view())
	watch_signals(warmup)
	warmup.stop()
	assert_signal_not_emitted(warmup, "finished")
	assert_false(warmup.is_warming())
	assert_null(warmup.view())
	assert_eq(warmup.get_child_count(), 0)
	await wait_process_frames(3)
	assert_null(warmup.view(), "nothing more is drawn")


func test_the_title_warms_both_rooms_and_a_new_game_stops_it() -> void:
	main = GAME.instantiate()
	main.store = SaveStore.new()
	main.store.path = "user://test_warmup_%d.json" % randi()
	main.store.clear()
	main.opening_enabled = false
	add_child_autofree(main)
	var warmup := main.find_child("ShaderWarmup") as ShaderWarmup
	var title := main.find_child("TitleScreen") as TitleScreen
	assert_true(warmup.is_warming(), "warming behind the title")
	assert_true(title.is_preparing_shown(), "the title says so")
	await wait_until(func() -> bool: return warmup.view() != null, 2.0)
	title.new_game_chosen.emit()
	await wait_physics_frames(2)
	assert_false(warmup.is_warming())
	assert_null(warmup.view())
	assert_eq(main.room.room_id, &"haven")
	assert_eq(get_tree().get_nodes_in_group(&"interactables").filter(
			func(node: Node) -> bool: return not main.is_ancestor_of(node)).size(), 0,
			"no person or door of the warmup is left")


func test_the_title_says_the_rooms_are_being_prepared_until_they_are_and_its_buttons_work() -> void:
	main = GAME.instantiate()
	main.store = SaveStore.new()
	main.store.path = "user://test_warmup_%d.json" % randi()
	main.store.clear()
	add_child_autofree(main)
	var warmup := main.find_child("ShaderWarmup") as ShaderWarmup
	var title := main.find_child("TitleScreen") as TitleScreen
	var line := title.find_child("PreparingLabel") as Label
	assert_eq(line.text, "Preparing the cellars…")
	assert_true(line.visible)
	assert_false((title.find_child("NewGameButton") as Button).disabled, "New game works meanwhile")
	await wait_until(func() -> bool: return not warmup.is_warming(), 3.0)
	assert_false(line.visible, "gone once the rooms are ready")
	assert_true(title.is_open(), "the title stays")


func test_without_the_title_nothing_is_warmed() -> void:
	main = add_child_autofree(preload("res://scenes/main.tscn").instantiate())
	await wait_physics_frames(2)
	assert_false((main.find_child("ShaderWarmup") as ShaderWarmup).is_warming())
