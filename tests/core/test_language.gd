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
	assert_eq(tr("You have fallen — press Enter"), "Has caído — pulsa Intro")
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
	main.player.take_hit(999)
	await wait_physics_frames(2)
	assert_eq(main.hud.find_child("FallenLabel").text, "Has caído — pulsa Intro")
	assert_eq(main.hud.panels()[0].find_child("StateLabel").text, "Caído")

func test_controls_built_after_the_switch_are_spanish_too() -> void:
	Language.apply("es")
	var main: Main = add_child_autoqfree(MAIN.instantiate())
	await wait_physics_frames(3)
	main.select(main.party[2])
	assert_eq(main.hud.gift_buttons()[1].text, "2 Martillazo (25)")

func test_an_unknown_locale_reads_as_english() -> void:
	Language.apply(Language.pick("sv", "sv_SE"))
	assert_eq(tr("The Fury"), "The Fury")
