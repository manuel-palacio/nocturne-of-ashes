extends GutTest

var arena: Arena
var alvar: Unit
var foe: Unit
var gifts: GiftUser

func before_each() -> void:
	arena = Arena.new(self)
	alvar = arena.spawn(Arena.ALVAR, Vector3.ZERO)
	foe = arena.spawn(Arena.CRUSADER, Vector3(0, 0, 5))
	gifts = alvar.get_node("Gifts")
	await wait_physics_frames(3)

func test_alvar_carries_iron_sinew_and_baleful_eye() -> void:
	assert_eq(gifts.count(), 2)
	assert_eq([gifts.gift(0).display_name, gifts.gift(1).display_name], ["Iron Sinew", "Baleful Eye"])
	assert_eq([gifts.gift(0).blood_cost, gifts.gift(1).blood_cost], [20, 10])
	assert_eq([gifts.gift(0).cooldown, gifts.gift(1).cooldown], [12.0, 10.0])

func test_iron_sinew_makes_him_faster_and_stronger() -> void:
	assert_true(gifts.use(0))
	assert_true(alvar.has_effect(&"iron_sinew"))
	assert_almost_eq(alvar.speed_multiplier(), 1.4, 0.001)
	assert_almost_eq(alvar.damage_dealt_multiplier(), 1.5, 0.001)
	assert_eq(alvar.stats.blood, 40)

func test_baleful_eye_stuns_an_enemy_in_range() -> void:
	assert_true(gifts.use(1, foe))
	assert_true(foe.is_stunned())
	assert_eq(alvar.stats.blood, 50)

func test_baleful_eye_does_not_reach_past_eight_metres() -> void:
	foe.global_position = Vector3(0, 0, 8.5)
	assert_false(gifts.use(1, foe))
	assert_eq(alvar.stats.blood, 60)
