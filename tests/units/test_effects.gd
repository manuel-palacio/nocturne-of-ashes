# tests/units/test_effects.gd
extends GutTest

var arena: Arena
var alvar: Unit
var foe: Unit

func before_each() -> void:
	arena = Arena.new(self)
	alvar = arena.spawn(Arena.ALVAR, Vector3.ZERO)
	foe = arena.spawn(Arena.CRUSADER, Vector3(0, 0, 1.2))
	await wait_physics_frames(3)

func _effect(id: StringName, duration: float) -> StatusEffect:
	var effect := StatusEffect.new()
	effect.id = id
	effect.duration = duration
	return effect

func test_an_effect_lasts_its_duration() -> void:
	watch_signals(alvar)
	alvar.add_effect(_effect(&"test", 0.5))
	assert_true(alvar.has_effect(&"test"))
	assert_signal_emitted(alvar, "effects_changed")
	await wait_seconds(0.7)
	assert_false(alvar.has_effect(&"test"))

func test_the_same_id_replaces_and_restarts() -> void:
	alvar.add_effect(_effect(&"test", 0.5))
	await wait_seconds(0.3)
	alvar.add_effect(_effect(&"test", 0.5))
	await wait_seconds(0.3)
	assert_true(alvar.has_effect(&"test"))

func test_multipliers_combine() -> void:
	var a := _effect(&"a", 5.0)
	a.damage_dealt_multiplier = 1.5
	var b := _effect(&"b", 5.0)
	b.damage_dealt_multiplier = 2.0
	b.damage_taken_multiplier = 0.4
	alvar.add_effect(a)
	alvar.add_effect(b)
	assert_almost_eq(alvar.damage_dealt_multiplier(), 3.0, 0.001)
	assert_almost_eq(alvar.damage_taken_multiplier(), 0.4, 0.001)
	assert_almost_eq(alvar.speed_multiplier(), 1.0, 0.001)

func test_damage_taken_is_scaled_and_never_below_one() -> void:
	var hide := _effect(&"hide", 5.0)
	hide.damage_taken_multiplier = 0.4
	alvar.add_effect(hide)
	assert_eq(alvar.take_hit(10), 4)
	assert_eq(alvar.take_hit(1), 1)
	assert_eq(alvar.stats.health, 115)

func test_damage_dealt_is_scaled() -> void:
	var sinew := _effect(&"sinew", 5.0)
	sinew.damage_dealt_multiplier = 1.5
	alvar.add_effect(sinew)
	alvar.get_node("Melee").try_hit(foe)
	assert_eq(foe.stats.health, foe.stats.max_health - 23)  # round(15 * 1.5) = 23

func test_a_stunned_unit_neither_walks_nor_strikes_and_then_resumes() -> void:
	var stun := _effect(&"stun", 0.6)
	stun.stuns = true
	alvar.add_effect(stun)
	assert_true(alvar.is_stunned())
	assert_false(alvar.get_node("Melee").try_hit(foe))
	alvar.order_move(Vector3(-4, 0, 0))
	await wait_seconds(0.4)
	assert_lt(Arena.flat(alvar.global_position, Vector3.ZERO), 0.1)
	assert_eq(alvar.current_order(), Unit.Order.MOVE)
	await wait_for_signal(alvar.arrived, 4.0)
	assert_lt(Arena.flat(alvar.global_position, Vector3(-4, 0, 0)), 0.5)

func test_speed_is_scaled() -> void:
	var haste := _effect(&"haste", 5.0)
	haste.speed_multiplier = 2.0
	alvar.add_effect(haste)
	alvar.order_move(Vector3(8, 0, 0))
	await wait_seconds(1.0)
	assert_gt(alvar.global_position.x, 6.0)  # 4 m/s doubled, less a little start-up

func test_the_largest_taunt_radius_counts() -> void:
	var a := _effect(&"a", 5.0)
	a.taunt_radius = 4.0
	var b := _effect(&"b", 5.0)
	b.taunt_radius = 8.0
	alvar.add_effect(a)
	alvar.add_effect(b)
	assert_eq(alvar.taunt_radius(), 8.0)

func test_death_clears_effects() -> void:
	alvar.add_effect(_effect(&"test", 5.0))
	alvar.take_hit(Arena.LETHAL)
	assert_false(alvar.has_effect(&"test"))

func test_a_stunned_unit_resumes_its_attack_when_the_stun_ends() -> void:
	var stun := _effect(&"stun", 0.6)
	stun.stuns = true
	alvar.add_effect(stun)
	alvar.order_attack(foe)
	await wait_seconds(0.4)
	assert_eq(foe.stats.health, foe.stats.max_health, "no strike while stunned")
	assert_eq(alvar.current_order(), Unit.Order.ATTACK)
	await wait_until(func() -> bool: return foe.stats.health < foe.stats.max_health, 2.0)
	assert_lt(foe.stats.health, foe.stats.max_health, "struck once the stun ended")
