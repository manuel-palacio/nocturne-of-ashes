class_name ShaderWarmup
extends Node
## Draws the rooms off screen while the title is up, a few kinds of thing a frame, so that their
## shaders are compiled then and not on the game's first frame. The Compatibility renderer compiles a
## shader the first time something is drawn with it, and a browser's WebGL can hold the page for a
## second for each program it links (Firefox does), so a room drawn whole took over nine seconds in a
## single frame there. Spread over frames, the title is drawn and takes clicks and keys between them.
##
## Each room gets its own small `SubViewport` with a world of its own, seen from above, with a
## selection ring (the marks have their shader too). At first only the ring shows, then, a frame each,
## the room's built pieces (those with normal maps, the stone kit, then the rest, such as the flames),
## its lights' shadows, its people, and its sparks and embers, each kind drawn with the shaders the
## kinds before it already compiled. A shader's first use still costs about two seconds in Firefox,
## one for each of the two programs the renderer links for it at once; that is the longest frame.
## The frame after the last kind, the view is freed and the next room's is added. `finished` is
## emitted after the last room; `stop()` frees whatever is left without it. Either way `ended` follows,
## once. Nothing of it stays in the game's world.

## Emitted once every room given to `start()` has been drawn whole.
signal finished
## Emitted once the warmup is over, whether it finished or was stopped.
signal ended

## Frames the title is drawn on before the first room is, so it shows before the work starts.
const TITLE_FRAMES: int = 10
## The off-screen view's size in pixels; the shaders compiled do not depend on it.
const VIEW_SIZE: Vector2i = Vector2i(320, 180)
## The view looks down at the room's middle from this far, at the game camera's pitch, wide enough
## to hold every room.
const VIEW_DISTANCE: float = 40.0
const VIEW_PITCH_DEGREES: float = 57.0
const VIEW_SIZE_METRES: float = 34.0

## What a room shows, a step at a time, after the frame with only the ring.
enum Step { KIT, PIECES, SHADOWS, PEOPLE, AIR, DONE }

var _waiting: Array[PackedScene] = []
var _title_frames: int = 0
var _warming: bool = false
var _view: SubViewport
var _step: Step = Step.DONE
## The room's drawn things by kind, hidden until their step, and its lights that cast shadows.
var _kit: Array[GeometryInstance3D] = []
var _pieces: Array[GeometryInstance3D] = []
var _people: Array[GeometryInstance3D] = []
var _air: Array[GeometryInstance3D] = []
var _shadowed: Array[Light3D] = []


func _ready() -> void:
	set_process(_warming)


## Draws each of `rooms` in turn, after `TITLE_FRAMES` frames, in place of any warmup still going.
func start(rooms: Array[PackedScene]) -> void:
	stop()
	_waiting = rooms.duplicate()
	_title_frames = TITLE_FRAMES
	_warming = true
	set_process(true)


## Frees the room being drawn, if any, and draws no more; `finished` is not emitted, `ended` is if it
## was warming.
func stop() -> void:
	var was_warming: bool = _warming
	_halt()
	if was_warming:
		ended.emit()


## True until every room given to `start()` has been drawn, or `stop()`.
func is_warming() -> bool:
	return _warming


## The view drawing a room now, if any.
func view() -> SubViewport:
	return _view


func _process(_delta: float) -> void:
	# What was shown in the last frame has been drawn at its end (the engine draws after processing).
	if _title_frames > 0:
		_title_frames -= 1
		return
	if _view != null and _step != Step.DONE:
		_show(_step)
		_step = (_step + 1) as Step
		return
	_free_view()
	if _waiting.is_empty():
		_halt()
		finished.emit()
		ended.emit()
		return
	_view = _make_view()
	add_child(_view)
	# In the tree first, so that the room's people have dressed by the time they are sorted.
	_fill(_view, _waiting.pop_front())
	_step = Step.KIT


func _show(step: Step) -> void:
	match step:
		Step.KIT:
			_reveal(_kit)
		Step.PIECES:
			_reveal(_pieces)
		Step.SHADOWS:
			for light: Light3D in _shadowed:
				light.shadow_enabled = true
		Step.PEOPLE:
			_reveal(_people)
		Step.AIR:
			_reveal(_air)


func _reveal(things: Array[GeometryInstance3D]) -> void:
	for thing: GeometryInstance3D in things:
		if is_instance_valid(thing):
			thing.visible = true


## An empty view, with a world of its own, a camera over a room's middle and a ring.
func _make_view() -> SubViewport:
	var view := SubViewport.new()
	view.name = &"WarmupView"
	view.size = VIEW_SIZE
	view.own_world_3d = true
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	view.add_child(FloorRing.new())
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


## Puts `room` in `view` with only the ring showing: everything the room draws is hidden and sorted
## by kind, and its lights cast no shadows yet.
func _fill(view: SubViewport, room: PackedScene) -> void:
	var instance: Node = room.instantiate()
	view.add_child(instance)
	view.move_child(instance, 0)
	_kit.clear()
	_pieces.clear()
	_people.clear()
	_air.clear()
	_shadowed.clear()
	for node: Node in instance.find_children("*", "GeometryInstance3D", true, false):
		var thing := node as GeometryInstance3D
		if not thing.visible:
			continue
		if thing is CPUParticles3D or thing is GPUParticles3D:
			_air.append(thing)
		elif _in_figure(thing, instance):
			_people.append(thing)
		elif _normal_mapped(thing):
			_kit.append(thing)
		else:
			_pieces.append(thing)
		thing.visible = false
	for node: Node in instance.find_children("*", "Light3D", true, false):
		var light := node as Light3D
		if light.shadow_enabled:
			_shadowed.append(light)
			light.shadow_enabled = false


## Whether `thing` belongs to a person's figure (under a `UnitVisual`) inside `room`.
static func _in_figure(thing: Node, room: Node) -> bool:
	var node: Node = thing.get_parent()
	while node != null and node != room:
		if node is UnitVisual:
			return true
		node = node.get_parent()
	return false


## Whether `thing` draws its first surface with a normal-mapped material, as the stone kit does.
static func _normal_mapped(thing: GeometryInstance3D) -> bool:
	var material: Material = thing.material_override
	var mesh_instance := thing as MeshInstance3D
	if material == null and mesh_instance != null and mesh_instance.mesh != null \
			and mesh_instance.mesh.get_surface_count() > 0:
		material = mesh_instance.get_active_material(0)
	return material is BaseMaterial3D and (material as BaseMaterial3D).normal_enabled


func _halt() -> void:
	_waiting.clear()
	_free_view()
	_warming = false
	set_process(false)


func _free_view() -> void:
	_step = Step.DONE
	_kit.clear()
	_pieces.clear()
	_people.clear()
	_air.clear()
	_shadowed.clear()
	if _view == null:
		return
	remove_child(_view)
	_view.queue_free()
	_view = null
