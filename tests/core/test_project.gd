# tests/core/test_project.gd
extends GutTest

func test_project_uses_the_compatibility_renderer() -> void:
	assert_eq(ProjectSettings.get_setting("rendering/renderer/rendering_method"), "gl_compatibility")

func test_project_is_named() -> void:
	assert_eq(ProjectSettings.get_setting("application/config/name"), "Nocturne of Ashes")

func test_confirm_is_bound_to_enter_and_the_keypad_enter() -> void:
	var keys: Array[Key] = []
	for event: InputEvent in InputMap.action_get_events(&"confirm"):
		var key := event as InputEventKey
		if key != null:
			keys.append(key.physical_keycode)
	assert_true(keys.has(KEY_ENTER), "Enter confirms")
	assert_true(keys.has(KEY_KP_ENTER), "and so does the keypad's Enter")
