# tests/core/test_translation_coverage.gd
extends GutTest
## Every text a player can read has its Spanish, and the catalogues hold nothing else.
##
## The texts are found where the game keeps them: the conversations' lines, choices and speakers in
## `dialogue/*.dialogue` (as the add-on compiles them); in `src/`, every literal given to `tr()` and
## every string constant (the notices, hints, cards, prompts and controls are constants handed to
## `tr()` later), apart from the few in `NOT_TEXT`; in `scenes/` and `resources/`, the names, the doors'
## texts and the `text`, `tooltip_text` and `placeholder_text` of every node whose automatic translation
## is on. A string with no letter in it ("?") is not counted. Static text on a node whose automatic
## translation is off is never translated, so only the game's name may be there.

const INTERFACE: String = "res://assets/i18n/es.po"
const DIALOGUE: String = "res://assets/i18n/es-dialogue.po"
const DIALOGUE_FOLDER: String = "res://dialogue"
## The message context the add-on and the dialogue box give a speaker's name.
const SPEAKER_CONTEXT: String = "dialogue"
## String constants in `src/` that are not shown to a player: name parts, cue names, file suffixes,
## feature names, locale codes, the portraits' keys and developer errors.
const NOT_TEXT: Array[String] = ["ENTRY_PREFIX", "ENEMY_PREFIX", "OPENING_CUE", "_ONLY_HOOKS",
	"TEMP_SUFFIX", "PROBE_SUFFIX", "PUBLIC_FEATURE", "SUPPORTED", "BY_NAME", "SPEAKERS"]
## Texts that read the same in Spanish: names, "Alma" and "No".
const SAME_IN_BOTH: Array[String] = ["Alma", "No", "Malakor", "Zahra", "Gonzalo", "Íñigo", "Álvar"]
## Exported properties of scenes and resources whose text reaches `tr()` in code.
const TEXT_PROPERTIES: Array[String] = ["display_name", "locked_text", "later_text"]
## Node properties the engine translates by itself while the node's automatic translation is on.
const NODE_TEXT_PROPERTIES: Array[String] = ["text", "tooltip_text", "placeholder_text"]
## Static text set in a scene on a node whose automatic translation is off, shown as written: the
## game's name. Any other such text would never be translated (code that sets it replaces it).
const SHOWN_AS_WRITTEN: Array[String] = ["Nocturne of Ashes"]


## The entries of the catalogue at `path`, by key ("context" + U+0004 + "msgid", or the msgid alone
## without a context), each the Spanish text.
func _catalogue(path: String) -> Dictionary:
	var translation: Translation = load(path)
	var entries: Dictionary = {}
	for key: String in translation.get_message_list():
		var parts: PackedStringArray = key.split(char(4))
		var context: String = parts[0] if parts.size() == 2 else ""
		var message: String = parts[parts.size() - 1]
		entries[key] = String(translation.get_message(message, context))
	return entries


static func _key(message: String, context: String = "") -> String:
	return message if context.is_empty() else context + char(4) + message


## Every game conversation file, at any depth under `DIALOGUE_FOLDER`.
func _dialogue_files() -> Array[String]:
	return _scripts(DIALOGUE_FOLDER, ["dialogue"])


## The texts of the conversations, by catalogue key: each spoken line and choice under its static id,
## each speaker under `SPEAKER_CONTEXT`. The value says where it is, for the failure message.
func _dialogue_texts() -> Dictionary:
	var texts: Dictionary = {}
	for path: String in _dialogue_files():
		var resource: DialogueResource = load(path)
		for speaker: String in resource.character_names:
			texts[_key(speaker, SPEAKER_CONTEXT)] = "%s: speaker %s" % [path, speaker]
		for id: String in resource.lines:
			var line: Dictionary = resource.lines[id]
			if line.type in [DMConstants.TYPE_DIALOGUE, DMConstants.TYPE_RESPONSE]:
				texts[_key(line.text, line.static_id)] = "%s: %s" % [path, line.text]
	return texts


