# tests/units/test_hits_and_revival.gd
extends GutTest

var arena: Arena
var alvar: Unit
var foe: Unit

func before_each() -> void:
	arena = Arena.new(self)
	alvar = arena.spawn(Arena.ALVAR, Vector3.ZERO)
	foe = arena.spawn(Arena.CRUSADER, Vector3(0, 0, 1.2))
	await wait_physics_frames(3)

func test_a_hit_reports_its_amount_and_source() -> void:
	watch_signals(foe)
	assert_eq(foe.take_hit(10, alvar), 10)
	assert_signal_emitted_with_parameters(foe, "was_hit", [10, alvar])

func test_zero_negative_and_posthumous_hits_do_nothing() -> void:
	assert_eq(foe.take_hit(0), 0)
	assert_eq(foe.take_hit(-5), 0)
	foe.take_hit(Arena.LETHAL)
	assert_eq(foe.take_hit(10), 0)

func test_melee_goes_through_take_hit() -> void:
	watch_signals(foe)
	alvar.get_node("Melee").try_hit(foe)
	assert_signal_emitted_with_parameters(foe, "was_hit", [15, alvar])

func test_a_dead_unit_cannot_strike() -> void:
	alvar.take_hit(Arena.LETHAL)
	assert_false(alvar.get_node("Melee").try_hit(foe))

func test_revival_restores_a_working_unit() -> void:
	watch_signals(alvar)
	alvar.take_hit(Arena.LETHAL)
	await wait_physics_frames(3)
	alvar.revive()
	await wait_physics_frames(3)
	assert_true(alvar.is_alive())
	assert_eq(alvar.stats.health, 36)  # 30% of 120
	assert_eq(alvar.collision_layer, 2)
	assert_signal_emitted(alvar, "revived")
	alvar.order_move(Vector3(3, 0, 0))
	await wait_for_signal(alvar.arrived, 4.0)
	assert_lt(Arena.flat(alvar.global_position, Vector3(3, 0, 0)), 0.5)

func test_a_revived_unit_can_die_again() -> void:
	watch_signals(alvar)
	alvar.take_hit(Arena.LETHAL)
	alvar.revive()
	alvar.take_hit(Arena.LETHAL)
	assert_signal_emit_count(alvar, "died", 2)

func test_reviving_the_living_does_nothing() -> void:
	alvar.take_hit(20)
	alvar.revive()
	assert_eq(alvar.stats.health, 100)
