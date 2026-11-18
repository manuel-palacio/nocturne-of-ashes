# tests/visual/test_kit.gd
extends GutTest
## The stone kit made by `tools/blender/kit.py`: every piece loads, stays under the triangle cap, fills
## the footprint it is made for, blocks movement only where it should, and is drawn only with the five
## shared materials.

const KIT_DIR: String = "res://assets/kit/"
const MAX_TRIANGLES: int = 2000
const TOLERANCE: float = 0.05
## Each piece's drawn bounds, smallest and largest corner, in metres: the origin is at floor level in the
## middle of the piece's footprint, and the side that faces the room is +z.
const BOUNDS: Dictionary = {
	"floor_slab": [Vector3(-1, -0.1, -1), Vector3(1, 0, 1)],
	"wall": [Vector3(-1, 0, -0.25), Vector3(1, 4, 0.25)],
	"wall_brick": [Vector3(-1, 0, -0.25), Vector3(1, 4, 0.25)],
	"pillar": [Vector3(-0.4, 0, -0.4), Vector3(0.4, 4, 0.4)],
	"arch_horseshoe": [Vector3(-1, 0, -0.4), Vector3(1, 4, 0.4)],
	"arch_round": [Vector3(-2, 0, -0.4), Vector3(2, 4, 0.4)],
	"vault_barrel": [Vector3(-2, 4, -1), Vector3(2, 6, 1)],
	"door_frame": [Vector3(-1, 0, -0.25), Vector3(1, 4, 0.3)],
	"door_leaf": [Vector3(-0.7, 0, -0.05), Vector3(0.7, 2.4, 0.09)],
	"stair_down": [Vector3(-1, -2.4, -2), Vector3(1, 0, 2)],
	"forge": [Vector3(-1.3, 0, -0.7), Vector3(1.3, 4, 0.7)],
	"anvil": [Vector3(-0.42, 0, -0.25), Vector3(0.3, 0.82, 0.25)],
	"rack": [Vector3(-1, 0, -0.25), Vector3(1, 1.9, 0.25)],
	"barrel": [Vector3(-0.33, 0, -0.33), Vector3(0.33, 0.9, 0.33)],
	"bench": [Vector3(-0.8, 0, -0.2), Vector3(0.8, 0.5, 0.2)],
	"bars": [Vector3(-1, 0, -0.03), Vector3(1, 2.4, 0.03)],
	"sconce": [Vector3(-0.08, 1.9, -0.2), Vector3(0.08, 2.6, 0.2)],
	"lock_seal": [Vector3(-0.7, 0, -0.15), Vector3(0.7, 2.4, 0.15)],
}
## Pieces that block nothing: the vault is overhead, the sconce and the seal lie flat on a wall, and a
## door's own body (`scenes/rooms/door.tscn`) does the door's blocking.
const OPEN: Array[String] = ["vault_barrel", "door_leaf", "sconce", "lock_seal"]
## Blocking pieces on the "walls" layer (3), which the click ray ignores; the rest block on "world" (1).
const ON_WALLS: Array[String] = ["wall", "wall_brick", "door_frame", "bars"]
const WORLD_LAYER: int = 0b001
const WALLS_LAYER: int = 0b100
const MATERIALS: Array[String] = ["stone", "brick", "plaster", "wood", "iron"]
const MAX_TEXTURE: int = 1024


func _piece(piece_name: String) -> Node3D:
	var scene := load(KIT_DIR + piece_name + ".glb") as PackedScene
	return add_child_autofree(scene.instantiate()) as Node3D


func _meshes(piece: Node) -> Array[MeshInstance3D]:
	var found: Array[MeshInstance3D] = []
	for node: Node in piece.find_children("*", "MeshInstance3D", true, false):
		found.append(node as MeshInstance3D)
	return found


