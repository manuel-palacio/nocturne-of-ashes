# tests/ui/test_portraits_and_theme.gd
extends GutTest

const MAIN := preload("res://scenes/main.tscn")
const GAME := preload("res://scenes/game.tscn")
const HAVEN := preload("res://scenes/rooms/forge_haven.tscn")
const BOX := preload("res://scenes/ui/dialogue_box.tscn")
const PALETTES: Array[String] = ["alvar", "captive", "crusader", "gonzalo", "malakor", "sergeant", "smith", "zahra"]

var main: Main


func after_each() -> void:
	Story.finish(main)


func _skirmish() -> void:
	main = add_child_autoqfree(MAIN.instantiate())
	await wait_physics_frames(3)


func _boot_with_title(saved: GameState) -> void:
	main = GAME.instantiate()
	main.store = SaveStore.new()
	main.store.path = "user://test_portraits_title_%d.json" % randi()
	main.store.clear()
	if saved != null:
		main.store.save(saved)
	main.opening_enabled = false
	add_child_autofree(main)
	await wait_physics_frames(3)


func _title() -> TitleScreen:
	return main.find_child("TitleScreen") as TitleScreen


func _click(viewport: Viewport, at: Vector2) -> void:
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.position = at
	click.global_position = at
	click.pressed = true
	viewport.push_input(click, true)
	var release: InputEventMouseButton = click.duplicate()
	release.pressed = false
	viewport.push_input(release, true)


func _tap(action: StringName) -> void:
	Input.action_press(action)
	await wait_physics_frames(2)
	Input.action_release(action)
	await wait_physics_frames(2)


func _controls(under: Node) -> Array[Control]:
	var found: Array[Control] = []
	for node: Node in under.find_children("*", "Control", true, false):
		found.append(node as Control)
	if under is Control:
		found.append(under as Control)
	return found


## The theme a control draws with: its own, else its nearest ancestor control's.
func _theme_of(control: Control) -> Theme:
	var node: Node = control
	while node is Control:
		if (node as Control).theme != null:
			return (node as Control).theme
		node = node.get_parent()
	return null


# --- Portraits ---

func test_a_portrait_exists_for_each_palette_at_256_px() -> void:
	for palette: String in PALETTES:
		var path: String = "res://assets/portraits/%s.png" % palette
		assert_true(ResourceLoader.exists(path), path)
		var texture: Texture2D = load(path)
		assert_eq(texture.get_size(), Vector2(256, 256), path)
		# Not an empty frame: a lit figure on a dark ground.
		var image: Image = texture.get_image()
		if image.is_compressed():
			image.decompress()
		var middle: Color = image.get_pixel(128, 110)
		var corner: Color = image.get_pixel(4, 4)
		assert_gt(middle.get_luminance(), corner.get_luminance(), path)
		assert_lt(corner.get_luminance(), 0.12, path)


func test_every_speaker_in_the_haven_wears_the_portrait_of_their_dress() -> void:
	var haven: Node = autofree(HAVEN.instantiate())
	var npcs: Array[Node] = haven.find_children("*", "Npc", true, false)
	assert_gt(npcs.size(), 4)
	for node: Node in npcs:
		var npc := node as Npc
		assert_not_null(Portraits.of_speaker(npc.label), npc.label)
		assert_eq(Portraits.of_speaker(npc.label), Portraits.of_dress(npc.dress), npc.label)
	assert_eq(Portraits.of_speaker("Álvar").resource_path, "res://assets/portraits/alvar.png")
	assert_null(Portraits.of_speaker("Somebody"))
