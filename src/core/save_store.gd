class_name SaveStore
extends RefCounted
## Keeps one `GameState` in one JSON file. A file that exists but cannot be used is reported with a
## warning and treated as no save. `keeps_saves()` tells whether saves will last.

## Appended to `path` for the file a save is written to before it replaces the old one.
const TEMP_SUFFIX: String = ".tmp"
## Appended to `path` for the small file `keeps_saves()` writes, reads back and removes.
const PROBE_SUFFIX: String = ".probe"

var path: String = "user://save.json"


## Writes `state` over any earlier save; false when it cannot be written, and then the earlier save
## is kept. The state goes to a temporary file first, renamed over the save once complete, so an
## interrupted write cannot leave a truncated save.
func save(state: GameState) -> bool:
	var temp: String = path + TEMP_SUFFIX
	var file := FileAccess.open(temp, FileAccess.WRITE)
	if file == null:
		return false
	var written: bool = file.store_string(JSON.stringify(state.to_dict()))
	file.close()
	if written and DirAccess.rename_absolute(temp, path) == OK:
		return true
	if FileAccess.file_exists(temp):
		DirAccess.remove_absolute(temp)
	return false


## Whether saves will last: a small value written beside the save reads back the same, and the engine
## says its `user://` is persistent. In a browser `user://` lives in IndexedDB; the engine reports it
## not persistent when that could not be opened (site data blocked, some private windows). A browser
## that opens IndexedDB and wipes it when the window closes (most private windows) cannot be told
## apart from here. The probe file is removed afterwards.
func keeps_saves() -> bool:
	if not OS.is_userfs_persistent():
		return false
	var probe: String = path + PROBE_SUFFIX
	var value: String = "%d" % Time.get_ticks_usec()
	var file := FileAccess.open(probe, FileAccess.WRITE)
	if file == null:
		return false
	var written: bool = file.store_string(value)
	file.close()
	var read: String = FileAccess.get_file_as_string(probe) if written else ""
	if FileAccess.file_exists(probe):
		DirAccess.remove_absolute(probe)
	return written and read == value


## The saved state; null when there is no save, and also, with a warning, when the file is unusable.
func load_state() -> GameState:
	var result: Variant = _read()
	if result is String:
		push_warning("Ignoring the save file %s: %s" % [path, result])
		return null
	return result as GameState


## Whether a usable save exists.
func has_save() -> bool:
	return _read() is GameState


## Removes the save and any temporary file left by an interrupted save.
func clear() -> void:
	for file: String in [path, path + TEMP_SUFFIX]:
		if FileAccess.file_exists(file):
			DirAccess.remove_absolute(file)


## The saved state, null when there is no file, or a String saying why the file is unusable.
func _read() -> Variant:
	if not FileAccess.file_exists(path):
		return null
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return "it cannot be opened (%s)" % error_string(FileAccess.get_open_error())
	var text: String = file.get_as_text()
	file.close()
	var json := JSON.new()
	if json.parse(text) != OK:
		return "it is not JSON (%s at line %d)" % [json.get_error_message(), json.get_error_line()]
	var state: GameState = GameState.from_dict(json.data)
	if state == null:
		return "it is not a version %d game state" % GameState.VERSION
	return state
