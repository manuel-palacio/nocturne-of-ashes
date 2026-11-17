# tests/core/test_loose_ends.gd
extends GutTest
## Small fixes carried from earlier milestones, one or two tests each.

const MAIN := preload("res://scenes/main.tscn")

var main: Main

func after_each() -> void:
	Story.finish(main)

func _skirmish() -> void:
	main = add_child_autoqfree(MAIN.instantiate())
	await wait_physics_frames(3)

## Presses and releases mouse `button` over the middle of `control`.
func _click(control: Control, button: MouseButton = MOUSE_BUTTON_LEFT) -> void:
	var click := InputEventMouseButton.new()
	click.button_index = button
	click.position = control.get_global_rect().get_center()
	click.global_position = click.position
	click.pressed = true
	# In the viewport's own coordinates, as the test window is stretched.
	control.get_viewport().push_input(click, true)
	var release: InputEventMouseButton = click.duplicate()
	release.pressed = false
	control.get_viewport().push_input(release, true)
	await wait_physics_frames(2)

# 1. A fallen companion never stays selected.

func test_a_fallen_companion_hands_selection_to_the_next_living_member_while_alvar_is_down() -> void:
	await _skirmish()
	main.select(main.party[1])
	main.player.take_hit(999)
	main.party[1].take_hit(999)
	assert_eq(main.selected, main.party[2])
	assert_eq(main.rig.target, main.party[2])

func test_selection_stays_on_alvar_when_nobody_lives() -> void:
	await _skirmish()
	main.select(main.party[1])
	main.player.take_hit(999)
	main.party[2].take_hit(999)
	main.party[1].take_hit(999)
	assert_eq(main.selected, main.player)
