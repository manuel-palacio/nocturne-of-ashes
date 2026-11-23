extends SceneTree
## Renders a head-and-shoulders portrait of each dressed character to `assets/portraits/<name>.png`,
## 256 × 256: the game's own figure (a `UnitVisual` wearing `resources/dress/<name>.tres`, so its
## model, palette, head and clothes), its cloth settled as the game settles it, held in its idle clip
## at `HOLD_AT`, framed from the top of the head to the top of the chest in a three-quarter view from
## a little below the eyes (so they show under a helmet's brim), lit by one warm key ahead of the face
## and to the side it looks towards, a faint cool fill on the other side and a fainter cool rim, on a
## dark ground. What it holds in its hands is hidden: it would only crowd the frame. Towards the edges,
## from a centre on the face, the whole picture darkens to `GROUND_EDGE`'s depth, so it sits on any
## dark panel without a seam. `<name>` is the dress's palette name (`palette-<name>.png`).
##
##     godot --path . -s tools/render_portraits.gd [-- <name>...]
##
## With Álvar's it also writes the title's picture of him, `assets/portraits/title-alvar.png`, 512 ×
## 512: the same view drawn larger, he moved towards its left (`TITLE_SHIFT`) so the face turned to
## the title's words stays clear of them, its edges fading out to transparent rather than to dark, so
## it melts into whatever ground the title has.
##
## With no names it renders every dress in `resources/dress/`. It draws, so it needs a window (not
## `--headless`). Each figure is drawn at 1024 px and scaled down on the CPU; the figure's own faint
## light for dark rooms (`UnitVisual.LIFT`) is turned off here, so the lights alone model the face and
## it is not flattened. Two runs on the same machine write the same bytes.

const DRESSES: String = "res://resources/dress/"
const OUT: String = "res://assets/portraits/"
const SIZE: int = 256
## The title's picture: whose, how large, and where it goes.
const TITLE_NAME: String = "alvar"
const TITLE_SIZE: int = 512
const TITLE_OUT: String = "res://assets/portraits/title-alvar.png"
## How far towards the left of the title's picture the figure is moved, as a share of its width: the
## title's words stand to the right of it, and the face turned towards them stays clear of them.
const TITLE_SHIFT: float = 0.14
## The size each portrait is drawn at before it is scaled down.
const DRAWN: int = 1024
## The ground behind the figure, at the middle and, as dark as the darkening makes it, at the edges.
const GROUND: Color = Color(0.085, 0.065, 0.055)
const GROUND_EDGE: Color = Color(0.008, 0.006, 0.006)
## The camera: how far round from straight in front (towards the figure's left, positive; this is round
## to its right, so its face looks across the picture to the right), its field of view, how far it
## stands from the head, and the point it looks at, above the head bone's joint, in metres.
const TURN_DEGREES: float = -18.0
const FOV: float = 20.0
const DISTANCE: float = 1.55
const LOOK_ABOVE_HEAD: float = 0.06
## How far above the point it looks at the camera stands, in metres: below it, so the eyes show
## under a helmet's brim.
const EYE_ABOVE: float = -0.08
## Where the warm key stands, seen from the head: turned about the vertical from straight in front
## (towards the figure's left, positive: the side its face looks towards) and raised, in degrees; and
## the faint cool fill, on the other side.
const KEY_YAW: float = 35.0
const KEY_PITCH: float = 12.0
const FILL_YAW: float = -70.0
const FILL_PITCH: float = 5.0
## The rim's place, behind the figure, as the key's.
const RIM_YAW: float = 160.0
const RIM_PITCH: float = 20.0
## Who looks across the picture to the left rather than the right (the camera, key and fill all
## mirrored): the sergeant, so the two soldiers, alike in helmet and frame, are not one picture.
const FACING_LEFT: Array[String] = ["sergeant"]
## The idle clip's time the figure is held at, in seconds.
const HOLD_AT: float = 0.0
## Where the darkening towards the edges is centred, as fractions of the picture's width and height:
## on the face, so the chest falls off into the dark sooner than the head.
const VIGNETTE_CENTRE: Vector2 = Vector2(0.5, 0.42)
## Where the darkening towards the edges starts, as a fraction of the way from its centre to an edge.
const VIGNETTE_FROM: float = 0.6

