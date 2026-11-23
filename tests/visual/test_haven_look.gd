# tests/visual/test_haven_look.gd
extends GutTest
## The forge-haven built from the stone kit: its markers, people and stair door stay where they were
## and stand on the navmesh, it is drawn with kit pieces only, everyone in it can still be walked up to
## and spoken with, and it keeps within its light and triangle budgets.

const HAVEN: PackedScene = preload("res://scenes/rooms/forge_haven.tscn")
## How far a gameplay position may move from where it was in the grey-box haven, in metres.
const MOVE: float = 0.5
## Where each marker, person and door stood in the grey-box haven (x and z; height does not count).
const OLD_POSITIONS: Dictionary = {
	"Entry_start": Vector2(-7, 0),
	"Entry_start/Companion1": Vector2(-7, 1.5),
	"Entry_start/Companion2": Vector2(-7, -1.5),
	# Moved west from (7, 0) so that on arrival from the vault Malakor stands clear of the party panels.
	"Entry_from_vault": Vector2(1.5, -0.8),
	"Entry_from_vault/Companion1": Vector2(1.5, 0.7),
	"Entry_from_vault/Companion2": Vector2(3, -1.3),
	"StairDoor": Vector2(8.85, 2.5),
	"Malakor": Vector2(-2.2, -4.2),
	"Smith": Vector2(2.6, -3.5),
	"Captive": Vector2(-7.6, 4.7),
	"ZahraNpc": Vector2(6, 4.4),
	"GonzaloNpc": Vector2(6.5, -4.3),
}
## Who sits behind bars, off the walkable floor: he is spoken with across them, from the floor in
## front, which `test_everyone_can_be_walked_up_to_and_spoken_with` checks. His bench belongs to the
## cell, not to him, so it stays, drawn and solid, once he is gone.
const BEHIND_BARS: Array[String] = ["Captive"]
const MAX_LIGHTS: int = 6
const MAX_SHADOWED_LIGHTS: int = 2
const MAX_TRIANGLES: int = 150000

var main: Main


func after_each() -> void:
	Story.finish(main)


func _flat(at: Vector3) -> Vector2:
	return Vector2(at.x, at.z)


func _haven() -> Room:
	var room: Room = add_child_autofree(HAVEN.instantiate())
	var map: RID = room.get_world_3d().navigation_map
	var region: RID = (room.get_node("NavigationRegion3D") as NavigationRegion3D).get_rid()
	# Until the region has taken its navmesh in, and the map the region after that.
	await wait_until(func() -> bool: return NavigationServer3D.region_get_iteration_id(region) > 0, 2.0)
	var before: int = NavigationServer3D.map_get_iteration_id(map)
	await wait_until(func() -> bool: return NavigationServer3D.map_get_iteration_id(map) > before, 2.0)
	return room


## The haven after the waking, Álvar alone, with no conversation open.
func _after_waking() -> GameState:
	var state := GameState.new_game()
	state.set_flag(&"met_malakor")
	state.learn(&"alvar", &"iron_sinew")
	return state


func test_markers_people_and_the_door_stay_put_and_stand_on_the_navmesh() -> void:
	var room: Room = await _haven()
	var map: RID = room.get_world_3d().navigation_map
	for path: String in OLD_POSITIONS:
		var node := room.get_node_or_null(path) as Node3D
		assert_not_null(node, path)
		if node == null:
			continue
		var moved: float = _flat(node.global_position).distance_to(OLD_POSITIONS[path])
		assert_lte(moved, MOVE, "%s moved %.2f m" % [path, moved])
		if path in BEHIND_BARS:
			continue
		# A door stands in its wall; Álvar uses it from its use mark, which must be walkable.
		var stand: Vector3 = node.global_position
		if node is Door:
			stand = node.global_transform * (node as Door).use_mark_position()
		var closest: Vector3 = NavigationServer3D.map_get_closest_point(map, stand)
		assert_lt(_flat(closest).distance_to(_flat(stand)), 0.05, "%s stands on the navmesh" % path)


func test_the_room_is_drawn_with_kit_pieces_only() -> void:
	var room: Room = await _haven()
	for node: Node in room.find_children("*", "MeshInstance3D", true, false):
		var mesh: Mesh = (node as MeshInstance3D).mesh
		assert_false(mesh is BoxMesh, "%s is a box" % room.get_path_to(node))
		assert_false(mesh is CapsuleMesh, "%s is a capsule" % room.get_path_to(node))
		assert_false(mesh is QuadMesh, "%s is a quad" % room.get_path_to(node))


func test_everyone_can_be_walked_up_to_and_spoken_with() -> void:
	main = Story.boot(self, _after_waking())
	await wait_physics_frames(3)
	var npcs: Array[Npc] = main.room.npcs()
	assert_eq(npcs.size(), 5, "five people stand in the haven")
	for npc: Npc in npcs:
		watch_signals(npc)
	for index: int in npcs.size():
		var npc: Npc = npcs[index]
		# From the middle of the room each time.
		main.player.global_position = Vector3.ZERO
		await wait_physics_frames(2)
		main.player.order_interact(npc)
		await wait_until(func() -> bool: return get_signal_emit_count(npc, "used") > 0, 15.0)
		assert_signal_emitted_with_parameters(npc, "used", [main.player])
		# Only the one ordered was used, and each of those before once.
		for other: int in npcs.size():
			assert_signal_emit_count(npcs[other], "used", 1 if other <= index else 0,
					"%s used when %s was ordered" % [npcs[other].name, npc.name])
		# Through the conversation, the first choice each time, before the next.
		var guard: int = 0
		while main.is_talking() and guard < 60:
			guard += 1
			var buttons: Array[Node] = main.find_child("DialogueBox").find_child("Choices").get_children()
			if buttons.size() > 0:
				main.dialogue.choose(0)
			else:
				main.dialogue.advance()
			await wait_physics_frames(2)
		assert_false(main.is_talking(), "the talk with %s ended" % npc.name)


