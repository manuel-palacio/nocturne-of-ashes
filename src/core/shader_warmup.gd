class_name ShaderWarmup
extends Node
## Draws rooms once each, off screen, while the title is up, so that their shaders are compiled then
## and not on the game's first frame. The Compatibility renderer compiles a shader the first time
## something is drawn with it, and a browser's WebGL can take a second for each (Firefox does; it holds
## the page still meanwhile), so the first frame of a room can take several seconds. Here that wait
## falls on the title, where the player is reading, after the title has been drawn.
##
## Each room is drawn in its own small `SubViewport` with a world of its own, from above, with a
## selection ring in view (the marks have their shader too), and is freed on the next frame, once the
## frame it was added in has been drawn (the engine draws after processing, in the same frame).
## `stop()` frees whatever is left; nothing of it stays in the game's world.

## Frames the title is drawn on before the first room is, so it shows before the wait.
const TITLE_FRAMES: int = 10
## The off-screen view's size in pixels; the shaders compiled do not depend on it.
const VIEW_SIZE: Vector2i = Vector2i(320, 180)
## The view looks down at the room's middle from this far, at the game camera's pitch, wide enough
## to hold every room.
const VIEW_DISTANCE: float = 40.0
const VIEW_PITCH_DEGREES: float = 57.0
const VIEW_SIZE_METRES: float = 34.0

var _waiting: Array[PackedScene] = []
var _title_frames: int = 0
var _warming: bool = false
var _view: SubViewport


func _ready() -> void:
	set_process(_warming)


## Draws each of `rooms` in turn, one a frame, after `TITLE_FRAMES` frames, in place of any warmup
## still going.
func start(rooms: Array[PackedScene]) -> void:
	stop()
	_waiting = rooms.duplicate()
	_title_frames = TITLE_FRAMES
	_warming = true
	set_process(true)


## Frees the room being drawn, if any, and draws no more.
func stop() -> void:
	_waiting.clear()
	_free_view()
	_warming = false
	set_process(false)


## True until every room given to `start()` has been drawn, or `stop()`.
func is_warming() -> bool:
	return _warming


## The view drawing a room now, if any.
func view() -> SubViewport:
	return _view


func _process(_delta: float) -> void:
	# The room added in the last frame has been drawn at its end.
	_free_view()
	if _title_frames > 0:
		_title_frames -= 1
		return
	if _waiting.is_empty():
		stop()
		return
	_view = _make_view(_waiting.pop_front())
	add_child(_view)


func _make_view(room: PackedScene) -> SubViewport:
	var view := SubViewport.new()
	view.name = &"WarmupView"
	view.size = VIEW_SIZE
	view.own_world_3d = true
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	view.add_child(room.instantiate())
	var ring := FloorRing.new()
	view.add_child(ring)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = VIEW_SIZE_METRES
	camera.far = VIEW_DISTANCE * 2.0
	var pitch: float = deg_to_rad(VIEW_PITCH_DEGREES)
	camera.position = Vector3(0.0, sin(pitch), cos(pitch)) * VIEW_DISTANCE
	camera.rotation = Vector3(-pitch, 0.0, 0.0)
	camera.current = true
	view.add_child(camera)
	return view


func _free_view() -> void:
	if _view == null:
		return
	remove_child(_view)
	_view.queue_free()
	_view = null