var _viewport: SubViewport
var _key: DirectionalLight3D
var _fill: DirectionalLight3D
var _rim: DirectionalLight3D


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var names: PackedStringArray = OS.get_cmdline_user_args()
	if names.is_empty():
		names = _all_names()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	_viewport = _stage()
	var failed: bool = false
	for name: String in names:
		var dress: Dress = _dress_named(name)
		if dress == null:
			push_error("No dress in %s has the palette %s" % [DRESSES, name])
			failed = true
			continue
		var drawn: Image = await _render(dress)
		failed = not _save(_portrait(drawn), OUT + name + ".png") or failed
		if name == TITLE_NAME:
			failed = not _save(_title_picture(await _render(dress, TITLE_SHIFT)), TITLE_OUT) or failed
	quit(1 if failed else 0)


func _save(image: Image, path: String) -> bool:
	if image.save_png(path) != OK:
		push_error("Could not write %s" % path)
		return false
	print("wrote ", path)
	return true


## Every dress's palette name, sorted.
func _all_names() -> PackedStringArray:
	var names: PackedStringArray = []
	for file: String in DirAccess.get_files_at(DRESSES):
		if file.ends_with(".tres"):
			var dress := load(DRESSES + file) as Dress
			if dress != null and dress.palette != null:
				names.append(dress.palette_name())
	names.sort()
	return names


func _dress_named(name: String) -> Dress:
	for file: String in DirAccess.get_files_at(DRESSES):
		if not file.ends_with(".tres"):
			continue
		var dress := load(DRESSES + file) as Dress
		if dress != null and dress.palette != null and dress.palette_name() == name:
			return dress
	return null


## The world the figures stand in: the viewport, its camera's ground and its lights.
func _stage() -> SubViewport:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(DRAWN, DRAWN)
	viewport.own_world_3d = true
	viewport.msaa_3d = Viewport.MSAA_4X
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = GROUND
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.32, 0.3, 0.34)
	environment.ambient_light_energy = 0.25
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var world := WorldEnvironment.new()
	world.environment = environment
	viewport.add_child(world)
	# The key: warm, raised a little, ahead of the face and to the side it looks towards, as from a
	# torch; no shadows, so a helmet's brim does not put out the eyes.
	_key = _light(Color(1.0, 0.87, 0.72), 1.0)
	# A faint cool fill from the other side, so the shadow side of the face keeps its shape, and a
	# fainter cool rim from behind, so dark hair and cloth part from the dark ground.
	_fill = _light(Color(0.62, 0.68, 0.86), 0.5)
	_rim = _light(Color(0.6, 0.62, 0.8), 0.5)
	for light: DirectionalLight3D in [_key, _fill, _rim]:
		viewport.add_child(light)
	var camera := Camera3D.new()
	camera.fov = FOV
	camera.current = true
	viewport.add_child(camera)
	return viewport


func _light(colour: Color, energy: float) -> DirectionalLight3D:
	var light := DirectionalLight3D.new()
	light.light_color = colour
	light.light_energy = energy
	return light


## Turns `light` to shine at the figure from `yaw` degrees round from straight in front of it (towards
## its left, positive) and `pitch` degrees above.
func _aim(light: DirectionalLight3D, yaw: float, pitch: float) -> void:
	var towards: Vector3 = Vector3(0.0, 0.0, -1.0).rotated(Vector3.UP, deg_to_rad(yaw))
	towards = towards.rotated(towards.cross(Vector3.UP).normalized(), deg_to_rad(pitch))
	light.basis = Basis.looking_at(-towards)


