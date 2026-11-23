# tests/visual/test_vault_look.gd
extends GutTest
## The vault built from the stone kit: its gameplay positions stay where they were, it is drawn with
## kit pieces only, clicks between its piers reach the floor, and it keeps within its light and
## triangle budgets.

const VAULT: PackedScene = preload("res://scenes/rooms/vault_room.tscn")
const MAIN: PackedScene = preload("res://scenes/main.tscn")
## How far a gameplay position may move from where it was in the grey-box vault, in metres.
const MOVE: float = 0.5
## Where each marker, door and pier stood in the grey-box vault (x and z; height does not count).
const OLD_POSITIONS: Dictionary = {
	"Entry_start": Vector2(-10, 0),
	"Entry_start/Companion1": Vector2(-10, 1.5),
	"Entry_start/Companion2": Vector2(-10, -1.5),
	"Entry_from_haven": Vector2(-10, 0),
	"Entry_from_haven/Companion1": Vector2(-10, 1.5),
	"Entry_from_haven/Companion2": Vector2(-10, -1.5),
	"EnemySpawn1": Vector2(0.5, 0),
	"EnemySpawn2": Vector2(1.5, -1.5),
	"EnemySpawn3": Vector2(1.5, 1.5),
	"EnemySpawn4": Vector2(9, 0),
	"EnemySpawn5": Vector2(10, -2),
	"EnemySpawn6": Vector2(10, 2),
	"WestDoor": Vector2(-11.85, 3),
	"LastLock": Vector2(11.85, -5),
	"NavigationRegion3D/Pillars/Pillar1": Vector2(-6, -3.5),
	"NavigationRegion3D/Pillars/Pillar2": Vector2(0, -3.5),
	"NavigationRegion3D/Pillars/Pillar3": Vector2(6, -3.5),
	"NavigationRegion3D/Pillars/Pillar4": Vector2(-6, 3.5),
	"NavigationRegion3D/Pillars/Pillar5": Vector2(0, 3.5),
	"NavigationRegion3D/Pillars/Pillar6": Vector2(6, 3.5),
}
const MAX_LIGHTS: int = 6
const MAX_SHADOWED_LIGHTS: int = 2
const MAX_TRIANGLES: int = 150000

var story: Main


func after_each() -> void:
	Story.finish(story)


func _flat(at: Vector3) -> Vector2:
	return Vector2(at.x, at.z)


func _vault() -> Room:
	var room: Room = add_child_autofree(VAULT.instantiate())
	var map: RID = room.get_world_3d().navigation_map
	var region: RID = (room.get_node("NavigationRegion3D") as NavigationRegion3D).get_rid()
	# Until the region has taken its navmesh in, and the map the region after that.
	await wait_until(func() -> bool: return NavigationServer3D.region_get_iteration_id(region) > 0, 2.0)
	var before: int = NavigationServer3D.map_get_iteration_id(map)
	await wait_until(func() -> bool: return NavigationServer3D.map_get_iteration_id(map) > before, 2.0)
	return room


func test_markers_doors_and_piers_stay_put_and_markers_and_doors_are_on_the_navmesh() -> void:
	var room: Room = await _vault()
	var map: RID = room.get_world_3d().navigation_map
	for path: String in OLD_POSITIONS:
		var node := room.get_node_or_null(path) as Node3D
		assert_not_null(node, path)
		if node == null:
			continue
		var moved: float = _flat(node.global_position).distance_to(OLD_POSITIONS[path])
		assert_lte(moved, MOVE, "%s moved %.2f m" % [path, moved])
		if path.begins_with("NavigationRegion3D"):
			continue
		# A door stands in its wall; Álvar uses it from its use mark, which must be walkable.
		var stand: Vector3 = node.global_position
		if node is Door:
			stand = node.global_transform * (node as Door).use_mark_position()
		var closest: Vector3 = NavigationServer3D.map_get_closest_point(map, stand)
		assert_lt(_flat(closest).distance_to(_flat(stand)), 0.05, "%s stands on the navmesh" % path)


