# tests/units/test_combat_brain.gd
extends GutTest

var arena: Arena
var alvar: Unit
var foe: Unit

func before_each() -> void:
	arena = Arena.new(self)
	alvar = arena.spawn(Arena.ALVAR, Vector3(-8, 0, -8))
	foe = arena.spawn(Arena.CRUSADER, Vector3(8, 0, 8), true)
	await wait_physics_frames(3)

func test_ignores_a_player_beyond_the_aggro_radius() -> void:
	await wait_seconds(0.6)
	assert_null(foe.attack_target())

func test_attacks_a_player_who_comes_within_the_radius() -> void:
	alvar.global_position = Vector3(3, 0, 8)
	await wait_seconds(0.6)
	assert_eq(foe.attack_target(), alvar)

func test_wounds_a_player_who_stands_still() -> void:
	alvar.global_position = Vector3(5, 0, 8)
	await wait_seconds(4.0)
	assert_lt(alvar.stats.health, 120)

func test_a_dead_enemy_does_nothing() -> void:
	foe.stats.take_damage(999)
	alvar.global_position = Vector3(6, 0, 8)
	await wait_seconds(0.6)
	assert_null(foe.attack_target())

func test_switches_to_a_much_nearer_hostile() -> void:
	# foe has engaged alvar on its own; a second player unit appears right beside it
	alvar.global_position = Vector3(3, 0, 8)
	await wait_seconds(0.6)
	assert_eq(foe.attack_target(), alvar)
	var second: Unit = arena.spawn(Arena.ALVAR, foe.global_position + Vector3(0.8, 0, 0))
	alvar.global_position = Vector3(1, 0, 8)
	await wait_seconds(0.6)
	assert_eq(foe.attack_target(), second)

func test_keeps_its_target_when_the_other_is_only_slightly_nearer() -> void:
	alvar.global_position = Vector3(4, 0, 8)
	await wait_seconds(0.6)
	var second: Unit = arena.spawn(Arena.ALVAR, Vector3(4.5, 0, 8))
	await wait_seconds(0.6)
	assert_eq(foe.attack_target(), alvar)

func test_a_taunt_overrides_everything() -> void:
	alvar.global_position = Vector3(6, 0, 8)
	await wait_seconds(0.6)
	var tank: Unit = arena.spawn(Arena.ALVAR, Vector3(1, 0, 8))
	var taunt := StatusEffect.new()
	taunt.id = &"taunt"
	taunt.duration = 5.0
	taunt.taunt_radius = 8.0
	tank.add_effect(taunt)
	await wait_seconds(0.6)
	assert_eq(foe.attack_target(), tank)

func test_a_disabled_brain_does_nothing() -> void:
	(foe.get_node("Brain") as CombatBrain).enabled = false
	alvar.global_position = Vector3(5, 0, 8)
	await wait_seconds(0.6)
	assert_null(foe.attack_target())

func test_disabling_stops_a_follow_walk_but_not_a_fight() -> void:
	var friend: Unit = arena.spawn(Arena.CRUSADER, Vector3(-8, 0, 8), true)
	var brain := friend.get_node("Brain") as CombatBrain
	brain.leader = foe
	await wait_seconds(0.8)
	assert_true(friend.is_moving())
	brain.enabled = false
	assert_false(friend.is_moving())
	brain.enabled = true
	alvar.global_position = friend.global_position + Vector3(2, 0, 0)
	await wait_seconds(0.6)
	brain.enabled = false
	assert_eq(friend.attack_target(), alvar)

func test_leaves_an_order_it_did_not_give() -> void:
	alvar.global_position = Vector3(5, 0, 8)
	foe.order_move(Vector3(8, 0, -8))
	await wait_seconds(0.6)
	assert_eq(foe.current_order(), Unit.Order.MOVE)
	assert_null(foe.attack_target())

func test_follows_its_leader_when_idle() -> void:
	var friend: Unit = arena.spawn(Arena.CRUSADER, Vector3(-8, 0, 8), true)
	(friend.get_node("Brain") as CombatBrain).leader = foe
	await wait_seconds(5.0)
	assert_lt(Arena.flat(friend.global_position, foe.global_position), 4.5)
	assert_gt(Arena.flat(friend.global_position, foe.global_position), 1.5)

