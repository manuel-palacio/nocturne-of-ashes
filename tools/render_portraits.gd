extends SceneTree
## Renders a head-and-shoulders portrait of each dressed character to `assets/portraits/<name>.png`,
## 256 × 256: the game's own figure (a `UnitVisual` wearing `resources/dress/<name>.tres`, so its
## model, palette and gear), standing in the first frame of its idle clip, seen in a three-quarter
## view, lit warm from one side with a faint cool fill and rim, on a dark ground; towards the edges
## the whole picture darkens to `GROUND_EDGE`'s depth, so it sits on any dark panel without a seam. `<name>` is the dress's palette name (`palette-<name>.png`).
##
##     godot --path . -s tools/render_portraits.gd [-- <name>...]
##
## With no names it renders every dress in `resources/dress/`. It draws, so it needs a window (not
## `--headless`). Each figure is drawn at 1024 px and scaled down on the CPU; the figure's own faint
## light (`UnitVisual.LIFT`) is turned off here, so the side light alone models the face. Two runs on
## the same machine write the same bytes.

const DRESSES: String = "res://resources/dress/"
const OUT: String = "res://assets/portraits/"
const SIZE: int = 256
## The size each portrait is drawn at before it is scaled down.
const DRAWN: int = 1024
## The ground behind the figure, at the middle and, as dark as the darkening makes it, at the edges.
const GROUND: Color = Color(0.085, 0.065, 0.055)
const GROUND_EDGE: Color = Color(0.008, 0.006, 0.006)
## The camera: how far round from straight in front (towards the figure's left), its field of view,
## and where it looks, as fractions of the figure's height.
const TURN_DEGREES: float = 32.0
const FOV: float = 24.0
const LOOK_AT: float = 0.85
const DISTANCE: float = 1.95
const EYE_ABOVE: float = 0.05
## Where the darkening towards the edges starts, as a fraction of the way from the middle to an edge.
const VIGNETTE_FROM: float = 0.45

var _viewport: SubViewport


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
		var image: Image = await _render(dress)
		var path: String = OUT + name + ".png"
		if image.save_png(path) != OK:
			push_error("Could not write %s" % path)
			failed = true
			continue
		print("wrote ", path)
	quit(1 if failed else 0)


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
	environment.ambient_light_energy = 0.35
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var world := WorldEnvironment.new()
	world.environment = environment
	viewport.add_child(world)
	# The key: warm, high and to the figure's right, as from a torch beside it.
	viewport.add_child(_light(Color(1.0, 0.84, 0.68), 1.3, Vector3(-30.0, -62.0, 0.0), true))
	# A faint cool fill from the other side and a rim from behind, so the dark side keeps its shape.
	viewport.add_child(_light(Color(0.45, 0.52, 0.7), 0.35, Vector3(-10.0, 70.0, 0.0), false))
	viewport.add_child(_light(Color(0.75, 0.7, 0.9), 0.9, Vector3(-20.0, 160.0, 0.0), false))
	var camera := Camera3D.new()
	camera.fov = FOV
	camera.current = true
	viewport.add_child(camera)
	return viewport


func _light(colour: Color, energy: float, degrees: Vector3, shadows: bool) -> DirectionalLight3D:
	var light := DirectionalLight3D.new()
	light.light_color = colour
	light.light_energy = energy
	light.rotation_degrees = degrees
	light.shadow_enabled = shadows
	return light


## Draws the figure wearing `dress` and gives it at `SIZE`, on its ground.
func _render(dress: Dress) -> Image:
	var figure := UnitVisual.new()
	figure.dress = dress
	_viewport.add_child(figure)
	# Held in its first idle frame: the clip is set and posed on entering the tree.
	figure.process_mode = Node.PROCESS_MODE_DISABLED
	_without_own_light(figure)
	var camera: Camera3D = _viewport.get_camera_3d()
	var target := Vector3(0.0, dress.height * LOOK_AT, 0.0)
	# The model faces -Z; the camera stands in front of it, turned towards the figure's left.
	var turn: float = deg_to_rad(TURN_DEGREES)
	camera.position = target + Vector3(-sin(turn), 0.0, -cos(turn)) * DISTANCE + Vector3.UP * EYE_ABOVE
	camera.look_at(target)
	for frame: int in 4:
		await RenderingServer.frame_post_draw
	var image: Image = _viewport.get_texture().get_image()
	_viewport.remove_child(figure)
	figure.free()
	image.convert(Image.FORMAT_RGB8)
	image.resize(SIZE, SIZE, Image.INTERPOLATE_LANCZOS)
	_darken_edges(image)
	return image


## Turns off the faint light every figure carries in the game, on all its materials.
func _without_own_light(figure: UnitVisual) -> void:
	for node: Node in figure.find_children("*", "MeshInstance3D", true, false):
		var material := (node as MeshInstance3D).material_override as StandardMaterial3D
		if material != null:
			material.emission_energy_multiplier = 0.0


## Darkens the picture towards its edges: each pixel is scaled by how far it lies from the middle,
## from `VIGNETTE_FROM` of the way to an edge's midpoint, so figure and ground fall off together.
func _darken_edges(image: Image) -> void:
	var middle := Vector2(SIZE, SIZE) * 0.5
	var ground_lum: float = GROUND.get_luminance()
	var edge_lum: float = GROUND_EDGE.get_luminance()
	for y: int in SIZE:
		for x: int in SIZE:
			var reach: float = (Vector2(x + 0.5, y + 0.5) - middle).length() / (SIZE * 0.5)
			var keep: float = lerpf(1.0, edge_lum / ground_lum, smoothstep(VIGNETTE_FROM, 1.0, reach))
			var pixel: Color = image.get_pixel(x, y)
			image.set_pixel(x, y, Color(pixel.r * keep, pixel.g * keep, pixel.b * keep))