func test_the_room_is_drawn_with_kit_pieces_only() -> void:
	var room: Room = await _vault()
	for node: Node in room.find_children("*", "MeshInstance3D", true, false):
		var mesh: Mesh = (node as MeshInstance3D).mesh
		assert_false(mesh is BoxMesh, "%s is a box" % room.get_path_to(node))
		assert_false(mesh is CapsuleMesh, "%s is a capsule" % room.get_path_to(node))


func test_a_click_on_the_floor_between_two_piers_orders_a_move_there() -> void:
	var main: Main = add_child_autofree(MAIN.instantiate())
	await wait_physics_frames(3)
	for enemy: Unit in main.enemies:
		enemy.get_node("Brain").free()
		enemy.global_position.x = 11.0
	main.player.global_position = Vector3(-3, 0, 0)
	main.rig.snap_to_target()
	await wait_physics_frames(3)
	# Midway between the two western piers of each row, under the arch that springs between them.
	for spot: Vector3 in [Vector3(-3, 0, -3.5), Vector3(-3, 0, 3.5)]:
		main.input.click_at(main.rig.camera().unproject_position(spot))
		await wait_for_signal(main.player.arrived, 4.0)
		assert_lt(_flat(main.player.global_position).distance_to(_flat(spot)), 0.5, "walked to %s" % spot)


func test_the_room_has_at_most_six_lights_and_two_shadows() -> void:
	var room: Room = await _vault()
	var lights: Array[Node] = room.find_children("*", "Light3D", true, false)
	assert_lte(lights.size(), MAX_LIGHTS)
	var shadowed: int = lights.filter(func(light: Light3D) -> bool: return light.shadow_enabled).size()
	assert_lte(shadowed, MAX_SHADOWED_LIGHTS)


func test_the_room_draws_fewer_than_150000_triangles() -> void:
	var room: Room = await _vault()
	var triangles: int = 0
	for node: Node in room.find_children("*", "MeshInstance3D", true, false):
		var instance := node as MeshInstance3D
		if not instance.is_visible_in_tree() or instance.mesh == null:
			continue
		triangles += instance.mesh.get_faces().size() / 3
	gut.p("the vault draws %d triangles" % triangles)
	assert_lt(triangles, MAX_TRIANGLES)


func test_the_arcade_and_the_wall_on_the_camera_side_are_cut_at_each_turn() -> void:
	var main: Main = add_child_autofree(MAIN.instantiate())
	await wait_physics_frames(3)
	var north := main.room.get_node("NavigationRegion3D/Arcades/North") as Node3D
	var south := main.room.get_node("NavigationRegion3D/Arcades/South") as Node3D
	var walls: Array[Node3D] = []
	for side: String in ["North", "West", "South", "East"]:
		walls.append(main.room.get_node("NavigationRegion3D/Walls/" + side) as Node3D)
	# Looking north, then west, south and east, a quarter turn at a time.
	var expected: Array = [[true, false], [true, true], [false, true], [true, true]]
	for turn: int in 4:
		await wait_process_frames(2)
		assert_eq([north.visible, south.visible], expected[turn], "turn %d: north and south arcades drawn" % turn)
		for side: int in 4:
			# The wall behind the camera is the one two quarter turns from the way it looks.
			assert_eq(walls[side].visible, side != (turn + 2) % 4, "turn %d: %s wall drawn" % [turn, walls[side].name])
		main.rig.rotate_by(PI / 2)


## Clear of the gift bar (56 px, bottom-anchored) with room for a unit's rings, on a 720 px frame.
const BOTTOM_CLEAR_PX: float = 80.0