## Every file under `folder` with one of `extensions`, at any depth.
func _scripts(folder: String, extensions: Array[String] = ["gd"]) -> Array[String]:
	var found: Array[String] = []
	for file: String in DirAccess.get_files_at(folder):
		if file.get_extension() in extensions:
			found.append(folder.path_join(file))
	for sub: String in DirAccess.get_directories_at(folder):
		found.append_array(_scripts(folder.path_join(sub), extensions))
	return found


static func _has_letter(text: String) -> bool:
	return RegEx.create_from_string("\\p{L}").search(text) != null


## The interface's texts, each by itself as its catalogue key, the value where it was found.
func _interface_texts() -> Dictionary:
	var texts: Dictionary = {}
	var literal := RegEx.create_from_string("(?<![&\\w])\"((?:[^\"\\\\]|\\\\.)*)\"")
	var tr_literal := RegEx.create_from_string("\\btr\\(\\s*\"((?:[^\"\\\\]|\\\\.)*)\"")
	var constant := RegEx.create_from_string("^(?:static )?const (\\w+)")
	for path: String in _scripts("res://src"):
		var lines: PackedStringArray = FileAccess.get_file_as_string(path).split("\n")
		var index: int = 0
		while index < lines.size():
			var line: String = lines[index]
			if line.strip_edges().begins_with("#"):
				index += 1
				continue
			for found: RegExMatch in tr_literal.search_all(line):
				texts[found.get_string(1).c_unescape()] = "%s:%d" % [path, index + 1]
			var named: RegExMatch = constant.search(line)
			if named == null:
				index += 1
				continue
			# The constant's whole value, to where its brackets close.
			var depth: int = 0
			var first: int = index
			while true:
				# Brackets counted outside strings and comments.
				var code: String = literal.sub(lines[index], "\"\"", true).get_slice("#", 0)
				for c: String in code:
					if c in "([{":
						depth += 1
					elif c in ")]}":
						depth -= 1
				if depth <= 0 or index == lines.size() - 1:
					break
				index += 1
			if not named.get_string(1) in NOT_TEXT:
				for at: int in range(first, index + 1):
					for found: RegExMatch in literal.search_all(lines[at]):
						var text: String = found.get_string(1).c_unescape()
						if _has_letter(text) and not text.begins_with("res://") and not text.begins_with("uid://"):
							texts[text] = "%s:%d (%s)" % [path, at + 1, named.get_string(1)]
			index += 1
	var property := RegEx.create_from_string("^(\\w+) = \"((?:[^\"\\\\]|\\\\.)*)\"$")
	var files: Array[String] = _scripts("res://scenes", ["tscn"])
	files.append_array(_scripts("res://resources", ["tres"]))
	for path: String in files:
		# Node by node: a node's `text` counts only while its automatic translation is on.
		for block: String in ("\n" + FileAccess.get_file_as_string(path)).split("\n["):
			var translated: bool = not "\nauto_translate_mode = 2" in block
			for line: String in block.split("\n"):
				var found: RegExMatch = property.search(line)
				if found == null:
					continue
				var text: String = found.get_string(2).c_unescape()
				var name: String = found.get_string(1)
				if (name in TEXT_PROPERTIES or (name in NODE_TEXT_PROPERTIES and translated)) and _has_letter(text):
					texts[text] = "%s (%s)" % [path, name]
	return texts


## Static texts in scenes on nodes whose automatic translation is off, each with where it is.
func _untranslated_scene_texts() -> Array[String]:
	var found: Array[String] = []
	var property := RegEx.create_from_string("^(\\w+) = \"((?:[^\"\\\\]|\\\\.)*)\"$")
	for path: String in _scripts("res://scenes", ["tscn"]):
		for block: String in ("\n" + FileAccess.get_file_as_string(path)).split("\n["):
			if not "\nauto_translate_mode = 2" in block:
				continue
			for line: String in block.split("\n"):
				var found_line: RegExMatch = property.search(line)
				if found_line != null and found_line.get_string(1) in NODE_TEXT_PROPERTIES and _has_letter(found_line.get_string(2)):
					var text: String = found_line.get_string(2).c_unescape()
					if not text in SHOWN_AS_WRITTEN:
						found.append("%s: %s" % [path, text])
	return found


