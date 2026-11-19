# tests/core/test_shader_warmup.gd
extends GutTest
## The rooms are drawn off screen behind the title, one a frame, and nothing of them is left once the
## game starts.

const GAME := preload("res://scenes/game.tscn")
const HAVEN := preload("res://scenes/rooms/forge_haven.tscn")
const VAULT := preload("res://scenes/rooms/vault_room.tscn")

var main: Main


func after_each() -> void:
	if main != null:
		Story.finish(main)
	main = null


## What each off-screen view holds, as it is added: its room, whether it has a world of its own, the
## marks and cameras beside the room.
func _describe(view: Node) -> String:
	var beside: Array[Node] = view.get_children().slice(1)
	return "%s own=%s rings=%d cameras=%d" % [(view.get_child(0) as Room).room_id,
			(view as SubViewport).own_world_3d,
			beside.filter(func(node: Node) -> bool: return node is FloorRing).size(),
			beside.filter(func(node: Node) -> bool: return node is Camera3D).size()]


func test_each_room_is_drawn_once_in_its_own_world_with_a_ring_then_freed() -> void:
	var warmup: ShaderWarmup = add_child_autofree(ShaderWarmup.new())
	var seen: Array[String] = []
	warmup.child_entered_tree.connect(func(view: Node) -> void: seen.append(_describe(view)))
	warmup.start([HAVEN, VAULT])
	assert_true(warmup.is_warming())
	assert_null(warmup.view(), "the title is drawn first")
	await wait_until(func() -> bool: return not warmup.is_warming(), 2.0)
	assert_eq(seen, [
		"haven own=true rings=1 cameras=1", "vault own=true rings=1 cameras=1",
	] as Array[String])
	assert_false(warmup.is_warming())
	assert_null(warmup.view())
	assert_eq(warmup.get_child_count(), 0)


func test_stop_frees_the_room_being_drawn() -> void:
	var warmup: ShaderWarmup = add_child_autofree(ShaderWarmup.new())
	warmup.start([HAVEN, VAULT])
	await wait_until(func() -> bool: return warmup.view() != null, 2.0)
	assert_not_null(warmup.view())
	warmup.stop()
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
	assert_true(warmup.is_warming(), "warming behind the title")
	await wait_until(func() -> bool: return warmup.view() != null, 2.0)
	(main.find_child("TitleScreen") as TitleScreen).new_game_chosen.emit()
	await wait_physics_frames(2)
	assert_false(warmup.is_warming())
	assert_null(warmup.view())
	assert_eq(main.room.room_id, &"haven")
	assert_eq(get_tree().get_nodes_in_group(&"interactables").filter(
			func(node: Node) -> bool: return not main.is_ancestor_of(node)).size(), 0,
			"no person or door of the warmup is left")


func test_without_the_title_nothing_is_warmed() -> void:
	main = add_child_autofree(preload("res://scenes/main.tscn").instantiate())
	await wait_physics_frames(2)
	assert_false((main.find_child("ShaderWarmup") as ShaderWarmup).is_warming())
