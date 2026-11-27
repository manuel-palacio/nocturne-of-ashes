extends GutTest

var arena: Arena
var alvar: Unit
var foe: Unit

func before_each() -> void:
	arena = Arena.new(self)
	alvar = arena.spawn(Arena.ALVAR, Vector3.ZERO)
	foe = arena.spawn(Arena.CRUSADER, Vector3(0, 0, 1.2))
	await wait_physics_frames(3)

func test_only_a_weakened_enemy_can_be_fed_on() -> void:
	assert_false(alvar.can_feed_on(foe))
	# Álvar feeds at or below his `feed_threshold` of the target's maximum health, and not above it.
	Arena.weaken(foe, alvar.feed_threshold + 0.01)
	assert_false(alvar.can_feed_on(foe))
	Arena.weaken(foe, alvar.feed_threshold)
	assert_true(alvar.can_feed_on(foe))

func test_mortals_do_not_feed_and_friends_are_not_food() -> void:
	alvar.take_hit(100)  # 20 of 120
	assert_false(foe.can_feed_on(alvar))
	var friend: Unit = arena.spawn(Arena.ALVAR, Vector3(2, 0, 0))
	friend.take_hit(100)
	assert_false(alvar.can_feed_on(friend))

func test_a_full_feed_kills_the_target_and_gives_blood() -> void:
	watch_signals(alvar)
	Arena.weaken(foe, 0.15)
	alvar.order_feed(foe)
	await wait_seconds(0.5)
	assert_true(alvar.is_feeding())
	assert_true(foe.is_stunned())
	assert_eq(alvar.current_order(), Unit.Order.FEED)
	await wait_seconds(2.0)
	assert_false(foe.is_alive())
	assert_eq(alvar.stats.blood, 100)  # 60 and a feed's Blood, up to the maximum
	assert_signal_emitted_with_parameters(alvar, "fed", [foe])
	assert_eq(alvar.current_order(), Unit.Order.NONE)

func test_blood_gained_is_capped_at_the_maximum() -> void:
	alvar.stats.gain_blood(30)  # 90
	Arena.weaken(foe, 0.15)
	alvar.order_feed(foe)
	await wait_seconds(2.6)
	assert_eq(alvar.stats.blood, 100)

## The Blood is set directly, not spent: spending it under the Fury's line would start the Fury.
func _feed_with(blood: int) -> void:
	alvar.stats.blood = blood
	alvar.take_hit(80)  # 40 of 120
	Arena.weaken(foe, 0.15)
	alvar.order_feed(foe)
	await wait_for_signal(alvar.fed, 5.0)


## The heal a feed gives a drinker who had `blood` Blood: the share of `feed_heal` the Blood taken back
## makes of a whole feed's, never less than `Feeder.MIN_HEAL_SHARE`.
func _heal_at(blood: int) -> int:
	var restored: int = mini(alvar.feed_gain, alvar.stats.max_blood - blood)
	return roundi(alvar.feed_heal * maxf(float(restored) / alvar.feed_gain, Feeder.MIN_HEAL_SHARE))


func test_a_parched_drinker_is_healed_in_full() -> void:
	await _feed_with(0)
	assert_eq(alvar.stats.blood, alvar.feed_gain)
	assert_eq(alvar.stats.health, 40 + alvar.feed_heal)


func test_a_drinker_at_half_his_blood_is_healed_by_what_he_takes_back() -> void:
	await _feed_with(50)
	assert_eq(alvar.stats.blood, 100)
	assert_eq(_heal_at(50), roundi(alvar.feed_heal * 50.0 / alvar.feed_gain), "50 of 80 taken back")
	assert_eq(alvar.stats.health, 40 + _heal_at(50))


## Nearly full or full, the heal does not fall off a cliff: it is never less than half a feed's.
func test_a_drinker_nearly_full_of_blood_is_still_healed_half() -> void:
	await _feed_with(90)
	assert_eq(alvar.stats.health, 40 + roundi(alvar.feed_heal * Feeder.MIN_HEAL_SHARE))


func test_a_drinker_one_short_of_full_is_healed_half() -> void:
	await _feed_with(99)
	assert_eq(alvar.stats.health, 40 + roundi(alvar.feed_heal * Feeder.MIN_HEAL_SHARE))


func test_a_drinker_full_of_blood_is_healed_half() -> void:
	await _feed_with(100)
	assert_eq(alvar.stats.blood, 100)
	assert_eq(alvar.stats.health, 40 + roundi(alvar.feed_heal * Feeder.MIN_HEAL_SHARE))


func test_the_feeder_walks_to_a_distant_target_first() -> void:
	foe.global_position = Vector3(0, 0, 6)
	Arena.weaken(foe, 0.15)
	alvar.order_feed(foe)
	await wait_for_signal(alvar.fed, 8.0)
	assert_false(foe.is_alive())

func test_a_new_order_breaks_the_feed_and_frees_the_target() -> void:
	watch_signals(alvar)
	Arena.weaken(foe, 0.15)
	alvar.order_feed(foe)
	await wait_seconds(0.8)
	alvar.order_move(Vector3(4, 0, 0))
	await wait_physics_frames(3)
	assert_false(alvar.is_feeding())
	assert_false(foe.is_stunned())
	assert_true(foe.is_alive())
	assert_eq(alvar.stats.blood, 60)
	assert_signal_emitted(alvar, "feed_broken")