func test_every_piece_exists_and_loads() -> void:
	var files: Array = Array(DirAccess.get_files_at(KIT_DIR)).filter(
			func(file: String) -> bool: return file.get_extension() == "glb")
	files.sort()
	var expected: Array = BOUNDS.keys().map(func(piece_name: String) -> String: return piece_name + ".glb")
	expected.sort()
	assert_eq(files, expected, "the kit holds exactly the pieces of the table")
	for piece_name: String in BOUNDS:
		assert_true(ResourceLoader.exists(KIT_DIR + piece_name + ".glb"), piece_name)
		var piece: Node3D = _piece(piece_name)
		assert_not_null(piece, piece_name)
		assert_gt(_meshes(piece).size(), 0, "%s has a mesh" % piece_name)


func test_each_piece_is_under_the_triangle_cap() -> void:
	for piece_name: String in BOUNDS:
		var triangles: int = 0
		for mesh: MeshInstance3D in _meshes(_piece(piece_name)):
			for surface: int in mesh.mesh.get_surface_count():
				triangles += mesh.mesh.surface_get_array_index_len(surface) / 3
		assert_gt(triangles, 0, piece_name)
		assert_lt(triangles, MAX_TRIANGLES, piece_name)


func test_each_piece_fits_its_footprint_and_height() -> void:
	for piece_name: String in BOUNDS:
		var piece: Node3D = _piece(piece_name)
		var box := AABB()
		var first: bool = true
		for mesh: MeshInstance3D in _meshes(piece):
			var part: AABB = piece.global_transform.affine_inverse() * mesh.global_transform * mesh.get_aabb()
			box = part if first else box.merge(part)
			first = false
		var expected: Array = BOUNDS[piece_name]
		for axis: int in 3:
			assert_almost_eq(box.position[axis], (expected[0] as Vector3)[axis], TOLERANCE,
					"%s: lowest %s" % [piece_name, "xyz"[axis]])
			assert_almost_eq(box.end[axis], (expected[1] as Vector3)[axis], TOLERANCE,
					"%s: highest %s" % [piece_name, "xyz"[axis]])


func test_blocking_pieces_have_a_collision_shape_and_open_ones_none() -> void:
	for piece_name: String in BOUNDS:
		var piece: Node3D = _piece(piece_name)
		var bodies: Array[Node] = piece.find_children("*", "CollisionObject3D", true, false)
		var shapes: Array[Node] = piece.find_children("*", "CollisionShape3D", true, false)
		if piece_name in OPEN:
			assert_eq(bodies.size(), 0, "%s blocks nothing" % piece_name)
			assert_eq(shapes.size(), 0, "%s has no shape" % piece_name)
			continue
		assert_gt(shapes.size(), 0, "%s has a collision shape" % piece_name)
		for shape: CollisionShape3D in shapes:
			assert_not_null(shape.shape, "%s: %s" % [piece_name, shape.name])
			assert_true(shape.get_parent() is StaticBody3D, "%s: %s hangs from a static body" % [piece_name, shape.name])
		var layer: int = WALLS_LAYER if piece_name in ON_WALLS else WORLD_LAYER
		for body: CollisionObject3D in bodies:
			assert_eq(body.collision_layer, layer, "%s: %s layer" % [piece_name, body.name])
			assert_eq(body.collision_mask, 0, "%s: %s looks for nothing" % [piece_name, body.name])


func test_pieces_draw_only_with_the_shared_materials_and_textures() -> void:
	var shared: Array = MATERIALS.map(func(material: String) -> String:
			return "res://resources/materials/%s.tres" % material)
	for piece_name: String in BOUNDS:
		for mesh: MeshInstance3D in _meshes(_piece(piece_name)):
			for surface: int in mesh.mesh.get_surface_count():
				var material := mesh.get_active_material(surface) as BaseMaterial3D
				assert_not_null(material, "%s surface %d" % [piece_name, surface])
				if material == null:
					continue
				assert_has(shared, material.resource_path, "%s surface %d" % [piece_name, surface])
	for path: String in shared:
		var material := load(path) as BaseMaterial3D
		for texture: Texture2D in [material.albedo_texture, material.normal_texture]:
			assert_not_null(texture, path)
			assert_true(texture.resource_path.begins_with("res://assets/textures/"), texture.resource_path)
			assert_lte(maxi(texture.get_width(), texture.get_height()), MAX_TEXTURE, texture.resource_path)
