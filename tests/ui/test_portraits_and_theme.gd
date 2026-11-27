# tests/ui/test_portraits_and_theme.gd
extends GutTest

const MAIN := preload("res://scenes/main.tscn")
const GAME := preload("res://scenes/game.tscn")
const HAVEN := preload("res://scenes/rooms/forge_haven.tscn")
const BOX := preload("res://scenes/ui/dialogue_box.tscn")
const THEME := preload("res://resources/ui/theme.tres")
const PALETTES: Array[String] = ["alvar", "captive", "crusader", "gonzalo", "malakor", "sergeant", "smith", "zahra"]
## How a palette's square may look under the portraits' lights: from this much dimmer to this much
## brighter, and this far off its colour once brought to its brightness.
const PORTRAIT_DIMMEST: float = 0.35
const PORTRAIT_BRIGHTEST: float = 1.6
const PORTRAIT_HUE_SLACK: float = 0.15
## How far an eye white lies from its iris at most, in pixels of a 256 px portrait, and how unlike
## their brightness may be (as a factor) for them to be in the same light.
const EYE_REACH: int = 4
const EYE_SAME_LIGHT: float = 1.6
## An eye's iris, in pixels of a 256 px portrait: its size, fewest and most; how far the middle third's
## columns are widened to look for it (the sergeant, facing left, has his far eye's middle 3 px outside
## the third); how far apart two eyes' middles lie, least and most; how far apart their rows may be; and
## how many pixels of skin lie between them at least.
const EYE_SIZE: Vector2i = Vector2i(3, 150)
const EYE_MARGIN: int = 8
const EYE_APART: Vector2 = Vector2(18.0, 50.0)
const EYE_LEVEL: float = 5.0
const EYE_BRIDGE: int = 5
## How unlike two portraits' light and shade (`_shape`) are at least, on average per pixel: the same
## portrait recoloured scores about 0.03 to 0.11.
const PORTRAITS_APART: float = 0.15

var main: Main


## GUT's layers a test hid.
var _runner_layers: Array[Node] = []


func after_each() -> void:
	Story.finish(main)
	for node: Node in _runner_layers:
		if is_instance_valid(node):
			(node as CanvasLayer).visible = true
	_runner_layers.clear()


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


## The portrait of `palette` as an image, decompressed.
func _portrait_image(palette: String) -> Image:
	var image: Image = (load("res://assets/portraits/%s.png" % palette) as Texture2D).get_image()
	if image.is_compressed():
		image.decompress()
	image.convert(Image.FORMAT_RGB8)
	return image


## The colour of `region`'s square in the palette `palette`.
func _square(palette: String, region: Dress.Region) -> Color:
	var image: Image = (load("res://assets/characters/human/palette-%s.png" % palette) as Texture2D).get_image()
	if image.is_compressed():
		image.decompress()
	return image.get_pixel(region * image.get_width() / Dress.Region.size(), 0)


## How strongly `square`'s colour is lit at each pixel of `image`: the pixel's brightness over the
## square's where the pixel is that colour under some light (as bright as it from `PORTRAIT_DIMMEST` to
## `PORTRAIT_BRIGHTEST` times, and, brought to its brightness, within `PORTRAIT_HUE_SLACK` of it); 0
## where it is not.
func _lit_as(image: Image, square: Color) -> PackedFloat32Array:
	var lit := PackedFloat32Array()
	lit.resize(image.get_width() * image.get_height())
	var square_lum: float = maxf(square.get_luminance(), 0.001)
	for y: int in image.get_height():
		for x: int in image.get_width():
			var pixel: Color = image.get_pixel(x, y)
			var ratio: float = maxf(pixel.get_luminance(), 0.001) / square_lum
			if ratio < PORTRAIT_DIMMEST or ratio > PORTRAIT_BRIGHTEST:
				continue
			var scaled: Color = pixel * (1.0 / ratio)
			var off: float = maxf(maxf(absf(scaled.r - square.r), absf(scaled.g - square.g)), absf(scaled.b - square.b))
			if off < PORTRAIT_HUE_SLACK:
				lit[y * image.get_width() + x] = ratio
	return lit