func test_a_stun_breaks_the_feed() -> void:
	Arena.weaken(foe, 0.15)
	alvar.order_feed(foe)
	await wait_seconds(0.8)
	var stun := StatusEffect.new()
	stun.id = &"stun"
	stun.duration = 1.0
	stun.stuns = true
	alvar.add_effect(stun)
	await wait_physics_frames(3)
	assert_false(alvar.is_feeding())
	assert_false(foe.has_effect(&"fed_on"))

func test_a_target_killed_by_another_ends_the_feed_without_blood() -> void:
	Arena.weaken(foe, 0.15)
	alvar.order_feed(foe)
	await wait_seconds(0.8)
	foe.take_hit(Arena.LETHAL)
	await wait_physics_frames(3)
	assert_false(alvar.is_feeding())
	assert_eq(alvar.stats.blood, 60)
	assert_eq(alvar.current_order(), Unit.Order.NONE)

func test_a_target_freed_mid_feed_causes_no_error() -> void:
	Arena.weaken(foe, 0.15)
	alvar.order_feed(foe)
	await wait_seconds(0.8)
	foe.free()
	await wait_physics_frames(5)
	assert_false(alvar.is_feeding())
	assert_eq(alvar.stats.blood, 60)

func test_the_feeder_dying_breaks_the_feed_once_and_revives_without_one() -> void:
	watch_signals(alvar)
	Arena.weaken(foe, 0.15)
	alvar.order_feed(foe)
	await wait_seconds(0.8)
	alvar.take_hit(Arena.LETHAL)
	await wait_physics_frames(3)
	assert_false(alvar.is_feeding())
	assert_false(foe.has_effect(&"fed_on"))
	assert_signal_emit_count(alvar, "feed_broken", 1)
	alvar.revive()
	await wait_seconds(2.0)
	assert_false(alvar.is_feeding())
	assert_eq(alvar.current_order(), Unit.Order.NONE)
	assert_true(foe.is_alive())
	assert_eq(alvar.stats.blood, 60)
	assert_signal_emit_count(alvar, "feed_broken", 1)
	assert_signal_not_emitted(alvar, "fed")

func test_a_target_already_held_by_a_feed_cannot_be_fed_on_by_another() -> void:
	Arena.weaken(foe, 0.15)
	alvar.order_feed(foe)
	await wait_seconds(0.5)
	var zahra: Unit = arena.spawn(Arena.ZAHRA, Vector3(0, 0, 2.4))
	await wait_physics_frames(3)
	assert_false(zahra.can_feed_on(foe))
	zahra.order_feed(foe)
	assert_eq(zahra.current_order(), Unit.Order.NONE)
	assert_true(alvar.is_feeding())

## Two feeders reaching the same target at once: exactly one drinks, the other's feed is broken.
func _two_feeders_on_one_target() -> Array[Unit]:
	var zahra: Unit = arena.spawn(Arena.ZAHRA, Vector3(0, 0, 2.4))
	await wait_physics_frames(3)
	Arena.weaken(foe, 0.15)
	watch_signals(alvar)
	watch_signals(zahra)
	alvar.order_feed(foe)
	zahra.order_feed(foe)
	await wait_seconds(0.5)
	var feeding: Array[Unit] = []
	var other: Array[Unit] = []
	for unit: Unit in [alvar, zahra]:
		if unit.is_feeding():
			feeding.append(unit)
		else:
			other.append(unit)
	assert_eq(feeding.size(), 1)
	if feeding.size() != 1:
		return []
	assert_signal_emitted(other[0], "feed_broken")
	assert_eq(other[0].current_order(), Unit.Order.NONE)
	return [feeding[0], other[0]]

func test_two_feeders_at_once_leave_one_feeding_and_a_break_frees_the_target() -> void:
	var pair: Array[Unit] = await _two_feeders_on_one_target()
	if pair.is_empty():
		return
	pair[0].order_move(Vector3(-3, 0, 0))
	await wait_physics_frames(3)
	assert_false(pair[0].is_feeding())
	assert_false(pair[1].is_feeding())
	assert_false(foe.is_stunned())
	await wait_seconds(2.0)
	assert_true(foe.is_alive())

func test_two_feeders_at_once_leave_one_feeding_until_it_completes() -> void:
	var pair: Array[Unit] = await _two_feeders_on_one_target()
	if pair.is_empty():
		return
	await wait_seconds(2.0)
	assert_false(foe.is_alive())
	assert_false(pair[1].is_feeding())
	assert_signal_emitted(pair[0], "fed")
	assert_signal_not_emitted(pair[1], "fed")
	assert_eq(pair[1].stats.blood, 60)

func test_can_act_only_when_alive_unstunned_not_feeding_and_not_in_the_fury() -> void:
	assert_true(alvar.can_act())
	var stun := StatusEffect.new()
	stun.id = &"stun"
	stun.duration = 1.0
	stun.stuns = true
	alvar.add_effect(stun)
	assert_false(alvar.can_act())
	alvar.remove_effect(&"stun")
	assert_true(alvar.can_act())
	Arena.weaken(foe, 0.15)
	alvar.order_feed(foe)
	await wait_seconds(0.5)
	assert_true(alvar.is_feeding())
	assert_false(alvar.can_act())
	alvar.stats.spend_blood(55)
	assert_true(alvar.is_in_fury())
	assert_false(alvar.can_act())
	alvar.take_hit(Arena.LETHAL)
	assert_false(alvar.is_in_fury())
	assert_false(alvar.can_act())
