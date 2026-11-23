extends GutTest

var arena: Arena
var alvar: Unit
var foe: Unit

func before_each() -> void:
	arena = Arena.new(self)
	alvar = arena.spawn(Arena.ALVAR, Vector3.ZERO)
	foe = arena.spawn(Arena.CRUSADER, Vector3(0, 0, 5))
	await wait_physics_frames(3)

func test_spending_below_the_threshold_starts_the_fury() -> void:
	watch_signals(alvar)
	alvar.stats.spend_blood(45)  # 15
	assert_false(alvar.is_in_fury())
	alvar.stats.spend_blood(10)  # 5
	assert_true(alvar.is_in_fury())
	assert_signal_emit_count(alvar, "fury_started", 1)
	assert_true(alvar.has_effect(&"fury"))
	assert_almost_eq(alvar.damage_dealt_multiplier(), 1.5, 0.001)

func test_mortals_have_no_fury() -> void:
	foe.stats.spend_blood(95)
	assert_false(foe.is_in_fury())

func test_the_fury_attacks_the_nearest_unit_friend_or_foe() -> void:
	var friend: Unit = arena.spawn(Arena.ALVAR, Vector3(2, 0, 0))
	await wait_physics_frames(2)
	alvar.stats.spend_blood(55)
	await wait_physics_frames(5)
	assert_eq(alvar.attack_target(), friend)

func test_orders_are_ignored_in_the_fury() -> void:
	alvar.stats.spend_blood(55)
	await wait_physics_frames(5)
	alvar.order_move(Vector3(-8, 0, -8))
	alvar.stop()
	assert_eq(alvar.current_order(), Unit.Order.ATTACK)
	assert_eq(alvar.attack_target(), foe)

func test_the_fury_ends_after_its_time_and_leaves_the_unit_idle() -> void:
	alvar.fury_time = 0.6
	watch_signals(alvar)
	alvar.stats.spend_blood(55)
	await wait_seconds(1.0)
	assert_false(alvar.is_in_fury())
	assert_signal_emitted(alvar, "fury_ended")
	assert_eq(alvar.current_order(), Unit.Order.NONE)
	alvar.order_move(Vector3(-3, 0, 0))
	assert_eq(alvar.current_order(), Unit.Order.MOVE)

func test_the_fury_moves_on_when_its_target_dies() -> void:
	var friend: Unit = arena.spawn(Arena.ALVAR, Vector3(1.2, 0, 0))
	await wait_physics_frames(2)
	alvar.stats.spend_blood(55)
	await wait_physics_frames(5)
	friend.take_hit(Arena.LETHAL)
	await wait_physics_frames(5)
	assert_eq(alvar.attack_target(), foe)

func test_falling_further_while_already_in_the_fury_does_not_restart_it() -> void:
	watch_signals(alvar)
	alvar.stats.spend_blood(52)  # 8
	alvar.stats.spend_blood(5)   # 3
	assert_signal_emit_count(alvar, "fury_started", 1)

func test_death_ends_the_fury_once_and_revival_brings_none() -> void:
	alvar.fury_time = 0.6
	watch_signals(alvar)
	alvar.stats.spend_blood(55)
	await wait_physics_frames(5)
	alvar.take_hit(Arena.LETHAL)
	assert_false(alvar.is_in_fury())
	assert_false(alvar.has_effect(&"fury"))
	assert_signal_emit_count(alvar, "fury_ended", 1)
	alvar.revive()
	await wait_seconds(1.0)
	assert_false(alvar.is_in_fury())
	assert_eq(alvar.current_order(), Unit.Order.NONE)
	assert_signal_emit_count(alvar, "fury_started", 1)
	assert_signal_emit_count(alvar, "fury_ended", 1)
	alvar.order_move(Vector3(-3, 0, 0))
	assert_eq(alvar.current_order(), Unit.Order.MOVE)

func test_removing_the_fury_effect_ends_the_fury() -> void:
	watch_signals(alvar)
	alvar.stats.spend_blood(55)
	await wait_physics_frames(5)
	alvar.remove_effect(&"fury")
	assert_false(alvar.is_in_fury())
	assert_signal_emit_count(alvar, "fury_ended", 1)
	alvar.order_move(Vector3(-3, 0, 0))
	assert_eq(alvar.current_order(), Unit.Order.MOVE)
	await wait_physics_frames(3)
	assert_signal_emit_count(alvar, "fury_ended", 1)
