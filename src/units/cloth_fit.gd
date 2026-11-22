class_name ClothFit
extends RefCounted
## Keeps the legs inside a cloth piece hung rigidly from one bone. The piece's shape keys (`fore`, `aft`,
## `left`, `right`, made by `tools/blender/gear.py`) stand it out that way as over a knee, to at most
## 1.4 times its hem's reach; a skirt's `<way>_up` keys lift its hem that way once a leg needs more. Each time the skeleton is posed, `fit()`
## sets each key just far enough that every leg point at a height the piece covers lies inside it, so a
## striding leg pushes the skirt out where it strides and a running figure's mantle swings back; a leg
## further out than the keys can go shows below the lifted hem. A key lets go slowly, so the cloth settles rather than snaps.
## It reads the skeleton and writes only the piece's own key weights.

## Each key's way, in the piece's frame (the model's frame at rest: -z is forward, -x the left).
const DIRECTIONS: Dictionary = {
	&"fore": Vector3(0, 0, -1), &"aft": Vector3(0, 0, 1), &"left": Vector3(-1, 0, 0), &"right": Vector3(1, 0, 0),
}
## Down each leg, the points that must stay inside, as a share of the way from the hip to the knee
## (0 to 1) and from the knee to the ankle (1 to 2), and the leg's half-thickness there, in metres.
const POINTS: Array[Vector2] = [
	Vector2(0.5, 0.085), Vector2(0.75, 0.08), Vector2(1.0, 0.075), Vector2(1.25, 0.07), Vector2(1.5, 0.065),
	Vector2(1.75, 0.06), Vector2(2.0, 0.055),
]
const LEGS: Array[Array] = [
	[&"DEF-thigh.L", &"DEF-shin.L", &"DEF-foot.L"], [&"DEF-thigh.R", &"DEF-shin.R", &"DEF-foot.R"],
]
## The `hang` key starts to lay the cloth against the back once the piece leans over by more than
## this (the sine of the angle, fore or aft), and lays it fully `HANG_FULL` further.
const HANG_FROM: float = 0.1
const HANG_FULL: float = 0.25
## A figure lies only once its piece's bone leans further than this from upright (the cosine of the
## angle): falling, it still stands at first, and its hem lies flat only as it comes down.
const LYING_UPRIGHT: float = 0.7
## How fast a key lets go, in full weights per second.
const SETTLE: float = 2.5
## How fast the hem lays flat once the figure lies down, and rises again, in full weights per second.
const FLATTEN: float = 1.5
## A point the keys face less squarely than this (the sum of the cubes of how squarely each faces it)
## is beside the piece, not inside it, as beside a mantle open at the front; it pushes nothing.
const SQUARELY: float = 0.3

## The pieces are lathes of 16 sides: between two of their columns the cloth lies this much nearer the
## middle than the ellipse through their reaches (1 / cos(180° / 16)), so a point needs that much more.
const CHORD: float = 1.02
## A key's `_up` key lifts the hem fully once a leg needs this much more than the key's full weight
## (a wanted weight of 1 + this).
const LIFT_BEYOND: float = 0.25
## A key's weight is written only when it moves by more than this: each write marks the mesh dirty.
const STEP: float = 0.002

var _mesh: MeshInstance3D
var _skeleton: Skeleton3D
var _bone: int
## The piece's mesh relative to its bone.
var _hang: Transform3D
var _clearance: float
## The leg bones, three per leg (hip, knee, ankle), left leg first.
var _legs: PackedInt32Array = PackedInt32Array()
## Per stretching key: its blend shape index, its way flat on XZ (x, z), and its rings, from the
## lowest up, as (height, reach of the piece that way at rest, how much further the key takes it).
var _indices: PackedInt32Array = PackedInt32Array()
## Per stretching key: its `_up` key's blend shape index, or −1.
var _ups: PackedInt32Array = PackedInt32Array()
var _ways: PackedVector2Array = PackedVector2Array()
var _rings: Array[PackedVector3Array] = []
## The `flat` key's blend shape index, or −1.
var _flat: int = -1
## The `seat` key's blend shape index, or −1.
var _seat: int = -1
## The `hang` key's blend shape index, or −1.
var _drape: int = -1
## The weights last written: the stretching keys', their `_up` keys', then the `flat`, `seat` and
## `hang` keys'.
var _weights: PackedFloat32Array = PackedFloat32Array()
## Reused every fit: the leg points (x, y, z in the piece's frame, and the room each needs), each
## key's wanted weight, and how squarely each key faces the point being pushed.
var _points: PackedVector4Array = PackedVector4Array()
var _wanted: PackedFloat32Array = PackedFloat32Array()
var _facing: PackedFloat32Array = PackedFloat32Array()
var _squares: PackedFloat32Array = PackedFloat32Array()


