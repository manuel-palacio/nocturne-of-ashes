class_name ClothFit
extends RefCounted
## Keeps the legs inside a cloth piece hung rigidly from one bone. The piece's shape keys (`fore`, `aft`,
## `left`, `right`, made by `tools/blender/gear.py`) stretch its hem that way, more the lower it hangs.
## Each time the skeleton is posed, `fit()` sets each key just far enough that every leg point at a
## height the piece covers lies inside it, so a striding leg pushes the skirt out and a running
## figure's mantle swings back. A key lets go slowly, so the cloth settles rather than snaps.
## It reads the skeleton and writes only the piece's own key weights.

## Each key's way, in the piece's frame (the model's frame at rest: -z is forward, -x the left).
const DIRECTIONS: Dictionary = {
	&"fore": Vector3(0, 0, -1), &"aft": Vector3(0, 0, 1), &"left": Vector3(-1, 0, 0), &"right": Vector3(1, 0, 0),
}
## Down each leg, the points that must stay inside, as a share of the way from the hip to the knee
## (0 to 1) and from the knee to the ankle (1 to 2), and the leg's half-thickness there, in metres.
const POINTS: Array[Vector2] = [Vector2(0.5, 0.085), Vector2(1.0, 0.075), Vector2(1.5, 0.065), Vector2(2.0, 0.055)]
const LEGS: Array[Array] = [
	[&"DEF-thigh.L", &"DEF-shin.L", &"DEF-foot.L"], [&"DEF-thigh.R", &"DEF-shin.R", &"DEF-foot.R"],
]
## How fast a key lets go, in full weights per second.
const SETTLE: float = 2.5
## How fast the hem lays flat once the figure lies down, and rises again, in full weights per second.
const FLATTEN: float = 1.5
## A point the keys face less squarely than this (the sum of the cubes of how squarely each faces it)
## is beside the piece, not inside it, as beside a mantle open at the front; it pushes nothing.
const SQUARELY: float = 0.3

var _mesh: MeshInstance3D
var _skeleton: Skeleton3D
var _bone: int
## The piece's mesh relative to its bone.
var _hang: Transform3D
var _clearance: float
var _legs: Array[PackedInt32Array] = []
## One entry per key: its blend shape index, its way, and per ring of the piece, from the lowest up,
## (height, reach of the piece that way at rest, how much further the key takes it at full weight).
var _keys: Array[Dictionary] = []
## The `flat` key's blend shape index, or −1.
var _flat: int = -1

static var _measured: Dictionary = {}  # ArrayMesh -> what `_measure()` found


## `hang` is where the mesh lies relative to `bone`'s pose; `clearance` is how far it keeps from the
## legs beyond their thickness.
func _init(mesh: MeshInstance3D, skeleton: Skeleton3D, bone: int, hang: Transform3D, clearance: float) -> void:
	_mesh = mesh
	_skeleton = skeleton
	_bone = bone
	_hang = hang
	_clearance = clearance
	for leg: Array in LEGS:
		var bones := PackedInt32Array()
		for bone_name: StringName in leg:
			bones.append(skeleton.find_bone(bone_name))
		_legs.append(bones)
	var array_mesh := mesh.mesh as ArrayMesh
	if array_mesh == null:
		return
	# Every wearer of a piece shares its mesh, so its rings are worked out once.
	if not _measured.has(array_mesh):
		_measured[array_mesh] = _measure(array_mesh)
	var measured: Dictionary = _measured[array_mesh]
	_flat = measured["flat"]
	_keys = measured["keys"]


## The `flat` key's index (or −1) and the stretching keys of `array_mesh`, as `_keys` holds them.
static func _measure(array_mesh: ArrayMesh) -> Dictionary:
	var flat: int = -1
	var keys: Array[Dictionary] = []
	var rest: PackedVector3Array = array_mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var shapes: Array = array_mesh.surface_get_blend_shape_arrays(0)
	for index: int in array_mesh.get_blend_shape_count():
		if array_mesh.get_blend_shape_name(index) == &"flat":
			flat = index
			continue
		var way: Variant = DIRECTIONS.get(array_mesh.get_blend_shape_name(index))
		if way == null:
			continue
		var shaped: PackedVector3Array = shapes[index][Mesh.ARRAY_VERTEX]
		if array_mesh.blend_shape_mode == Mesh.BLEND_SHAPE_MODE_RELATIVE:
			for i: int in shaped.size():
				shaped[i] += rest[i]
		keys.append({"index": index, "way": way, "rings": _rings(rest, shaped, way)})
	return {"flat": flat, "keys": keys}


func is_fitting() -> bool:
	return not _keys.is_empty() or _flat >= 0


