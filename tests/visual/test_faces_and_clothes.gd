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
## The seams between a garment's pieces, and between a garment and the body it meets. Each names the
## outer piece, the inner one, the axis the two overlap along (in the outer piece's frame), and which of
## the inner one's vertices at rest are its rim at the overlap: in a band of height (`y`) or of
## distance from the middle (`x`, either side), in metres, in the skeleton's frame. In every pose each
## rim vertex must stay inside the outer piece: within its length along the axis and inside its
## section there. A piece is found by its bone; `skirt` is the stretching piece on the hips, `pelvis`
## and `elbow.*` the body's own vertices that the hips or the upper arm move most.
const SEAMS: Dictionary = {
	"chest over abdomen": ["chest", "abdomen", Vector3.UP, "y", 1.22, 1.31],
	"skirt over abdomen": ["skirt", "abdomen", Vector3.UP, "y", 0.94, 0.99],
	"abdomen over pelvis": ["abdomen", "pelvis", Vector3.UP, "y", 1.0, 1.08],
	"chest over left sleeve": ["chest", "sleeve.L", Vector3.UP, "x", 0.0, 0.15],
	"chest over right sleeve": ["chest", "sleeve.R", Vector3.UP, "x", 0.0, 0.15],
	"left sleeve over elbow": ["sleeve.L", "elbow.L", Vector3.RIGHT, "x", 0.0, 1.0],
	"right sleeve over elbow": ["sleeve.R", "elbow.R", Vector3.RIGHT, "x", 0.0, 1.0],
}
## The seams each dress has. Left out, as they cannot apply: `skirt over abdomen` for the captive and
## the smiths (no skirt: their tunic and shirt reach over the pelvis instead, `abdomen over pelvis`),
## and `abdomen over pelvis` for those with a skirt (the skirt covers the pelvis). A cuff (Alvar's,
## Malakor's) hangs from the forearm bone, as the forearm does, so their seam cannot open; the elbow
## seam is the one that can.
const ALL_SEAMS: Array[String] = ["chest over abdomen", "chest over left sleeve", "chest over right sleeve",
		"left sleeve over elbow", "right sleeve over elbow"]
const SKIRTED: Array[String] = ["alvar", "zahra", "malakor", "crusader", "sergeant"]
const UNSKIRTED: Array[String] = ["captive", "gonzalo", "smith"]
## Outer vertices this far either side of a rim vertex along the axis make the section it must be in.
const SLAB: float = 0.09
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


func test_no_seam_opens_in_the_bent_clips() -> void:
	var dresses: Dictionary = _dresses()
	assert_eq(SKIRTED.size() + UNSKIRTED.size(), dresses.size(), "every dress is skirted or not")
	var checked: int = 0
	for dress_name: String in dresses:
		var seams: Array[String] = ALL_SEAMS.duplicate()
		seams.append("skirt over abdomen" if dress_name in SKIRTED else "abdomen over pelvis")
		var figure: UnitVisual = _figure(dresses[dress_name])
		figure.process_mode = Node.PROCESS_MODE_DISABLED
		var skeleton: Skeleton3D = _skeleton(figure)
		var parts: Dictionary = _parts(figure)
		var player := figure.model().find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
		for seam: String in seams:
			var spec: Array = SEAMS[seam]
			var outer: Dictionary = parts.get(spec[0], {})
			var inner: Dictionary = parts.get(spec[1], {})
			assert_false(outer.is_empty() or inner.is_empty(), "%s: %s has both its pieces" % [dress_name, seam])
			if outer.is_empty() or inner.is_empty():
				continue
			var rim: PackedInt32Array = _rim(inner, skeleton, spec)
			assert_gt(rim.size(), 6, "%s: %s has a rim" % [dress_name, seam])
			var open: Array[String] = []
			for clip_name: StringName in BENT_CLIPS:
				var length: float = player.get_animation(clip_name).length
				for sample: int in SAMPLES:
					var time: float = length * sample / float(SAMPLES - 1)
					player.play(clip_name)
					player.seek(time, true)
					var out: Vector2 = _outside(outer, inner, rim, skeleton, spec[2])
					if out.x > 0:
						open.append("%s at %.2f s: %d of %d rim vertices out, by up to %.3f m" % [clip_name, time, out.x, rim.size(), out.y])
			assert_eq(open, [] as Array[String], "%s: %s stays closed" % [dress_name, seam])
			gut.p("%s %s: %s" % [dress_name, seam, "closed" if open.is_empty() else "; ".join(open)])
			checked += 1
	assert_eq(checked, 8 * ALL_SEAMS.size() + SKIRTED.size() + UNSKIRTED.size(), "seams checked")


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


