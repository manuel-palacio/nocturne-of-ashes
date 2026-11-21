# tests/visual/test_faces_and_clothes.gd
extends GutTest
## Faces and clothes on the human model. Heads: the mannequin's own head is gone from `human.glb`, and
## every dress wears a head made by `tools/blender/heads.py`, hung from the head bone, small, and
## drawn with the body's own material.

const HUMAN := preload("res://assets/characters/human/human.glb")
const DRESSES: String = "res://resources/dress/"
## The tool that makes the model; it names the height of the neck joint's top as `NECK_TOP`.
const CHARACTER_TOOL: String = "res://tools/make_character.py"
const HEAD_BONE: StringName = &"DEF-head"
const HEAD_TRIANGLES: int = 900
## How far a head may reach from the head bone's rest head, in metres: sideways (either way, x or z),
## up, and down (Malakor's hair reaches further down).
const HEAD_SIDEWAYS: float = 0.16
const HEAD_UP: float = 0.3
const HEAD_DOWN: float = 0.1
const LONG_HAIR_DOWN: float = 0.3
const LONG_HAIRED: Array[String] = ["malakor"]
## The model, its head and its gear together.
const FIGURE_TRIANGLES: int = 15000


## Every dress in `resources/dress/`, by file name without `.tres`.
func _dresses() -> Dictionary:
	var found: Dictionary = {}
	for file: String in ResourceLoader.list_directory(DRESSES):
		if file.ends_with(".tres"):
			found[file.get_basename()] = load(DRESSES + file) as Dress
	return found


## `NECK_TOP` as the character tool defines it.
func _neck_top() -> float:
	var source: String = FileAccess.get_file_as_string(CHARACTER_TOOL)
	var match := RegEx.create_from_string("(?m)^NECK_TOP = ([0-9.]+)").search(source)
	assert_not_null(match, "the tool names NECK_TOP")
	return float(match.get_string(1)) if match != null else 0.0


func _mesh_of(scene: PackedScene) -> MeshInstance3D:
	var node: Node = autofree(scene.instantiate())
	return node.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D


func _figure(dress: Dress, resting: StringName = &"idle") -> UnitVisual:
	var figure := UnitVisual.new()
	figure.dress = dress
	figure.resting = resting
	add_child_autofree(figure)
	return figure


func _skeleton(figure: UnitVisual) -> Skeleton3D:
	return figure.model().find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D


func _attachments(figure: UnitVisual) -> Array[Node]:
	return figure.model().find_children("*", "BoneAttachment3D", true, false)


func test_every_dress_wears_a_head_on_the_head_bone() -> void:
	var dresses: Dictionary = _dresses()
	assert_eq(dresses.size(), 8)
	for dress_name: String in dresses:
		var dress: Dress = dresses[dress_name]
		assert_not_null(dress.head, dress_name)
		if dress.head == null:
			continue
		assert_eq(dress.head.bone, HEAD_BONE, dress_name)
		assert_not_null(dress.head.scene, dress_name)
		assert_false(dress.head.cloth, "%s: coloured from the palette's own squares" % dress_name)


func test_the_model_has_no_triangle_above_the_neck_joint() -> void:
	var neck_top: float = _neck_top()
	assert_gt(neck_top, 1.5)
	var human: Node3D = add_child_autofree(HUMAN.instantiate())
	var mesh := human.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D
	var highest: float = -INF
	for corner: Vector3 in mesh.mesh.get_faces():
		highest = maxf(highest, (mesh.global_transform * corner).y)
	assert_lte(highest, neck_top, "the highest corner of the model")


