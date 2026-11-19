# tests/visual/test_atmosphere.gd
extends GutTest
## The rooms' light and air: both share one environment with no fog measured from the camera.

const ROOMS: Array[PackedScene] = [
	preload("res://scenes/rooms/vault_room.tscn"),
	preload("res://scenes/rooms/forge_haven.tscn"),
]
const ENVIRONMENT: String = "res://resources/environment/cellar.tres"


func _room(scene: PackedScene) -> Room:
	return add_child_autofree(scene.instantiate()) as Room


func test_both_rooms_share_one_environment_without_distance_fog() -> void:
	for scene: PackedScene in ROOMS:
		var room: Room = _room(scene)
		var worlds: Array[Node] = room.find_children("*", "WorldEnvironment", true, false)
		assert_eq(worlds.size(), 1, "%s: one WorldEnvironment" % room.room_id)
		if worlds.is_empty():
			continue
		var environment: Environment = (worlds[0] as WorldEnvironment).environment
		assert_eq(environment.resource_path, ENVIRONMENT, "%s: the shared environment" % room.room_id)
		assert_false(environment.fog_enabled, "no fog measured from the camera")
		assert_false(environment.volumetric_fog_enabled, "no volumetric fog")
