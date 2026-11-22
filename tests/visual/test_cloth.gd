# tests/visual/test_cloth.gd
extends GutTest
## The cloth: each shipped table of how a piece stretches (`assets/gear/<piece>_cloth.tres`, written by
## `tools/blender/gear.py`) matches its piece, and `ClothFit.fit` pushes the hem out round a leg that
## strides into it and lets it go again. Headless, no figure is on screen, so the figures never fit
## their cloth themselves; these tests call the fit directly.

const GEAR: String = "res://resources/gear/"
## Each stretching piece: its keys, whether it lays flat when its wearer lies down, and whether it
## stands out like cloth over a knee, no further than its hem goes (the apron, a board on a strap,
## swings out from its top instead, furthest at the hem).
const TABLES: Dictionary = {
	"apron": [["fore"], false, false],
	"mantle": [["aft"], false, true],
	"skirt_long": [["fore", "aft", "left", "right"], true, true],
	"skirt_short": [["fore", "aft", "left", "right"], true, true],
}


func _piece(piece_name: String) -> GearPiece:
	return load(GEAR + piece_name + ".tres") as GearPiece


func _mesh_of(piece: GearPiece) -> MeshInstance3D:
	var worn: Node = autofree(piece.scene.instantiate())
	return worn.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D


func test_the_stretching_pieces_are_those_of_the_table() -> void:
	var found: Array[String] = []
	for file: String in ResourceLoader.list_directory(GEAR):
		var piece := load(GEAR + file) as GearPiece
		if piece != null and piece.shape != null:
			found.append(file.get_basename())
	found.sort()
	assert_eq(found, ["apron", "mantle", "skirt_long", "skirt_short"] as Array[String])


func test_the_apron_table_fits_its_piece() -> void:
	_check_table("apron")


func test_the_mantle_table_fits_its_piece() -> void:
	_check_table("mantle")


func test_the_long_skirt_table_fits_its_piece() -> void:
	_check_table("skirt_long")


func test_the_short_skirt_table_fits_its_piece() -> void:
	_check_table("skirt_short")


## The table of `piece_name` names the piece's own shape keys, one ring list per key, each running
## upward from the hem with a reach at rest and a stretch. Cloth that stands out over a knee goes no
## further out at any ring than at its hem, and its hem by less than 0.6 of its reach at rest (the
## reach measured from the bone, which sits a little behind the skirt's middle: from the middle, the
## cap is 1.4, which the leg test measures); a swinging piece stretches less higher up.
func _check_table(piece_name: String) -> void:
	var piece: GearPiece = _piece(piece_name)
	assert_true(piece.cloth, piece_name)
	var shape: ClothShape = piece.shape
	assert_not_null(shape, piece_name)
	if shape == null:
		return
	var expected: Array = TABLES[piece_name]
	assert_eq(Array(shape.keys), expected[0], "%s: its keys" % piece_name)
	assert_eq(shape.flattens, expected[1], "%s: lays flat" % piece_name)
	assert_eq(shape.rings.size(), shape.keys.size(), "%s: one ring list per key" % piece_name)
	var mesh: MeshInstance3D = _mesh_of(piece)
	for key: String in shape.keys:
		assert_true(ClothFit.DIRECTIONS.has(StringName(key)), "%s: %s is a way the fit knows" % [piece_name, key])
		assert_gte(mesh.find_blend_shape_by_name(StringName(key)), 0, "%s: the mesh has %s" % [piece_name, key])
	assert_eq(mesh.find_blend_shape_by_name(&"flat") >= 0, shape.flattens, "%s: a flat key iff it lays flat" % piece_name)
	assert_eq(mesh.find_blend_shape_by_name(&"seat") >= 0, shape.seats, "%s: a seat key iff it seats" % piece_name)
	for k: int in mini(shape.rings.size(), shape.keys.size()):
		var rings: PackedVector3Array = shape.rings[k]
		var key: String = shape.keys[k]
		assert_gte(rings.size(), 2, "%s %s: rings" % [piece_name, key])
		assert_gt(rings[0].z, 0.0, "%s %s: the hem stretches" % [piece_name, key])
		for i: int in rings.size():
			assert_gt(rings[i].y, 0.0, "%s %s ring %d: a reach at rest" % [piece_name, key, i])
			assert_gte(rings[i].z, 0.0, "%s %s ring %d: no stretch inward" % [piece_name, key, i])
			if expected[2]:
				assert_lte(rings[i].y + rings[i].z, rings[0].y + rings[0].z + 0.001,
						"%s %s ring %d: no further out than the hem" % [piece_name, key, i])
			if i > 0:
				assert_gt(rings[i].x, rings[i - 1].x, "%s %s ring %d: upward" % [piece_name, key, i])
				if not expected[2]:
					assert_lte(rings[i].z, rings[i - 1].z, "%s %s ring %d: stretched less than the one below" % [piece_name, key, i])
		if expected[2]:
			assert_lt(rings[0].z, 0.6 * rings[0].y, "%s %s: the hem goes out by less than 0.6 of its reach" % [piece_name, key])


