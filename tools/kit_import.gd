@tool
extends EditorScenePostImport
## Godot's importer runs this on every kit piece (`assets/kit/*.glb`; each piece's `.import` names it
## as its import script). It does two things the glTF file cannot say:
##
## - Each surface's material is named after one of the six shared materials (`stone`, `brick`,
##   `plaster`, `wood`, `iron`, `ember`) by `tools/blender/kit.py`; this swaps it for
##   `resources/materials/<name>.tres`, so every piece draws with the same six materials and carries no
##   texture of its own. A surface asking for any other material fails the piece's import (and
##   `godot --headless --import` exits with code 1).
## - The collision bodies the importer made from the `-convcolonly` meshes go on the layer their
##   name asks for: a body whose name ends in `-walls` on layer 3 "walls" (units bump into it, but the
##   click ray ignores that layer, so clicks pass through the undrawn wall nearest the camera, a grille
##   or a stairwell), any other on layer 1 "world". No body looks for collisions itself (mask 0), as in
##   the rooms. The tool decides the layer, per collider; nothing here lists pieces.
##
## Editor-only (it is never exported): `tools/` is left out of the web build.

const MATERIALS: String = "res://resources/materials/%s.tres"
## The end of a collider's name that puts its body on the "walls" layer.
const WALLS_MARKER: String = "-walls"
const WORLD_LAYER: int = 0b001
const WALLS_LAYER: int = 0b100


func _post_import(scene: Node) -> Object:
	var piece: String = get_source_file().get_file().get_basename()
	var wrong: PackedStringArray = swap_materials(scene)
	if not wrong.is_empty():
		for problem: String in wrong:
			push_error("Kit piece %s: %s" % [piece, problem])
		# Run headless, as `godot --headless --import` is, the run ends with exit code 1, so a script
		# that imports notices; in the editor's window the piece is simply not imported.
		if DisplayServer.get_name() == "headless":
			(Engine.get_main_loop() as SceneTree).quit(1)
		return null
	for node: Node in scene.find_children("*", "StaticBody3D", true, false):
		var body := node as StaticBody3D
		body.collision_layer = WALLS_LAYER if String(body.name).ends_with(WALLS_MARKER) else WORLD_LAYER
		body.collision_mask = 0
	return scene


## Swaps each surface's material in `scene` for the shared material it is named after. Returns what
## is wrong: one line per surface whose material is not one of the shared ones, left as it was.
static func swap_materials(scene: Node) -> PackedStringArray:
	var wrong: PackedStringArray = []
	for node: Node in scene.find_children("*", "MeshInstance3D", true, false):
		var mesh: Mesh = (node as MeshInstance3D).mesh
		for surface: int in mesh.get_surface_count():
			var imported: Material = mesh.surface_get_material(surface)
			var wanted: String = imported.resource_name if imported != null else "(none)"
			var shared: String = MATERIALS % wanted
			if imported == null or not ResourceLoader.exists(shared):
				wrong.append("surface %d of %s asks for material \"%s\", which is not one of the shared materials in resources/materials/"
						% [surface, node.name, wanted])
				continue
			mesh.surface_set_material(surface, load(shared))
	return wrong
