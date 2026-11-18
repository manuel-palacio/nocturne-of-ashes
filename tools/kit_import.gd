@tool
extends EditorScenePostImport
## Godot's importer runs this on every kit piece (`assets/kit/*.glb`; each piece's `.import` names it
## as its import script). It does two things the glTF file cannot say:
##
## - Each surface's material is named after one of the six shared materials (`stone`, `brick`,
##   `plaster`, `wood`, `iron`, `ember`) by `tools/blender/kit.py`; this swaps it for
##   `resources/materials/<name>.tres`, so every piece draws with the same six materials and carries no
##   texture of its own.
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
	for node: Node in scene.find_children("*", "MeshInstance3D", true, false):
		var mesh: Mesh = (node as MeshInstance3D).mesh
		for surface: int in mesh.get_surface_count():
			var imported: Material = mesh.surface_get_material(surface)
			var wanted: String = imported.resource_name if imported != null else "(none)"
			var shared: String = MATERIALS % wanted
			if imported == null or not ResourceLoader.exists(shared):
				push_error("Kit piece %s: surface %d asks for material \"%s\", which is not one of the shared materials in resources/materials/; the piece would draw without it"
						% [piece, surface, wanted])
				continue
			mesh.surface_set_material(surface, load(shared))
	for node: Node in scene.find_children("*", "StaticBody3D", true, false):
		var body := node as StaticBody3D
		body.collision_layer = WALLS_LAYER if String(body.name).ends_with(WALLS_MARKER) else WORLD_LAYER
		body.collision_mask = 0
	return scene
