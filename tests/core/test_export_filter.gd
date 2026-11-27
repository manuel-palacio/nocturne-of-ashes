# tests/core/test_export_filter.gd
extends GutTest
## The web export leaves out what the game never loads, and nothing that it does: every kit piece
## ships only if a scene of the game uses it.

const GAME_SCENES: Array[String] = ["res://scenes/game.tscn", "res://scenes/main.tscn"]
## Scripts name what they load in `res://` strings, which `ResourceLoader.get_dependencies()` does
## not list; those of the game's code are read here.
const CODE: String = "res://src"
const KIT: String = "res://assets/kit"


func _excluded() -> PackedStringArray:
	var presets := ConfigFile.new()
	assert_eq(presets.load("res://export_presets.cfg"), OK)
	var patterns := PackedStringArray()
	for pattern: String in String(presets.get_value("preset.0", "exclude_filter", "")).split(",", false):
		patterns.append(pattern.strip_edges())
	return patterns


func _is_excluded(path: String, patterns: PackedStringArray) -> bool:
	for pattern: String in patterns:
		if path.trim_prefix("res://").match(pattern):
			return true
	return false


## Every `res://` path named in a script under `folder`, at any depth.
func _named_in_code(folder: String) -> Array[String]:
	var named: Array[String] = []
	var quoted := RegEx.create_from_string("\"(res://[^\"]+)\"")
	for file: String in DirAccess.get_files_at(folder):
		if file.get_extension() == "gd":
			for found: RegExMatch in quoted.search_all(FileAccess.get_file_as_string(folder.path_join(file))):
				named.append(found.get_string(1))
	for sub: String in DirAccess.get_directories_at(folder):
		named.append_array(_named_in_code(folder.path_join(sub)))
	return named


## Every resource the game's scenes and code load, directly or through others, and the translation
## catalogues the project settings list (`internationalization/locale/translations`), which the engine
## loads at start.
func _loaded() -> Dictionary:
	var found: Dictionary = {}
	var queue: Array[String] = GAME_SCENES.duplicate()
	queue.append_array(_named_in_code(CODE))
	queue.append_array(Array(ProjectSettings.get_setting("internationalization/locale/translations", PackedStringArray())))
	while not queue.is_empty():
		var path: String = queue.pop_back()
		if found.has(path):
			continue
		found[path] = true
		for dependency: String in ResourceLoader.get_dependencies(path):
			var next: String = dependency.get_slice("::", dependency.get_slice_count("::") - 1)
			if next.begins_with("uid://"):
				next = ResourceUID.get_id_path(ResourceUID.text_to_id(next))
			if next.begins_with("res://"):
				queue.append(next)
	return found


func test_nothing_the_game_loads_is_left_out() -> void:
	var patterns: PackedStringArray = _excluded()
	for path: String in _loaded():
		assert_false(_is_excluded(path, patterns), "%s is loaded but left out of the export" % path)


func test_the_translation_catalogues_ship() -> void:
	var catalogues: PackedStringArray = ProjectSettings.get_setting("internationalization/locale/translations", PackedStringArray())
	assert_true(catalogues.has("res://assets/i18n/es.po"))
	assert_true(catalogues.has("res://assets/i18n/es-dialogue.po"))
	var loaded: Dictionary = _loaded()
	var patterns: PackedStringArray = _excluded()
	for path: String in catalogues:
		assert_true(loaded.has(path), path)
		assert_false(_is_excluded(path, patterns), "%s is a catalogue but left out of the export" % path)


func test_a_kit_piece_ships_only_if_a_room_uses_it() -> void:
	var patterns: PackedStringArray = _excluded()
	var loaded: Dictionary = _loaded()
	for file: String in DirAccess.get_files_at(KIT):
		if file.get_extension() != "glb":
			continue
		var path: String = KIT.path_join(file)
		assert_ne(loaded.has(path), _is_excluded(path, patterns),
				"%s: used by a room, or else left out of the export" % path)