## The clusters of the iris's colour near the middle third of `palette`'s portrait (its rows, and its
## columns widened by `EYE_MARGIN` on each side) that could be an eye: 8-connected, of `EYE_SIZE`
## pixels, and with the eye white's colour beside them (beside some of their pixels, within `EYE_REACH`
## along the row, in the same light: brightness within `EYE_SAME_LIGHT` of each other's; one side is
## enough, as the far eye in a three-quarter view shows white on one side only). Each is a Dictionary: `size`,
## `centre` (Vector2), `left` and `right` (its outermost columns).
func _eye_clusters(image: Image, palette: String) -> Array[Dictionary]:
	var width: int = image.get_width()
	var white: PackedFloat32Array = _lit_as(image, _square(palette, Dress.Region.EYE_WHITE))
	var iris: PackedFloat32Array = _lit_as(image, _square(palette, Dress.Region.IRIS))
	var third: int = width / 3
	var area := Rect2i(third - EYE_MARGIN, third, third + 2 * EYE_MARGIN, third)
	var seen: Dictionary[Vector2i, bool] = {}
	var clusters: Array[Dictionary] = []
	for y: int in range(area.position.y, area.end.y):
		for x: int in range(area.position.x, area.end.x):
			if iris[y * width + x] == 0.0 or seen.has(Vector2i(x, y)):
				continue
			var cluster: Array[Vector2i] = [Vector2i(x, y)]
			seen[Vector2i(x, y)] = true
			var next: int = 0
			while next < cluster.size():
				var at: Vector2i = cluster[next]
				next += 1
				for dy: int in range(-1, 2):
					for dx: int in range(-1, 2):
						var near: Vector2i = at + Vector2i(dx, dy)
						if area.has_point(near) and not seen.has(near) and iris[near.y * width + near.x] > 0.0:
							seen[near] = true
							cluster.append(near)
			if cluster.size() < EYE_SIZE.x or cluster.size() > EYE_SIZE.y:
				continue
			var beside: Array[bool] = [false, false]
			var centre := Vector2.ZERO
			var left: int = width
			var right: int = 0
			for at: Vector2i in cluster:
				centre += Vector2(at) / cluster.size()
				left = mini(left, at.x)
				right = maxi(right, at.x)
				var light: float = iris[at.y * width + at.x]
				for step: int in range(-EYE_REACH, EYE_REACH + 1):
					var other: float = white[at.y * width + at.x + step]
					if step != 0 and other > 0.0 and absf(log(other / light)) < log(EYE_SAME_LIGHT):
						beside[0 if step < 0 else 1] = true
			if beside[0] or beside[1]:
				clusters.append({"size": cluster.size(), "centre": centre, "left": left, "right": right})
	return clusters


## The two eyes of `palette`'s portrait: two of `_eye_clusters`, one either side of the face's vertical
## midline, which in a three-quarter view is the skin between the eyes (the outline's middle is no
## guide: the near eye lies on it), so: at least `EYE_BRIDGE` pixels of skin on the row between them, the
## two `EYE_APART` pixels apart and level (rows within `EYE_LEVEL`). Of such pairs, the one with the
## most iris pixels; empty when there is none.
func _eyes(palette: String) -> Array[Dictionary]:
	var image: Image = _portrait_image(palette)
	var width: int = image.get_width()
	var skin: PackedFloat32Array = _lit_as(image, _square(palette, Dress.Region.SKIN))
	var clusters: Array[Dictionary] = _eye_clusters(image, palette)
	var best: Array[Dictionary] = []
	var best_size: int = 0
	for a: Dictionary in clusters:
		for b: Dictionary in clusters:
			var gap: float = (b.centre as Vector2).x - (a.centre as Vector2).x
			if gap < EYE_APART.x or gap > EYE_APART.y or absf((b.centre as Vector2).y - (a.centre as Vector2).y) > EYE_LEVEL:
				continue
			var row: int = roundi(((a.centre as Vector2).y + (b.centre as Vector2).y) / 2.0)
			var bridge: int = 0
			for x: int in range(int(a.right) + 1, int(b.left)):
				if skin[row * width + x] > 0.0 or skin[(row - 1) * width + x] > 0.0 or skin[(row + 1) * width + x] > 0.0:
					bridge += 1
			if bridge >= EYE_BRIDGE and int(a.size) + int(b.size) > best_size:
				best_size = int(a.size) + int(b.size)
				best = [a, b]
	return best

