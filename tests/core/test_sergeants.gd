# tests/core/test_sergeants.gd
extends GutTest

const MAIN := preload("res://scenes/main.tscn")

func test_the_room_has_four_crusaders_and_a_sergeant_in_each_group() -> void:
	var main: Main = add_child_autofree(MAIN.instantiate())
	await wait_physics_frames(3)
	assert_eq(main.enemies.size(), 6)
	var crusaders: int = 0
	var sergeants: Array[Unit] = []
	for enemy: Unit in main.enemies:
		if enemy.display_name == "Sergeant":
			sergeants.append(enemy)
		elif enemy.display_name == "Crusader":
			crusaders += 1
	assert_eq(crusaders, 4)
	assert_eq(sergeants.size(), 2)
	var xs: Array = sergeants.map(func(s: Unit) -> float: return s.global_position.x)
	assert_eq(xs.filter(func(x: float) -> bool: return x < 5.0).size(), 1, "one in the near group")
	assert_eq(xs.filter(func(x: float) -> bool: return x > 5.0).size(), 1, "one in the far group")

## The vault's numbers as tuned so that the fight needs the Blood (see `test_fight_balance.gd`).
func test_a_sergeant_has_1450_health_and_hits_for_10_every_2_seconds() -> void:
	var arena := Arena.new(self)
	var sergeant: Unit = arena.spawn(Arena.SERGEANT, Vector3.ZERO)
	var alvar: Unit = arena.spawn(Arena.ALVAR, Vector3(0, 0, 1.2))
	await wait_physics_frames(3)
	assert_eq(sergeant.stats.health, 1450)
	assert_eq(sergeant.stats.max_health, 1450)
	assert_eq(sergeant.get_node("Melee").cooldown, 2.0)
	assert_true(sergeant.get_node("Melee").try_hit(alvar))
	assert_eq(alvar.stats.health, 110)


func test_a_crusader_has_800_health_and_hits_for_3_every_2_seconds() -> void:
	var arena := Arena.new(self)
	var crusader: Unit = arena.spawn(Arena.CRUSADER, Vector3.ZERO)
	var alvar: Unit = arena.spawn(Arena.ALVAR, Vector3(0, 0, 1.2))
	await wait_physics_frames(3)
	assert_eq(crusader.stats.max_health, 800)
	assert_eq(crusader.get_node("Melee").cooldown, 2.0)
	assert_true(crusader.get_node("Melee").try_hit(alvar))
	assert_eq(alvar.stats.health, 117)
