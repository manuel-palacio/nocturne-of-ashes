# tests/visual/test_gear_and_marks.gd
extends GutTest

const MAIN := preload("res://scenes/main.tscn")
const HAVEN := preload("res://dialogue/haven.dialogue")

## What each character wears, by the pieces' file names.
const WORN: Dictionary = {
	"alvar": ["skirt_long.glb", "mantle.glb", "sword.glb", "shield.glb"],
	"zahra": ["skirt_long.glb", "veil.glb", "staff.glb"],
	"gonzalo": ["apron.glb", "hammer.glb"],
	"crusader": ["skirt_short.glb", "helmet.glb", "sword.glb", "shield.glb"],
	"sergeant": ["skirt_short.glb", "helmet.glb", "mail_coif.glb", "sword.glb", "shield_large.glb"],
	"malakor": ["skirt_long.glb", "mantle.glb", "sword.glb"],
	"smith": ["apron.glb", "hammer.glb"],
	"captive": [],
}

var main: Main

func after_each() -> void:
	Story.finish(main)

func _skirmish() -> void:
	main = add_child_autoqfree(MAIN.instantiate())
	await wait_physics_frames(3)

## The haven after the waking, with no conversation open.
func _haven() -> void:
	var state := GameState.new_game()
	state.set_flag(&"met_malakor")
	main = Story.boot(self, state)
	await wait_physics_frames(3)

func _visual(unit: Node) -> UnitVisual:
	return unit.get_node("Visual") as UnitVisual

func _npc(label: String) -> Npc:
	for npc: Node in main.room.find_children("*", "Npc", true, false):
		if (npc as Npc).label == label:
			return npc
	return null

func _crusader() -> Unit:
	for enemy: Unit in main.enemies:
		if enemy.display_name == "Crusader":
			return enemy
	return null

func _lit(units: Array[Unit]) -> Array[Unit]:
	return units.filter(func(unit: Unit) -> bool: return unit.has_selected_mark())

## Puts Álvar at `at`, the camera on him, and waits for the marks to follow.
func _place_alvar(at: Vector3) -> void:
	main.player.global_position = at
	main.rig.snap_to_target()
	await wait_physics_frames(3)

func test_each_character_wears_its_gear() -> void:
	for dress_name: String in WORN:
		var dress: Dress = load("res://resources/dress/%s.tres" % dress_name)
		var files: Array = dress.gear.map(func(piece: GearPiece) -> String: return piece.scene.resource_path.get_file())
		assert_eq(files, WORN[dress_name], dress_name)

func test_gear_hangs_from_bones_and_stays_small() -> void:
	await _skirmish()
	var figures: Array[Unit] = []
	figures.append_array(main.party)
	figures.append_array(main.enemies)
	for unit: Unit in figures:
		var visual: UnitVisual = _visual(unit)
		var attachments: Array[Node] = visual.model().find_children("*", "BoneAttachment3D", true, false)
		# The head first, then the gear.
		var pieces: Array[GearPiece] = [visual.dress.head]
		pieces.append_array(visual.dress.gear)
		assert_eq(attachments.size(), pieces.size(), unit.name)
		for i: int in mini(attachments.size(), pieces.size()):
			var attachment := attachments[i] as BoneAttachment3D
			var piece: GearPiece = pieces[i]
			assert_true(attachment.get_parent() is Skeleton3D, "%s hangs from the skeleton" % attachment.name)
			assert_eq(attachment.bone_name, String(piece.bone), "%s of %s" % [attachment.name, unit.name])
			var meshes: Array[Node] = attachment.find_children("*", "MeshInstance3D", true, false)
			assert_gt(meshes.size(), 0, "%s has a mesh" % attachment.name)
			for mesh: MeshInstance3D in meshes:
				var triangles: int = mesh.mesh.surface_get_array_index_len(0) / 3
				assert_lt(triangles, 900 if i == 0 else 600, "%s triangles" % attachment.name)

func test_exactly_one_member_shows_the_selected_ring_and_it_follows_selection() -> void:
	await _skirmish()
	assert_eq(_lit(main.party), [main.player])
	assert_true(_visual(main.player).is_selected_mark_shown())
	var zahra: Unit = main.party[1]
	main.select(zahra)
	assert_eq(_lit(main.party), [zahra])
	assert_true(_visual(zahra).is_selected_mark_shown())
	assert_false(_visual(main.player).is_selected_mark_shown())
	main.select_next()
	assert_eq(_lit(main.party), [main.party[2]])

func test_the_selected_ring_follows_a_companions_fall_and_a_restart() -> void:
	await _skirmish()
	var zahra: Unit = main.party[1]
	main.select(zahra)
	zahra.take_hit(999)
	await wait_physics_frames(2)
	assert_eq(_lit(main.party), [main.player], "back to Álvar when Zahra falls")
	assert_false(_visual(zahra).is_selected_mark_shown())
	main.select(main.party[2])
	main.start_room()
	await wait_physics_frames(2)
	assert_eq(_lit(main.party), [main.player], "Álvar after a restart")
	assert_true(_visual(main.player).is_selected_mark_shown())

func test_the_feed_mark_is_a_drop_over_the_head_that_follows_can_feed_on() -> void:
	await _skirmish()
	var foe: Unit = _crusader()
	assert_false(_visual(foe).is_feed_mark_shown())
	foe.take_hit(40)
	await wait_physics_frames(2)
	assert_true(main.player.can_feed_on(foe))
	assert_true(foe.has_feed_mark())
	var drop: Node3D = _visual(foe).find_child("FeedDrop", false, false)
	assert_true(drop.visible)
	assert_gt(drop.global_position.y - foe.global_position.y, _visual(foe).dress.height)
	assert_null(foe.get_node_or_null("FeedMark"), "the red sphere is gone")
	foe.stats.heal(30)
	await wait_physics_frames(2)
	assert_false(drop.visible)

