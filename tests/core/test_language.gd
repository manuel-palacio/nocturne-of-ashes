# tests/core/test_language.gd
extends GutTest

const MAIN := preload("res://scenes/main.tscn")

func after_each() -> void:
	TranslationServer.set_locale("en")

func test_pick_prefers_the_request_then_the_system_then_english() -> void:
	assert_eq(Language.pick("es", "en_US"), "es")
	assert_eq(Language.pick("", "es_ES"), "es")
	assert_eq(Language.pick("ES-mx", "en"), "es")
	assert_eq(Language.pick("sv", "sv_SE"), "en")
	assert_eq(Language.pick("xx", "es_AR"), "es")
	assert_eq(Language.pick("", ""), "en")

func test_english_is_the_source() -> void:
	assert_eq(tr("The vault is quiet"), "The vault is quiet")

func test_spanish_translates_the_prompts() -> void:
	Language.apply("es")
	assert_eq(tr("You have fallen — press Enter or click"), "Has caído — pulsa Intro o haz clic")
	assert_eq(tr("Paused — give your orders"), "En pausa — da tus órdenes")
	assert_eq(tr("The vault is quiet"), "La cripta está en silencio")

func test_every_gift_and_unit_name_has_spanish() -> void:
	Language.apply("es")
	for english: String in ["Iron Sinew", "Baleful Eye", "Mend Flesh", "Blood Lance", "Stone Hide", "Hammerfall", "Brother Álvar", "Crusader", "Sergeant", "Fallen", "The Fury", "Feeding"]:
		assert_ne(tr(english), english, english)

func test_the_hud_follows_a_language_change() -> void:
	var main: Main = add_child_autoqfree(MAIN.instantiate())
	await wait_physics_frames(3)
	Language.apply("es")
	await wait_physics_frames(2)
	assert_eq(main.hud.gift_buttons()[0].text, "1 Tendón de Hierro (20)")
	assert_eq(main.hud.panels()[0].find_child("NameLabel").text, "Hermano Álvar")
	main.player.take_hit(Arena.LETHAL)
	await wait_physics_frames(2)
	assert_eq(main.hud.find_child("FallenLabel").text, "Has caído — pulsa Intro o haz clic")
	assert_eq(main.hud.panels()[0].find_child("StateLabel").text, "Fuera de combate")

func test_controls_built_after_the_switch_are_spanish_too() -> void:
	Language.apply("es")
	var main: Main = add_child_autoqfree(MAIN.instantiate())
	await wait_physics_frames(3)
	main.select(main.party[2])
	assert_eq(main.hud.gift_buttons()[1].text, "2 Martillazo (25)")

func test_an_unknown_locale_reads_as_english() -> void:
	Language.apply(Language.pick("sv", "sv_SE"))
	assert_eq(tr("The Fury"), "The Fury")

func test_a_requested_english_wins_over_a_spanish_browser() -> void:
	assert_eq(Language.pick("en", "es_ES"), "en")

func test_speakers_names_follow_the_language() -> void:
	assert_eq(DialogueRunner.speaker_name("The captive"), "The captive")
	Language.apply("es")
	assert_eq(DialogueRunner.speaker_name("The captive"), "El cautivo")
	assert_eq(DialogueRunner.speaker_name("Malakor"), "Malakor")
	assert_eq(DialogueRunner.speaker_name(""), "")

func test_texts_put_together_read_in_spanish() -> void:
	Language.apply("es")
	var main: Main = Story.boot(self)
	await wait_physics_frames(3)
	main.hud.show_hint(Hints.TEXTS[&"dry"], ["Brother Álvar"])
	assert_eq(main.hud.find_child("HintLabel").text, "Hermano Álvar se queda sin Sangre. Aliméntate, o la Furia elegirá por ti.")
	main.hud.show_notice(PlayerInput.FULL_BLOOD_TEXT, ["Zahra"])
	assert_eq(main.hud.find_child("NoticeLabel").text, "Zahra tiene la Sangre llena")
	assert_eq(main.hud.find_child("ConscienceLabel").text, "Alma %d/10" % main.state.conscience)
	main.hud.show_closing(8)
	assert_string_contains((main.hud.find_child("ClosingCard") as ClosingCard).text(), "con el Alma que llevas (8 de 10)")
	Story.finish(main)
	TranslationServer.set_locale("en")
	await wait_physics_frames(2)  # the HUD rebuilt in English frees what it built in Spanish

## The longest state, "Fuera de combate", on a companion's panel: the panel keeps its width and the
## label holds the whole text. The HUD scales as a whole (`canvas_items`), so this holds at 800 × 500.
func test_the_fallen_state_fits_a_panel_in_spanish() -> void:
	var main: Main = add_child_autoqfree(MAIN.instantiate())
	await wait_physics_frames(3)
	var width: float = main.hud.panels()[1].size.x
	Language.apply("es")
	await wait_physics_frames(2)
	main.party[1].take_hit(Arena.LETHAL)
	await wait_physics_frames(2)
	var panel: PartyMemberPanel = main.hud.panels()[1]
	var label := panel.find_child("StateLabel") as Label
	assert_eq(label.text, "Fuera de combate")
	assert_eq(panel.size.x, width)
	assert_lte(label.get_minimum_size().x, label.size.x)
	TranslationServer.set_locale("en")
	await wait_physics_frames(2)
