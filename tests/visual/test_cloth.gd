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


## The clips in which a leg moves most under a skirt, each sampled at `LEG_SAMPLES` times.
const BENT_CLIPS: Array[StringName] = [&"attack", &"cast", &"feed", &"sit", &"death", &"run"]
const LEG_SAMPLES: int = 5
const SKIRTED: Array[String] = ["alvar", "zahra", "malakor", "crusader", "sergeant"]
## Each leg's bones as the joints that bound them, hip to toe, and each part's name.
const LEGS: Array[Array] = [
	[&"DEF-thigh.L", &"DEF-shin.L", &"DEF-foot.L", &"DEF-toe.L"], [&"DEF-thigh.R", &"DEF-shin.R", &"DEF-foot.R", &"DEF-toe.R"],
]
const PARTS: Array[String] = ["thigh", "shin", "foot"]
## The leg's half-thickness at each joint, hip to toe, in metres.
const LEG_THICKNESS: Array[float] = [0.08, 0.06, 0.045, 0.03]
## Points sampled along each bone of a leg, ends included.
const ALONG: int = 5
## Standing, no hem may reach out further than this many times its reach at rest (the cap, and a
## little); lying, the flat key widens it by `FLAT_WIDENING` more (`wearable.py`'s `FLAT_WIDTH`).
const HEM_SPREAD: float = 1.45
const FLAT_WIDENING: float = 1.15


## In each bent clip, with the skirt fitted as the game fits it, no point of a leg lies outside the
## skirt where the skirt covers it: each point along the thigh, shin and foot, taken at the leg's side
## away from the skirt's middle, is joined to the skirt's middle at its own height, and that line must
## not cross the cloth. Below the hem a leg may show; where it does it is listed. And the hem never
## balloons past its cap.
func test_no_leg_comes_through_a_skirt_in_the_bent_clips() -> void:
	var checked: int = 0
	for dress_name: String in SKIRTED:
		var visual := UnitVisual.new()
		visual.dress = load("res://resources/dress/%s.tres" % dress_name)
		add_child_autofree(visual)
		visual.process_mode = Node.PROCESS_MODE_DISABLED
		var skeleton: Skeleton3D = visual.find_children("*", "Skeleton3D", true, false)[0]
		var player: AnimationPlayer = visual.find_children("*", "AnimationPlayer", true, false)[0]
		var skirts: Array[ClothFit] = visual.cloth_fits().filter(func(each: ClothFit) -> bool:
			return String(each.mesh().get_parent().get_parent().name).begins_with("skirt"))
		assert_eq(skirts.size(), 1, "%s wears one skirt" % dress_name)
		if skirts.is_empty():
			continue
		var fit: ClothFit = skirts[0]
		var mesh: MeshInstance3D = fit.mesh()
		var attachment := mesh.get_parent().get_parent() as BoneAttachment3D
		var hang: Transform3D = attachment.global_transform.affine_inverse() * mesh.global_transform
		var bone: int = skeleton.find_bone(attachment.bone_name)
		var arrays: Array = mesh.mesh.surface_get_arrays(0)
		var rest: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var triangles: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var middle: Vector2 = _middle(rest)
		var spread_out: PackedVector3Array = _spread_out(mesh, rest)
		var widest: float = 0.0
		var through: Array[String] = []
		var beyond: Dictionary = {}
		var below: Dictionary = {}
		for clip_name: StringName in BENT_CLIPS:
			var lying: bool = clip_name == &"death"
			var seated: bool = clip_name in UnitVisual.SEATED_CLIPS
			var length: float = player.get_animation(clip_name).length
			for sample: int in LEG_SAMPLES:
				var time: float = length * sample / float(LEG_SAMPLES - 1)
				player.play(clip_name)
				player.seek(time, true)
				fit.fit(UnitVisual.SETTLED_AFTER, lying, seated)
				var fitted: PackedVector3Array = _fitted(mesh, rest)
				if lying:
					widest = maxf(widest, _spread(rest, fitted, middle) / FLAT_WIDENING)
				elif not seated:  # seated, the front lies forward over the lap
					widest = maxf(widest, _spread(rest, fitted, middle))
				var reach: float = 0.0
				for vertex: Vector3 in fitted:
					reach = maxf(reach, (Vector2(vertex.x, vertex.z) - middle).length())
				var to_piece: Transform3D = (skeleton.get_bone_global_pose(bone) * hang).affine_inverse()
				for leg: Array in LEGS:
					var joints: Array[Vector3] = []
					for bone_name: StringName in leg:
						joints.append(to_piece * skeleton.get_bone_global_pose(skeleton.find_bone(bone_name)).origin)
					for part: int in PARTS.size():
						for step: int in ALONG:
							var t: float = step / float(ALONG - 1)
							var point: Vector3 = _beside(joints[part].lerp(joints[part + 1], t),
									lerpf(LEG_THICKNESS[part], LEG_THICKNESS[part + 1], t), middle)
							checked += 1
							var where: String = "%s %.2f s, %s %s at %d%%" % [clip_name, time, String(leg[0]).get_extension(),
									PARTS[part], roundi(t * 100.0)]
							var flat := Vector2(point.x, point.z) - middle
							if _crosses(Vector3(middle.x, point.y, middle.y), point, fitted, triangles):
								if _crosses(Vector3(middle.x, point.y, middle.y), point, spread_out, triangles):
									var key: String = "%s %s" % [clip_name, PARTS[part]]
									beyond[key] = int(beyond.get(key, 0)) + 1
								else:
									through.append(where)
							elif flat.length() > reach:
								var key: String = "%s %s" % [clip_name, PARTS[part]]
								below[key] = int(below.get(key, 0)) + 1
		gut.p("%s: the hem spreads to %.2f times its reach; %d leg points within the cap through the cloth;"
				% [dress_name, widest, through.size()] + " beyond the cap through it: %s; out below the hem: %s" % [beyond, below])
		for line: String in through:
			gut.p("  through: " + line)
		assert_lte(widest, HEM_SPREAD, "%s: no balloon" % dress_name)
		assert_eq(through, [] as Array[String], "%s: no leg comes through" % dress_name)
	assert_eq(checked, SKIRTED.size() * BENT_CLIPS.size() * LEG_SAMPLES * LEGS.size() * PARTS.size() * ALONG,
			"leg points checked")


