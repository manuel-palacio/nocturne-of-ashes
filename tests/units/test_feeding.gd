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
	foe.take_hit(39)  # 21 of 60 = 35%
	assert_true(alvar.can_feed_on(foe))

func test_mortals_do_not_feed_and_friends_are_not_food() -> void:
	alvar.take_hit(100)  # 20 of 120
	assert_false(foe.can_feed_on(alvar))
	var friend: Unit = arena.spawn(Arena.ALVAR, Vector3(2, 0, 0))
	friend.take_hit(100)
	assert_false(alvar.can_feed_on(friend))

func test_a_full_feed_kills_the_target_and_gives_blood() -> void:
	watch_signals(alvar)
	foe.take_hit(45)
	alvar.order_feed(foe)
	await wait_seconds(0.5)
	assert_true(alvar.is_feeding())
	assert_true(foe.is_stunned())
	assert_eq(alvar.current_order(), Unit.Order.FEED)
	await wait_seconds(2.0)
	assert_false(foe.is_alive())
	assert_eq(alvar.stats.blood, 100)  # 60 + 40
	assert_signal_emitted_with_parameters(alvar, "fed", [foe])
	assert_eq(alvar.current_order(), Unit.Order.NONE)

func test_blood_gained_is_capped_at_the_maximum() -> void:
	alvar.stats.gain_blood(30)  # 90
	foe.take_hit(45)
	alvar.order_feed(foe)
	await wait_seconds(2.6)
	assert_eq(alvar.stats.blood, 100)

func test_the_feeder_walks_to_a_distant_target_first() -> void:
	foe.global_position = Vector3(0, 0, 6)
	foe.take_hit(45)
	alvar.order_feed(foe)
	await wait_for_signal(alvar.fed, 8.0)
	assert_false(foe.is_alive())

func test_a_new_order_breaks_the_feed_and_frees_the_target() -> void:
	watch_signals(alvar)
	foe.take_hit(45)
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
	foe.take_hit(45)
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
	foe.take_hit(45)
	alvar.order_feed(foe)
	await wait_seconds(0.8)
	foe.take_hit(999)
	await wait_physics_frames(3)
	assert_false(alvar.is_feeding())
	assert_eq(alvar.stats.blood, 60)
	assert_eq(alvar.current_order(), Unit.Order.NONE)

func test_a_target_freed_mid_feed_causes_no_error() -> void:
	foe.take_hit(45)
	alvar.order_feed(foe)
	await wait_seconds(0.8)
	foe.free()
	await wait_physics_frames(5)
	assert_false(alvar.is_feeding())
	assert_eq(alvar.stats.blood, 60)

func test_the_feeder_dying_breaks_the_feed_once_and_revives_without_one() -> void:
	watch_signals(alvar)
	foe.take_hit(45)
	alvar.order_feed(foe)
	await wait_seconds(0.8)
	alvar.take_hit(999)
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
