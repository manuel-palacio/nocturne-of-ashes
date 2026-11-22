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
## Where each head lies, as the head tool puts it: its bounds from the head bone's rest head, in metres
## (the lowest and highest corners), measured from `tools/blender/heads.py`'s output. A head moved or
## grown by more than `HEAD_PLACE` (half a centimetre) fails.
const HEAD_BOUNDS: Dictionary = {
	"alvar": [Vector3(-0.096, -0.038, -0.138), Vector3(0.096, 0.265, 0.116)],
	"captive": [Vector3(-0.105, -0.039, -0.140), Vector3(0.105, 0.272, 0.130)],
	"crusader": [Vector3(-0.094, -0.038, -0.138), Vector3(0.094, 0.266, 0.111)],
	"gonzalo": [Vector3(-0.104, -0.038, -0.149), Vector3(0.104, 0.265, 0.117)],
	"malakor": [Vector3(-0.110, -0.089, -0.139), Vector3(0.110, 0.279, 0.132)],
	"sergeant": [Vector3(-0.095, -0.038, -0.140), Vector3(0.095, 0.266, 0.111)],
	"smith": [Vector3(-0.102, -0.038, -0.138), Vector3(0.102, 0.269, 0.115)],
	"zahra": [Vector3(-0.088, -0.038, -0.129), Vector3(0.088, 0.266, 0.107)],
}
const HEAD_PLACE: float = 0.005
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
		var pinned: Array = HEAD_BOUNDS[dress_name]
		var reach: String = "%s reaches %s to %s" % [dress_name, box.position, box.end]
		for axis: int in 3:
			assert_almost_eq(box.position[axis], (pinned[0] as Vector3)[axis], HEAD_PLACE, reach)
			assert_almost_eq(box.end[axis], (pinned[1] as Vector3)[axis], HEAD_PLACE, reach)


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
	var mesh := head.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D
	var centres: Array[Vector3] = []
	var reaches: Array[float] = []
	for sample: int in 2:
		await wait_seconds(0.6)
		assert_eq(figure.clip(), &"feed")
		var centre: Vector3 = mesh.global_transform * mesh.get_aabb().get_center()
		var bone_origin: Vector3 = (skeleton.global_transform * skeleton.get_bone_global_pose(bone)).origin
		centres.append(centre)
		reaches.append(centre.distance_to(bone_origin))
	assert_almost_eq(reaches[0], reaches[1], 0.002, "the head keeps its distance to the head bone")
	assert_gt(centres[0].distance_to(centres[1]), 0.005, "the head moves with the bowing figure")


func test_a_dressed_figure_stays_under_its_triangle_budget() -> void:
	var dresses: Dictionary = _dresses()
	for dress_name: String in dresses:
		var figure: UnitVisual = _figure(dresses[dress_name])
		var triangles: int = 0
		for mesh: MeshInstance3D in figure.model().find_children("*", "MeshInstance3D", true, false):
			triangles += mesh.mesh.get_faces().size() / 3
		gut.p("%s: %d triangles" % [dress_name, triangles])
		assert_lt(triangles, FIGURE_TRIANGLES, dress_name)


# ---- clothes ------------------------------------------------------------------------------------

## The bones the garments cover, as `tools/blender/gear.py`'s table names them: the chest, the abdomen
## (the lower spine) and the upper arms. The model has none of its own body there.
const CHEST_BONE: StringName = &"DEF-spine.003"
const ABDOMEN_BONE: StringName = &"DEF-spine.001"
const UPPER_ARM_BONES: Array[StringName] = [&"DEF-upper_arm.L", &"DEF-upper_arm.R"]
const GARMENT_TRIANGLES: int = 600
## The bone segments, as pairs of bones from head to head, that the body a chest or an abdomen piece
## stands in for followed: the chest round the upper spine, the neck and the collarbones, the
## abdomen round the lower spine.
const COVERED: Dictionary = {
	CHEST_BONE: [[&"DEF-spine.002", &"DEF-spine.003"], [&"DEF-spine.003", &"DEF-neck"],
			[&"DEF-shoulder.L", &"DEF-upper_arm.L"], [&"DEF-shoulder.R", &"DEF-upper_arm.R"]],
	ABDOMEN_BONE: [[&"DEF-hips", &"DEF-spine.001"], [&"DEF-spine.001", &"DEF-spine.002"],
			[&"DEF-spine.002", &"DEF-spine.003"]],
}
## How much further from the segments it covers than at rest a vertex may get in any pose: more, and
## the piece floats off the body.
const FLOAT_LIMIT: float = 0.08
## Bones whose pieces meet: in every pose their bounds must overlap.
const NEIGHBOURS: Array[Array] = [
	[CHEST_BONE, ABDOMEN_BONE], [CHEST_BONE, &"DEF-upper_arm.L"], [CHEST_BONE, &"DEF-upper_arm.R"],
	[ABDOMEN_BONE, &"DEF-hips"], [&"DEF-upper_arm.L", &"DEF-forearm.L"], [&"DEF-upper_arm.R", &"DEF-forearm.R"],
	[CHEST_BONE, &"DEF-neck"],
]
const BENT_CLIPS: Array[StringName] = [&"attack", &"cast", &"feed", &"sit", &"death", &"run"]
const SAMPLES: int = 5
## At most this many materials on one figure: the body's (its head and garments too), cloth regions,
## and the one of the gear's own colours.
const FIGURE_MATERIALS: int = 4


