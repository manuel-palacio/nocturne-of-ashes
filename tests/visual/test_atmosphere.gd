# tests/visual/test_atmosphere.gd
extends GutTest
## The rooms' light and air: both share one environment with no fog measured from the camera, and
## the baked light they draw with is exported in a form every browser reads.

const ROOMS: Array[PackedScene] = [
	preload("res://scenes/rooms/vault_room.tscn"),
	preload("res://scenes/rooms/forge_haven.tscn"),
]
const ENVIRONMENT: String = "res://resources/environment/cellar.tres"
## Lossless, in the lightmap's `.import`: a VRAM-compressed lightmap is stored in formats some
## browsers' WebGL cannot read.
const LOSSLESS: int = 0


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


func test_the_baked_light_is_exported_in_a_form_browsers_read() -> void:
	var presets := ConfigFile.new()
	assert_eq(presets.load("res://export_presets.cfg"), OK)
	var excluded: PackedStringArray = String(presets.get_value("preset.0", "exclude_filter", "")).split(",", false)
	for scene: PackedScene in ROOMS:
		var room: Room = _room(scene)
		var bakes: Array[Node] = room.find_children("*", "LightmapGI", true, false)
		assert_eq(bakes.size(), 1, "%s: one LightmapGI" % room.room_id)
		if bakes.is_empty():
			continue
		var data: LightmapGIData = (bakes[0] as LightmapGI).light_data
		assert_not_null(data, "%s: baked" % room.room_id)
		if data == null:
			continue
		var textures: Array[TextureLayered] = data.get_lightmap_textures()
		assert_gt(textures.size(), 0, "%s: the bake has its lightmap" % room.room_id)
		var files: Array[String] = [data.resource_path]
		for texture: TextureLayered in textures:
			files.append(texture.resource_path)
			var import := ConfigFile.new()
			assert_eq(import.load(texture.resource_path + ".import"), OK, texture.resource_path)
			assert_eq(import.get_value("params", "compress/mode", -1), LOSSLESS,
					"%s is stored lossless" % texture.resource_path)
		for file: String in files:
			assert_true(file.begins_with("res://") and FileAccess.file_exists(file), "%s is a file" % file)
			for pattern: String in excluded:
				assert_false(file.trim_prefix("res://").match(pattern.strip_edges()),
						"%s is not left out of the export by %s" % [file, pattern])
