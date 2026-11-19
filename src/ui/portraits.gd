class_name Portraits
extends RefCounted
## The characters' portraits, `assets/portraits/<name>.png` (made by `tools/render_portraits.gd`):
## one per dress, named after the dress's palette (`Dress.palette_name()`). A party member's comes from
## its dress; a speaker in a conversation is looked up by the name the conversation gives, which is
## the key here and never the name shown, so a translated name finds nothing.

## Each portrait, by its palette name.
const BY_NAME: Dictionary[String, Texture2D] = {
	"alvar": preload("res://assets/portraits/alvar.png"),
	"captive": preload("res://assets/portraits/captive.png"),
	"crusader": preload("res://assets/portraits/crusader.png"),
	"gonzalo": preload("res://assets/portraits/gonzalo.png"),
	"malakor": preload("res://assets/portraits/malakor.png"),
	"sergeant": preload("res://assets/portraits/sergeant.png"),
	"smith": preload("res://assets/portraits/smith.png"),
	"zahra": preload("res://assets/portraits/zahra.png"),
}

## Who speaks in the conversations (as `dialogue/*.dialogue` names them) and the palette name of the
## dress each wears, `resources/dress/<name>.tres`, in the rooms or in the party.
const SPEAKERS: Dictionary[String, String] = {
	"Malakor": "malakor",
	"Álvar": "alvar",
	"Íñigo": "smith",
	"The captive": "captive",
	"Zahra": "zahra",
	"Gonzalo": "gonzalo",
}

## The portrait of whoever wears `dress`; null without a dress or a portrait for it.
static func of_dress(dress: Dress) -> Texture2D:
	if dress == null:
		return null
	return BY_NAME.get(dress.palette_name())


## The portrait of `speaker`, a speaker's name as the conversation gives it; null for anyone else.
static func of_speaker(speaker: String) -> Texture2D:
	return BY_NAME.get(SPEAKERS.get(speaker, ""))

