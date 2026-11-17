class_name FeedDrop
extends Node3D
## The mark over a figure that can be fed on: a pale drop with a dark outline, bobbing slowly. It is
## unshaded, so it reads in the dark and against any body colour, and it casts no shadow; it shares
## the marks' one material. It bobs while its figure processes, so it stops with the world.

const COLOUR: Color = Color(0.98, 0.93, 0.9)
const OUTLINE: Color = Color(0.12, 0.0, 0.02)
## How much bigger the outline shell is than the drop, in metres.
const OUTLINE_WIDTH: float = 0.024
## Metres up and down, and how long one bob takes, in seconds.
const BOB: float = 0.05
const BOB_TIME: float = 2.4
const SIDES: int = 14

static var _mesh: ArrayMesh

var _time: float = 0.0
var _drop: MeshInstance3D


func _ready() -> void:
	_drop = MeshInstance3D.new()
	_drop.name = &"Drop"
	_drop.mesh = _shared_mesh()
	_drop.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_drop)


func _process(delta: float) -> void:
	_time = fmod(_time + delta, BOB_TIME)
	_drop.position.y = BOB * sin(TAU * _time / BOB_TIME)


## A drop 0.2 m tall, its round end at the bottom, near its origin, in pale vertex colours; round it a
## slightly larger dark shell turned inside out, so only its far side is drawn: the outline.
static func _shared_mesh() -> ArrayMesh:
	if _mesh != null:
		return _mesh
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	_lathe(tool, _profile(0.0), COLOUR, false)
	_lathe(tool, _profile(OUTLINE_WIDTH), OUTLINE, true)
	_mesh = tool.commit()
	_mesh.surface_set_material(0, FloorRing.marks_material())
	return _mesh


## The drop's outline from the bottom to the tip, as (radius, height), grown by `grow` all round.
static func _profile(grow: float) -> Array[Vector2]:
	var profile: Array[Vector2] = []
	var radius: float = 0.085 + grow
	for i: int in 7:
		var a: float = -PI / 2.0 + (PI / 2.0 + 0.5) * i / 6.0
		profile.append(Vector2(radius * cos(a), radius * sin(a)))
	profile.append(Vector2(0.0, 0.2 + grow * 1.5))
	return profile


## Turns `profile` round the vertical axis, facing out, or in when `inward`.
static func _lathe(tool: SurfaceTool, profile: Array[Vector2], colour: Color, inward: bool) -> void:
	tool.set_color(colour)
	var steps: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 0), Vector2i(1, 1), Vector2i(0, 0), Vector2i(1, 1), Vector2i(0, 1)]
	if inward:
		steps = [Vector2i(0, 0), Vector2i(1, 1), Vector2i(1, 0), Vector2i(0, 0), Vector2i(0, 1), Vector2i(1, 1)]
	for ring: int in profile.size() - 1:
		for side: int in SIDES:
			for step: Vector2i in steps:
				var point: Vector2 = profile[ring + step.y]
				var a: float = TAU * (side + step.x) / SIDES
				tool.add_vertex(Vector3(point.x * cos(a), point.y - 0.03, point.x * sin(a)))