## The figure's pieces and body parts that meet at seams, by the names `SEAMS` uses. Each is its
## vertices, how each is placed (a piece by one bone, the body by its skin weights) and, for a piece,
## its vertices' bounds along each axis.
func _parts(figure: UnitVisual) -> Dictionary:
	var skeleton: Skeleton3D = _skeleton(figure)
	var found: Dictionary = {}
	for node: Node in _attachments(figure):
		var attachment := node as BoneAttachment3D
		var mesh := attachment.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D
		var rigid: bool = (mesh.mesh as ArrayMesh).get_blend_shape_count() == 0
		var bone := StringName(attachment.bone_name)
		var kind: String = ""
		if bone == CHEST_BONE and rigid:
			kind = "chest"
		elif bone == ABDOMEN_BONE:
			kind = "abdomen"
		elif bone in UPPER_ARM_BONES:
			kind = "sleeve." + String(bone).get_extension()
		elif bone == &"DEF-hips" and String(attachment.name).begins_with("skirt"):
			kind = "skirt"
		if kind.is_empty():
			continue
		found[kind] = {"vertices": mesh.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array,
			"bone": skeleton.find_bone(bone), "hang": attachment.global_transform.affine_inverse() * mesh.global_transform}
	var body := figure.model().find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D
	var arrays: Array = body.mesh.surface_get_arrays(0)
	var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
	var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var binds: Array[int] = []
	for i: int in body.skin.get_bind_count():
		var bone: int = body.skin.get_bind_bone(i)
		binds.append(bone if bone >= 0 else skeleton.find_bone(body.skin.get_bind_name(i)))
	var lead_of := {&"pelvis": &"DEF-hips", &"elbow.L": &"DEF-upper_arm.L", &"elbow.R": &"DEF-upper_arm.R"}
	for kind: StringName in lead_of:
		var lead: int = skeleton.find_bone(lead_of[kind])
		var picked := PackedVector3Array()
		var skin: Array[PackedVector4Array] = []
		for v: int in vertices.size():
			var strongest: int = 0
			for k: int in 4:
				if weights[v * 4 + k] > weights[v * 4 + strongest]:
					strongest = k
			if binds[bones[v * 4 + strongest]] != lead:
				continue
			picked.append(vertices[v])
			var influences := PackedVector4Array()
			for k: int in 4:
				influences.append(Vector4(bones[v * 4 + k], weights[v * 4 + k], 0.0, 0.0))
			skin.append(influences)
		found[String(kind)] = {"vertices": picked, "skin": skin, "binds": binds, "body": body.skin}
	for kind: String in found:
		if found[kind].has("hang"):
			var box := AABB((found[kind].vertices as PackedVector3Array)[0], Vector3.ZERO)
			for vertex: Vector3 in found[kind].vertices as PackedVector3Array:
				box = box.expand(vertex)
			found[kind]["box"] = box
	return found


## Where vertex `i` of `part` is, posed now or at rest, in the skeleton's frame.
func _place(part: Dictionary, i: int, skeleton: Skeleton3D, at_rest: bool) -> Vector3:
	var vertex: Vector3 = (part.vertices as PackedVector3Array)[i]
	if part.has("hang"):
		var bone_place: Transform3D = skeleton.get_bone_global_rest(part.bone) if at_rest else skeleton.get_bone_global_pose(part.bone)
		return bone_place * (part.hang as Transform3D) * vertex
	var out := Vector3.ZERO
	for influence: Vector4 in (part.skin as Array)[i] as PackedVector4Array:
		if influence.y <= 0.0:
			continue
		var bone: int = (part.binds as Array)[int(influence.x)]
		var bone_place: Transform3D = skeleton.get_bone_global_rest(bone) if at_rest else skeleton.get_bone_global_pose(bone)
		out += (bone_place * (part.body as Skin).get_bind_pose(int(influence.x)) * vertex) * influence.y
	return out


## The inner part's vertices that are its rim at the seam `spec`, chosen at rest.
func _rim(inner: Dictionary, skeleton: Skeleton3D, spec: Array) -> PackedInt32Array:
	var rim := PackedInt32Array()
	for i: int in (inner.vertices as PackedVector3Array).size():
		var at: Vector3 = _place(inner, i, skeleton, true)
		var measure: float = at.y if spec[3] == "y" else absf(at.x)
		if measure >= spec[4] and measure <= spec[5]:
			rim.append(i)
	return rim


## How many of the rim's vertices lie outside the outer piece as posed now (beyond its length along
## `axis`, or outside the section its own vertices make there), and by how far at most.
func _outside(outer: Dictionary, inner: Dictionary, rim: PackedInt32Array, skeleton: Skeleton3D, axis: Vector3) -> Vector2:
	var to_outer: Transform3D = (skeleton.get_bone_global_pose(outer.bone) * (outer.hang as Transform3D)).affine_inverse()
	var box: AABB = outer.box
	var low: float = box.position.dot(axis) if axis == Vector3.UP else box.position.x
	var high: float = box.end.dot(axis) if axis == Vector3.UP else box.end.x
	var count: int = 0
	var furthest: float = 0.0
	for i: int in rim:
		var point: Vector3 = to_outer * _place(inner, i, skeleton, false)
		var along: float = point.dot(axis)
		if along <= low or along >= high:
			count += 1
			furthest = maxf(furthest, maxf(low - along, along - high))
			continue
		var section := PackedVector2Array()
		for vertex: Vector3 in outer.vertices as PackedVector3Array:
			if absf(vertex.dot(axis) - along) <= SLAB:
				section.append(_across(vertex, axis))
		var hull: PackedVector2Array = Geometry2D.convex_hull(section)
		var flat: Vector2 = _across(point, axis)
		if hull.size() < 3 or not Geometry2D.is_point_in_polygon(flat, hull):
			count += 1
			var nearest: float = INF
			for k: int in range(1, hull.size()):
				nearest = minf(nearest, flat.distance_to(Geometry2D.get_closest_point_to_segment(flat, hull[k - 1], hull[k])))
			furthest = maxf(furthest, nearest if hull.size() >= 3 else INF)
	return Vector2(count, furthest)


static func _across(point: Vector3, axis: Vector3) -> Vector2:
	return Vector2(point.x, point.z) if axis == Vector3.UP else Vector2(point.y, point.z)


## What makes a material compile to its own shader.
func _features(material: StandardMaterial3D) -> Array:
	return [material.shading_mode, material.transparency, material.cull_mode, material.texture_filter,
		material.emission_enabled, material.vertex_color_use_as_albedo, material.billboard_mode,
		material.normal_enabled, material.depth_draw_mode, material.blend_mode, material.diffuse_mode,
		material.specular_mode, material.albedo_texture != null, material.emission_texture != null]