## How many pixels of the middle third of `palette`'s portrait are its skin.
func _skin_pixels(palette: String) -> int:
	var image: Image = _portrait_image(palette)
	var skin: PackedFloat32Array = _lit_as(image, _square(palette, Dress.Region.SKIN))
	var third: int = image.get_width() / 3
	var found: int = 0
	for y: int in range(third, 2 * third):
		for x: int in range(third, 2 * third):
			if skin[y * image.get_width() + x] > 0.0:
				found += 1
	return found


## A guard against a portrait that is another recoloured: their light and shade must differ. It passed
## before the portraits were relit as well as after.
func test_no_two_portraits_are_the_same_picture() -> void:
	var shapes: Dictionary[String, PackedFloat32Array] = {}
	for palette: String in PALETTES:
		shapes[palette] = _shape(_portrait_image(palette))
	for a: int in PALETTES.size():
		for b: int in range(a + 1, PALETTES.size()):
			var total: float = 0.0
			for i: int in shapes[PALETTES[a]].size():
				total += absf(shapes[PALETTES[a]][i] - shapes[PALETTES[b]][i])
			assert_gt(total / shapes[PALETTES[a]].size(), PORTRAITS_APART, "%s and %s" % [PALETTES[a], PALETTES[b]])


## The picture's light and shade, whatever its colours: `image` at 32 × 32, each pixel's brightness
## less the mean, over the spread, so a portrait recoloured keeps nearly the same shape.
func _shape(image: Image) -> PackedFloat32Array:
	var small: Image = image.duplicate()
	small.resize(32, 32, Image.INTERPOLATE_BILINEAR)
	var values := PackedFloat32Array()
	for y: int in 32:
		for x: int in 32:
			values.append(small.get_pixel(x, y).get_luminance())
	var mean: float = 0.0
	for value: float in values:
		mean += value / values.size()
	var spread: float = 0.0
	for value: float in values:
		spread += (value - mean) * (value - mean) / values.size()
	spread = maxf(sqrt(spread), 0.001)
	for i: int in values.size():
		values[i] = (values[i] - mean) / spread
	return values


## Each portrait shows a face: skin in its middle third, and two eyes, the iris's colour with the eye
## white's beside it, one either side of the face's middle, level. Iris pixels per eye (near, far) as
## rendered: alvar 42, 21; captive 50, 19; crusader 29, 15; gonzalo 45, 33; malakor 87, 20; sergeant 39,
## 8; smith 28, 26; zahra 27, 14 (also printed by the test).
func test_each_portrait_has_a_face_in_its_middle_third() -> void:
	for palette: String in PALETTES:
		assert_gt(_skin_pixels(palette), 1000, "%s: skin" % palette)
		var eyes: Array[Dictionary] = _eyes(palette)
		assert_eq(eyes.size(), 2, "%s: two eyes, either side of the face's middle" % palette)
		if eyes.size() == 2:
			gut.p("%s: eyes of %d and %d iris pixels at %s and %s" % [palette, eyes[0].size, eyes[1].size,
					eyes[0].centre, eyes[1].centre])


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


func test_plain_text_headers_keys_and_the_title_each_have_their_colour() -> void:
	await _boot_with_title(null)
	var parchment := Color(0.9, 0.85, 0.76)
	var amber := Color(0.93, 0.74, 0.44)
	var title_tan := Color(0.86, 0.72, 0.52)
	var title_label := _title().find_child("TitleLabel") as Label
	assert_eq(title_label.get_theme_color(&"font_color"), title_tan)
	var plain := Label.new()
	var header := Label.new()
	header.theme_type_variation = &"HeaderLabel"
	var key := Label.new()
	key.theme_type_variation = &"KeyLabel"
	for label: Label in [plain, header, key]:
		_title().add_child(label)
	assert_eq(plain.get_theme_color(&"font_color"), parchment, "plain text")
	assert_eq(header.get_theme_color(&"font_color"), amber, "headers")
	assert_eq(key.get_theme_color(&"font_color"), amber, "keys")
	for label: Label in [plain, header, key]:
		label.free()
	# Each type is written once: no type the theme does not mean to have.
	var types: PackedStringArray = THEME.get_type_list()
	types.sort()
	assert_eq(types, PackedStringArray(["BloodBar", "Button", "HeaderLabel", "HealthBar", "KeyLabel", "Label", "Panel",
			"PanelContainer", "PortraitFrame", "ProgressBar", "SelectedPanel", "TargetingButton", "TitleLabel"]))


