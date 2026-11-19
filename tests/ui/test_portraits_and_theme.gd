# tests/ui/test_portraits_and_theme.gd
extends GutTest

const MAIN := preload("res://scenes/main.tscn")
const GAME := preload("res://scenes/game.tscn")
const HAVEN := preload("res://scenes/rooms/forge_haven.tscn")
const BOX := preload("res://scenes/ui/dialogue_box.tscn")
const THEME := preload("res://resources/ui/theme.tres")
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


func test_each_party_panel_shows_its_members_portrait() -> void:
	await _skirmish()
	var expected: Array[String] = ["alvar", "zahra", "gonzalo"]
	for index: int in 3:
		var portrait := main.hud.panels()[index].find_child("Portrait") as TextureRect
		assert_not_null(portrait)
		assert_eq(portrait.texture.resource_path, "res://assets/portraits/%s.png" % expected[index])
		assert_eq(portrait.size, Vector2(64, 64))
		assert_null(main.hud.panels()[index].find_child("Swatch"), "the swatch is gone")


func test_the_dialogue_box_shows_the_speakers_portrait_and_none_for_a_stranger() -> void:
	var box: DialogueBox = add_child_autofree(BOX.instantiate())
	var runner: DialogueRunner = autofree(DialogueRunner.new())
	box.bind(runner)
	var lines: Array[String] = []
	runner.line_shown.emit("Malakor", "You wake.", lines)
	await wait_physics_frames(2)
	var portrait := box.find_child("Portrait") as TextureRect
	assert_true(portrait.is_visible_in_tree())
	assert_eq(portrait.texture.resource_path, "res://assets/portraits/malakor.png")
	assert_eq(portrait.size, Vector2(128, 128))
	runner.line_shown.emit("Somebody", "Who am I?", lines)
	await wait_physics_frames(2)
	assert_false(portrait.is_visible_in_tree())


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


func test_every_control_of_the_hud_the_dialogue_box_and_the_title_uses_the_theme() -> void:
	await _boot_with_title(null)
	var title: TitleScreen = _title()
	var hud: Hud = main.hud
	var controls: Array[Control] = _controls(title) + _controls(hud)
	assert_gt(controls.size(), 20)
	for control: Control in controls:
		assert_eq(_theme_of(control), THEME, str(control.get_path()))
		assert_eq(control.get_theme_default_font(), THEME.default_font, str(control.get_path()))
		var label := control as Label
		if label != null and label.label_settings != null:
			assert_null(label.label_settings.font, "%s keeps the theme's face" % label.get_path())


func test_a_panel_and_a_gift_button_write_nothing_while_nothing_changes() -> void:
	await _skirmish()
	main.set_paused(true)
	await wait_physics_frames(2)
	var panel: PartyMemberPanel = main.hud.panels()[0]
	var button: GiftButton = main.hud.gift_buttons()[0]
	var panel_writes: int = panel.text_writes()
	var button_writes: int = button.text_writes()
	await wait_physics_frames(30)
	assert_eq(panel.text_writes(), panel_writes)
	assert_eq(button.text_writes(), button_writes)
	main.player.stats.spend_blood(42)  # 18, too little for Iron Sinew's 20
	main.player.take_hit(10)
	await wait_physics_frames(2)
	assert_gt(panel.text_writes(), panel_writes, "a change is written")
	assert_gt(button.text_writes(), button_writes, "a change is written")


# --- The controls card ---

func test_the_hud_question_button_opens_the_controls_card_and_holds_the_world() -> void:
	await _skirmish()
	var hold := main.get_node("WorldHold") as WorldHold
	var button := main.hud.find_child("ControlsButton") as Button
	assert_eq(button.text, "?")
	assert_eq(button.focus_mode, Control.FOCUS_NONE)
	button.pressed.emit()
	await wait_physics_frames(2)
	var card := main.hud.find_child("ControlsCard") as ControlsCard
	assert_true(card.is_open())
	assert_true(hold.is_held())
	assert_true(hold.is_air_held(), "the room's air freezes, as on pause")
	assert_false(main.is_paused(), "a hold of its own, not the pause")
	await _tap(&"pause")
	assert_false(main.is_paused(), "Space does not pause behind the card")
	await _tap(&"cancel")
	assert_false(card.is_open())
	assert_false(hold.is_held())


func test_a_click_outside_the_card_closes_it_and_gives_no_order() -> void:
	await _skirmish()
	var card := main.hud.find_child("ControlsCard") as ControlsCard
	main.hud.find_child("ControlsButton").pressed.emit()
	await wait_physics_frames(2)
	assert_true(card.is_open())
	_click(main.hud.get_viewport(), Vector2(30, 680))
	await wait_physics_frames(2)
	assert_false(card.is_open())
	assert_eq(main.player.current_order(), Unit.Order.NONE)
	assert_false((main.get_node("WorldHold") as WorldHold).is_held())


func test_the_card_lists_every_control_in_both_languages() -> void:
	await _skirmish()
	var card := main.hud.find_child("ControlsCard") as ControlsCard
	assert_eq(card.rows(), 9)
	assert_true(card.text().contains("Space"))
	Language.apply("es")
	await wait_physics_frames(2)
	assert_true(card.text().contains("Espacio"), card.text())
	TranslationServer.set_locale("en")


func test_the_title_controls_button_opens_the_card_and_escape_closes_it() -> void:
	await _boot_with_title(null)
	var button := _title().find_child("ControlsButton") as Button
	assert_eq(button.text, "Controls")
	button.pressed.emit()
	await wait_physics_frames(2)
	var card := _title().find_child("ControlsCard") as ControlsCard
	assert_true(card.is_open())
	await _tap(&"confirm")
	assert_true(_title().is_open(), "Enter does not start a game behind the card")
	await _tap(&"cancel")
	assert_false(card.is_open())
	assert_true(_title().is_open())


# --- The fallen prompt and the cleared line ---

func test_the_fallen_prompt_says_enter_or_click() -> void:
	await _skirmish()
	main.player.take_hit(999)
	await wait_physics_frames(2)
	assert_eq(main.hud.find_child("FallenLabel").text, "You have fallen — press Enter or click")
	Language.apply("es")
	await wait_physics_frames(2)
	assert_eq(main.hud.find_child("FallenLabel").text, "Has caído — pulsa Intro o haz clic")
	TranslationServer.set_locale("en")


func test_the_cleared_line_fades_after_four_seconds() -> void:
	await _skirmish()
	assert_eq(main.hud.cleared_time, 4.0)
	main.hud.cleared_time = 0.3
	var label := main.hud.find_child("ClearedLabel") as Label
	main.hud.show_cleared()
	await wait_seconds(0.2)
	assert_true(label.visible)
	await wait_seconds(0.3 + Hud.CLEARED_FADE + 0.2)
	assert_false(label.visible)
