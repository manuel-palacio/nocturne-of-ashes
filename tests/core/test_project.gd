# tests/core/test_project.gd
extends GutTest

func test_project_uses_the_compatibility_renderer() -> void:
	assert_eq(ProjectSettings.get_setting("rendering/renderer/rendering_method"), "gl_compatibility")

func test_project_is_named() -> void:
	assert_eq(ProjectSettings.get_setting("application/config/name"), "Nocturne of Ashes")