## `hang` is where the mesh lies relative to `bone`'s pose; `clearance` is how far it keeps from the
## legs beyond their thickness; `shape` holds the piece's measured tables. Nothing is read from the
## mesh. A skeleton without the leg bones is reported once, and the piece then does not fit.
func _init(mesh: MeshInstance3D, skeleton: Skeleton3D, bone: int, hang: Transform3D, clearance: float,
		shape: ClothShape) -> void:
	_mesh = mesh
	_skeleton = skeleton
	_bone = bone
	_hang = hang
	_clearance = clearance
	if shape == null:
		return
	for leg: Array in LEGS:
		for bone_name: StringName in leg:
			var leg_bone: int = skeleton.find_bone(bone_name)
			if leg_bone < 0:
				push_error("The skeleton has no %s; %s will not fit round the legs" % [bone_name, mesh.name])
				return
			_legs.append(leg_bone)
	if shape.flattens:
		_flat = mesh.find_blend_shape_by_name(&"flat")
	if shape.seats:
		_seat = mesh.find_blend_shape_by_name(&"seat")
	if shape.hangs:
		_drape = mesh.find_blend_shape_by_name(&"hang")
	for k: int in shape.keys.size():
		var key_name := StringName(shape.keys[k])
		var index: int = mesh.find_blend_shape_by_name(key_name)
		if index >= 0 and DIRECTIONS.has(key_name):
			var way: Vector3 = DIRECTIONS[key_name]
			_indices.append(index)
			_ups.append(mesh.find_blend_shape_by_name(StringName(key_name + "_up")) if shape.lifts else -1)
			_ways.append(Vector2(way.x, way.z))
			_rings.append(shape.rings[k])
	_weights.resize(_indices.size() * 2 + 3)
	_wanted.resize(_indices.size())
	_facing.resize(_indices.size())
	_squares.resize(_indices.size())
	_points.resize(LEGS.size() * POINTS.size())


## The piece it fits.
func mesh() -> MeshInstance3D:
	return _mesh


func is_fitting() -> bool:
	return not _indices.is_empty() or _flat >= 0 or _seat >= 0 or _drape >= 0


## Sets every key from the legs as now posed; `delta` is the time since the last fit. While `lying`,
## the `flat` key (where there is one) lays the hem flat, and the legs still push it out; while
## `seated`, the `seat` key (where there is one) lays the front over the lap and the stretching keys
## let go. The `hang` key follows how far the piece leans over. Returns whether any weight moved.
func fit(delta: float, lying: bool = false, seated: bool = false) -> bool:
	var moved: bool = false
	lying = lying and _skeleton.get_bone_global_pose(_bone).basis.y.normalized().y < LYING_UPRIGHT
	var flat_slot: int = _indices.size() * 2
	if _flat >= 0:
		moved = _write(_flat, flat_slot, move_toward(_weights[flat_slot], 1.0 if lying else 0.0, FLATTEN * delta))
	if _seat >= 0:
		var seated_now: bool = seated and not lying
		moved = _write(_seat, flat_slot + 1, move_toward(_weights[flat_slot + 1], 1.0 if seated_now else 0.0,
				FLATTEN * delta)) or moved
	if _drape >= 0:
		var down: Vector3 = (_skeleton.get_bone_global_pose(_bone) * _hang).basis.inverse() * Vector3.DOWN
		var lean: float = clampf((absf(down.normalized().z) - HANG_FROM) / HANG_FULL, 0.0, 1.0)
		moved = _write(_drape, flat_slot + 2, move_toward(_weights[flat_slot + 2], lean, FLATTEN * delta)) or moved
	if _indices.is_empty():
		return moved
	_wanted.fill(0.0)
	if not (seated and _seat >= 0):
		_place_points()
		for point: Vector4 in _points:
			_push(point)
	for k: int in _indices.size():
		var target: float = clampf(_wanted[k], 0.0, 1.0)
		var weight: float = maxf(target, move_toward(_weights[k], target, SETTLE * delta))
		moved = _write(_indices[k], k, weight) or moved
		if _ups[k] >= 0:
			var up: int = _indices.size() + k
			var lift: float = clampf((_wanted[k] - 1.0) / LIFT_BEYOND, 0.0, 1.0)
			moved = _write(_ups[k], up, maxf(lift, move_toward(_weights[up], lift, SETTLE * delta))) or moved
	return moved