func _missing(texts: Dictionary, catalogue: Dictionary) -> Array[String]:
	var missing: Array[String] = []
	for key: String in texts:
		if String(catalogue.get(key, "")).strip_edges().is_empty():
			missing.append(texts[key])
	return missing


func test_every_line_choice_and_speaker_has_spanish() -> void:
	var missing: Array[String] = _missing(_dialogue_texts(), _catalogue(DIALOGUE))
	assert_eq(missing, [] as Array[String], "conversation texts without Spanish:\n" + "\n".join(missing))


func test_every_interface_text_has_spanish() -> void:
	var missing: Array[String] = _missing(_interface_texts(), _catalogue(INTERFACE))
	assert_eq(missing, [] as Array[String], "interface texts without Spanish:\n" + "\n".join(missing))


func test_no_scene_text_is_kept_from_translation_but_the_games_name() -> void:
	var found: Array[String] = _untranslated_scene_texts()
	assert_eq(found, [] as Array[String], "text on a node with translation off:\n" + "\n".join(found))


func test_the_catalogues_hold_nothing_the_game_does_not_use() -> void:
	var stale: Array[String] = []
	for pair: Array in [[INTERFACE, _interface_texts()], [DIALOGUE, _dialogue_texts()]]:
		for key: String in _catalogue(pair[0]):
			if not (pair[1] as Dictionary).has(key):
				stale.append("%s: %s" % [pair[0], key.replace(char(4), " | ")])
	assert_eq(stale, [] as Array[String], "entries nothing uses:\n" + "\n".join(stale))


func test_spanish_differs_from_english_but_for_names() -> void:
	var same: Array[String] = []
	for path: String in [INTERFACE, DIALOGUE]:
		var entries: Dictionary = _catalogue(path)
		for key: String in entries:
			var english: String = key.get_slice(char(4), key.get_slice_count(char(4)) - 1)
			if entries[key] == english and not english in SAME_IN_BOTH:
				same.append("%s: %s" % [path, english])
	assert_eq(same, [] as Array[String], "left in English:\n" + "\n".join(same))


func test_spanish_keeps_the_places_filled_in_and_the_line_breaks() -> void:
	var wrong: Array[String] = []
	var place := RegEx.create_from_string("%[sd]")
	for path: String in [INTERFACE, DIALOGUE]:
		var entries: Dictionary = _catalogue(path)
		for key: String in entries:
			var english: String = key.get_slice(char(4), key.get_slice_count(char(4)) - 1)
			var spanish: String = entries[key]
			var ours: Array = place.search_all(english).map(func(m: RegExMatch) -> String: return m.get_string())
			var theirs: Array = place.search_all(spanish).map(func(m: RegExMatch) -> String: return m.get_string())
			if ours != theirs or english.count("\n") != spanish.count("\n"):
				wrong.append("%s: %s" % [path, english])
	assert_eq(wrong, [] as Array[String], "places or line breaks differ:\n" + "\n".join(wrong))


func test_every_spoken_line_and_choice_has_its_own_stable_id() -> void:
	var problems: Array[String] = []
	var seen: Dictionary = {}
	for path: String in _dialogue_files():
		var resource: DialogueResource = load(path)
		for id: String in resource.lines:
			var line: Dictionary = resource.lines[id]
			if not line.type in [DMConstants.TYPE_DIALOGUE, DMConstants.TYPE_RESPONSE]:
				continue
			var static_id: String = line.get("static_id", "")
			if static_id.is_empty() or static_id == line.text:
				problems.append("%s: no id: %s" % [path, line.text])
			elif seen.has(static_id):
				problems.append("%s: id %s also on: %s" % [path, static_id, seen[static_id]])
			else:
				seen[static_id] = line.text
	assert_eq(problems, [] as Array[String], "\n".join(problems))


func test_every_speaker_has_a_portrait_key() -> void:
	for path: String in _dialogue_files():
		for speaker: String in (load(path) as DialogueResource).character_names:
			assert_true(Portraits.SPEAKERS.has(speaker), speaker)
