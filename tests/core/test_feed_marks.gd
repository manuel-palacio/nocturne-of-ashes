# tests/core/test_feed_marks.gd
extends GutTest

const MAIN := preload("res://scenes/main.tscn")

var main: Main

func before_each() -> void:
	main = add_child_autoqfree(MAIN.instantiate())
	await wait_physics_frames(3)

## A crusader of the room (60 health); the first enemy spawned.
func _crusader() -> Unit:
	for enemy: Unit in main.enemies:
		if enemy.display_name == "Crusader":
			return enemy
	return null

func _hold(unit: Unit) -> void:
	var hold := StatusEffect.new()
	hold.id = Feeder.FED_ON
	hold.stuns = true
	hold.duration = 10.0
	unit.add_effect(hold)

func _assert_marks_follow(member: Unit) -> void:
	for enemy: Unit in main.enemies:
		assert_eq(enemy.has_feed_mark(), member.can_feed_on(enemy), "%s for %s" % [enemy.name, member.display_name])

func test_a_healthy_enemy_has_no_mark() -> void:
	for enemy: Unit in main.enemies:
		assert_false(enemy.has_feed_mark())

func test_a_weakened_enemy_shows_a_mark_within_two_frames() -> void:
	var foe: Unit = _crusader()
	Arena.weaken(foe, main.player.feed_threshold)
	await wait_physics_frames(2)
	assert_true(foe.has_feed_mark())

func test_healing_it_above_the_threshold_removes_the_mark() -> void:
	var foe: Unit = _crusader()
	Arena.weaken(foe, 0.15)
	await wait_physics_frames(2)
	foe.stats.heal(foe.stats.max_health)
	await wait_physics_frames(2)
	assert_false(foe.has_feed_mark())

func test_another_feeders_held_meal_shows_no_mark() -> void:
	var foe: Unit = _crusader()
	Arena.weaken(foe, 0.15)
	_hold(foe)
	await wait_physics_frames(2)
	assert_false(main.player.can_feed_on(foe))
	assert_false(foe.has_feed_mark())

func test_a_fallen_enemy_shows_no_mark() -> void:
	var foe: Unit = _crusader()
	Arena.weaken(foe, 0.15)
	await wait_physics_frames(2)
	foe.take_hit(Arena.LETHAL)
	await wait_physics_frames(2)
	assert_false(foe.has_feed_mark())

func test_marks_follow_the_selected_member() -> void:
	Arena.weaken(_crusader(), 0.15)
	var zahra: Unit = main.party[1]
	main.select(zahra)
	assert_true(_crusader().has_feed_mark(), "updated on selection")
	_assert_marks_follow(zahra)
	zahra.stats.spend_blood(55)  # the Fury: she can feed on no one
	await wait_physics_frames(2)
	assert_false(zahra.can_feed_on(_crusader()))
	_assert_marks_follow(zahra)
	main.select(main.party[2])
	_assert_marks_follow(main.party[2])
	assert_true(_crusader().has_feed_mark())

func test_marks_update_while_paused() -> void:
	main.set_paused(true)
	var foe: Unit = _crusader()
	Arena.weaken(foe, 0.15)
	await wait_physics_frames(2)
	assert_true(foe.has_feed_mark())

func test_marks_hide_while_alvar_is_down_and_at_room_start() -> void:
	Arena.weaken(_crusader(), 0.15)
	await wait_physics_frames(2)
	main.player.take_hit(Arena.LETHAL)
	await wait_physics_frames(2)
	for enemy: Unit in main.enemies:
		assert_false(enemy.has_feed_mark())
	main.start_room()
	for enemy: Unit in main.enemies:
		assert_false(enemy.has_feed_mark())
