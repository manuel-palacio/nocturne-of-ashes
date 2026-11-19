# tests/ui/test_party_hud.gd
extends GutTest

const MAIN := preload("res://scenes/main.tscn")

var main: Main
var hud: Hud

func before_each() -> void:
	main = add_child_autoqfree(MAIN.instantiate())
	await wait_physics_frames(3)
	hud = main.hud

func _panel(index: int) -> PartyMemberPanel:
	return hud.panels()[index]

func test_one_panel_per_member_with_name_health_and_blood() -> void:
	assert_eq(hud.panels().size(), 3)
	assert_eq(_panel(1).find_child("NameLabel").text, "Zahra")
	assert_eq(_panel(1).find_child("HealthBar").max_value, 80.0)
	assert_eq(_panel(1).find_child("HealthBar").value, 80.0)
	assert_eq(_panel(1).find_child("BloodBar").value, 60.0)

func test_bars_follow_the_unit() -> void:
	main.party[2].take_hit(40)
	main.party[2].stats.spend_blood(20)
	assert_eq(_panel(2).find_child("HealthBar").value, 120.0)
	assert_eq(_panel(2).find_child("BloodBar").value, 40.0)

func test_the_selected_panel_is_marked() -> void:
	assert_true(_panel(0).is_selected())
	main.select(main.party[2])
	assert_false(_panel(0).is_selected())
	assert_true(_panel(2).is_selected())

func test_pressing_a_panel_selects_its_member() -> void:
	_panel(1).pressed.emit(main.party[1])
	assert_eq(main.selected, main.party[1])

func test_the_state_label_shows_fallen_then_fury_then_feeding() -> void:
	main.party[1].stats.spend_blood(55)
	await wait_physics_frames(2)
	assert_eq(_panel(1).find_child("StateLabel").text, "The Fury")
	main.party[1].take_hit(999)
	await wait_physics_frames(2)
	assert_eq(_panel(1).find_child("StateLabel").text, "Fallen")
	assert_eq(_panel(0).find_child("StateLabel").text, "")

func test_the_gift_bar_shows_the_selected_members_gifts() -> void:
	assert_eq(hud.gift_buttons().map(func(b: GiftButton) -> String: return b.text), ["1 Iron Sinew (20)", "2 Baleful Eye (15)"])
	main.select(main.party[2])
	assert_eq(hud.gift_buttons().map(func(b: GiftButton) -> String: return b.text), ["1 Stone Hide (20)", "2 Hammerfall (25)"])

func test_a_gift_button_uses_the_gift() -> void:
	hud.gift_buttons()[0].chosen.emit(0)
	assert_true(main.player.has_effect(&"iron_sinew"))

func test_a_gift_on_cooldown_is_disabled_and_counts_down() -> void:
	main.input.press_gift(0)
	await wait_physics_frames(3)
	var button: GiftButton = hud.gift_buttons()[0]
	assert_true(button.disabled)
	assert_eq(button.find_child("CooldownLabel").text, "12")

func test_a_gift_too_dear_is_disabled() -> void:
	main.player.stats.spend_blood(42)  # 18
	await wait_physics_frames(2)
	assert_true(hud.gift_buttons()[0].disabled)   # 20
	assert_false(hud.gift_buttons()[1].disabled)  # 15

func test_targeting_marks_its_button() -> void:
	main.input.press_gift(1)
	assert_true(hud.gift_buttons()[1].is_targeting())
	main.input.cancel_targeting()
	assert_false(hud.gift_buttons()[1].is_targeting())

func test_pause_and_cleared_labels() -> void:
	main.set_paused(true)
	assert_true(hud.find_child("PausedLabel").visible)
	assert_eq(hud.find_child("PausedLabel").text, "Paused — give your orders")
	main.set_paused(false)
	assert_false(hud.find_child("PausedLabel").visible)
	for enemy: Unit in main.enemies:
		enemy.take_hit(999)
	await wait_physics_frames(3)
	assert_true(hud.find_child("ClearedLabel").visible)
	assert_eq(hud.find_child("ClearedLabel").text, "The vault is quiet")

