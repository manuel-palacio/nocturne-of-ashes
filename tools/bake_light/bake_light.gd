@tool
extends EditorPlugin
## Bakes the lightmap (`LightmapGI`) of every room listed in `ROOMS`, then quits the editor. It runs
## only when the editor is started with the user argument `--bake-light`, as `ops/bake-light.sh` does:
## the lightmapper needs the Forward+ renderer, while the game draws with Compatibility. Otherwise it
## does nothing; the script enables it in `project.godot` for its run only.
##
## Godot binds no script method to bake a lightmap, so this presses the editor's own "Bake Lightmaps"
## button with the room's `LightmapGI` selected. Each room bakes into `<scene>.lmbake` and
## `<scene>.exr` beside its scene; the `.exr` is imported lossless, the one lightmap format every
## browser's WebGL reads.

const ROOMS: Array[String] = [
	"res://scenes/rooms/vault_room.tscn",
	"res://scenes/rooms/forge_haven.tscn",
]
const ARGUMENT: String = "--bake-light"
const BUTTON_TEXT: String = "Bake Lightmaps"
## How long to give the editor to settle after it starts and after a scene opens, in seconds.
const SETTLE: float = 2.0


func _enter_tree() -> void:
	if ARGUMENT in OS.get_cmdline_user_args():
		_bake_all.call_deferred()


func _bake_all() -> void:
	await get_tree().create_timer(SETTLE).timeout
	var failed: int = 0
	for scene: String in ROOMS:
		if not await _bake(scene):
			failed += 1
	print("bake-light: %d of %d rooms baked" % [ROOMS.size() - failed, ROOMS.size()])
	get_tree().quit(1 if failed > 0 else 0)


func _bake(scene: String) -> bool:
	EditorInterface.open_scene_from_path(scene)
	await get_tree().create_timer(SETTLE).timeout
	var root: Node = EditorInterface.get_edited_scene_root()
	var found: Array[Node] = root.find_children("*", "LightmapGI", true, false) if root != null else []
	if found.size() != 1:
		push_error("bake-light: %s needs exactly one LightmapGI" % scene)
		return false
	var lightmap := found[0] as LightmapGI
	var data_path: String = scene.get_basename() + ".lmbake"
	if lightmap.light_data == null or lightmap.light_data.resource_path != data_path:
		push_error("bake-light: the LightmapGI of %s must use %s" % [scene, data_path])
		return false
	_import_lossless(scene.get_basename() + ".exr.import")
	EditorInterface.edit_node(lightmap)
	await get_tree().process_frame
	var button := _find_button(EditorInterface.get_base_control())
	if button == null:
		push_error("bake-light: no \"%s\" button in the editor" % BUTTON_TEXT)
		return false
	# The bake runs inside the press and has written the data when it returns.
	button.pressed.emit()
	if _import_lossless(scene.get_basename() + ".exr.import"):
		EditorInterface.get_resource_filesystem().reimport_files([scene.get_basename() + ".exr"])
	print("bake-light: baked %s" % scene)
	return true


## Sets the lightmap's import to lossless; true when it was not. The lightmapper keeps an existing
## compression setting, so this holds from the second bake on.
func _import_lossless(import_path: String) -> bool:
	var config := ConfigFile.new()
	if config.load(import_path) != OK:
		return false
	if config.get_value("params", "compress/mode", -1) == 0:
		return false
	config.set_value("params", "compress/mode", 0)
	config.save(import_path)
	return true


func _find_button(node: Node) -> Button:
	if node is Button and (node as Button).text == BUTTON_TEXT:
		return node as Button
	for child: Node in node.get_children(true):
		var found: Button = _find_button(child)
		if found != null:
			return found
	return null
