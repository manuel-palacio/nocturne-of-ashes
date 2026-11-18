# tests/visual/test_kit.gd
extends GutTest
## The stone kit made by `tools/blender/kit.py`: every piece loads, stays under the triangle cap, fills
## the footprint it is made for, blocks movement only where it should, and is drawn only with the six
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
	"wall_corner": [Vector3(-0.25, 0, -0.25), Vector3(0.25, 4, 0.25)],
	"pillar": [Vector3(-0.4, 0, -0.4), Vector3(0.4, 4, 0.4)],
	"arch_horseshoe": [Vector3(-1, 0, -0.4), Vector3(1, 4, 0.4)],
	"arch_round": [Vector3(-2, 0, -0.4), Vector3(2, 4, 0.4)],
	"arch_segmental": [Vector3(-3, 0, -0.4), Vector3(3, 4, 0.4)],
	"vault_barrel": [Vector3(-2, 4, -1), Vector3(2, 6, 1)],
	"door_frame": [Vector3(-1, 0, -0.25), Vector3(1, 4, 0.3)],
	"door_leaf": [Vector3(-0.7, 0, -0.05), Vector3(0.7, 2.4, 0.09)],
	"stair_down": [Vector3(-1, -2.4, -2), Vector3(1, 0, 2)],
	"forge": [Vector3(-1.3, 0, -0.7), Vector3(1.3, 4, 0.7)],
	"embers": [Vector3(-0.75, 0.72, -0.35), Vector3(0.75, 0.81, 0.35)],
	"anvil": [Vector3(-0.42, 0, -0.25), Vector3(0.3, 0.82, 0.25)],
	"rack": [Vector3(-1, 0, -0.25), Vector3(1, 1.9, 0.25)],
	"barrel": [Vector3(-0.33, 0, -0.33), Vector3(0.33, 0.9, 0.33)],
	"bench": [Vector3(-0.8, 0, -0.2), Vector3(0.8, 0.5, 0.2)],
	"bars": [Vector3(-1, 0, -0.03), Vector3(1, 2.4, 0.03)],
	"sconce": [Vector3(-0.08, 1.9, -0.2), Vector3(0.08, 2.6, 0.2)],
	"lock_seal": [Vector3(-0.7, 0, -0.15), Vector3(0.7, 2.4, 0.15)],
}
## Pieces that block nothing: the vault is overhead, the sconce and the seal lie flat on a wall, the
## embers lie in the forge's pan, and a door's own body (`scenes/rooms/door.tscn`) does the door's blocking.
const OPEN: Array[String] = ["vault_barrel", "door_leaf", "sconce", "lock_seal", "embers"]
## Blocking pieces a click passes through, to whatever lies beyond: the wall nearest the camera is
## not drawn, a grille is seen through, and a click on the stairwell means the floor. The others stop a
## click where they stand.
const CLICK_THROUGH: Array[String] = ["wall", "wall_brick", "wall_corner", "door_frame", "bars", "stair_down"]
## The click ray tests only this layer (`Picker`).
const WORLD_LAYER: int = 0b001
const WALLS_LAYER: int = 0b100
## What a unit bumps into (`unit_base.tscn`), and the size of one.
const UNIT_MASK: int = 0b101
const UNIT_RADIUS: float = 0.35
const UNIT_HEIGHT: float = 1.8
## Where the pieces stand in the physics tests, one per spot, far enough apart not to touch.
const SPACING: float = 12.0
const MATERIALS: Array[String] = ["stone", "brick", "plaster", "wood", "iron", "ember"]
const MAX_TEXTURE: int = 1024


func _piece(piece_name: String) -> Node3D:
	var scene := load(KIT_DIR + piece_name + ".glb") as PackedScene
	return add_child_autofree(scene.instantiate()) as Node3D


## `piece_name` placed `SPACING` metres along x per `slot`, in the physics world.
func _placed(piece_name: String, slot: int) -> Node3D:
	var piece: Node3D = _piece(piece_name)
	piece.position = Vector3(slot * SPACING, 0, 0)
	return piece


## Whether a unit standing at `at` (relative to `piece`) touches anything it would bump into.
func _unit_blocked(piece: Node3D, at: Vector3) -> bool:
	var shape := CapsuleShape3D.new()
	shape.radius = UNIT_RADIUS
	shape.height = UNIT_HEIGHT
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.collision_mask = UNIT_MASK
	query.transform = Transform3D(Basis(), piece.position + at + Vector3(0, UNIT_HEIGHT / 2 + 0.05, 0))
	return not piece.get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()


## Whether a unit walking from `from` to `to` (relative to `piece`, 5 cm steps) is stopped on the way.
func _walk_blocked(piece: Node3D, from: Vector3, to: Vector3) -> bool:
	var steps: int = ceili(from.distance_to(to) / 0.05)
	for i: int in steps + 1:
		if _unit_blocked(piece, from.lerp(to, float(i) / steps)):
			return true
	return false