func test_every_dress_covers_its_chest_abdomen_and_upper_arms() -> void:
	var dresses: Dictionary = _dresses()
	for dress_name: String in dresses:
		var bones: Array[StringName] = []
		for piece: GearPiece in (dresses[dress_name] as Dress).gear:
			bones.append(piece.bone)
		for bone: StringName in [CHEST_BONE, ABDOMEN_BONE] + UPPER_ARM_BONES:
			assert_has(bones, bone, "%s wears a piece on %s" % [dress_name, bone])


func test_every_worn_piece_is_small() -> void:
	var dresses: Dictionary = _dresses()
	for dress_name: String in dresses:
		for piece: GearPiece in (dresses[dress_name] as Dress).gear:
			var triangles: int = _mesh_of(piece.scene).mesh.get_faces().size() / 3
			assert_lt(triangles, GARMENT_TRIANGLES, "%s: %s" % [dress_name, piece.scene.resource_path.get_file()])


func test_every_piece_with_shape_keys_has_its_table() -> void:
	for file: String in ResourceLoader.list_directory("res://resources/gear/"):
		var piece := load("res://resources/gear/" + file) as GearPiece
		if piece == null:
			continue
		var mesh: MeshInstance3D = _mesh_of(piece.scene)
		var keys: int = (mesh.mesh as ArrayMesh).get_blend_shape_count()
		if keys > 0:
			assert_true(piece.cloth, "%s stretches, so it is cloth" % file)
			assert_not_null(piece.shape, "%s has shape keys and a table" % file)


func test_nothing_floats_or_tears_in_the_bent_clips() -> void:
	var dresses: Dictionary = _dresses()
	for dress_name: String in dresses:
		var figure: UnitVisual = _figure(dresses[dress_name])
		figure.process_mode = Node.PROCESS_MODE_DISABLED
		var skeleton: Skeleton3D = _skeleton(figure)
		var pieces: Array[Dictionary] = _worn_pieces(figure)
		var player := figure.model().find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
		var rest: Dictionary = {}
		for piece: Dictionary in pieces:
			if COVERED.has(piece.bone) and piece.rigid:
				rest[piece] = _distances(piece, skeleton, true)
		var worst: float = 0.0
		var worst_at: String = ""
		var tears: Array[String] = []
		for clip_name: StringName in BENT_CLIPS:
			var length: float = player.get_animation(clip_name).length
			for sample: int in SAMPLES:
				var time: float = length * sample / float(SAMPLES - 1)
				player.play(clip_name)
				player.seek(time, true)
				for piece: Dictionary in rest:
					var now: PackedFloat32Array = _distances(piece, skeleton, false)
					var was: PackedFloat32Array = rest[piece]
					for i: int in now.size():
						if now[i] - was[i] > worst:
							worst = now[i] - was[i]
							worst_at = "%s in %s at %.2f s" % [piece.name, clip_name, time]
				var boxes: Dictionary = _boxes(pieces, skeleton)
				for pair: Array in NEIGHBOURS:
					if boxes.has(pair[0]) and boxes.has(pair[1]) and not (boxes[pair[0]] as AABB).intersects(boxes[pair[1]]):
						tears.append("%s %s %.2f: %s and %s apart" % [dress_name, clip_name, time, pair[0], pair[1]])
		gut.p("%s: the chest and abdomen get at most %.3f m further from what they cover (%s)" % [dress_name, worst, worst_at])
		assert_lte(worst, FLOAT_LIMIT, "%s: nothing floats" % dress_name)
		assert_eq(tears, [] as Array[String], "%s: nothing tears" % dress_name)


