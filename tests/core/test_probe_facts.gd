# tests/core/test_probe_facts.gd
extends GutTest
## The read-only facts the browser probe reports.

const MAIN := preload("res://scenes/main.tscn")

var main: Main

func before_each() -> void:
	main = add_child_autoqfree(MAIN.instantiate())
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
		enemy.take_hit(Arena.LETHAL)
	await wait_physics_frames(2)
	assert_true(main.is_cleared())
	main.start_room()
	assert_false(main.is_cleared())

## The probe's foe details, read with the probe pointed at this game (on the web `watch()` does that).
func test_foe_details_tell_the_kinds_the_marks_the_attacks_and_the_stuns() -> void:
	var probe: Node = get_node("/root/Probe")
	probe._main = main
	var sergeant: Unit = main.enemies.filter(func(e: Unit) -> bool: return e.display_name == "Sergeant")[0]
	var crusader: Unit = main.enemies.filter(func(e: Unit) -> bool: return e.display_name == "Crusader")[0]
	Arena.weaken(crusader, 0.15)
	sergeant.order_attack(main.player)
	var stun := _effect(&"stun")
	stun.stuns = true
	crusader.add_effect(stun)
	await wait_physics_frames(2)
	var details: Array[Dictionary] = probe._foe_details(Vector2(1280, 720))
	probe._main = null
	var kinds: Array = details.map(func(d: Dictionary) -> String: return d.kind)
	assert_eq(kinds.filter(func(k: String) -> bool: return k == "sergeant").size(),
			main.enemies.filter(func(e: Unit) -> bool: return e.display_name == "Sergeant").size())
	assert_true(details.any(func(d: Dictionary) -> bool: return d.kind == "sergeant" and d.attacking))
	assert_true(details.any(func(d: Dictionary) -> bool: return d.kind == "crusader" and d.marked and d.stunned))
	assert_false(details.any(func(d: Dictionary) -> bool: return d.kind == "crusader" and d.attacking))
