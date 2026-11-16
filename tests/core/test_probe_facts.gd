# tests/core/test_probe_facts.gd
extends GutTest
## The read-only facts the browser probe reports.

const MAIN := preload("res://scenes/main.tscn")

var main: Main

func before_each() -> void:
	main = add_child_autofree(MAIN.instantiate())
	await wait_physics_frames(3)

func _effect(id: StringName) -> StatusEffect:
	var effect := StatusEffect.new()
	effect.id = id
	effect.duration = 5.0
	return effect

func test_effect_ids_lists_the_active_effects_in_order() -> void:
	assert_eq(main.player.effect_ids(), [] as Array[StringName])
	main.player.add_effect(_effect(&"first"))
	main.player.add_effect(_effect(&"second"))
	assert_eq(main.player.effect_ids(), [&"first", &"second"] as Array[StringName])
	main.player.remove_effect(&"first")
	assert_eq(main.player.effect_ids(), [&"second"] as Array[StringName])

func test_is_cleared_once_the_last_enemy_falls_until_the_next_round() -> void:
	assert_false(main.is_cleared())
	for enemy: Unit in main.enemies:
		enemy.take_hit(999)
	await wait_physics_frames(2)
	assert_true(main.is_cleared())
	main.start_room()
	assert_false(main.is_cleared())