## What a straight-down ray at `at` (relative to `piece`) hits on `mask`, or an empty dictionary.
func _ray_down(piece: Node3D, at: Vector3, mask: int) -> Dictionary:
	var origin: Vector3 = piece.position + Vector3(at.x, 20.0, at.z)
	var query := PhysicsRayQueryParameters3D.create(origin, origin + Vector3.DOWN * 40.0, mask)
	return piece.get_world_3d().direct_space_state.intersect_ray(query)


## The middle of each collision shape of `piece`, relative to the piece.
func _shape_centres(piece: Node3D) -> Array[Vector3]:
	var centres: Array[Vector3] = []
	for node: Node in piece.find_children("*", "CollisionShape3D", true, false):
		var shape := node as CollisionShape3D
		var points: PackedVector3Array = (shape.shape as ConvexPolygonShape3D).points
		var sum := Vector3.ZERO
		for point: Vector3 in points:
			sum += point
		centres.append(piece.global_transform.affine_inverse() * shape.global_transform * (sum / points.size()))
	return centres


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
		for body: CollisionObject3D in bodies:
			assert_has([WORLD_LAYER, WALLS_LAYER], body.collision_layer, "%s: %s is on world or walls" % [piece_name, body.name])
			assert_eq(body.collision_mask, 0, "%s: %s looks for nothing" % [piece_name, body.name])


func test_clicks_pass_through_walls_grilles_and_stairwells_and_stop_on_the_rest() -> void:
	var slot: int = 0
	for piece_name: String in BOUNDS:
		if piece_name in OPEN:
			continue
		var piece: Node3D = _placed(piece_name, slot)
		slot += 1
		await wait_physics_frames(1)
		for centre: Vector3 in _shape_centres(piece):
			var stops_units: bool = not _ray_down(piece, centre, UNIT_MASK).is_empty()
			assert_true(stops_units, "%s: units bump into its shape at %s" % [piece_name, centre])
			var click: Dictionary = _ray_down(piece, centre, WORLD_LAYER)
			if piece_name in CLICK_THROUGH:
				assert_true(click.is_empty(), "%s: a click at %s passes through" % [piece_name, centre])
			else:
				assert_false(click.is_empty(), "%s: a click at %s stops on it" % [piece_name, centre])


func test_a_click_on_the_stairwell_lands_on_the_floor_plane() -> void:
	var stair: Node3D = _placed("stair_down", 0)
	var camera := Camera3D.new()
	add_child_autofree(camera)
	camera.position = stair.position + Vector3(0, 10, 4)
	camera.look_at(stair.position + Vector3(0, -1.2, 0))
	camera.make_current()
	await wait_physics_frames(1)
	var screen: Vector2 = camera.unproject_position(stair.position + Vector3(0, -1.2, 0))
	var ground: Variant = Picker.ground_at(camera, screen)
	assert_not_null(ground)
	assert_almost_eq((ground as Vector3).y, 0.0, 0.01, "at floor level, not on a collider over the steps")


func test_a_unit_walks_through_the_openings_and_not_through_walls_piers_bars_or_the_stair() -> void:
	var pieces: Dictionary = {}
	var slot: int = 0
	for piece_name: String in ["arch_horseshoe", "arch_round", "door_frame", "wall", "wall_corner", "pillar", "bars", "stair_down"]:
		pieces[piece_name] = _placed(piece_name, slot)
		slot += 1
	await wait_physics_frames(1)
	for opening: String in ["arch_horseshoe", "arch_round", "door_frame"]:
		assert_false(_walk_blocked(pieces[opening], Vector3(0, 0, 2), Vector3(0, 0, -2)), "through %s" % opening)
	assert_true(_walk_blocked(pieces["arch_horseshoe"], Vector3(-2, 0, 0), Vector3(2, 0, 0)), "not through the horseshoe's jambs")
	assert_true(_walk_blocked(pieces["arch_round"], Vector3(-3, 0, 0), Vector3(3, 0, 0)), "not through the round arch's jambs")
	assert_true(_walk_blocked(pieces["door_frame"], Vector3(-0.85, 0, 2), Vector3(-0.85, 0, -2)), "not through the door frame's wall")
	for solid: String in ["wall", "wall_corner", "pillar"]:
		assert_true(_walk_blocked(pieces[solid], Vector3(0, 0, 2), Vector3(0, 0, -2)), "not through %s" % solid)
	for x: float in [-0.95, -0.5, 0.0, 0.5, 0.95]:
		assert_true(_walk_blocked(pieces["bars"], Vector3(x, 0, 1), Vector3(x, 0, -1)), "the bars stop a unit at x = %.2f" % x)
	assert_true(_unit_blocked(pieces["bars"], Vector3(0.95, 0, 0)), "the bars span their 2 m")
	assert_false(_unit_blocked(pieces["bars"], Vector3(1.4, 0, 0)), "and no further")
	assert_true(_walk_blocked(pieces["stair_down"], Vector3(0, 0, 3), Vector3(0, 0, 0)), "not into the stair's mouth")
	for x: float in [-2.0, 2.0]:
		assert_true(_walk_blocked(pieces["stair_down"], Vector3(x, 0, 0), Vector3(0, 0, 0)), "not in over its side from x = %d" % x)


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
			for side: int in [texture.get_width(), texture.get_height()]:
				assert_eq(side & (side - 1), 0, "%s is a power of two" % texture.resource_path)
