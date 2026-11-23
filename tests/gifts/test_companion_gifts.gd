extends GutTest

var arena: Arena
var zahra: Unit
var gonzalo: Unit
var foe: Unit

func before_each() -> void:
	arena = Arena.new(self)
	zahra = arena.spawn(Arena.ZAHRA, Vector3.ZERO)
	gonzalo = arena.spawn(Arena.GONZALO, Vector3(2, 0, 0))
	foe = arena.spawn(Arena.CRUSADER, Vector3(2, 0, 2))
	await wait_physics_frames(3)

func _gifts(unit: Unit) -> GiftUser:
	return unit.get_node("Gifts")

func test_each_companion_carries_two_gifts_in_order() -> void:
	assert_eq([_gifts(zahra).gift(0).display_name, _gifts(zahra).gift(1).display_name], ["Mend Flesh", "Blood Lance"])
	assert_eq([_gifts(gonzalo).gift(0).display_name, _gifts(gonzalo).gift(1).display_name], ["Stone Hide", "Hammerfall"])

func test_mend_flesh_heals_an_ally_up_to_the_maximum() -> void:
	gonzalo.take_hit(60)  # 100 of 160
	assert_true(_gifts(zahra).use(0, gonzalo))
	assert_eq(gonzalo.stats.health, 140)
	assert_eq(zahra.stats.blood, 40)

func test_mend_flesh_cannot_raise_the_fallen_or_help_an_enemy() -> void:
	gonzalo.take_hit(Arena.LETHAL)
	assert_false(_gifts(zahra).use(0, gonzalo))
	assert_false(_gifts(zahra).use(0, foe))
	assert_eq(zahra.stats.blood, 60)

func test_blood_lance_wounds_at_range() -> void:
	foe.global_position = Vector3(0, 0, 9)
	watch_signals(foe)
	assert_true(_gifts(zahra).use(1, foe))
	assert_eq(foe.stats.health, foe.stats.max_health - 30)
	assert_signal_emitted_with_parameters(foe, "was_hit", [30, zahra])

func test_stone_hide_hardens_gonzalo() -> void:
	assert_true(_gifts(gonzalo).use(0))
	assert_eq(gonzalo.take_hit(10), 4)
	assert_eq(gonzalo.taunt_radius(), 8.0)

func test_stone_hide_draws_an_enemy_off_another_target() -> void:
	var hunter: Unit = arena.spawn(Arena.CRUSADER, Vector3(0, 0, 3), true)
	await wait_seconds(0.6)
	assert_eq(hunter.attack_target(), zahra)
	_gifts(gonzalo).use(0)
	await wait_seconds(0.6)
	assert_eq(hunter.attack_target(), gonzalo)

func test_hammerfall_hits_and_stuns_enemies_around_him_only() -> void:
	var far: Unit = arena.spawn(Arena.CRUSADER, Vector3(8, 0, 0))
	assert_true(_gifts(gonzalo).use(1))
	assert_eq(foe.stats.health, foe.stats.max_health - 15)
	assert_true(foe.is_stunned())
	assert_eq(far.stats.health, far.stats.max_health)
	assert_false(far.is_stunned())
	assert_eq(zahra.stats.health, 80)
	assert_false(zahra.is_stunned())

func test_hammerfall_with_nobody_near_still_costs_blood() -> void:
	foe.global_position = Vector3(9, 0, 9)
	assert_true(_gifts(gonzalo).use(1))
	assert_eq(gonzalo.stats.blood, 35)
