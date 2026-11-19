extends SceneTree
## Writes the licence of the Godot Engine running it, and the copyright and licence of every
## third-party component built into that engine, as plain text to the file given:
##
##     godot --headless --path . -s tools/engine_licenses.gd -- <output.txt>
##
## The text comes from the engine itself (`Engine.get_license_text()`, `get_copyright_info()` and
## `get_license_info()`), so it always matches the engine that exports the game; `ops/build-web.sh`
## runs it at each build. Two runs with the same engine write the same bytes.


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() != 1:
		push_error("Usage: godot --headless --path . -s tools/engine_licenses.gd -- <output.txt>")
		quit(1)
		return
	var file := FileAccess.open(args[0], FileAccess.WRITE)
	if file == null:
		push_error("Cannot write %s: %s" % [args[0], error_string(FileAccess.get_open_error())])
		quit(1)
		return
	file.store_string(engine_licenses())
	file.close()
	quit(0)


## The whole text: the engine's own licence, then each component's files, copyright and licence
## name, then the text of each licence those name.
static func engine_licenses() -> String:
	var version: Dictionary = Engine.get_version_info()
	var lines: PackedStringArray = []
	lines.append("Godot Engine %s (https://godotengine.org/license)" % version.string)
	lines.append("")
	lines.append(Engine.get_license_text().strip_edges())
	lines.append("")
	lines.append("")
	lines.append("Third-party components built into the engine")
	lines.append("")
	for component: Dictionary in Engine.get_copyright_info():
		lines.append("- %s" % component.name)
		for part: Dictionary in component.parts:
			lines.append("  Files: %s" % ", ".join(part.files))
			for holder: String in part.copyright:
				lines.append("  Copyright: %s" % holder)
			lines.append("  License: %s" % part.license)
		lines.append("")
	lines.append("")
	lines.append("Licence texts")
	var licenses: Dictionary = Engine.get_license_info()
	var names: Array = licenses.keys()
	names.sort()
	for name: String in names:
		lines.append("")
		lines.append("== %s ==" % name)
		lines.append("")
		lines.append(String(licenses[name]).strip_edges())
	return "\n".join(lines) + "\n"
