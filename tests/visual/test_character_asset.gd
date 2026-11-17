# tests/visual/test_character_asset.gd
extends GutTest

const HUMAN := preload("res://assets/characters/human/human.glb")
const CLIPS: Array[StringName] = [&"idle", &"walk", &"run", &"attack", &"hit", &"death", &"cast", &"interact", &"stagger", &"talk", &"sit"]
const PALETTES: Array[String] = ["alvar", "zahra", "gonzalo", "crusader", "sergeant", "malakor", "smith", "captive"]

var human: Node3D

func before_each() -> void:
	human = add_child_autofree(HUMAN.instantiate())

func _player() -> AnimationPlayer:
	return human.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer

func _mesh() -> MeshInstance3D:
	return human.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D

func test_it_has_exactly_the_clips_we_use() -> void:
	var names: Array = Array(_player().get_animation_list()).filter(func(n: String) -> bool: return n != "RESET")
	names.sort()
	var expected: Array = CLIPS.map(func(n: StringName) -> String: return String(n))
	expected.sort()
	assert_eq(names, expected)

func test_looping_clips_loop_and_the_others_do_not() -> void:
	for clip: StringName in CLIPS:
		var loops: bool = _player().get_animation(clip).loop_mode != Animation.LOOP_NONE
		assert_eq(loops, clip in [&"idle", &"walk", &"run", &"stagger", &"talk", &"sit"], clip)

func test_it_is_one_mesh_with_one_surface_under_the_triangle_budget() -> void:
	assert_eq(human.find_children("*", "MeshInstance3D", true, false).size(), 1)
	var mesh: Mesh = _mesh().mesh
	assert_eq(mesh.get_surface_count(), 1)
	assert_lt(mesh.get_faces().size() / 3, 15000)

func test_it_stands_on_its_origin_at_human_height() -> void:
	var box: AABB = _mesh().global_transform * _mesh().get_aabb()
	assert_almost_eq(box.position.y, 0.0, 0.05)
	assert_almost_eq(box.size.y, 1.8, 0.1)

func test_every_palette_is_eight_by_one() -> void:
	for palette: String in PALETTES:
		var image: Image = (load("res://assets/characters/human/palette-%s.png" % palette) as Texture2D).get_image()
		assert_eq(image.get_size(), Vector2i(8, 1), palette)

func test_no_two_palettes_are_the_same() -> void:
	var seen: Dictionary = {}
	for palette: String in PALETTES:
		var image: Image = (load("res://assets/characters/human/palette-%s.png" % palette) as Texture2D).get_image()
		var key: String = image.get_data().hex_encode()
		assert_false(seen.has(key), palette)
		seen[key] = true