func test_a_unit_at_the_camera_side_wall_stands_clear_of_the_gift_bar_at_each_turn() -> void:
	var main: Main = add_child_autofree(MAIN.instantiate())
	await wait_physics_frames(3)
	for enemy: Unit in main.enemies:
		enemy.get_node("Brain").free()
	var view: Vector2 = main.get_viewport().get_visible_rect().size
	var lowest: float = view.y - BOTTOM_CLEAR_PX * view.y / 720.0
	# The walkable edge 0.4 m inside the wall nearest the camera, as the camera looks north, west,
	# south and east.
	var edges: Array[Vector3] = [Vector3(0, 0, 7.6), Vector3(11.6, 0, 0), Vector3(0, 0, -7.6), Vector3(-11.6, 0, 0)]
	for turn: int in 4:
		main.player.global_position = edges[turn]
		main.rig.snap_to_target()
		var feet: Vector2 = main.rig.camera().unproject_position(edges[turn])
		assert_true(Rect2(Vector2.ZERO, view).has_point(feet), "turn %d: the feet at %s are on screen" % [turn, feet])
		assert_lte(feet.y, lowest, "turn %d: the feet are %.0f px above the bottom" % [turn, view.y - feet.y])
		main.rig.rotate_by(PI / 2)


func test_the_west_door_is_cut_with_its_wall_and_can_still_be_used() -> void:
	story = Story.boot(self, GameState.skirmish())
	await wait_physics_frames(3)
	for enemy: Unit in story.enemies:
		enemy.take_hit(Arena.LETHAL)
	await wait_physics_frames(3)
	# The story's vault, cleared, says the story rests here: the card is dismissed to play on.
	assert_true(story.is_closing_open())
	story.hud.hide_closing()
	var door := story.room.get_node("WestDoor") as Door
	var leaf := door.get_node("Leaf") as Node3D
	var frame := story.room.get_node("NavigationRegion3D/Walls/West/West6") as Node3D
	story.player.global_position = Vector3(-8, 0, 3)
	# Looking east: the west wall, the door's, is behind the camera.
	story.rig.rotate_by(-PI / 2)
	await wait_process_frames(3)
	assert_false(frame.is_visible_in_tree(), "the frame is cut with its wall")
	assert_false(leaf.is_visible_in_tree(), "the leaf is cut with its frame")
	story.rig.rotate_by(PI / 2)
	await wait_process_frames(3)
	assert_true(frame.is_visible_in_tree(), "the frame is drawn again")
	assert_true(leaf.is_visible_in_tree(), "and the leaf with it")
	story.rig.rotate_by(-PI / 2)
	await wait_process_frames(3)
	# Who used it, by member id: going through the door replaces the party.
	var users: Array[StringName] = []
	door.used.connect(func(by: Unit) -> void: users.append(by.member_id))
	story.player.order_interact(door)
	await wait_until(func() -> bool: return not users.is_empty(), 10.0)
	assert_eq(users, [GameState.LEADER] as Array[StringName], "Álvar walked up to the door and used it")


func test_the_last_locks_seal_is_cut_with_its_wall_and_the_lock_can_still_be_used() -> void:
	story = Story.boot(self, GameState.skirmish())
	await wait_physics_frames(3)
	for enemy: Unit in story.enemies:
		enemy.take_hit(Arena.LETHAL)
	await wait_physics_frames(3)
	assert_true(story.is_closing_open())
	story.hud.hide_closing()
	var lock := story.room.get_node("LastLock") as Door
	var seal := lock.get_node("Seal") as Node3D
	var leaf := lock.get_node("Leaf") as Node3D
	var frame := story.room.get_node("NavigationRegion3D/Walls/East/East2") as Node3D
	story.player.global_position = Vector3(8, 0, -3)
	# Looking west: the east wall, the lock's, is behind the camera.
	story.rig.rotate_by(PI / 2)
	await wait_process_frames(3)
	assert_false(frame.is_visible_in_tree(), "the frame is cut with its wall")
	assert_false(seal.is_visible_in_tree(), "the seal is cut with its frame")
	assert_false(leaf.is_visible_in_tree(), "the sealed lock shows no leaf")
	story.rig.rotate_by(-PI / 2)
	await wait_process_frames(3)
	assert_true(frame.is_visible_in_tree(), "the frame is drawn again")
	assert_true(seal.is_visible_in_tree(), "and the seal with it")
	assert_false(leaf.is_visible_in_tree(), "and still no leaf")
	story.rig.rotate_by(PI / 2)
	await wait_process_frames(3)
	var users: Array[StringName] = []
	lock.used.connect(func(by: Unit) -> void: users.append(by.member_id))
	story.player.order_interact(lock)
	await wait_until(func() -> bool: return not users.is_empty(), 10.0)
	assert_eq(users, [GameState.LEADER] as Array[StringName], "Álvar walked up to the lock and used it")
	assert_eq(story.hud.notice(), "The last lock does not yield. This is where the story rests, for now.")


