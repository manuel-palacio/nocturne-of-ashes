# tests/ui/test_hud.gd
extends GutTest

const HUD := preload("res://scenes/ui/hud.tscn")
const ALVAR := preload("res://scenes/units/alvar.tscn")

var hud: Hud
var unit: Unit

func before_each() -> void:
	hud = add_child_autofree(HUD.instantiate())
	unit = add_child_autofree(ALVAR.instantiate())
	hud.bind(unit)

func test_shows_the_name_and_full_health() -> void:
	assert_eq(hud.find_child("NameLabel").text, "Brother Álvar")
	var bar: ProgressBar = hud.find_child("HealthBar")
	assert_eq(bar.max_value, 120.0)
	assert_eq(bar.value, 120.0)

func test_the_bar_follows_damage() -> void:
	unit.stats.take_damage(20)
	assert_eq(hud.find_child("HealthBar").value, 100.0)

func test_the_fallen_prompt_is_hidden_until_asked() -> void:
	assert_false(hud.is_fallen_shown())
	hud.show_fallen()
	assert_true(hud.is_fallen_shown())
	assert_eq(hud.find_child("FallenLabel").text, "You have fallen — press Enter")
	hud.hide_fallen()
	assert_false(hud.is_fallen_shown())