func test_the_fallen_prompt_shows_and_restart_clears_the_labels() -> void:
	main.player.take_hit(999)
	await wait_physics_frames(2)
	assert_true(hud.is_fallen_shown())
	assert_eq(hud.find_child("FallenLabel").text, "You have fallen — press Enter or click")
	main.start_room()
	assert_false(hud.is_fallen_shown())
	assert_false(hud.find_child("ClearedLabel").visible)
	assert_eq(hud.panels().size(), 3)

func test_a_restart_during_the_fury_rebuilds_the_hud_for_the_new_party() -> void:
	main.player.stats.spend_blood(55)
	await wait_physics_frames(2)
	assert_eq(_panel(0).find_child("StateLabel").text, "The Fury")
	var old_panels: Array[int] = []
	for panel: PartyMemberPanel in hud.panels():
		old_panels.append(panel.get_instance_id())
	main.start_room()
	await wait_physics_frames(2)
	assert_eq(hud.panels().size(), 3)
	for panel: PartyMemberPanel in hud.panels():
		assert_false(old_panels.has(panel.get_instance_id()))
	for id: int in old_panels:
		assert_false(is_instance_valid(instance_from_id(id)))
	assert_eq(_panel(0).find_child("StateLabel").text, "")
	assert_true(_panel(0).is_selected())
	assert_eq(_panel(0).find_child("BloodBar").value, 60.0)
	assert_eq(hud.gift_buttons().size(), 2)
	assert_false(hud.gift_buttons()[0].disabled)

func test_a_clicked_gift_button_takes_no_focus_so_space_still_pauses() -> void:
	var button: GiftButton = hud.gift_buttons()[0]
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.position = button.get_global_rect().get_center()
	click.global_position = click.position
	click.pressed = true
	# In the viewport's own coordinates, as the test window is stretched.
	hud.get_viewport().push_input(click, true)
	var release: InputEventMouseButton = click.duplicate()
	release.pressed = false
	hud.get_viewport().push_input(release, true)
	await wait_physics_frames(2)
	assert_true(main.player.has_effect(&"iron_sinew"), "the click reached the button")
	assert_eq(main.player.current_order(), Unit.Order.NONE, "the click gave no order in the world")
	for control: Control in hud.gift_buttons() + hud.panels():
		assert_eq(control.focus_mode, Control.FOCUS_NONE)
	assert_null(hud.get_viewport().gui_get_focus_owner())
	main.player.get_node("Gifts").reset_cooldowns()
	var blood: int = main.player.stats.blood
	var space := InputEventKey.new()
	space.keycode = KEY_SPACE
	space.physical_keycode = KEY_SPACE
	space.pressed = true
	Input.parse_input_event(space)
	await wait_physics_frames(2)
	var up: InputEventKey = space.duplicate()
	up.pressed = false
	Input.parse_input_event(up)
	await wait_physics_frames(2)
	assert_true(main.is_paused())
	assert_eq(main.player.stats.blood, blood, "Space used no Gift")

func test_an_allys_panel_takes_an_ally_gift_while_targeting() -> void:
	var zahra: Unit = main.party[1]
	var gonzalo: Unit = main.party[2]
	main.select(zahra)
	gonzalo.take_hit(100)  # 60 of 160
	main.input.press_gift(0)  # Mend Flesh
	assert_eq(main.input.targeting_gift(), 0)
	_panel(2).pressed.emit(gonzalo)
	assert_eq(gonzalo.stats.health, 100, "healed")
	assert_eq(main.selected, zahra, "still selected")
	assert_eq(main.input.targeting_gift(), -1, "targeting closed")

func test_an_allys_panel_selects_while_an_enemy_gift_is_targeting() -> void:
	main.input.press_gift(1)  # Baleful Eye
	assert_eq(main.input.targeting_gift(), 1)
	_panel(1).pressed.emit(main.party[1])
	assert_eq(main.selected, main.party[1])
	assert_eq(main.input.targeting_gift(), -1)

func test_an_empty_notice_hides_the_notice() -> void:
	var label: Label = hud.find_child("NoticeLabel")
	hud.show_notice("Not while they are upon you")
	assert_true(label.visible)
	hud.show_notice("")
	assert_false(label.visible)
	assert_eq(hud.notice(), "")