## Sets every key from the legs as now posed; `delta` is the time since the last fit. While `lying`,
## the `flat` key (where there is one) lays the hem flat and the others let go.
func fit(delta: float, lying: bool = false) -> void:
	if _flat >= 0:
		var flat: float = move_toward(_mesh.get_blend_shape_value(_flat), 1.0 if lying else 0.0, FLATTEN * delta)
		_mesh.set_blend_shape_value(_flat, flat)
	if _keys.is_empty():
		return
	var to_piece: Transform3D = (_skeleton.get_bone_global_pose(_bone) * _hang).affine_inverse()
	var wanted: PackedFloat32Array = PackedFloat32Array()
	wanted.resize(_keys.size())
	if not lying:
		for point: Vector4 in _leg_points(to_piece):
			_push(point, wanted)
	for k: int in _keys.size():
		var index: int = _keys[k]["index"]
		var target: float = clampf(wanted[k], 0.0, 1.0)
		var now: float = _mesh.get_blend_shape_value(index)
		_mesh.set_blend_shape_value(index, maxf(target, move_toward(now, target, SETTLE * delta)))


## Each leg's points in the piece's frame, with the room each needs round it as `w`.
func _leg_points(to_piece: Transform3D) -> Array[Vector4]:
	var points: Array[Vector4] = []
	for leg: PackedInt32Array in _legs:
		var joints: Array[Vector3] = []
		for bone: int in leg:
			joints.append(_skeleton.get_bone_global_pose(bone).origin)
		for point: Vector2 in POINTS:
			var along: float = point.x
			var at: Vector3 = joints[0].lerp(joints[1], along) if along <= 1.0 else joints[1].lerp(joints[2], along - 1.0)
			var local: Vector3 = to_piece * at
			points.append(Vector4(local.x, local.y, local.z, point.y + _clearance))
	return points


## Raises the keys' `wanted` weights so that `point`, with its room, lies inside the piece. The piece's
## reach towards the point is taken as the ellipse through the keys' reaches; the keys facing it share
## the push, each by how squarely it faces the point.
func _push(point: Vector4, wanted: PackedFloat32Array) -> void:
	var flat := Vector2(point.x, point.z)
	if flat.length() < 0.001:
		return
	var toward: Vector2 = flat.normalized()
	var inverse_square: float = 0.0
	var shared: float = 0.0
	var facing: PackedFloat32Array = PackedFloat32Array()
	facing.resize(_keys.size())
	for k: int in _keys.size():
		var rings: PackedVector3Array = _keys[k]["rings"]
		if point.y < rings[0].x or point.y > rings[rings.size() - 1].x:
			return
		var way: Vector3 = _keys[k]["way"]
		var square: float = maxf(toward.dot(Vector2(way.x, way.z)), 0.0)
		var ring: Vector3 = _ring_at(rings, point.y)
		if square <= 0.0 or ring.z <= 0.005:
			continue
		facing[k] = square / ring.z  # divided out below, so a key's weight is its share of its reach
		inverse_square += pow(square / maxf(ring.y, 0.01), 2.0)
		shared += pow(square, 3.0)
	if shared < SQUARELY or inverse_square <= 0.0:
		return
	var need: float = flat.length() + point.w - 1.0 / sqrt(inverse_square)
	if need <= 0.0:
		return
	for k: int in _keys.size():
		if facing[k] > 0.0:
			wanted[k] = maxf(wanted[k], need * facing[k] / shared)


## Per height of the mesh's rings, lowest first: (height, reach along `way` at rest, extra reach of the
## key at full weight).
static func _rings(rest: PackedVector3Array, shaped: PackedVector3Array, way: Vector3) -> PackedVector3Array:
	var by_height: Dictionary = {}  # int millimetres -> Vector2(reach, extra)
	for i: int in rest.size():
		var height: int = roundi(rest[i].y * 1000.0)
		var reach: float = rest[i].dot(way)
		var extra: float = (shaped[i] - rest[i]).dot(way)
		var known: Vector2 = by_height.get(height, Vector2(-INF, 0.0))
		if reach > known.x:
			by_height[height] = Vector2(reach, extra)
	var heights: Array = by_height.keys()
	heights.sort()
	var rings := PackedVector3Array()
	for height: int in heights:
		var ring: Vector2 = by_height[height]
		rings.append(Vector3(height / 1000.0, ring.x, ring.y))
	return rings


static func _ring_at(rings: PackedVector3Array, height: float) -> Vector3:
	for i: int in range(1, rings.size()):
		if height <= rings[i].x:
			var t: float = inverse_lerp(rings[i - 1].x, rings[i].x, height)
			return rings[i - 1].lerp(rings[i], t)
	return rings[rings.size() - 1]
