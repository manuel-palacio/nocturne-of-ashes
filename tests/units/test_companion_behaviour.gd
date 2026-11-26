# tests/units/test_companion_behaviour.gd
extends GutTest

var arena: Arena
var alvar: Unit
var zahra: Unit
var gonzalo: Unit

func before_each() -> void:
	arena = Arena.new(self)
	alvar = arena.spawn(Arena.ALVAR, Vector3(-6, 0, 0))
	zahra = arena.spawn(Arena.ZAHRA, Vector3.ZERO, true)
	gonzalo = arena.spawn(Arena.GONZALO, Vector3(3, 0, 0), true)
	await wait_physics_frames(3)

func test_zahra_mends_a_badly_hurt_ally() -> void:
	alvar.global_position = Vector3(-3, 0, 0)
	alvar.take_hit(80)  # 40 of 120
	await wait_seconds(0.6)
	assert_eq(alvar.stats.health, 80)
	assert_eq(zahra.stats.blood, 40)

func test_zahra_leaves_a_lightly_hurt_ally_alone() -> void:
	alvar.global_position = Vector3(-3, 0, 0)
	alvar.take_hit(30)
	await wait_seconds(0.6)
	assert_eq(zahra.stats.blood, 60)

func test_zahra_throws_a_lance_at_her_enemy() -> void:
	var foe: Unit = arena.spawn(Arena.CRUSADER, Vector3(0, 0, 6))
	await wait_seconds(0.6)
	assert_eq(foe.stats.health, foe.stats.max_health - 30)

func test_gonzalo_hardens_when_two_enemies_close_in() -> void:
	(zahra.get_node("Brain") as CombatBrain).enabled = false
	arena.spawn(Arena.CRUSADER, Vector3(3, 0, -1.5))
	await wait_seconds(0.6)
	assert_false(gonzalo.has_effect(&"stone_hide"))
	arena.spawn(Arena.CRUSADER, Vector3(3, 0, 1.5))
	await wait_seconds(0.6)
	assert_true(gonzalo.has_effect(&"stone_hide"))

func test_a_companion_never_spends_itself_into_the_fury() -> void:
	zahra.stats.spend_blood(40)  # 20: a lance would leave 5
	var foe: Unit = arena.spawn(Arena.CRUSADER, Vector3(0, 0, 6))
	await wait_seconds(1.0)
	assert_eq(zahra.stats.blood, 20)
	assert_false(zahra.is_in_fury())

func test_a_thirsty_companion_feeds_on_a_weakened_enemy() -> void:
	(zahra.get_node("Brain") as CombatBrain).enabled = false  # or her lance would finish his meal
	gonzalo.stats.spend_blood(35)  # 25
	var foe: Unit = arena.spawn(Arena.CRUSADER, Vector3(3, 0, 1.2))
	Arena.weaken(foe, 0.15)
	await wait_for_signal(gonzalo.fed, 6.0)
	assert_eq(gonzalo.stats.blood, mini(25 + gonzalo.feed_gain, gonzalo.stats.max_blood))

func test_a_disabled_brain_spends_nothing() -> void:
	(zahra.get_node("Brain") as CombatBrain).enabled = false
	alvar.global_position = Vector3(-3, 0, 0)
	alvar.take_hit(80)
	await wait_seconds(0.6)
	assert_eq(zahra.stats.blood, 60)

func test_zahra_does_not_lance_an_enemy_beyond_her_aggro_radius() -> void:
	arena.spawn(Arena.CRUSADER, Vector3(0, 0, 9))  # in Blood Lance's 10 m, outside her 8 m
	await wait_seconds(0.6)
	assert_eq(zahra.stats.blood, 60)

func test_a_companion_does_not_lance_its_own_meal() -> void:
	zahra.stats.spend_blood(35)  # 25: a lance would leave 10
	var foe: Unit = arena.spawn(Arena.CRUSADER, Vector3(-5, 0, 0))  # a walk of several thinks
	Arena.weaken(foe, 0.15)
	await wait_for_signal(zahra.fed, 6.0)
	assert_gt(zahra.stats.blood, 25)

func test_a_companion_does_not_spoil_a_friends_meal() -> void:
	var zahra_brain := zahra.get_node("Brain") as CombatBrain
	zahra_brain.enabled = false
	gonzalo.stats.spend_blood(35)  # 25
	var foe: Unit = arena.spawn(Arena.CRUSADER, Vector3(3, 0, 1.2))
	Arena.weaken(foe, 0.15)
	while not Feeder.is_held(foe):
		await wait_physics_frames(1)
	zahra_brain.enabled = true  # her lance reaches him; his health is 15 of 60
	await wait_for_signal(gonzalo.fed, 6.0)
	assert_eq(gonzalo.stats.blood, mini(25 + gonzalo.feed_gain, gonzalo.stats.max_blood))

func test_a_taunt_comes_before_a_meal() -> void:
	(zahra.get_node("Brain") as CombatBrain).enabled = false
	gonzalo.stats.spend_blood(35)  # 25
	var meal: Unit = arena.spawn(Arena.CRUSADER, Vector3(3, 0, 1.2))
	Arena.weaken(meal, 0.15)
	var taunter: Unit = arena.spawn(Arena.CRUSADER, Vector3(3, 0, -2))
	var taunt := StatusEffect.new()
	taunt.id = &"taunt"
	taunt.duration = 5.0
	taunt.taunt_radius = 8.0
	taunter.add_effect(taunt)
	await wait_seconds(0.6)
	assert_eq(gonzalo.attack_target(), taunter)

func test_zahra_keeps_the_blood_to_mend() -> void:
	var gifts := zahra.get_node("Gifts") as GiftUser
	var foe: Unit = arena.spawn(Arena.CRUSADER, Vector3(0, 0, 6))
	for i: int in 6:
		await wait_seconds(0.3)
		foe.stats.heal(999)  # the lances never kill it
		gifts.reset_cooldowns()
	assert_eq(zahra.stats.blood, 30, "two lances, then she keeps Mend Flesh's 20 and her Fury's 10")
	alvar.take_hit(80)  # 40 of 120
	await wait_seconds(0.6)
	assert_eq(alvar.stats.health, 80)
	assert_eq(zahra.stats.blood, 10)

func test_a_meal_is_claimed_from_the_feed_order() -> void:
	# Gonzalo's brain thinks first in a shared frame, so his claim exists before Zahra's next think;
	# from then on her lance must leave his meal alone through his whole walk in.
	(gonzalo.get_node("Brain") as Node).process_physics_priority = -1
	gonzalo.stats.spend_blood(35)  # 25
	var foe: Unit = arena.spawn(Arena.CRUSADER, Vector3(3, 0, 3))  # in her lance's reach
	Arena.weaken(foe, 0.15)
	await wait_for_signal(gonzalo.fed, 6.0)
	assert_eq(gonzalo.stats.blood, mini(25 + gonzalo.feed_gain, gonzalo.stats.max_blood))
	assert_eq(zahra.stats.blood, 60, "no lance thrown at his meal")
