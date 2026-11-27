# tests/dialogue/test_conversations_es.gd
extends GutTest
## The Fragua's conversations in Spanish: what the box shows is the catalogue's Spanish, the story
## plays as it does in English for the same choices, a language change shows the line on show in the
## new language, and a line without its Spanish is shown in English.

const HAVEN := preload("res://dialogue/haven.dialogue")
const DIALOGUE := "res://assets/i18n/es-dialogue.po"

## The first and the last line of each conversation, as the box shows them in Spanish, on the run that
## drinks a little from the captive and hands the letter over.
const FIRST_AND_LAST: Dictionary = {
	"waking": ["Despiertas. Bien. No todos despiertan.", "Íñigo te contará el resto. Yo no digo las cosas dos veces."],
	"smith": ["Quédate ahí, lejos de las chispas. Él me mandó que te contara cómo están las cosas, y tengo hierro enfriándose.",
		"Y el Silencio: los vivos de arriba no deben saber nunca lo que camina bajo sus pies. Eso es todo. Al salir, pásame las tenazas."],
	"malakor_early": ["No bajarás solo. Zahra y Gonzalo irán contigo. Búscalos.", "Y ocúpate del prisionero. Es tuyo."],
	"zahra": ["Así que tú eres el fraile de la puerta. ¿Cómo te sienta la Sangre? ¿Todavía te pesa?",
		"Cuesta Sangre, como todo aquí. ¿Quién crees que lo paga al final?"],
	"gonzalo": ["Tú eres el nuevo.", "Mantén la hoja baja. Andando."],
	"captive": ["Atrás. Tomé la cruz en Montpellier. Ante ti no me arrodillo.", "Has parado. ¿Por qué has parado?"],
	"smith_again": ["Ya te lo dije una vez. Cuando la Sangre escasea, bebes.",
		"Si dejas que se agote, la Furia elige por ti. Y ahora, ojo con las chispas."],
	"malakor_order": ["Bajo esta ciudad hay criptas más antiguas que sus iglesias.", "La escalera está abierta. Ve."],
	"malakor_after": ["La escalera está abierta. Baja.", "La escalera está abierta. Baja."],
	"malakor_vault": ["Así que la primera sala está en silencio. El cerrojo que hay debajo ha sobrevivido a reyes. Aguardará hasta que yo lo diga.",
		"Así que la primera sala está en silencio. El cerrojo que hay debajo ha sobrevivido a reyes. Aguardará hasta que yo lo diga."],
}
const CAPTIVE_CHOICES: Array[String] = ["Beber un poco", "Desangrarlo", "Dejarlo en paz"]
const LETTER_CHOICES: Array[String] = ["Entregársela", "Decir que ardió en el barrio"]
## The captive's last line for each choice.
const CAPTIVE_LAST: Array[String] = ["Has parado. ¿Por qué has parado?", "La Sangre está caliente. Él no.",
	"Vete, pues. Seas lo que seas, rezaré por ti. No sé a quién."]
## The speakers' names as the box shows them in Spanish, by the name the conversation gives.
const SPEAKERS_ES: Dictionary = {"Malakor": "Malakor", "Álvar": "Álvar", "Íñigo": "Íñigo",
	"The captive": "El cautivo", "Zahra": "Zahra", "Gonzalo": "Gonzalo"}

var main: Main


func after_each() -> void:
	Story.finish(main)
	Language.apply("en")
	# What the HUD and the box rebuilt in English frees what they built in Spanish.
	await wait_physics_frames(2)


func _box() -> DialogueBox:
	return main.find_child("DialogueBox") as DialogueBox


## What the box shows: the speaker, the line and the choices (without their numbers).
func _shown() -> Array:
	var box: DialogueBox = _box()
	var choices: Array[String] = []
	for button: Node in box.find_child("Choices").get_children():
		choices.append((button as Button).text.get_slice(". ", 1))
	return [(box.find_child("SpeakerLabel") as Label).text, (box.find_child("TextLabel") as Label).text, choices]


## Plays the open conversation to its end, taking `choice` at its choices; returns what the box showed,
## line by line, as `_shown()` gives it.
func _play(choice: int = 0) -> Array:
	var shown: Array = []
	var guard: int = 0
	while main.is_talking() and guard < 60:
		guard += 1
		var now: Array = _shown()
		shown.append(now)
		if not (now[2] as Array).is_empty():
			main.dialogue.choose(mini(choice, (now[2] as Array).size() - 1))
		else:
			main.dialogue.advance()
		await wait_physics_frames(2)
	assert_lt(guard, 60, "the conversation did not end")
	return shown


func _talk(title: String, choice: int = 0) -> Array:
	main.talk(HAVEN, title)
	await wait_physics_frames(2)
	return await _play(choice)


