# tests/story/test_playability.gd
extends GutTest
## Nobody gets stuck, nothing drags: the end of the story says it is the end, the vault is one fight,
## leaving a fight and the silent refusals are said aloud, saves that will not keep are owned up to,
## a hidden page pauses, Íñigo does not repeat himself and the title shows its preparing advance.

const HAVEN := preload("res://dialogue/haven.dialogue")
const GAME := preload("res://scenes/game.tscn")
const SKIRMISH := preload("res://scenes/main.tscn")

var main: Main


func after_each() -> void:
	Story.finish(main)
	TranslationServer.set_locale("en")


func _boot(state: GameState) -> void:
	main = Story.boot(self, state)
	await wait_physics_frames(3)


func _tap(action: StringName) -> void:
	Input.action_press(action)
	await wait_physics_frames(2)
	Input.action_release(action)
	await wait_physics_frames(2)


func _click(at: Vector2) -> void:
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.position = at
	click.global_position = at
	click.pressed = true
	main.hud.get_viewport().push_input(click, true)
	var release: InputEventMouseButton = click.duplicate()
	release.pressed = false
	main.hud.get_viewport().push_input(release, true)


func _clear_the_vault() -> void:
	for enemy: Unit in main.enemies:
		enemy.take_hit(999)
	await wait_physics_frames(3)


func _door(node_name: String) -> Door:
	return main.room.find_child(node_name) as Door


## The lines of the conversation at `title`, played through with the first choice at each.
func _lines_of(title: String) -> Array[String]:
	var lines: Array[String] = []
	var note := func(_speaker: String, text: String, _choices: Array[String]) -> void: lines.append(text)
	main.dialogue.line_shown.connect(note)
	main.talk(HAVEN, title)
	await wait_physics_frames(2)
	var guard: int = 0
	while main.is_talking() and guard < 60:
		guard += 1
		if main.dialogue.choice_texts().size() > 0:
			main.dialogue.choose(0)
		else:
			main.dialogue.advance()
		await wait_physics_frames(2)
	main.dialogue.line_shown.disconnect(note)
	return lines


func _haven_after_the_order() -> GameState:
	var state := PageBoot.haven_finished()
	state.room = &"haven"
	state.entry = &"start"
	return state


# --- 1. The end says it is the end ---

func test_clearing_the_story_vault_opens_the_closing_card_which_holds_the_world() -> void:
	await _boot(PageBoot.haven_finished())
	var hold := main.get_node("WorldHold") as WorldHold
	assert_false(main.is_closing_open())
	await _clear_the_vault()
	assert_true(main.is_closing_open(), "the card opens once the vault is quiet")
	assert_true(hold.is_held(), "and holds the world")
	assert_false(main.is_paused(), "a hold of its own, not the pause")
	var card := main.hud.find_child("ClosingCard") as ClosingCard
	assert_eq(card.focus_mode, Control.FOCUS_NONE)
	assert_string_contains(card.text(), "Here the descent rests")
	assert_string_contains(card.text(), "(%d of 10)" % main.state.conscience)
	await _tap(&"pause")
	assert_false(main.is_closing_open(), "Space closes it, it does not pause behind it")
	assert_false(main.is_paused())
	assert_false(hold.is_held())
	await wait_physics_frames(3)
	assert_false(main.is_paused(), "the Space that closed it did not pause afterwards")


func test_enter_closes_the_closing_card_and_it_is_not_shown_again_after_a_reload() -> void:
	await _boot(PageBoot.haven_finished())
	await _clear_the_vault()
	assert_true(main.is_closing_open())
	await _tap(&"confirm")
	assert_false(main.is_closing_open(), "Enter closes it")
	assert_true(main.store.load_state().has_flag(Main.REST_SHOWN_FLAG), "dismissed, and saved so")
	main.reload_checkpoint()
	await wait_physics_frames(3)
	assert_eq(main.room.room_id, &"vault")
	assert_false(main.is_closing_open(), "not again on a reload")
	assert_eq(main.hud.notice(), "The vault is quiet. The story rests here, for now.")


func test_a_click_closes_the_closing_card_and_gives_no_order() -> void:
	await _boot(PageBoot.haven_finished())
	await _clear_the_vault()
	assert_true(main.is_closing_open())
	# Where the test runner's own window does not cover the game, as the controls card's test clicks.
	_click(Vector2(30, 680))
	await wait_physics_frames(3)
	assert_false(main.is_closing_open())
	assert_eq(main.player.current_order(), Unit.Order.NONE, "the click went to the card")


func test_a_reload_while_the_card_is_open_shows_it_again() -> void:
	await _boot(PageBoot.haven_finished())
	await _clear_the_vault()
	assert_true(main.is_closing_open())
	main.reload_checkpoint()
	await wait_physics_frames(3)
	assert_true(main.is_closing_open(), "not dismissed, so not yet seen")


func test_a_vault_cleared_by_an_older_save_shows_the_card_once_on_entry() -> void:
	var state := PageBoot.haven_finished()
	state.set_flag(&"vault_cleared")
	await _boot(state)
	assert_true(main.is_closing_open())


