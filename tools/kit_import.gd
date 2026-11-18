@tool
extends EditorScenePostImport
## Godot's importer runs this on every kit piece (`assets/kit/*.glb`; each piece's `.import` names it
## as its import script). It does two things the glTF file cannot say:
##
## - Each surface's material is named after one of the five shared materials (`stone`, `brick`,
##   `plaster`, `wood`, `iron`) by `tools/blender/kit.py`; this swaps it for
##   `resources/materials/<name>.tres`, so every piece draws with the same five materials and carries no
##   texture of its own.
## - The collision bodies the importer made from the `-convcolonly` meshes go on layer 3 "walls" for
##   the wall-like pieces (the click ray ignores that layer, so clicks pass through the undrawn wall
##   nearest the camera and through a grille), and on layer 1 "world" for everything else. No body
##   looks for collisions itself (mask 0), as in the rooms.
##
## Editor-only (it is never exported): `tools/` is left out of the web build.

const MATERIALS: String = "res://resources/materials/%s.tres"
## Pieces whose bodies go on the "walls" layer.
const ON_WALLS: Array[String] = ["wall", "wall_brick", "door_frame", "bars"]
const WORLD_LAYER: int = 0b001
const WALLS_LAYER: int = 0b100


func _post_import(scene: Node) -> Object:
	var piece: String = get_source_file().get_file().get_basename()
	for node: Node in scene.find_children("*", "MeshInstance3D", true, false):
		var mesh: Mesh = (node as MeshInstance3D).mesh
		for surface: int in mesh.get_surface_count():
			var imported: Material = mesh.surface_get_material(surface)
			var shared: String = MATERIALS % (imported.resource_name if imported != null else "")
			if imported == null or not ResourceLoader.exists(shared):
				push_error("%s: surface %d has no shared material (%s)" % [piece, surface, shared])
				continue
			mesh.surface_set_material(surface, load(shared))
	for node: Node in scene.find_children("*", "StaticBody3D", true, false):
		var body := node as StaticBody3D
		body.collision_layer = WALLS_LAYER if piece in ON_WALLS else WORLD_LAYER
		body.collision_mask = 0
	return scene
