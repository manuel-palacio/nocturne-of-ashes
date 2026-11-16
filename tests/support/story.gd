class_name Story
extends RefCounted
## Test helper: boots the story game with a throwaway save file.

const GAME: PackedScene = preload("res://scenes/game.tscn")


## Adds the story game to `test`, starting from `state` (a new game when null), with no title screen.
## The opening conversation of a new game plays only when `opening` is true.
static func boot(test: GutTest, state: GameState = null, opening: bool = false) -> Main:
	var main: Main = GAME.instantiate()
	main.store = SaveStore.new()
	main.store.path = "user://test_story_%d.json" % randi()
	main.store.clear()
	main.state = state if state != null else GameState.new_game()
	main.show_title = false
	main.opening_enabled = opening
	test.add_child_autofree(main)
	return main


static func finish(main: Main) -> void:
	if is_instance_valid(main) and main.store != null:
		main.store.clear()