func test_the_card_waits_while_the_controls_card_is_open_and_opens_when_it_closes() -> void:
	await _boot(PageBoot.haven_finished())
	main.hud.find_child("ControlsButton").pressed.emit()
	await wait_physics_frames(2)
	for enemy: Unit in main.enemies:
		enemy.take_hit(999)
	await wait_physics_frames(3)
	assert_false(main.is_closing_open(), "not over the controls card")
	await _tap(&"cancel")
	await wait_physics_frames(3)
	assert_true(main.is_closing_open(), "it opens once the controls card closes")


func test_the_card_waits_out_the_pause() -> void:
	await _boot(PageBoot.haven_finished())
	main.set_paused(true)
	for enemy: Unit in main.enemies:
		enemy.take_hit(999)
	await wait_physics_frames(3)
	assert_false(main.is_closing_open())
	main.set_paused(false)
	await wait_physics_frames(3)
	assert_true(main.is_closing_open())


func test_the_card_opens_with_a_companion_selected_and_in_the_fury() -> void:
	await _boot(PageBoot.haven_finished())
	main.select(main.party[1])
	main.player.stats.spend_blood(main.player.stats.blood - 5)
	assert_true(main.player.is_in_fury())
	await _clear_the_vault()
	assert_true(main.is_closing_open())
	await _tap(&"confirm")
	assert_false(main.is_closing_open())


func test_the_card_reads_in_spanish() -> void:
	await _boot(PageBoot.haven_finished())
	await _clear_the_vault()
	Language.apply("es")
	await wait_physics_frames(2)
	var card := main.hud.find_child("ClosingCard") as ClosingCard
	assert_string_contains(card.text(), "Aquí se detiene el descenso")
	assert_string_contains(card.text(), "(%d de 10)" % main.state.conscience)


func test_the_skirmish_has_no_closing_card() -> void:
	main = add_child_autofree(SKIRMISH.instantiate())
	await wait_physics_frames(3)
	for enemy: Unit in main.enemies:
		enemy.take_hit(999)
	await wait_physics_frames(3)
	assert_false(main.is_closing_open())
	assert_true((main.hud.find_child("ClearedLabel") as Label).visible, "its line stays")


func test_the_last_lock_says_the_story_rests_once_the_vault_is_cleared() -> void:
	await _boot(PageBoot.haven_finished())
	_door("LastLock").use(main.player)
	await wait_physics_frames(2)
	assert_eq(main.hud.notice(), "The last lock does not yield. Not yet.")
	await _clear_the_vault()
	await _tap(&"confirm")
	_door("LastLock").use(main.player)
	await wait_physics_frames(2)
	assert_eq(main.hud.notice(), "The last lock does not yield. This is where the story rests, for now.")


func test_malakor_sends_nobody_anywhere_once_the_vault_is_cleared() -> void:
	var state := _haven_after_the_order()
	await _boot(state)
	var before: String = " ".join(await _lines_of("malakor"))
	assert_string_contains(before, "Go down.")
	main.state.set_flag(&"vault_cleared")
	var after: Array[String] = await _lines_of("malakor")
	assert_eq(after.size(), 1, "one closing line")
	assert_false(" ".join(after).contains("Go down"))
	assert_false(" ".join(after).contains("stair is open"))


# --- 2. The second group comes ---

func _second_group() -> Array[Unit]:
	return main.enemies.slice(3) as Array[Unit]


func test_when_the_first_enemy_falls_the_rest_come_for_the_party() -> void:
	await _boot(PageBoot.haven_finished())
	main.enemies[0].take_hit(999)
	var reached := func() -> bool:
		return _second_group().all(func(enemy: Unit) -> bool:
			return not enemy.is_alive() or enemy.attack_target() != null and main.party.any(
					func(member: Unit) -> bool: return Arena.flat(member.global_position, enemy.global_position) < 3.0))
	await wait_until(reached, 15.0)
	assert_true(reached.call(), "the second group reached the party within 15 s")


func test_ten_seconds_after_the_first_blow_every_enemy_is_alerted() -> void:
	await _boot(PageBoot.haven_finished())
	main.enemies[0].take_hit(1)
	await wait_seconds(9.0)
	assert_false(_second_group().any(func(enemy: Unit) -> bool: return enemy.attack_target() != null),
			"not before")
	await wait_seconds(2.0)
	assert_true(_second_group().all(func(enemy: Unit) -> bool: return enemy.attack_target() != null),
			"all of them, after")


# --- 3. Leaving a fight is said aloud ---

func test_coming_back_to_a_vault_whose_guard_was_restored_says_so() -> void:
	await _boot(PageBoot.haven_finished())
	assert_eq(main.hud.notice(), "", "nothing on a first entry")
	main.enemies[0].take_hit(30)
	_door("WestDoor").use(main.player)
	await wait_physics_frames(3)
	assert_eq(main.room.room_id, &"haven")
	_door("StairDoor").use(main.player)
	await wait_physics_frames(3)
	assert_eq(main.room.room_id, &"vault")
	assert_eq(main.hud.notice(), "The vault's guard has closed ranks again.")
	main.reload_checkpoint()
	await wait_physics_frames(3)
	assert_eq(main.hud.notice(), "", "nothing on a reload or Continue")