func test_each_head_is_small_and_lies_round_the_head_bone() -> void:
	var dresses: Dictionary = _dresses()
	for dress_name: String in dresses:
		var dress: Dress = dresses[dress_name]
		if dress.head == null:
			fail_test("%s has no head" % dress_name)
			continue
		var mesh: MeshInstance3D = _mesh_of(dress.head.scene)
		var triangles: int = mesh.mesh.get_faces().size() / 3
		assert_lt(triangles, HEAD_TRIANGLES, "%s: %d triangles" % [dress_name, triangles])
		var box: AABB = mesh.transform * mesh.get_aabb()
		var down: float = LONG_HAIR_DOWN if dress_name in LONG_HAIRED else HEAD_DOWN
		var reach: String = "%s reaches %s to %s" % [dress_name, box.position, box.end]
		assert_lte(maxf(absf(box.position.x), absf(box.end.x)), HEAD_SIDEWAYS, reach)
		assert_lte(maxf(absf(box.position.z), absf(box.end.z)), HEAD_SIDEWAYS, reach)
		assert_lte(box.end.y, HEAD_UP, reach)
		assert_gte(box.position.y, -down, reach)


func test_a_dressed_figure_stands_at_its_height_with_its_head() -> void:
	for dress_name: String in ["alvar", "gonzalo", "zahra"]:
		var dress: Dress = load(DRESSES + dress_name + ".tres")
		var figure: UnitVisual = _figure(dress)
		var top: float = -INF
		for mesh: MeshInstance3D in figure.model().find_children("*", "MeshInstance3D", true, false):
			top = maxf(top, (mesh.global_transform * mesh.get_aabb()).end.y)
		assert_almost_eq(top, dress.height, 0.1, dress_name)


func test_the_head_hangs_first_and_is_drawn_with_the_body() -> void:
	var dress: Dress = load(DRESSES + "gonzalo.tres")
	var figure: UnitVisual = _figure(dress)
	var attachments: Array[Node] = _attachments(figure)
	assert_eq(attachments.size(), dress.gear.size() + 1)
	var head := attachments[0] as BoneAttachment3D
	assert_eq(head.bone_name, String(HEAD_BONE))
	assert_eq(head.name, StringName(dress.head.scene.resource_path.get_file().get_basename()))
	var body := figure.model().find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D
	for mesh: MeshInstance3D in head.find_children("*", "MeshInstance3D", true, false):
		assert_same(mesh.material_override, body.material_override, "the body's own material")


func test_a_dress_without_a_head_logs_one_error_and_still_builds_the_figure() -> void:
	var dress: Dress = (load(DRESSES + "alvar.tres") as Dress).duplicate()
	dress.head = null
	var figure: UnitVisual = _figure(dress)
	assert_push_error("has no head")
	assert_push_error_count(1, "only the one")
	assert_not_null(figure.model())
	assert_eq(_attachments(figure).size(), dress.gear.size(), "the rest of its gear")


func test_the_head_follows_the_head_bone_while_feeding() -> void:
	var figure: UnitVisual = _figure(load(DRESSES + "alvar.tres"), &"feed")
	await wait_physics_frames(2)
	var skeleton: Skeleton3D = _skeleton(figure)
	var bone: int = skeleton.find_bone(HEAD_BONE)
	var head := _attachments(figure)[0] as BoneAttachment3D
	var seen: Array[Transform3D] = []
	for sample: int in 2:
		await wait_seconds(0.6)
		assert_eq(figure.clip(), &"feed")
		var bone_pose: Transform3D = skeleton.global_transform * skeleton.get_bone_global_pose(bone)
		assert_true(head.global_transform.is_equal_approx(bone_pose), "the head sits on the bone")
		seen.append(head.global_transform)
	assert_false(seen[0].is_equal_approx(seen[1]), "the head moves as the bone does")



func test_a_dressed_figure_stays_under_its_triangle_budget() -> void:
	var dresses: Dictionary = _dresses()
	for dress_name: String in dresses:
		var figure: UnitVisual = _figure(dresses[dress_name])
		var triangles: int = 0
		for mesh: MeshInstance3D in figure.model().find_children("*", "MeshInstance3D", true, false):
			triangles += mesh.mesh.get_faces().size() / 3
		gut.p("%s: %d triangles" % [dress_name, triangles])
		assert_lt(triangles, FIGURE_TRIANGLES, dress_name)