## A unit by the west wall, where the camera's focus is held, at the story's entry from the haven:
## it stands right of the party panels or below them, not under them.
func test_a_unit_at_the_west_wall_by_the_entry_stands_clear_of_the_party_panels() -> void:
	# The frame the game is played and shown in, not the headless window's square one.
	var window_size: Vector2i = get_tree().root.size
	get_tree().root.size = Vector2i(1280, 720)
	story = Story.boot(self, PageBoot.haven_finished())
	await wait_physics_frames(3)
	assert_eq(story.room.room_id, &"vault")
	assert_eq(story.party.size(), 3)
	story.rig.snap_to_target()
	await wait_process_frames(2)
	var panels: Rect2 = (story.hud.find_child("PartyColumn") as Control).get_global_rect()
	assert_gt(panels.size.y, 200.0, "three panels")
	var map: RID = story.get_world_3d().navigation_map
	var entry: Vector3 = story.player.global_position
	for z: float in [entry.z - 1.5, entry.z, entry.z + 1.5]:
		var edge: Vector3 = NavigationServer3D.map_get_closest_point(map, Vector3(-12.0, 0.0, z))
		var at: Vector2 = story.rig.camera().unproject_position(edge)
		assert_true(at.x > panels.end.x or at.y > panels.end.y,
				"a unit at %s is drawn at %s, clear of the panels %s" % [edge, at, panels])
	get_tree().root.size = window_size


## Turned a quarter, so the south wall is at the screen's left, where the party panels are: a unit by
## that wall stands right of the panels or below them, as it does by the west wall unturned.
func test_turned_a_quarter_a_unit_at_the_wall_on_the_left_stands_clear_of_the_party_panels() -> void:
	var window_size: Vector2i = get_tree().root.size
	get_tree().root.size = Vector2i(1280, 720)
	story = Story.boot(self, PageBoot.haven_finished())
	await wait_physics_frames(3)
	assert_eq(story.party.size(), 3)
	var map: RID = story.get_world_3d().navigation_map
	story.rig.rotate_by(PI / 2)
	story.player.global_position = NavigationServer3D.map_get_closest_point(map, Vector3(0.0, 0.0, 20.0))
	story.rig.snap_to_target()
	await wait_process_frames(2)
	var panels: Rect2 = (story.hud.find_child("PartyColumn") as Control).get_global_rect()
	var camera: Camera3D = story.rig.camera()
	var x: float = story.player.global_position.x
	for along: float in [x - 1.5, x, x + 1.5]:
		var edge: Vector3 = NavigationServer3D.map_get_closest_point(map, Vector3(along, 0.0, 20.0))
		var at: Vector2 = camera.unproject_position(edge)
		assert_lt(at.x, get_tree().root.size.x / 2.0, "the south wall is on the screen's left (%s)" % at)
		assert_true(at.x > panels.end.x or at.y > panels.end.y,
				"a unit at %s is drawn at %s, clear of the panels %s" % [edge, at, panels])
	get_tree().root.size = window_size