func test_the_fit_pushes_the_long_skirt_out_round_a_striding_leg_and_lets_it_go() -> void:
	var arena := Arena.new(self)
	var alvar: Unit = arena.spawn(Arena.ALVAR, Vector3.ZERO)
	await wait_physics_frames(2)
	var visual: UnitVisual = alvar.get_node(^"Visual")
	var fit: ClothFit = null
	var skirt: MeshInstance3D = null
	# His only piece that stretches four ways: the long skirt (the mantle stretches back only).
	for each: ClothFit in visual.cloth_fits():
		if each.mesh().find_blend_shape_by_name(&"left") >= 0:
			fit = each
			skirt = each.mesh()
	assert_not_null(fit, "Álvar's long skirt fits round his legs")
	if fit == null:
		return
	var fore: int = skirt.find_blend_shape_by_name(&"fore")
	var skeleton: Skeleton3D = visual.find_children("*", "Skeleton3D", true, false)[0]
	var thigh: int = skeleton.find_bone(&"DEF-thigh.L")
	# Held still, so no clip poses the skeleton meanwhile.
	visual.process_mode = Node.PROCESS_MODE_DISABLED
	# Standing as at rest, the legs are inside the skirt: nothing stretches.
	skeleton.reset_bone_poses()
	var rest: Quaternion = skeleton.get_bone_pose_rotation(thigh)
	fit.fit(1.0)
	assert_almost_eq(skirt.get_blend_shape_value(fore), 0.0, 0.01, "at rest")
	# The left leg swung forward by 50 degrees: the skirt is pushed out in front, not behind.
	var aft: int = skirt.find_blend_shape_by_name(&"aft")
	skeleton.set_bone_pose_rotation(thigh, rest * Quaternion(Vector3.RIGHT, deg_to_rad(-50.0)))
	var forward: float = _weight_after_fit(fit, skirt, fore)
	assert_gt(forward, 0.3, "a stride forward pushes the front out")
	assert_almost_eq(skirt.get_blend_shape_value(aft), 0.0, 0.01, "and not the back")
	# Swung back, the back is pushed out instead.
	skeleton.set_bone_pose_rotation(thigh, rest * Quaternion(Vector3.RIGHT, deg_to_rad(50.0)))
	assert_gt(_weight_after_fit(fit, skirt, aft), 0.3, "a stride back pushes the back out")
	assert_almost_eq(skirt.get_blend_shape_value(fore), 0.0, 0.01, "and not the front")
	skeleton.set_bone_pose_rotation(thigh, rest * Quaternion(Vector3.RIGHT, deg_to_rad(-50.0)))
	_weight_after_fit(fit, skirt, fore)
	# Back at rest, it lets go, slowly: not at once, fully within a second.
	skeleton.reset_bone_poses()
	fit.fit(0.05)
	assert_gt(skirt.get_blend_shape_value(fore), forward - 0.2, "it lets go slowly")
	fit.fit(1.0)
	assert_almost_eq(skirt.get_blend_shape_value(fore), 0.0, 0.01, "settled")


## The weight of the key `index` after fitting the pose on show, from a skirt let go.
func _weight_after_fit(fit: ClothFit, skirt: MeshInstance3D, index: int) -> float:
	fit.fit(1.0, true)
	fit.fit(1.0)
	return skirt.get_blend_shape_value(index)