func test_the_room_has_at_most_six_lights_and_two_shadows() -> void:
	var room: Room = await _haven()
	var lights: Array[Node] = room.find_children("*", "Light3D", true, false)
	assert_lte(lights.size(), MAX_LIGHTS)
	var shadowed: int = lights.filter(func(light: Light3D) -> bool: return light.shadow_enabled).size()
	assert_lte(shadowed, MAX_SHADOWED_LIGHTS)


func test_the_room_draws_fewer_than_150000_triangles() -> void:
	var room: Room = await _haven()
	var triangles: int = 0
	for node: Node in room.find_children("*", "MeshInstance3D", true, false):
		var instance := node as MeshInstance3D
		if not instance.is_visible_in_tree() or instance.mesh == null:
			continue
		triangles += instance.mesh.get_faces().size() / 3
	gut.p("the haven draws %d triangles" % triangles)
	assert_lt(triangles, MAX_TRIANGLES)


func test_the_wall_on_the_camera_side_is_cut_at_each_turn_and_the_cell_bars_never() -> void:
	main = Story.boot(self, _after_waking())
	await wait_physics_frames(3)
	var walls: Array[Node3D] = []
	for side: String in ["North", "West", "South", "East"]:
		walls.append(main.room.get_node("NavigationRegion3D/Walls/" + side) as Node3D)
	var bars: Array[Node] = main.room.get_node("NavigationRegion3D/Props/Cell").find_children("Bars*", "", true, false)
	assert_eq(bars.size(), 3, "the cell has three grilles")
	# Looking north, then west, south and east, a quarter turn at a time.
	for turn: int in 4:
		await wait_process_frames(2)
		for side: int in 4:
			# The wall behind the camera is the one two quarter turns from the way it looks.
			assert_eq(walls[side].visible, side != (turn + 2) % 4, "turn %d: %s wall drawn" % [turn, walls[side].name])
		# The grilles are seen through, so the captive stays behind his bars from every side.
		for grille: Node in bars:
			assert_true((grille as Node3D).is_visible_in_tree(), "turn %d: %s drawn" % [turn, grille.get_path()])
		main.rig.rotate_by(PI / 2)


func test_the_stair_door_is_cut_with_its_wall_and_can_still_be_used() -> void:
	main = Story.boot(self, _after_waking())
	await wait_physics_frames(3)
	var door := main.room.get_node("StairDoor") as Door
	var leaf := door.get_node("Leaf") as Node3D
	var frame := main.room.get_node("NavigationRegion3D/Walls/East/StairFrame") as Node3D
	main.player.global_position = Vector3(5, 0, 2.5)
	# Looking west: the east wall, the door's, is behind the camera.
	main.rig.rotate_by(PI / 2)
	await wait_process_frames(3)
	assert_false(frame.is_visible_in_tree(), "the frame is cut with its wall")
	assert_false(leaf.is_visible_in_tree(), "the leaf is cut with its frame")
	# Who used it, by member id: going through the door replaces the party.
	var users: Array[StringName] = []
	door.used.connect(func(by: Unit) -> void: users.append(by.member_id))
	main.player.order_interact(door)
	await wait_until(func() -> bool: return not users.is_empty(), 10.0)
	assert_eq(users, [GameState.LEADER] as Array[StringName], "Álvar walked up to the door and used it")
	main.rig.rotate_by(-PI / 2)
	await wait_process_frames(3)
	assert_true(frame.is_visible_in_tree(), "the frame is drawn again")
	assert_true(leaf.is_visible_in_tree(), "and the leaf with it")


## At a new game's first frame, a unit by the west wall stands right of the party panel or below it,
## not under it.
func test_at_the_waking_a_unit_at_the_west_wall_stands_clear_of_the_party_panel() -> void:
	# The frame the game is played and shown in, not the headless window's square one.
	var window_size: Vector2i = get_tree().root.size
	get_tree().root.size = Vector2i(1280, 720)
	main = Story.boot(self)
	await wait_physics_frames(3)
	assert_eq(main.room.room_id, &"haven")
	main.rig.snap_to_target()
	await wait_process_frames(2)
	var panels: Rect2 = (main.hud.find_child("PartyColumn") as Control).get_global_rect()
	var map: RID = main.get_world_3d().navigation_map
	var entry: Vector3 = main.player.global_position
	for z: float in [entry.z - 1.5, entry.z, entry.z + 1.5]:
		var edge: Vector3 = NavigationServer3D.map_get_closest_point(map, Vector3(-9.0, 0.0, z))
		var at: Vector2 = main.rig.camera().unproject_position(edge)
		assert_true(at.x > panels.end.x or at.y > panels.end.y,
				"a unit at %s is drawn at %s, clear of the panel %s" % [edge, at, panels])
	get_tree().root.size = window_size