func test_a_panel_and_a_gift_button_write_nothing_while_nothing_changes() -> void:
	await _skirmish()
	# The world runs; only the enemies stand idle, so no value changes by itself.
	for enemy: Unit in main.enemies:
		var brain: Node = enemy.get_node_or_null(^"Brain")
		if brain != null:
			enemy.remove_child(brain)
			brain.free()
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


func test_escape_closes_the_card_first_and_leaves_targeting_open() -> void:
	await _skirmish()
	main.input.press_gift(1)  # Baleful Eye waits for a target
	assert_eq(main.input.targeting_gift(), 1)
	main.hud.find_child("ControlsButton").pressed.emit()
	await wait_physics_frames(2)
	await _tap(&"cancel")
	assert_false((main.hud.find_child("ControlsCard") as ControlsCard).is_open())
	assert_eq(main.input.targeting_gift(), 1, "the Escape that closed the card cancelled nothing")
	await _tap(&"cancel")
	assert_eq(main.input.targeting_gift(), -1, "the next Escape does")


func test_no_key_or_click_reaches_the_game_behind_the_card() -> void:
	await _skirmish()
	main.hud.find_child("ControlsButton").pressed.emit()
	await wait_physics_frames(2)
	var blood: int = main.player.stats.blood
	for action: StringName in [&"gift_1", &"gift_2", &"select_next", &"pause"]:
		await _tap(action)
	main.input.click_at(Vector2(900, 360))
	main.input.press_gift(0)
	main.input.press_member(main.party[1])
	await wait_physics_frames(2)
	assert_eq(main.player.stats.blood, blood, "no Gift used")
	assert_false(main.player.has_effect(&"iron_sinew"))
	assert_eq(main.input.targeting_gift(), -1, "no targeting opened")
	assert_eq(main.selected, main.player, "the selection stays")
	assert_false(main.is_paused())
	assert_eq(main.player.current_order(), Unit.Order.NONE, "no order")
	assert_true((main.hud.find_child("ControlsCard") as ControlsCard).is_open())


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

## Only that Álvar has fallen while the prompt does not answer; how to go on once it does.
func test_the_fallen_prompt_says_enter_or_click_once_it_answers() -> void:
	await _skirmish()
	main.player.take_hit(Arena.LETHAL)
	await wait_physics_frames(2)
	var label := main.hud.find_child("FallenLabel") as Label
	assert_false(main.hud.is_fallen_answerable())
	assert_eq(label.text, "You have fallen")
	Language.apply("es")
	await wait_physics_frames(2)
	assert_eq(label.text, "Has caído")
	await wait_until(func() -> bool: return main.hud.is_fallen_answerable(), Hud.FALLEN_DELAY + 1.0)
	await wait_process_frames(2)
	assert_eq(label.text, "Has caído — pulsa Intro o haz clic")
	TranslationServer.set_locale("en")
	await wait_physics_frames(2)
	assert_eq(label.text, "You have fallen — press Enter or click")


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


# --- New game asks first ---

func test_new_game_with_a_save_asks_first_and_no_takes_it_back() -> void:
	await _boot_with_title(GameState.skirmish())
	watch_signals(_title())
	var new_game := _title().find_child("NewGameButton") as Button
	new_game.pressed.emit()
	await wait_physics_frames(2)
	assert_signal_not_emitted(_title(), "new_game_chosen")
	assert_false(new_game.visible)
	assert_eq((_title().find_child("QuestionLabel") as Label).text, "Erase the saved game?")
	assert_true(_title().find_child("QuestionLabel").is_visible_in_tree())
	var yes := _title().find_child("YesButton") as Button
	var no := _title().find_child("NoButton") as Button
	assert_eq(yes.text, "Yes, begin anew")
	assert_eq(no.text, "No")
	for button: Button in [yes, no]:
		assert_eq(button.focus_mode, Control.FOCUS_NONE)
	no.pressed.emit()
	await wait_physics_frames(2)
	assert_true(new_game.visible)
	assert_false(_title().find_child("QuestionLabel").is_visible_in_tree())
	new_game.pressed.emit()
	await wait_physics_frames(2)
	await _tap(&"cancel")
	assert_true(new_game.visible, "Escape takes it back too")
	assert_true(main.store.has_save())


