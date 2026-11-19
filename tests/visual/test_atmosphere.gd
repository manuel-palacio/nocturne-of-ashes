# tests/visual/test_atmosphere.gd
extends GutTest
## The rooms' light and air: each keeps within its light and particle budgets, both share one
## environment with no fog measured from the camera, the baked light they draw with is exported in a
## form every browser reads, the air (torch flicker, embers) stops with the world on a pause but
## keeps moving while people talk, and every figure carries a faint light of its own.

const MAIN: PackedScene = preload("res://scenes/main.tscn")
const ROOMS: Array[PackedScene] = [
	preload("res://scenes/rooms/vault_room.tscn"),
	preload("res://scenes/rooms/forge_haven.tscn"),
]
const ENVIRONMENT: String = "res://resources/environment/cellar.tres"
const MAX_LIGHTS: int = 6
const MAX_SHADOWED_LIGHTS: int = 2
const MAX_PARTICLES: int = 200
## Lossless, in the lightmap's `.import`: a VRAM-compressed lightmap is stored in formats some
## browsers' WebGL cannot read.
const LOSSLESS: int = 0


func _room(scene: PackedScene) -> Room:
	return add_child_autofree(scene.instantiate()) as Room


func _air_nodes(room: Room) -> Array[Node]:
	var found: Array[Node] = []
	found.append_array(room.air().find_children("*", "AnimationPlayer", true, false))
	found.append_array(room.air().find_children("*", "CPUParticles3D", true, false))
	found.append_array(room.air().find_children("*", "GPUParticles3D", true, false))
	return found


func test_lights_and_particles_keep_within_the_budget() -> void:
	for scene: PackedScene in ROOMS:
		var room: Room = _room(scene)
		var lights: Array[Node] = room.find_children("*", "Light3D", true, false)
		var shadowed: int = lights.filter(func(light: Light3D) -> bool: return light.shadow_enabled).size()
		assert_between(lights.size(), 1, MAX_LIGHTS, "%s: real-time lights" % room.room_id)
		assert_lte(shadowed, MAX_SHADOWED_LIGHTS, "%s: lights with shadows" % room.room_id)
		var particles: int = 0
		for emitter: Node in room.find_children("*", "CPUParticles3D", true, false):
			particles += (emitter as CPUParticles3D).amount
		for emitter: Node in room.find_children("*", "GPUParticles3D", true, false):
			particles += (emitter as GPUParticles3D).amount
		assert_between(particles, 1, MAX_PARTICLES, "%s: particles" % room.room_id)
		var flickers: Array[Node] = room.air().find_children("*", "AnimationPlayer", true, false)
		assert_gt(flickers.size(), 0, "%s: the torches flicker" % room.room_id)


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


func _positions(nodes: Array[Node]) -> Array[float]:
	var at: Array[float] = []
	for node: Node in nodes:
		if node is AnimationPlayer:
			at.append((node as AnimationPlayer).current_animation_position)
		else:
			at.append(-1.0)
	return at


func _check_air_moves(main: Main, moving: bool, why: String) -> void:
	var air: Array[Node] = _air_nodes(main.room)
	assert_gt(air.size(), 0, "%s: the room has air" % main.room.room_id)
	var before: Array[float] = _positions(air)
	await wait_seconds(0.3)
	var after: Array[float] = _positions(air)
	for index: int in air.size():
		var node: Node = air[index]
		assert_eq(node.can_process(), moving, "%s %s: %s" % [main.room.room_id, why, node.get_path()])
		if node is AnimationPlayer:
			assert_eq(not is_equal_approx(before[index], after[index]), moving,
					"%s %s: the flicker of %s" % [main.room.room_id, why, node.get_path()])


func test_a_pause_freezes_the_air_with_the_units_but_a_conversation_does_not() -> void:
	var skirmish: Main = add_child_autofree(MAIN.instantiate())
	var story: Main = Story.boot(self)
	await wait_physics_frames(3)
	for main: Main in [skirmish, story]:
		var hold: WorldHold = main.get_node("WorldHold")
		await _check_air_moves(main, true, "at play")
		main.set_paused(true)
		await _check_air_moves(main, false, "paused")
		main.set_paused(false)
		hold.set_held(&"talk", true)
		await _check_air_moves(main, true, "while people talk")
		hold.set_held(&"talk", false)
	Story.finish(story)


## Every party member and everyone to talk to carries a faint light of their own colours, so they stay
## distinguishable in a room's darkest corner (Step 5's rule: a lift on characters, not more room light).
func test_every_figure_carries_a_lift_of_its_own_colours() -> void:
	var state := GameState.new_game()
	state.join(&"zahra")
	state.join(&"gonzalo")
	var main: Main = Story.boot(self, state)
	await wait_physics_frames(3)
	var figures: Array[Node] = []
	figures.append_array(main.party)
	figures.append_array(main.room.npcs().filter(func(npc: Npc) -> bool: return npc.visible))
	assert_gt(figures.size(), 3, "the party and the people in the haven")
	for figure: Node in figures:
		var meshes: Array[Node] = figure.get_node("Visual").find_children("*", "MeshInstance3D", true, false)
		var lifted: int = 0
		for mesh: MeshInstance3D in meshes:
			var material := mesh.material_override as StandardMaterial3D
			if material == null or not material.emission_enabled:
				continue
			assert_eq(material.emission_texture, material.albedo_texture, "%s: its own colours" % mesh.get_path())
			assert_almost_eq(material.emission_energy_multiplier, UnitVisual.LIFT, 0.001, str(mesh.get_path()))
			lifted += 1
		assert_gt(lifted, 0, "%s is lifted" % figure.name)
	Story.finish(main)