## The whole Fragua in `locale`, from the waking to Malakor's closing line, taking `captive` at the
## captive and `letter` at the letter: what each conversation showed, and the story's state at the end.
func _haven(locale: String, captive: int, letter: int) -> Dictionary:
	Language.apply(locale)
	main = Story.boot(self, null, true)
	await wait_physics_frames(3)
	var talks: Dictionary = {}
	talks["waking"] = await _play()
	talks["smith"] = await _talk("smith")
	talks["malakor_early"] = await _talk("malakor")
	talks["captive"] = await _talk("captive", captive)
	talks["zahra"] = await _talk("zahra")
	talks["gonzalo"] = await _talk("gonzalo")
	talks["captive_again"] = await _talk("captive")
	talks["smith_again"] = await _talk("smith")
	talks["malakor_order"] = await _talk("malakor", letter)
	talks["malakor_after"] = await _talk("malakor")
	main.state.set_flag(&"vault_cleared")
	talks["malakor_vault"] = await _talk("malakor")
	var party: Array = main.party.map(func(u: Unit) -> StringName: return u.member_id)
	var result: Dictionary = {"talks": talks, "state": main.state.to_dict(), "party": party}
	Story.finish(main)
	main.queue_free()
	await wait_physics_frames(1)
	return result


func test_the_fragua_in_spanish_shows_the_catalogues_spanish() -> void:
	var run: Dictionary = await _haven("es", 0, 0)
	var talks: Dictionary = run["talks"]
	for title: String in FIRST_AND_LAST:
		var lines: Array = talks[title]
		assert_eq([lines[0][1], lines[-1][1]], FIRST_AND_LAST[title], title)
	assert_eq(talks["captive"][2][2], CAPTIVE_CHOICES)
	assert_eq(talks["malakor_order"][3][2], LETTER_CHOICES)
	assert_eq(talks["captive"][0][0], "El cautivo")


func test_every_choice_plays_as_in_english_and_reads_in_spanish() -> void:
	# Conscience ends at 6, 4 and 9: Malakor's plain, cold and pious lines after the order.
	for captive: int in 3:
		var letter: int = [0, 0, 1][captive]
		var english: Dictionary = await _haven("en", captive, letter)
		var spanish: Dictionary = await _haven("es", captive, letter)
		var label: String = "captive %d, letter %d" % [captive, letter]
		assert_eq(spanish["state"], english["state"], label)
		assert_eq(spanish["party"], english["party"], label)
		assert_eq(spanish["talks"]["captive"][-1][1], CAPTIVE_LAST[captive], label)
		for title: String in english["talks"]:
			var ours: Array = english["talks"][title]
			var theirs: Array = spanish["talks"][title]
			assert_eq(theirs.size(), ours.size(), "%s, %s: as many lines" % [label, title])
			for index: int in mini(ours.size(), theirs.size()):
				var line: String = "%s, %s, line %d" % [label, title, index + 1]
				assert_eq(theirs[index][0], SPEAKERS_ES[ours[index][0]], line)
				assert_false((theirs[index][1] as String).is_empty(), line)
				assert_ne(theirs[index][1], ours[index][1], line)
				assert_eq((theirs[index][2] as Array).size(), (ours[index][2] as Array).size(), line)


func test_a_language_change_mid_conversation_shows_the_line_on_show_in_the_new_language() -> void:
	main = Story.boot(self, null, true)
	await wait_physics_frames(3)
	assert_eq(_shown()[1], "You wake. Good. Not all of them do.")
	Language.apply("es")
	await wait_physics_frames(2)
	assert_eq(_shown(), ["Malakor", "Despiertas. Bien. No todos despiertan.", [] as Array[String]])
	assert_eq(main.dialogue.line_text(), "Despiertas. Bien. No todos despiertan.")
	await _play()
	main.talk(HAVEN, "captive")
	await wait_physics_frames(2)
	for i: int in 2:
		main.dialogue.advance()
		await wait_physics_frames(2)
	assert_eq(_shown()[2], CAPTIVE_CHOICES)
	Language.apply("en")
	await wait_physics_frames(2)
	assert_eq(_shown(), ["The captive", "My leg is broken, and I am thirsty, and I am not afraid of you. Do what you came for.",
		["Drink a little", "Drain him", "Leave him be"] as Array[String]])
	# The portrait and the probe keep the untranslated name.
	Language.apply("es")
	await wait_physics_frames(2)
	assert_eq(_shown()[0], "El cautivo")
	assert_eq(main.dialogue.speaker(), "The captive")
	assert_true(_box().find_child("PortraitFrame").visible)
	assert_eq((_box().find_child("HintLabel") as Label).text, "1–3 o clic")


func test_a_line_without_its_spanish_is_shown_in_english() -> void:
	var catalogue: Translation = load(DIALOGUE)
	var resource: DialogueResource = HAVEN
	var first: Dictionary = resource.lines.values().filter(func(line: Dictionary) -> bool:
		return line.get("text", "") == "You wake. Good. Not all of them do.")[0]
	var english: String = first.text
	var spanish: String = catalogue.get_message(english, first.static_id)
	assert_eq(spanish, "Despiertas. Bien. No todos despiertan.")
	catalogue.erase_message(english, first.static_id)
	Language.apply("es")
	main = Story.boot(self, null, true)
	await wait_physics_frames(3)
	var shown: Array = _shown()
	catalogue.add_message(english, spanish, first.static_id)
	assert_eq(shown, ["Malakor", english, [] as Array[String]])
	main.dialogue.advance()
	await wait_physics_frames(2)
	assert_eq(_shown()[1], "Elena. ¿Dónde está?")
