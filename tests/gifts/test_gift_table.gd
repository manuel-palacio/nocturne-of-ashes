# tests/gifts/test_gift_table.gd
extends GutTest
## Each Gift's numbers live in its resource only: the resources hold the design table of milestone 2's
## plan, and a Gift script's own defaults are neutral, so a number left out of a resource does nothing.

const GIFTS: String = "res://resources/gifts/"
## The design table: id -> the Gift's numbers as its resource holds them.
const TABLE: Dictionary = {
	&"iron_sinew": {"display_name": "Iron Sinew", "targeting": Gift.Targeting.SELF, "cast_range": 0.0, "blood_cost": 20,
			"cooldown": 12.0, "duration": 8.0, "speed_multiplier": 1.4, "damage_dealt_multiplier": 1.5},
	&"baleful_eye": {"display_name": "Baleful Eye", "targeting": Gift.Targeting.ENEMY, "cast_range": 8.0, "blood_cost": 10,
			"cooldown": 10.0, "duration": 5.0},
	&"mend_flesh": {"display_name": "Mend Flesh", "targeting": Gift.Targeting.ALLY, "cast_range": 8.0, "blood_cost": 20,
			"cooldown": 6.0, "amount": 40},
	&"blood_lance": {"display_name": "Blood Lance", "targeting": Gift.Targeting.ENEMY, "cast_range": 10.0, "blood_cost": 15,
			"cooldown": 4.0, "damage": 30},
	&"stone_hide": {"display_name": "Stone Hide", "targeting": Gift.Targeting.SELF, "cast_range": 0.0, "blood_cost": 30,
			"cooldown": 15.0, "duration": 6.0, "damage_taken_multiplier": 0.4, "taunt_radius": 2.0},
	&"hammerfall": {"display_name": "Hammerfall", "targeting": Gift.Targeting.SELF, "cast_range": 0.0, "blood_cost": 25,
			"cooldown": 12.0, "radius": 3.5, "damage": 15, "stun_time": 2.5},
}
## What a Gift script's own number defaults to: nothing happens with it.
const NEUTRAL: Dictionary = {
	"blood_cost": 0, "cooldown": 0.0, "cast_range": 0.0, "duration": 0.0, "amount": 0, "damage": 0, "radius": 0.0,
	"stun_time": 0.0, "taunt_radius": 0.0, "speed_multiplier": 1.0, "damage_dealt_multiplier": 1.0,
	"damage_taken_multiplier": 1.0,
}


func _resources() -> Array[Gift]:
	var found: Array[Gift] = []
	for file: String in ResourceLoader.list_directory(GIFTS):
		if file.ends_with(".tres"):
			found.append(load(GIFTS + file) as Gift)
	return found


func test_every_gift_resource_holds_its_row_of_the_design_table() -> void:
	var seen: Array[StringName] = []
	for gift: Gift in _resources():
		assert_not_null(gift)
		assert_true(TABLE.has(gift.id), "%s is in the table" % gift.id)
		if not TABLE.has(gift.id):
			continue
		seen.append(gift.id)
		var row: Dictionary = TABLE[gift.id]
		for key: String in row:
			assert_eq(gift.get(key), row[key], "%s: %s" % [gift.id, key])
	seen.sort()
	var expected: Array = TABLE.keys()
	expected.sort()
	assert_eq(seen, expected, "one resource per Gift of the table")


func test_a_gift_scripts_own_numbers_are_neutral() -> void:
	for gift: Gift in _resources():
		var fresh: Gift = (gift.get_script() as GDScript).new()
		assert_eq(fresh.id, &"", "%s: the id is the resource's" % gift.id)
		for key: String in NEUTRAL:
			if key in fresh:
				assert_eq(fresh.get(key), NEUTRAL[key], "%s: %s" % [gift.id, key])