func test_yes_begins_anew() -> void:
	await _boot_with_title(GameState.skirmish())
	_title().find_child("NewGameButton").pressed.emit()
	await wait_physics_frames(2)
	_title().find_child("YesButton").pressed.emit()
	await wait_physics_frames(3)
	assert_false(_title().is_open())
	assert_eq(main.room.room_id, &"haven")
	assert_eq(main.state.conscience, 7)
	assert_true(_title().find_child("NewGameButton").visible, "the title is as new when shown again")


func test_without_a_save_new_game_starts_at_once() -> void:
	await _boot_with_title(null)
	_title().find_child("NewGameButton").pressed.emit()
	await wait_physics_frames(3)
	assert_false(_title().is_open())
	assert_eq(main.room.room_id, &"haven")


## GUT draws its output on a layer over the test window, which takes the mouse where Yes stands:
## hidden until the test ends.
func _let_clicks_past_the_runner() -> void:
	for node: Node in get_tree().root.find_children("GutLayer", "CanvasLayer", true, false):
		_runner_layers.append(node)
		(node as CanvasLayer).visible = false


func _press_at(control: Control) -> void:
	_click(control.get_viewport(), control.get_global_rect().get_center())


func test_a_double_press_on_new_game_answers_nothing() -> void:
	await _boot_with_title(GameState.skirmish())
	_let_clicks_past_the_runner()
	var new_game := _title().find_child("NewGameButton") as Button
	var at: Rect2 = new_game.get_global_rect()
	_press_at(new_game)
	await wait_physics_frames(1)
	var no := _title().find_child("NoButton") as Button
	var yes := _title().find_child("YesButton") as Button
	assert_eq(no.get_global_rect(), at, "No takes the button's place, under the pointer")
	assert_false(yes.get_global_rect().intersects(at), "Yes stands away from it")
	_click(_title().get_viewport(), at.get_center())
	await wait_seconds(0.1)
	_click(_title().get_viewport(), at.get_center())
	await wait_physics_frames(2)
	assert_true(_title().is_open())
	assert_true(_title().find_child("QuestionLabel").is_visible_in_tree(), "still asking")
	assert_true(main.store.has_save(), "the save is kept")


func test_asking_moves_nothing_on_the_title() -> void:
	await _boot_with_title(GameState.skirmish())
	_let_clicks_past_the_runner()
	var watched: Array[String] = ["TitleLabel", "ContinueButton", "ControlsButton"]
	var before: Array[Rect2] = []
	for name: String in watched:
		before.append((_title().find_child(name) as Control).get_global_rect())
	_press_at(_title().find_child("NewGameButton"))
	await wait_physics_frames(2)
	for index: int in watched.size():
		assert_eq((_title().find_child(watched[index]) as Control).get_global_rect(), before[index], watched[index])


func test_yes_takes_a_press_after_the_delay() -> void:
	await _boot_with_title(GameState.skirmish())
	_let_clicks_past_the_runner()
	_press_at(_title().find_child("NewGameButton"))
	await wait_seconds(TitleScreen.ANSWER_DELAY + 0.1)
	_press_at(_title().find_child("YesButton"))
	await wait_physics_frames(3)
	assert_false(_title().is_open())
	assert_eq(main.room.room_id, &"haven")
	assert_eq(main.state.conscience, 7)


func test_held_or_repeated_space_does_not_answer_and_enter_keeps_the_save() -> void:
	await _boot_with_title(GameState.skirmish())
	_let_clicks_past_the_runner()
	watch_signals(_title())
	_press_at(_title().find_child("NewGameButton"))
	await wait_physics_frames(2)
	for i: int in 3:
		await _tap(&"pause")
	Input.action_press(&"pause")
	await wait_seconds(TitleScreen.ANSWER_DELAY + 0.1)
	Input.action_release(&"pause")
	await wait_physics_frames(2)
	assert_true(_title().is_open())
	assert_signal_not_emitted(_title(), "new_game_chosen")
	assert_true(main.store.has_save())
	# Enter keeps its meaning on the title: Continue, which keeps the save.
	await _tap(&"confirm")
	assert_signal_not_emitted(_title(), "new_game_chosen")
	assert_eq(main.room.room_id, &"vault")
	assert_true(main.store.has_save())