## The skirt's vertices with its keys at their weights now, in the piece's frame.
func _fitted(mesh: MeshInstance3D, rest: PackedVector3Array) -> PackedVector3Array:
	var fitted: PackedVector3Array = rest.duplicate()
	var shapes: Array = mesh.mesh.surface_get_blend_shape_arrays(0)
	for k: int in shapes.size():
		var weight: float = mesh.get_blend_shape_value(k)
		if weight == 0.0:
			continue
		var shaped: PackedVector3Array = (shapes[k] as Array)[Mesh.ARRAY_VERTEX]
		for i: int in fitted.size():
			fitted[i] += (shaped[i] - rest[i]) * weight
	return fitted


## The skirt's middle, flat: the middle of its hem at rest, in the piece's frame.
static func _middle(rest: PackedVector3Array) -> Vector2:
	var lowest: float = INF
	for vertex: Vector3 in rest:
		lowest = minf(lowest, vertex.y)
	var middle := Vector2.ZERO
	var count: int = 0
	for vertex: Vector3 in rest:
		if vertex.y < lowest + 0.001:
			middle += Vector2(vertex.x, vertex.z)
			count += 1
	return middle / count


## How many times its reach at rest the fitted hem reaches at most, flat, from the skirt's `middle`.
static func _spread(rest: PackedVector3Array, fitted: PackedVector3Array, middle: Vector2) -> float:
	var lowest: float = INF
	for vertex: Vector3 in rest:
		lowest = minf(lowest, vertex.y)
	var widest: float = 0.0
	for i: int in rest.size():
		if rest[i].y < lowest + 0.001:
			var was: float = (Vector2(rest[i].x, rest[i].z) - middle).length()
			widest = maxf(widest, (Vector2(fitted[i].x, fitted[i].z) - middle).length() / was)
	return widest


## The skirt with every key that stretches it at full weight: as far as it can reach every way.
static func _spread_out(mesh: MeshInstance3D, rest: PackedVector3Array) -> PackedVector3Array:
	var spread_out: PackedVector3Array = rest.duplicate()
	var shapes: Array = mesh.mesh.surface_get_blend_shape_arrays(0)
	for k: int in shapes.size():
		if ClothFit.DIRECTIONS.has((mesh.mesh as ArrayMesh).get_blend_shape_name(k)):
			var shaped: PackedVector3Array = (shapes[k] as Array)[Mesh.ARRAY_VERTEX]
			for i: int in spread_out.size():
				spread_out[i] += shaped[i] - rest[i]
	return spread_out


## `point` moved `by` metres flat away from the skirt's `middle`.
static func _beside(point: Vector3, by: float, middle: Vector2) -> Vector3:
	var flat := Vector2(point.x, point.z) - middle
	if flat.length() < 0.001:
		return point
	flat = flat.normalized() * by
	return point + Vector3(flat.x, 0.0, flat.y)


## Whether the segment from `from` to `to` crosses any of the fitted skirt's triangles.
static func _crosses(from: Vector3, to: Vector3, fitted: PackedVector3Array, triangles: PackedInt32Array) -> bool:
	for t: int in range(0, triangles.size(), 3):
		if Geometry3D.segment_intersects_triangle(from, to, fitted[triangles[t]], fitted[triangles[t + 1]],
				fitted[triangles[t + 2]]) != null:
			return true
	return false