func test_a_follower_breaks_off_to_fight() -> void:
	var friend: Unit = arena.spawn(Arena.CRUSADER, Vector3(-8, 0, 8), true)
	(friend.get_node("Brain") as CombatBrain).leader = foe
	alvar.global_position = Vector3(-6, 0, 6)
	await wait_seconds(0.8)
	assert_eq(friend.attack_target(), alvar)

func test_an_attack_running_when_re_enabled_is_left_alone() -> void:
	var brain := foe.get_node("Brain") as CombatBrain
	alvar.global_position = Vector3(3, 0, 8)
	await wait_seconds(0.6)
	assert_eq(foe.attack_target(), alvar)
	brain.enabled = false
	foe.order_attack(alvar)
	brain.enabled = true
	arena.spawn(Arena.ALVAR, foe.global_position + Vector3(0.8, 0, 0))
	alvar.global_position = Vector3(1, 0, 8)
	await wait_seconds(0.6)
	assert_eq(foe.attack_target(), alvar)

func test_a_follow_walk_reaims_when_the_leader_moves() -> void:
	var leader: Unit = arena.spawn(Arena.CRUSADER, Vector3(8, 0, 8))
	var friend: Unit = arena.spawn(Arena.CRUSADER, Vector3(-8, 0, 8), true)
	(friend.get_node("Brain") as CombatBrain).leader = leader
	await wait_seconds(1.0)
	assert_true(friend.is_moving())
	leader.global_position = Vector3(8, 0, -6)
	await wait_seconds(7.0)
	assert_lt(Arena.flat(friend.global_position, leader.global_position), 4.5)
	assert_gt(Arena.flat(friend.global_position, Vector3(8, 0, 8)), 6.0)

func test_a_follower_of_a_dead_leader_does_not_walk() -> void:
	var leader: Unit = arena.spawn(Arena.CRUSADER, Vector3(8, 0, 8))
	var friend: Unit = arena.spawn(Arena.CRUSADER, Vector3(-8, 0, 8), true)
	(friend.get_node("Brain") as CombatBrain).leader = leader
	leader.stats.take_damage(999)
	await wait_seconds(0.8)
	assert_false(friend.is_moving())
	assert_eq(friend.current_order(), Unit.Order.NONE)

func test_an_idle_enemy_turns_on_a_distant_hostile_that_hits_it() -> void:
	alvar.global_position = foe.global_position + Vector3(-12, 0, 0)
	await wait_physics_frames(2)
	foe.take_hit(5, alvar)
	assert_eq(foe.attack_target(), alvar)

func test_a_hit_from_a_third_unit_does_not_change_a_target() -> void:
	alvar.global_position = Vector3(5, 0, 8)
	await wait_seconds(0.6)
	assert_eq(foe.attack_target(), alvar)
	var sniper: Unit = arena.spawn(Arena.ALVAR, Vector3(-8, 0, 8))
	foe.take_hit(5, sniper)
	assert_eq(foe.attack_target(), alvar)

func test_a_hit_from_a_friend_does_not_turn_an_idle_enemy_on_it() -> void:
	var friend: Unit = arena.spawn(Arena.CRUSADER, Vector3(8, 0, 4))
	await wait_physics_frames(2)
	foe.take_hit(5, friend)
	await wait_seconds(0.6)
	assert_null(foe.attack_target())

func test_a_brain_leaves_a_target_once_it_is_held_by_a_feed() -> void:
	alvar.global_position = Vector3(5, 0, 8)
	await wait_seconds(0.6)
	assert_eq(foe.attack_target(), alvar)
	var hold := StatusEffect.new()
	hold.id = Feeder.FED_ON
	hold.duration = 5.0
	hold.stuns = true
	alvar.add_effect(hold)
	await wait_seconds(0.6)
	assert_null(foe.attack_target())

func test_a_hit_taken_while_paused_is_answered_on_unpause() -> void:
	arena.room.process_mode = Node.PROCESS_MODE_DISABLED  # as Main.set_paused(true) does to its units
	foe.take_hit(5, alvar)
	await wait_physics_frames(3)
	assert_null(foe.attack_target())
	arena.room.process_mode = Node.PROCESS_MODE_INHERIT
	await wait_physics_frames(3)
	assert_eq(foe.attack_target(), alvar)
