# tests/story/test_haven.gd
extends GutTest

const HAVEN := preload("res://dialogue/haven.dialogue")

var main: Main

func after_each() -> void:
	Story.finish(main)

func _boot(state: GameState = null) -> void:
	main = Story.boot(self, state, true)
	await wait_physics_frames(3)

## Plays the open conversation to its end, taking `choice` (0-based) at every choice.
func _play_through(choice: int = 0) -> void:
	var guard: int = 0
	while main.is_talking() and guard < 60:
		guard += 1
		var buttons: Array[Node] = main.find_child("DialogueBox").find_child("Choices").get_children()
		if buttons.size() > 0:
			main.dialogue.choose(mini(choice, buttons.size() - 1))
		else:
			main.dialogue.advance()
		await wait_physics_frames(2)
	assert_lt(guard, 60, "the conversation did not end")

func _talk(title: String, choice: int = 0) -> void:
	main.talk(HAVEN, title)
	await wait_physics_frames(2)
	await _play_through(choice)

func _after_waking() -> GameState:
	var state := GameState.new_game()
	state.set_flag(&"met_malakor")
	state.learn(&"alvar", &"iron_sinew")
	return state

func test_a_new_game_opens_on_the_waking() -> void:
	await _boot()
	await wait_physics_frames(3)
	assert_true(main.is_talking())
	assert_eq(main.find_child("DialogueBox").find_child("SpeakerLabel").text, "Malakor")
	await _play_through()
	assert_true(main.state.has_flag(&"met_malakor"))
	assert_true(main.state.knows(&"alvar", &"iron_sinew"))
	assert_eq(main.hud.gift_buttons().size(), 1)

func test_the_waking_plays_only_once() -> void:
	await _boot(_after_waking())
	await wait_physics_frames(3)
	assert_false(main.is_talking())

func test_five_people_stand_in_the_haven() -> void:
	await _boot(_after_waking())
	var names: Array = main.room.find_children("*", "Npc", true, false).map(func(n: Node) -> String: return (n as Npc).label)
	names.sort()
	assert_eq(names, ["Gonzalo", "Malakor", "The captive", "Zahra", "Íñigo"])

func test_zahra_joins_and_teaches() -> void:
	await _boot(_after_waking())
	await _talk("zahra")
	assert_eq(main.party.size(), 2)
	assert_true(main.state.knows(&"alvar", &"baleful_eye"))
	assert_false((main.room.find_child("ZahraNpc") as Npc).visible)

func test_gonzalo_joins() -> void:
	await _boot(_after_waking())
	await _talk("gonzalo")
	assert_eq(main.party.map(func(u: Unit) -> StringName: return u.member_id), [&"alvar", &"gonzalo"])

func _meet_the_captive(choice: int) -> void:
	await _boot(_after_waking())
	main.player.stats.spend_blood(30)  # 30
	await _talk("captive", choice)
	assert_true(main.state.has_flag(&"captive_done"))

func test_drinking_a_little_from_the_captive() -> void:
	await _meet_the_captive(0)
	assert_eq(main.state.conscience, 7)
	assert_eq(main.player.stats.blood, 60)
	assert_false(main.state.has_flag(&"captive_dead"))
	assert_true((main.room.find_child("Captive") as Npc).visible)

func test_draining_the_captive() -> void:
	await _meet_the_captive(1)
	assert_eq(main.state.conscience, 5)
	assert_eq(main.player.stats.blood, 100)
	assert_true(main.state.has_flag(&"captive_dead"))
	assert_false((main.room.find_child("Captive") as Npc).visible)

func test_leaving_the_captive_be() -> void:
	await _meet_the_captive(2)
	assert_eq(main.state.conscience, 8)
	assert_eq(main.player.stats.blood, 30)

func test_the_captive_decides_only_once() -> void:
	await _boot(_after_waking())
	await _talk("captive", 2)
	await _talk("captive", 1)
	assert_eq(main.state.conscience, 8)
	assert_false(main.state.has_flag(&"captive_dead"))