func test_the_hover_mark_shows_for_an_npc_under_the_cursor_and_hides_when_it_leaves() -> void:
	await _haven()
	var malakor: Npc = _npc("Malakor")
	# Over 4 m from Malakor, so only the cursor can light his ring.
	await _place_alvar(malakor.global_position + Vector3(5.0, 0.3, 3.0))
	assert_false(malakor.has_use_mark())
	var camera: Camera3D = main.rig.camera()
	main.input.point_at(camera.unproject_position(malakor.global_position + Vector3(0, 1.2, 0)))
	await wait_physics_frames(2)
	assert_true(malakor.has_use_mark())
	main.input.point_at(camera.unproject_position(main.player.global_position + Vector3(1.5, 0, 0)))
	await wait_physics_frames(2)
	assert_false(malakor.has_use_mark())

func test_the_nearest_usable_one_within_four_metres_shows_its_ring_but_not_while_talking() -> void:
	await _haven()
	var malakor: Npc = _npc("Malakor")
	await _place_alvar(malakor.global_position + Vector3(0, 0.3, 2.0))
	assert_true(malakor.has_use_mark())
	var others: Array[Node] = get_tree().get_nodes_in_group(&"interactables").filter(
			func(thing: Node) -> bool: return thing != malakor and (thing as Interactable).has_use_mark())
	assert_eq(others, [], "only the nearest")
	main.talk(HAVEN, "malakor")
	await wait_physics_frames(2)
	assert_true(main.is_talking())
	assert_false(malakor.has_use_mark(), "none while talking")

func test_a_fallen_unit_shows_no_marks() -> void:
	await _skirmish()
	var foe: Unit = _crusader()
	foe.take_hit(40)
	await wait_physics_frames(2)
	foe.take_hit(999)
	foe.set_feed_mark(true)
	assert_false(foe.has_feed_mark())
	assert_false(_visual(foe).is_feed_mark_shown())
	main.player.take_hit(999)
	await wait_physics_frames(2)
	assert_eq(main.selected, main.player, "the fallen leader stays selected")
	assert_false(main.player.has_selected_mark())
	assert_false(_visual(main.player).is_selected_mark_shown())

func _lit_interactables() -> Array[Node]:
	return get_tree().get_nodes_in_group(&"interactables").filter(
			func(thing: Node) -> bool: return (thing as Interactable).has_use_mark())

func test_the_selected_ring_is_on_alvar_after_a_reload() -> void:
	var state := GameState.new_game()
	state.set_flag(&"met_malakor")
	state.join(&"zahra")
	main = Story.boot(self, state)
	await wait_physics_frames(3)
	main.select(main.party[1])
	main.checkpoint()
	main.reload_checkpoint()
	await wait_physics_frames(3)
	assert_eq(_lit(main.party), [main.player])

func test_a_joiner_arrives_without_a_ring() -> void:
	await _haven()
	main.state.join(&"zahra")
	await wait_physics_frames(3)
	assert_eq(main.party.size(), 2)
	assert_eq(_lit(main.party), [main.player])
	assert_false(_visual(main.party[1]).is_selected_mark_shown())

func test_a_mark_asked_for_before_the_unit_is_ready_shows() -> void:
	var foe: Unit = (load("res://scenes/units/crusader.tscn") as PackedScene).instantiate()
	foe.set_feed_mark(true)
	add_child_autofree(foe)
	await wait_physics_frames(2)
	assert_true(_visual(foe).is_feed_mark_shown())

func test_only_one_use_ring_shows_and_the_hovered_one_wins() -> void:
	await _haven()
	var malakor: Npc = _npc("Malakor")
	var smith: Npc = _npc("Íñigo")
	await _place_alvar(smith.global_position + Vector3(0.5, 0.3, 2.0))
	assert_eq(_lit_interactables(), [smith], "the nearest")
	main.input.point_at(main.rig.camera().unproject_position(malakor.global_position + Vector3(0, 1.2, 0)))
	await wait_physics_frames(2)
	assert_eq(_lit_interactables(), [malakor], "the hovered one instead")

func test_a_door_nothing_answers_shows_no_ring() -> void:
	await _skirmish()
	var door := main.room.find_child("WestDoor") as Door
	await _place_alvar(door.global_position + Vector3(1.5, 0.3, 0.0))  # inside the room, by the west wall
	assert_eq(_lit_interactables(), [])

func test_a_story_flag_that_changes_what_can_be_used_moves_the_ring_at_once() -> void:
	await _haven()
	var gonzalo: Npc = _npc("Gonzalo")
	# On his east side, over 4 m from the smith.
	await _place_alvar(gonzalo.global_position + Vector3(1.5, 0.3, 1.0))
	# Until Álvar, the camera and the mouse are all still.
	await wait_seconds(2.0)
	assert_true(gonzalo.has_use_mark(), "the nearest one to use")
	main.state.set_flag(&"gonzalo_joined")
	await wait_physics_frames(2)
	assert_false(gonzalo.visible)
	assert_false(gonzalo.has_use_mark(), "no ring on him once he is gone")
	main.state.set_flag(&"gonzalo_joined", false)
	await wait_physics_frames(2)
	assert_true(gonzalo.has_use_mark(), "his ring again once he is back")
