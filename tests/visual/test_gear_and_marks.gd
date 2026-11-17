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
		assert_eq(attachments.size(), visual.dress.gear.size(), unit.name)
		for i: int in attachments.size():
			var attachment := attachments[i] as BoneAttachment3D
			var piece: GearPiece = visual.dress.gear[i]
			assert_true(attachment.get_parent() is Skeleton3D, "%s hangs from the skeleton" % attachment.name)
			assert_eq(attachment.bone_name, String(piece.bone), "%s of %s" % [attachment.name, unit.name])
			var meshes: Array[Node] = attachment.find_children("*", "MeshInstance3D", true, false)
			assert_gt(meshes.size(), 0, "%s has a mesh" % attachment.name)
			for mesh: MeshInstance3D in meshes:
				var triangles: int = mesh.mesh.surface_get_array_index_len(0) / 3
				assert_lt(triangles, 600, "%s triangles" % attachment.name)
