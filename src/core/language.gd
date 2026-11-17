class_name Language
extends RefCounted
## Chooses the language the game is shown in. English is the source text; every other language is a
## gettext catalogue under `assets/i18n/`, listed in the project settings.

## Languages with a full set of texts.
const SUPPORTED: Array[String] = ["en", "es"]


## `requested` if its language is supported, else `system`'s, else English. Both are locale codes such
## as "es", "es_ES" or "ES-mx"; only the language part counts.
static func pick(requested: String, system: String) -> String:
	for locale: String in [requested, system]:
		var language: String = _language_part(locale)
		if SUPPORTED.has(language):
			return language
	return "en"


## Shows the game in `locale` from now on.
static func apply(locale: String) -> void:
	TranslationServer.set_locale(locale)


## On the web, the page URL's `lang` query parameter; elsewhere, or when absent, "".
static func requested_from_page() -> String:
	return PageParams.value("lang")


static func _language_part(locale: String) -> String:
	return locale.replace("-", "_").get_slice("_", 0).to_lower()