func test_malakor_gives_no_order_before_the_rest_is_done() -> void:
	await _boot(_after_waking())
	await _talk("malakor")
	assert_false(main.state.has_flag(&"order_given"))
	assert_eq(main.state.conscience, 7)

func _receive_the_order(choice: int) -> void:
	var state := _after_waking()
	state.join(&"zahra")
	state.join(&"gonzalo")
	for flag: StringName in [&"zahra_joined", &"gonzalo_joined", &"captive_done"]:
		state.set_flag(flag)
	await _boot(state)
	await _talk("malakor", choice)
	assert_true(main.state.has_flag(&"order_given"))
	assert_false((main.room.find_child("StairDoor") as Door).is_locked(main.state))

func test_handing_over_the_letter() -> void:
	await _receive_the_order(0)
	assert_eq(main.state.conscience, 6)
	assert_true(main.state.has_flag(&"gave_letter"))
	assert_false(main.state.has_flag(&"kept_letter"))

func test_keeping_the_letter() -> void:
	await _receive_the_order(1)
	assert_eq(main.state.conscience, 8)
	assert_true(main.state.has_flag(&"kept_letter"))
	assert_false(main.state.has_flag(&"gave_letter"))

func test_the_smith_talks_without_changing_anything() -> void:
	await _boot(_after_waking())
	var before: Dictionary = main.state.to_dict()
	await _talk("smith")
	await _talk("smith")
	assert_eq(main.state.to_dict(), before)

func test_the_whole_haven_can_be_played_to_the_vault() -> void:
	await _boot()
	await wait_physics_frames(3)
	await _play_through()
	for title: String in ["smith", "captive", "zahra", "gonzalo", "malakor"]:
		await _talk(title, 0)
	assert_true(main.state.has_flag(&"order_given"))
	(main.room.find_child("StairDoor") as Door).use(main.player)
	await wait_physics_frames(3)
	assert_eq(main.room.room_id, &"vault")
	assert_eq(main.party.size(), 3)
	assert_eq(main.hud.gift_buttons().size(), 2)
	assert_eq(main.state.conscience, 6)

func test_a_new_game_from_the_title_opens_on_the_waking_once_the_title_closes() -> void:
	main = (load("res://scenes/game.tscn") as PackedScene).instantiate()
	main.store = SaveStore.new()
	main.store.path = "user://test_story_%d.json" % randi()
	main.store.clear()
	add_child_autofree(main)
	await wait_physics_frames(3)
	var title: TitleScreen = main.find_child("TitleScreen")
	assert_true(title.is_open())
	assert_false(main.is_talking())
	title.new_game_chosen.emit()
	await wait_physics_frames(3)
	assert_false(title.is_open())
	assert_true(main.is_talking())
	assert_eq(main.find_child("DialogueBox").find_child("SpeakerLabel").text, "Malakor")

func _lines_of(title: String) -> Array[String]:
	var lines: Array[String] = []
	var note := func(_speaker: String, text: String, _choices: Array[String]) -> void: lines.append(text)
	main.dialogue.line_shown.connect(note)
	await _talk(title)
	main.dialogue.line_shown.disconnect(note)
	return lines

func test_lines_fit_what_has_happened_so_far() -> void:
	var state := _after_waking()
	state.set_flag(&"captive_done")
	await _boot(state)
	var smith: Array[String] = await _lines_of("smith")
	assert_false(smith[0].to_lower().contains("again"))
	assert_false(smith[0].to_lower().contains("once more"))
	var both: String = " ".join(await _lines_of("malakor"))
	assert_true(both.contains("Zahra") and both.contains("Gonzalo"))
	main.state.set_flag(&"gonzalo_joined")
	var zahra_missing: String = " ".join(await _lines_of("malakor"))
	assert_true(zahra_missing.contains("Zahra"))
	assert_false(zahra_missing.contains("Gonzalo"))
	main.state.set_flag(&"gonzalo_joined", false)
	main.state.set_flag(&"zahra_joined")
	var gonzalo_missing: String = " ".join(await _lines_of("malakor"))
	assert_true(gonzalo_missing.contains("Gonzalo"))
	assert_false(gonzalo_missing.contains("Zahra"))