## Writes `weight` to the blend shape `index` (stored at `slot`) if it moved by more than `STEP`, or
## reached a rest; returns whether it was written.
func _write(index: int, slot: int, weight: float) -> bool:
	var settled: bool = weight == 0.0 or weight == 1.0
	if absf(weight - _weights[slot]) <= STEP and not (settled and weight != _weights[slot]):
		return false
	_weights[slot] = weight
	_mesh.set_blend_shape_value(index, weight)
	return true


## Fills `_points` with each leg's points in the piece's frame, with the room each needs round it as `w`.
func _place_points() -> void:
	var to_piece: Transform3D = (_skeleton.get_bone_global_pose(_bone) * _hang).affine_inverse()
	var at: int = 0
	for leg: int in LEGS.size():
		var hip: Vector3 = _skeleton.get_bone_global_pose(_legs[leg * 3]).origin
		var knee: Vector3 = _skeleton.get_bone_global_pose(_legs[leg * 3 + 1]).origin
		var ankle: Vector3 = _skeleton.get_bone_global_pose(_legs[leg * 3 + 2]).origin
		for point: Vector2 in POINTS:
			var along: float = point.x
			var local: Vector3 = to_piece * (hip.lerp(knee, along) if along <= 1.0 else knee.lerp(ankle, along - 1.0))
			_points[at] = Vector4(local.x, local.y, local.z, point.y + _clearance)
			at += 1


## Raises the keys' wanted weights so that `point`, with its room, lies inside the piece. The piece's
## reach towards the point is taken as the ellipse through the keys' reaches; the keys facing it share
## the push, each by how squarely it faces the point.
func _push(point: Vector4) -> void:
	var flat := Vector2(point.x, point.z)
	var distance: float = flat.length()
	if distance < 0.001:
		return
	var toward: Vector2 = flat / distance
	var inverse_square: float = 0.0
	var shared: float = 0.0
	for k: int in _indices.size():
		var rings: PackedVector3Array = _rings[k]
		if point.y < rings[0].x or point.y > rings[rings.size() - 1].x:
			return
		_facing[k] = 0.0
		_squares[k] = 0.0
		var square: float = maxf(toward.dot(_ways[k]), 0.0)
		if square <= 0.0:
			continue
		var ring: Vector3 = _ring_at(rings, point.y)
		if ring.z <= 0.005:
			continue
		_facing[k] = square / ring.z  # divided out below, so a key's weight is its share of its reach
		_squares[k] = square * square * square
		inverse_square += pow(square / maxf(ring.y, 0.01), 2.0)
		shared += square * square * square
	if shared < SQUARELY or inverse_square <= 0.0:
		return
	var need: float = (distance + point.w) * CHORD - 1.0 / sqrt(inverse_square)
	if need <= 0.0:
		return
	# What a key facing the point squarely cannot give beyond its full weight, the others facing it
	# give instead, so the cloth goes out as far as its keys together can take it.
	var lost: float = 0.0
	var others: float = 0.0
	for k: int in _indices.size():
		var weight: float = need * _facing[k] / shared
		if weight > 1.0:
			lost += need * _squares[k] / shared * (1.0 - 1.0 / weight)
		elif _facing[k] > 0.0:
			others += _squares[k]
	for k: int in _indices.size():
		if _facing[k] > 0.0:
			var weight: float = need * _facing[k] / shared
			if weight < 1.0 and others > 0.0:
				weight += lost * _facing[k] / others
			_wanted[k] = maxf(_wanted[k], weight)


static func _ring_at(rings: PackedVector3Array, height: float) -> Vector3:
	for i: int in range(1, rings.size()):
		if height <= rings[i].x:
			var t: float = inverse_lerp(rings[i - 1].x, rings[i].x, height)
			return rings[i - 1].lerp(rings[i], t)
	return rings[rings.size() - 1]
