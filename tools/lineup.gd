extends SceneTree
## Captures frames of the dressed figures for judging their look, into `build/shots/`.
##
##     godot --path . -s tools/lineup.gd -- <name>.png [view=front|side|back|three_quarter]
##         [frame=head|body] [clip=idle] [time=0.0] [dress names...]
##     godot --path . -s tools/lineup.gd -- <name>.png game
##
## The first form draws each dress (every one in `resources/dress/`, sorted, unless names are given)
## as the game builds it (a `UnitVisual`), held in `clip` at `time` seconds, in an even, neutral light
## on a mid-grey ground, each in its own square side by side, four to a row: `frame=head` is the head
## and shoulders, centred on the head bone; `frame=body` the whole figure, centred on its hips. The figure's own faint light
## is turned off. The second form boots the skirmish, stills everyone's brain, and captures the game
## camera as it starts, two of the enemies brought in beside the party. It draws, so it needs a window (not `--headless`).

const DRESSES: String = "res://resources/dress/"
const OUT: String = "res://build/shots/"
const CELL: int = 480
const PER_ROW: int = 4
const GROUND: Color = Color(0.42, 0.42, 0.43)
## How far the camera stands, and its field of view, per framing.
const FRAMES: Dictionary = {"head": [1.6, 18.0], "body": [5.2, 24.0]}
const VIEWS: Dictionary = {"front": 0.0, "three_quarter": -34.0, "side": -90.0, "back": 180.0}

var _viewport: SubViewport


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.is_empty() or not args[0].ends_with(".png"):
		push_error("Usage: godot --path . -s tools/lineup.gd -- <name>.png [options] [names]")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var out: String = OUT + args[0]
	if args.has("game"):
		quit(await _game(out))
		return
	var options: Dictionary = {"view": "front", "frame": "head", "clip": "idle", "time": "0.0"}
	var names: PackedStringArray = []
	for arg: String in args.slice(1):
		if "=" in arg:
			options[arg.get_slice("=", 0)] = arg.get_slice("=", 1)
		else:
			names.append(arg)
	if names.is_empty():
		for file: String in ResourceLoader.list_directory(DRESSES):
			if file.ends_with(".tres"):
				names.append(file.get_basename())
		names.sort()
	_viewport = _stage()
	var sheet := Image.create_empty(CELL * mini(names.size(), PER_ROW),
			CELL * ceili(names.size() / float(PER_ROW)), false, Image.FORMAT_RGB8)
	for i: int in names.size():
		var dress := load(DRESSES + names[i] + ".tres") as Dress
		var drawn: Image = await _render(dress, options)
		sheet.blit_rect(drawn, Rect2i(Vector2i.ZERO, drawn.get_size()), Vector2i(i % PER_ROW, i / PER_ROW) * CELL)
	quit(_save(sheet, out))


func _save(image: Image, path: String) -> int:
	if image.save_png(path) != OK:
		push_error("Could not write %s" % path)
		return 1
	print("wrote ", path)
	return 0


## The world each figure stands in: even light from the front-left, front-right and above.
func _stage() -> SubViewport:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(CELL, CELL)
	viewport.own_world_3d = true
	viewport.msaa_3d = Viewport.MSAA_4X
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = GROUND
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color.WHITE
	environment.ambient_light_energy = 0.35
	var world := WorldEnvironment.new()
	world.environment = environment
	viewport.add_child(world)
	for degrees: Vector3 in [Vector3(-25.0, -40.0, 0.0), Vector3(-25.0, 40.0, 0.0), Vector3(-70.0, 0.0, 0.0)]:
		var light := DirectionalLight3D.new()
		light.rotation_degrees = degrees
		light.light_energy = 0.55
		viewport.add_child(light)
	var camera := Camera3D.new()
	camera.current = true
	viewport.add_child(camera)
	return viewport


func _render(dress: Dress, options: Dictionary) -> Image:
	var figure := UnitVisual.new()
	figure.dress = dress
	_viewport.add_child(figure)
	figure.process_mode = Node.PROCESS_MODE_DISABLED
	for node: Node in figure.find_children("*", "MeshInstance3D", true, false):
		var material := (node as MeshInstance3D).material_override as StandardMaterial3D
		if material != null:
			material.emission_energy_multiplier = 0.0
	var player := figure.model().find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
	player.play(StringName(options["clip"]))
	player.seek(float(options["time"]), true)
	player.advance(0.0)
	figure.settle_cloth()
	var skeleton := figure.model().find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	await RenderingServer.frame_post_draw
	var target: Vector3 = _bone(skeleton, &"DEF-hips")
	if options["frame"] == "head":
		target = _bone(skeleton, &"DEF-head") + Vector3(0.0, 0.07, 0.0)
	var framing: Array = FRAMES[options["frame"]]
	var camera: Camera3D = _viewport.get_camera_3d()
	camera.fov = framing[1]
	var turn: float = deg_to_rad(VIEWS[options["view"]])
	camera.position = target + Vector3(-sin(turn), 0.0, -cos(turn)) * float(framing[0])
	camera.look_at(target)
	for frame: int in 3:
		await RenderingServer.frame_post_draw
	var image: Image = _viewport.get_texture().get_image()
	_viewport.remove_child(figure)
	figure.free()
	image.convert(Image.FORMAT_RGB8)
	return image


func _bone(skeleton: Skeleton3D, bone: StringName) -> Vector3:
	return (skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone(bone))).origin


## The skirmish as it starts, at the game camera, with every brain stilled.
func _game(out: String) -> int:
	root.size = Vector2i(1600, 900)
	var main: Main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	main.show_title = false
	root.add_child(main)
	for frame: int in 30:
		await process_frame
	for unit: Node in get_nodes_in_group(&"units"):
		var brain: Node = unit.get_node_or_null("Brain")
		if brain != null:
			brain.set(&"enabled", false)
	# Two of the enemies brought in beside the party, so both kinds of figure share the frame.
	var beside: Array[Vector3] = [Vector3(1.6, 0.0, -0.6), Vector3(2.2, 0.0, 0.8)]
	for i: int in mini(main.enemies.size(), beside.size()):
		main.enemies[i].global_position = main.player.global_position + beside[i]
	main.rig.snap_to_target()
	for frame: int in 30:
		await process_frame
	await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	image.convert(Image.FORMAT_RGB8)
	return _save(image, out)