## Draws the figure wearing `dress`, at `DRAWN` px, on its ground, moved `shift` of the picture's width
## to the left.
func _render(dress: Dress, shift: float = 0.0) -> Image:
	var figure := UnitVisual.new()
	figure.dress = dress
	_viewport.add_child(figure)
	# Held in its idle clip at `HOLD_AT`; the clip is set on entering the tree.
	figure.process_mode = Node.PROCESS_MODE_DISABLED
	var player := figure.model().find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
	player.play(&"idle")
	player.seek(HOLD_AT, true)
	player.advance(0.0)
	_without_own_light(figure)
	_without_hand_gear(figure)
	# Its cloth fitted to the held pose, as the game fits it to a figure standing still.
	figure.settle_cloth()
	await RenderingServer.frame_post_draw
	var skeleton := figure.model().find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var head: Transform3D = skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone(&"DEF-head"))
	var target: Vector3 = head.origin + Vector3.UP * LOOK_ABOVE_HEAD
	var side: float = -1.0 if dress.palette_name() in FACING_LEFT else 1.0
	_aim(_key, KEY_YAW * side, KEY_PITCH)
	_aim(_fill, FILL_YAW * side, FILL_PITCH)
	_aim(_rim, RIM_YAW * side, RIM_PITCH)
	var camera: Camera3D = _viewport.get_camera_3d()
	# The model faces -Z; the camera stands in front of it, turned round to its right, so the face
	# looks across the picture towards the right (to the left for those `FACING_LEFT`).
	var turn: float = deg_to_rad(TURN_DEGREES * side)
	camera.position = target + Vector3(-sin(turn), 0.0, -cos(turn)) * DISTANCE + Vector3.UP * EYE_ABOVE
	camera.look_at(target)
	camera.h_offset = shift * 2.0 * DISTANCE * tan(deg_to_rad(FOV) * 0.5)
	for frame: int in 4:
		await RenderingServer.frame_post_draw
	var image: Image = _viewport.get_texture().get_image()
	_viewport.remove_child(figure)
	figure.free()
	image.convert(Image.FORMAT_RGB8)
	return image


## Hides what the figure holds in its hands (sword, shield, hammer, staff): in a head-and-shoulders
## picture it only crowds the frame or cuts across the face.
func _without_hand_gear(figure: UnitVisual) -> void:
	for node: Node in figure.find_children("*", "BoneAttachment3D", true, false):
		if String((node as BoneAttachment3D).bone_name).contains("hand"):
			(node as BoneAttachment3D).visible = false


## The portrait: `drawn` at `SIZE`, darkened towards its edges.
func _portrait(drawn: Image) -> Image:
	var image: Image = drawn.duplicate()
	image.resize(SIZE, SIZE, Image.INTERPOLATE_LANCZOS)
	_darken_edges(image)
	return image


## The title's picture: `drawn` at `TITLE_SIZE`, fading to transparent towards its edges.
func _title_picture(drawn: Image) -> Image:
	var image: Image = drawn.duplicate()
	image.resize(TITLE_SIZE, TITLE_SIZE, Image.INTERPOLATE_LANCZOS)
	image.convert(Image.FORMAT_RGBA8)
	var centre: Vector2 = VIGNETTE_CENTRE - Vector2(TITLE_SHIFT, 0.0)
	for y: int in TITLE_SIZE:
		for x: int in TITLE_SIZE:
			var pixel: Color = image.get_pixel(x, y)
			pixel.a = 1.0 - _fade(Vector2(x + 0.5, y + 0.5) / TITLE_SIZE, centre)
			image.set_pixel(x, y, pixel)
	return image


## Turns off the faint light every figure carries in the game, on all its materials.
func _without_own_light(figure: UnitVisual) -> void:
	for node: Node in figure.find_children("*", "MeshInstance3D", true, false):
		var material := (node as MeshInstance3D).material_override as StandardMaterial3D
		if material != null:
			material.emission_energy_multiplier = 0.0


## Darkens the picture towards its edges: each pixel is scaled by how far it lies from
## `VIGNETTE_CENTRE`, from `VIGNETTE_FROM` of the way to an edge, so figure and ground fall off together.
func _darken_edges(image: Image) -> void:
	var ground_lum: float = GROUND.get_luminance()
	var edge_lum: float = GROUND_EDGE.get_luminance()
	for y: int in SIZE:
		for x: int in SIZE:
			var keep: float = lerpf(1.0, edge_lum / ground_lum, _fade(Vector2(x + 0.5, y + 0.5) / SIZE, VIGNETTE_CENTRE))
			var pixel: Color = image.get_pixel(x, y)
			image.set_pixel(x, y, Color(pixel.r * keep, pixel.g * keep, pixel.b * keep))


## How far a pixel at `at` (as fractions of the picture's width and height) has faded towards the
## edges, from 0 inside `VIGNETTE_FROM` of the way from `centre` to an edge to 1 at the edge and beyond:
## the way to each edge is measured from `centre`, so a picture whose centre is off its middle fades
## out fully on every side.
func _fade(at: Vector2, centre: Vector2) -> float:
	var off: Vector2 = at - centre
	off.x /= centre.x if off.x < 0.0 else 1.0 - centre.x
	off.y /= centre.y if off.y < 0.0 else 1.0 - centre.y
	return smoothstep(VIGNETTE_FROM, 1.0, off.length())
