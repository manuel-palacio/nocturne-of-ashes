extends GutTest

## A Gift that records what it was applied to.
class Marker extends Gift:
	var applied: Array = []
	func apply(caster: Unit, target: Unit) -> void:
		applied.append([caster, target])

var arena: Arena
var alvar: Unit
var foe: Unit
var gifts: GiftUser
var marker: Marker

func before_each() -> void:
	arena = Arena.new(self)
	alvar = arena.spawn(Arena.ALVAR, Vector3.ZERO)
	foe = arena.spawn(Arena.CRUSADER, Vector3(0, 0, 5))
	gifts = alvar.get_node("Gifts")
	marker = Marker.new()
	marker.id = &"marker"
	marker.blood_cost = 20
	marker.cooldown = 0.5
	marker.targeting = Gift.Targeting.ENEMY
	marker.cast_range = 8.0
	gifts.gifts = [marker]
	await wait_physics_frames(3)

func test_using_a_gift_spends_blood_applies_it_and_starts_the_cooldown() -> void:
	watch_signals(gifts)
	assert_true(gifts.use(0, foe))
	assert_eq(alvar.stats.blood, 40)
	assert_eq(marker.applied, [[alvar, foe]])
	assert_gt(gifts.cooldown_left(0), 0.0)
	assert_signal_emitted_with_parameters(gifts, "gift_used", [0, foe])

func test_no_use_during_the_cooldown_and_again_after_it() -> void:
	gifts.use(0, foe)
	assert_false(gifts.use(0, foe))
	assert_eq(alvar.stats.blood, 40)
	await wait_seconds(0.7)
	assert_true(gifts.use(0, foe))

func test_too_little_blood_refuses_and_costs_nothing() -> void:
	alvar.stats.spend_blood(45)  # 15
	assert_false(gifts.can_use(0, foe))
	assert_false(gifts.use(0, foe))
	assert_eq(alvar.stats.blood, 15)
	assert_eq(marker.applied.size(), 0)

func test_a_gift_may_take_blood_into_the_fury() -> void:
	alvar.stats.spend_blood(35)  # 25
	assert_true(gifts.use(0, foe))  # 5
	assert_eq(marker.applied.size(), 1)
	assert_true(alvar.is_in_fury())
	assert_false(gifts.can_use(0, foe))

func test_enemy_gifts_need_a_living_hostile_in_range() -> void:
	assert_false(gifts.can_use(0, null))
	assert_false(gifts.can_use(0, alvar))
	foe.global_position = Vector3(0, 0, 9)
	assert_false(gifts.can_use(0, foe))
	foe.global_position = Vector3(0, 0, 5)
	foe.take_hit(999)
	assert_false(gifts.can_use(0, foe))

func test_ally_gifts_accept_the_caster_and_friends_only() -> void:
	marker.targeting = Gift.Targeting.ALLY
	var friend: Unit = arena.spawn(Arena.ALVAR, Vector3(3, 0, 0))
	assert_true(gifts.can_use(0, alvar))
	assert_true(gifts.can_use(0, friend))
	assert_false(gifts.can_use(0, foe))

func test_self_gifts_need_no_target() -> void:
	marker.targeting = Gift.Targeting.SELF
	assert_true(gifts.use(0))
	assert_eq(marker.applied, [[alvar, null]])

func test_a_stunned_or_dead_caster_cannot_use_gifts() -> void:
	var stun := StatusEffect.new()
	stun.id = &"stun"
	stun.duration = 5.0
	stun.stuns = true
	alvar.add_effect(stun)
	assert_false(gifts.can_use(0, foe))
	alvar.clear_effects()
	alvar.take_hit(999)
	assert_false(gifts.can_use(0, foe))

func test_an_index_out_of_range_is_refused() -> void:
	assert_null(gifts.gift(3))
	assert_false(gifts.use(3, foe))
	assert_false(gifts.use(-1, foe))

func test_cooldowns_changed_fires_when_a_cooldown_starts_and_ends_only() -> void:
	watch_signals(gifts)
	gifts.use(0, foe)
	assert_signal_emit_count(gifts, "cooldowns_changed", 1)
	await wait_seconds(0.3)
	assert_signal_emit_count(gifts, "cooldowns_changed", 1)
	await wait_seconds(0.4)
	assert_eq(gifts.cooldown_left(0), 0.0)
	assert_signal_emit_count(gifts, "cooldowns_changed", 2)

func test_reset_cooldowns_makes_a_gift_usable_again_at_once() -> void:
	watch_signals(gifts)
	gifts.reset_cooldowns()
	assert_signal_emit_count(gifts, "cooldowns_changed", 0)
	gifts.use(0, foe)
	assert_false(gifts.can_use(0, foe))
	gifts.reset_cooldowns()
	assert_signal_emit_count(gifts, "cooldowns_changed", 2)
	assert_eq(gifts.cooldown_left(0), 0.0)
	assert_true(gifts.use(0, foe))

func test_a_caster_in_the_fury_cannot_use_gifts() -> void:
	alvar.stats.spend_blood(55)  # 5
	assert_true(alvar.is_in_fury())
	alvar.stats.gain_blood(40)  # 45
	assert_false(gifts.can_use(0, foe))
	assert_false(gifts.use(0, foe))
	assert_eq(alvar.stats.blood, 45)
	alvar.remove_effect(&"fury")
	assert_true(gifts.can_use(0, foe))

func test_replacing_the_gifts_keeps_the_cooldowns_of_gifts_kept_by_id() -> void:
	var other := Marker.new()
	other.id = &"other"
	other.cooldown = 4.0
	gifts.use(0, foe)
	var left: float = gifts.cooldown_left(0)
	gifts.replace_gifts([other, marker])
	assert_eq(gifts.count(), 2)
	assert_eq(gifts.cooldown_left(0), 0.0)
	assert_eq(gifts.cooldown_left(1), left)
	assert_false(gifts.can_use(1, foe))
