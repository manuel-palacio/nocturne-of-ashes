# tests/units/test_stats.gd
extends GutTest

var stats: Stats

func before_each() -> void:
	stats = Stats.new()

func test_starts_full() -> void:
	assert_eq(stats.health, 100)
	assert_eq(stats.blood, 100)

func test_damage_lowers_health_and_signals() -> void:
	watch_signals(stats)
	stats.take_damage(30)
	assert_eq(stats.health, 70)
	assert_signal_emitted_with_parameters(stats, "health_changed", [70, 100])

func test_overkill_clamps_and_dies_once() -> void:
	watch_signals(stats)
	stats.take_damage(250)
	stats.take_damage(10)
	assert_eq(stats.health, 0)
	assert_true(stats.is_dead())
	assert_signal_emit_count(stats, "died", 1)

func test_zero_and_negative_damage_are_ignored() -> void:
	watch_signals(stats)
	stats.take_damage(0)
	stats.take_damage(-20)
	assert_eq(stats.health, 100)
	assert_signal_not_emitted(stats, "health_changed")

func test_heal_clamps_to_max_and_does_not_raise_the_dead() -> void:
	stats.take_damage(40)
	stats.heal(100)
	assert_eq(stats.health, 100)
	stats.take_damage(100)
	stats.heal(50)
	assert_eq(stats.health, 0)

func test_spend_blood_refuses_what_it_cannot_pay() -> void:
	assert_true(stats.spend_blood(60))
	assert_eq(stats.blood, 40)
	assert_false(stats.spend_blood(41))
	assert_eq(stats.blood, 40)

func test_gain_blood_clamps_to_max() -> void:
	stats.spend_blood(10)
	stats.gain_blood(500)
	assert_eq(stats.blood, 100)

func test_two_stats_do_not_share_numbers() -> void:
	var other := Stats.new()
	stats.take_damage(10)
	assert_eq(other.health, 100)

func test_starting_blood_is_used_when_set() -> void:
	stats.starting_blood = 60
	stats.reset()
	assert_eq(stats.blood, 60)

func test_revive_only_raises_the_dead() -> void:
	stats.revive(50)
	assert_eq(stats.health, 100)
	stats.take_damage(999)
	stats.revive(50)
	assert_eq(stats.health, 50)

func test_a_maximum_of_zero_is_treated_as_one() -> void:
	stats.max_health = 0
	stats.reset()
	assert_eq(stats.health, 1)
	assert_false(stats.is_dead())