func test_every_material_of_a_figure_is_the_bodys_kind() -> void:
	var dresses: Dictionary = _dresses()
	for dress_name: String in dresses:
		var figure: UnitVisual = _figure(dresses[dress_name])
		var meshes: Array[Node] = figure.model().find_children("*", "MeshInstance3D", true, false)
		var body := (meshes[0] as MeshInstance3D).material_override as StandardMaterial3D
		var seen: Array[Material] = []
		for node: Node in meshes:
			var material: Material = (node as MeshInstance3D).material_override
			assert_true(material is StandardMaterial3D, "%s: %s" % [dress_name, node.name])
			if not material is StandardMaterial3D:
				continue
			assert_eq(_features(material as StandardMaterial3D), _features(body), "%s: %s" % [dress_name, node.get_parent().name])
			if not seen.has(material):
				seen.append(material)
		gut.p("%s: %d materials" % [dress_name, seen.size()])
		assert_lte(seen.size(), FIGURE_MATERIALS, dress_name)


func test_every_figure_in_the_game_wears_a_dress_with_a_head() -> void:
	var scenes: Array[String] = []
	for folder: String in ["res://scenes/units/", "res://scenes/rooms/"]:
		for file: String in ResourceLoader.list_directory(folder):
			if file.ends_with(".tscn") and file != "unit_base.tscn" and file != "npc.tscn":
				scenes.append(folder + file)
	var figures: int = 0
	for path: String in scenes:
		var root: Node = autofree((load(path) as PackedScene).instantiate())
		var found: Array[Node] = root.find_children("*", "Npc", true, false)
		found.append_array(root.find_children("Visual", "UnitVisual", true, false) if root is Unit else [])
		if root is Unit:
			found.append(root.get_node(^"Visual"))
		for node: Node in found:
			var dress: Dress = (node as Npc).dress if node is Npc else (node as UnitVisual).dress
			figures += 1
			assert_not_null(dress, "%s: %s" % [path, node.name])
			if dress != null:
				assert_not_null(dress.head, "%s: %s's dress has a head" % [path, node.name])
	assert_gte(figures, 10, "every unit and every person in the rooms")


## The figure's worn pieces, each with its bone, its mesh's vertices and its place on the bone, and
## whether it is rigid (no shape keys).
func _worn_pieces(figure: UnitVisual) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	for node: Node in _attachments(figure):
		var attachment := node as BoneAttachment3D
		for mesh: MeshInstance3D in attachment.find_children("*", "MeshInstance3D", true, false):
			var arrays: Array = mesh.mesh.surface_get_arrays(0)
			found.append({
				"name": attachment.name, "bone": StringName(attachment.bone_name),
				"index": _skeleton(figure).find_bone(attachment.bone_name),
				"vertices": arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array,
				"hang": attachment.global_transform.affine_inverse() * mesh.global_transform,
				"rigid": (mesh.mesh as ArrayMesh).get_blend_shape_count() == 0,
			})
	return found


## Each vertex's distance from the bone segments the piece covers, at rest or as posed now, in the
## skeleton's frame.
func _distances(piece: Dictionary, skeleton: Skeleton3D, at_rest: bool) -> PackedFloat32Array:
	var segments: Array[Vector3] = []
	for pair: Array in COVERED[piece.bone]:
		for bone_name: StringName in pair:
			var bone: int = skeleton.find_bone(bone_name)
			segments.append((skeleton.get_bone_global_rest(bone) if at_rest else skeleton.get_bone_global_pose(bone)).origin)
	var place: Transform3D = (skeleton.get_bone_global_rest(piece.index) if at_rest
			else skeleton.get_bone_global_pose(piece.index)) * (piece.hang as Transform3D)
	var out := PackedFloat32Array()
	for vertex: Vector3 in piece.vertices as PackedVector3Array:
		var point: Vector3 = place * vertex
		var nearest: float = INF
		for s: int in range(0, segments.size(), 2):
			var closest: Vector3 = Geometry3D.get_closest_point_to_segment(point, segments[s], segments[s + 1])
			nearest = minf(nearest, point.distance_to(closest))
		out.append(nearest)
	return out


## The posed bounds of all the pieces on each bone, in the skeleton's frame, by bone name.
func _boxes(pieces: Array[Dictionary], skeleton: Skeleton3D) -> Dictionary:
	var boxes: Dictionary = {}
	for piece: Dictionary in pieces:
		var place: Transform3D = skeleton.get_bone_global_pose(piece.index) * (piece.hang as Transform3D)
		for vertex: Vector3 in piece.vertices as PackedVector3Array:
			var point: Vector3 = place * vertex
			boxes[piece.bone] = (boxes[piece.bone] as AABB).expand(point) if boxes.has(piece.bone) else AABB(point, Vector3.ZERO)
	return boxes


## What makes a material compile to its own shader.
func _features(material: StandardMaterial3D) -> Array:
	return [material.shading_mode, material.transparency, material.cull_mode, material.texture_filter,
		material.emission_enabled, material.vertex_color_use_as_albedo, material.billboard_mode,
		material.normal_enabled, material.depth_draw_mode, material.blend_mode, material.diffuse_mode,
		material.specular_mode, material.albedo_texture != null, material.emission_texture != null]
