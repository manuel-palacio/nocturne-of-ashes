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

# 2. Effects are not added to the fallen.

func test_effects_are_not_added_to_the_fallen() -> void:
	await _skirmish()
	var zahra: Unit = main.party[1]
	zahra.take_hit(999)
	var stun := StatusEffect.new()
	stun.id = &"stun"
	stun.duration = 1.0
	stun.stuns = true
	zahra.add_effect(stun)
	assert_false(zahra.has_effect(&"stun"))
	assert_eq(zahra.effect_ids(), [] as Array[StringName])

# 3. `was_hit` before `died` on a killing blow.

func test_a_killing_blow_is_heard_as_a_hit_before_the_death() -> void:
	var arena := Arena.new(self)
	var foe: Unit = arena.spawn(Arena.CRUSADER, Vector3.ZERO)
	await wait_physics_frames(2)
	var heard: Array[String] = []
	foe.was_hit.connect(func(_amount: int, _source: Unit) -> void: heard.append("was_hit"))
	foe.died.connect(func(_unit: Unit) -> void: heard.append("died"))
	foe.take_hit(999)
	assert_eq(heard, ["was_hit", "died"] as Array[String])