# --- 4. Arriving from the vault, nobody stands under the party panels ---

func test_on_arriving_from_the_vault_nobody_to_talk_to_is_under_the_party_panels() -> void:
	var window_size: Vector2i = get_tree().root.size
	get_tree().root.size = Vector2i(1280, 720)
	var state := PageBoot.haven_finished()
	state.room = &"haven"
	state.entry = &"from_vault"
	state.set_flag(&"captive_spared")
	await _boot(state)
	main.rig.snap_to_target()
	await wait_process_frames(2)
	var panels: Rect2 = (main.hud.find_child("PartyColumn") as Control).get_global_rect()
	assert_gt(panels.size.y, 200.0, "three panels")
	var view: Rect2 = Rect2(Vector2.ZERO, Vector2(1280, 720))
	var camera: Camera3D = main.rig.camera()
	var shown: Array[String] = []
	for npc: Npc in main.room.npcs():
		if not npc.visible:
			continue
		shown.append(npc.label)
		for up: float in [0.1, 0.9, 1.7]:
			var at: Vector2 = camera.unproject_position(npc.global_position + Vector3.UP * up)
			# The captive's cell is at the far west wall, out of the view from the stair's side.
			if npc.label != "The captive":
				assert_true(view.has_point(at), "%s is on screen, feet to head (%s)" % [npc.label, at])
			assert_false(panels.grow(12.0).has_point(at),
					"%s is drawn at %s, under the panels %s" % [npc.label, at, panels])
	shown.sort()
	assert_eq(shown, ["Malakor", "The captive", "Íñigo"] as Array[String])
	var stair: Door = _door("StairDoor")
	for member: Unit in main.party:
		assert_gt(Arena.flat(member.global_position, stair.global_position), 1.5, "clear of the stair")
	get_tree().root.size = window_size


# --- 5. Silent refusals get a line ---

func test_a_click_to_feed_with_full_blood_says_so_and_attacks() -> void:
	main = add_child_autofree(SKIRMISH.instantiate())
	await wait_physics_frames(3)
	var meal: Unit = main.enemies[0]
	meal.get_node("Brain").queue_free()
	meal.take_hit(meal.stats.max_health - 10)
	meal.global_position = main.player.global_position + Vector3(2.0, 0, 0)
	main.player.stats.gain_blood(1000)
	main.rig.snap_to_target()
	await wait_physics_frames(3)
	assert_true(main.player.can_feed_on(meal))
	var at: Vector2 = main.rig.camera().unproject_position(meal.global_position + Vector3.UP * 0.9)
	main.input.click_at(at)
	assert_eq(main.player.current_order(), Unit.Order.ATTACK, "it still attacks")
	assert_eq(main.hud.notice(), "%s's Blood is full")
	assert_string_contains(main.hud.find_child("NoticeLabel").text, "Brother Álvar")


func test_a_door_in_the_fury_in_the_empty_fragua_names_the_fury() -> void:
	await _boot(_haven_after_the_order())
	main.player.stats.spend_blood(main.player.stats.blood - 5)
	assert_true(main.player.is_in_fury())
	_door("StairDoor").use(main.player)
	await wait_physics_frames(3)
	assert_eq(main.room.room_id, &"haven")
	assert_eq(main.hud.notice(), "Not while the Fury has you.")


# --- 6. Saves that will not keep ---

func _title_with(store_path: String) -> TitleScreen:
	main = GAME.instantiate()
	main.store = SaveStore.new()
	main.store.path = store_path
	main.store.clear()
	main.opening_enabled = false
	add_child_autofree(main)
	await wait_physics_frames(3)
	return main.find_child("TitleScreen") as TitleScreen


func test_a_store_that_cannot_write_shows_the_title_line() -> void:
	var title: TitleScreen = await _title_with("user://no_such_place/deeper/save.json")
	assert_false(main.store.keeps_saves())
	assert_true(title.is_storage_warning_shown())
	assert_eq((title.find_child("StorageLabel") as Label).text,
			"This browser is not keeping saves: progress lasts until the page is closed.")


func test_a_working_store_shows_no_title_line() -> void:
	var title: TitleScreen = await _title_with("user://test_playability_%d.json" % randi())
	assert_true(main.store.keeps_saves())
	assert_false(title.is_storage_warning_shown())
	assert_false(FileAccess.file_exists(main.store.path + SaveStore.PROBE_SUFFIX), "the probe is gone")


# --- 8. Íñigo does not repeat his speech ---

func test_inigo_says_it_all_once_then_reminds_in_two_lines() -> void:
	await _boot(_haven_after_the_order())
	var first: Array[String] = await _lines_of("smith")
	assert_gt(first.size(), 4)
	var second: Array[String] = await _lines_of("smith")
	assert_between(second.size(), 1, 2)
	var said: String = " ".join(second)
	assert_string_contains(said, "drink")
	assert_string_contains(said, "Fury")
