# tests/dialogue/test_conversations.gd
extends GutTest

const TALK := preload("res://tests/fixtures/test_talk.dialogue")
const NPC := preload("res://scenes/rooms/npc.tscn")

var main: Main
var smith: Npc

func after_each() -> void:
	Story.finish(main)

func before_each() -> void:
	main = Story.boot(self)
	await wait_physics_frames(3)
	smith = NPC.instantiate()
	smith.dialogue = TALK
	smith.label = "Smith"
	main.room.add_child(smith)
	smith.global_position = main.player.global_position + Vector3(3, 0, 0)
	smith.talk_requested.connect(func(npc: Npc, _by: Unit) -> void: main.talk(npc.dialogue, npc.title))
	await wait_physics_frames(2)

func _box() -> DialogueBox:
	return main.find_child("DialogueBox") as DialogueBox

func _tap(action: StringName) -> void:
	Input.action_press(action)
	await wait_physics_frames(2)
	Input.action_release(action)
	await wait_physics_frames(2)

func test_walking_up_to_someone_opens_the_conversation() -> void:
	main.player.order_interact(smith)
	await wait_for_signal(main.dialogue.line_shown, 5.0)
	assert_true(main.is_talking())
	assert_true(_box().visible)
	assert_eq(_box().find_child("SpeakerLabel").text, "Smith")
	assert_string_contains(_box().find_child("TextLabel").text, "The forge is cold tonight.")

func test_the_world_is_held_and_input_is_off_while_talking() -> void:
	main.talk(TALK, "start")
	await wait_physics_frames(2)
	assert_false(main.input.enabled)
	var from: Vector3 = main.player.global_position
	main.player.order_move(from + Vector3(-3, 0, 0))
	await wait_seconds(0.5)
	assert_lt(Arena.flat(main.player.global_position, from), 0.05)
	await _tap(&"pause")
	assert_false(main.is_paused())

func test_confirm_advances_and_number_keys_choose() -> void:
	main.talk(TALK, "start")
	await wait_physics_frames(2)
	await _tap(&"confirm")
	var buttons: Array[Node] = _box().find_child("Choices").get_children()
	assert_eq(buttons.map(func(b: Node) -> String: return (b as Button).text), ["1. Spare him", "2. Drain him"])
	await _tap(&"choice_2")
	assert_eq(main.state.conscience, 5)
	assert_string_contains(_box().find_child("TextLabel").text, "So be it.")

func test_confirm_does_not_skip_a_choice() -> void:
	main.talk(TALK, "start")
	await wait_physics_frames(2)
	await _tap(&"confirm")
	await _tap(&"confirm")
	assert_string_contains(_box().find_child("TextLabel").text, "What will you do with the prisoner?")
	assert_eq(main.state.conscience, 7)

func test_gift_keys_do_nothing_while_talking() -> void:
	main.state.learn(&"alvar", &"iron_sinew")
	main.enter_room(&"haven")
	await wait_physics_frames(3)
	main.talk(TALK, "start")
	await wait_physics_frames(2)
	await _tap(&"gift_1")
	assert_false(main.player.has_effect(&"iron_sinew"))

func test_blood_given_in_a_conversation_reaches_alvar() -> void:
	main.talk(TALK, "start")
	await wait_physics_frames(2)
	await _tap(&"confirm")
	await _tap(&"choice_2")
	assert_eq(main.player.stats.blood, 100)

func test_the_end_returns_control_and_saves_once() -> void:
	watch_signals(main)
	main.talk(TALK, "start")
	await wait_physics_frames(2)
	await _tap(&"confirm")
	await _tap(&"choice_1")
	assert_signal_not_emitted(main, "checkpoint_saved")
	await _tap(&"confirm")
	assert_false(main.is_talking())
	assert_false(_box().visible)
	assert_true(main.input.enabled)
	assert_signal_emit_count(main, "checkpoint_saved", 1)
	assert_true(main.store.load_state().has_flag(&"spared"))

func test_a_reload_mid_conversation_undoes_it() -> void:
	main.talk(TALK, "start")
	await wait_physics_frames(2)
	await _tap(&"confirm")
	await _tap(&"choice_2")
	main.reload_checkpoint()
	await wait_physics_frames(3)
	assert_false(main.is_talking())
	assert_false(_box().visible)
	assert_eq(main.state.conscience, 7)
	assert_eq(main.player.stats.blood, 60)
	assert_true(main.input.enabled)
	assert_false(main.is_paused())

func test_no_talking_after_a_fall() -> void:
	main.player.take_hit(999)
	await wait_physics_frames(2)
	main.talk(TALK, "start")
	assert_false(main.is_talking())

func test_no_talking_while_a_fight_is_on() -> void:
	main.enter_room(&"vault")
	await wait_physics_frames(3)
	main.enemies[0].order_attack(main.player)
	await wait_physics_frames(2)
	main.talk(TALK, "start")
	assert_false(main.is_talking())

func test_a_second_talk_while_talking_is_refused() -> void:
	main.talk(TALK, "start")
	await wait_physics_frames(2)
	main.talk(TALK, "again")
	await wait_physics_frames(2)
	assert_string_contains(_box().find_child("TextLabel").text, "The forge is cold tonight.")

func test_someone_hidden_by_a_flag_cannot_be_clicked() -> void:
	smith.hidden_if = &"smith_gone"
	main.state.set_flag(&"smith_gone")
	await wait_physics_frames(2)
	assert_false(smith.visible)
	assert_false(smith.can_be_used_by(main.player))

const BROKEN := preload("res://tests/fixtures/test_broken_talk.dialogue")

func _assert_play_goes_on() -> void:
	assert_false(main.is_talking())
	assert_false(_box().visible)
	assert_true(main.input.enabled)
	var from: Vector3 = main.player.global_position
	main.player.order_move(from + Vector3(-3, 0, 0))
	await wait_seconds(0.5)
	assert_gt(Arena.flat(main.player.global_position, from), 0.3)

func test_a_call_the_hooks_do_not_offer_ends_the_conversation_unsaved() -> void:
	watch_signals(main)
	main.talk(BROKEN, "refused")
	await wait_physics_frames(2)
	await _tap(&"confirm")
	assert_push_error("Method \"get_tree\" not found")
	await _assert_play_goes_on()
	assert_signal_emitted(main, "room_started", "the last checkpoint is reloaded")

func test_a_hook_called_with_the_wrong_arguments_ends_the_conversation_unsaved() -> void:
	watch_signals(main)
	main.talk(BROKEN, "wrong_args")
	await wait_physics_frames(2)
	await _tap(&"confirm")
	assert_engine_error("expected 1 argument(s), but called with 0")
	assert_eq(main.state.conscience, 7)
	await _assert_play_goes_on()
	assert_signal_emitted(main, "room_started", "the last checkpoint is reloaded")

func test_a_missing_cue_ends_the_conversation_unsaved() -> void:
	watch_signals(main)
	main.talk(TALK, "no_such_cue")
	await wait_physics_frames(2)
	assert_push_error("has no cue no_such_cue")
	await _assert_play_goes_on()
	assert_signal_emitted(main, "room_started", "the last checkpoint is reloaded")

const SLOW := preload("res://tests/fixtures/test_slow_talk.dialogue")

func test_a_line_that_takes_over_two_seconds_ends_the_conversation_unsaved() -> void:
	watch_signals(main)
	main.talk(SLOW, "too_slow")
	await wait_physics_frames(2)
	await _tap(&"confirm")  # the add-on now waits 3 s for the next line
	await wait_seconds(2.5)
	assert_push_error("waited more than 2 s")
	await _assert_play_goes_on()
	assert_signal_emitted(main, "room_started", "the last checkpoint is reloaded")
	# Past the add-on's wait, so its suspended call has finished before the test ends; what it ran
	# then changed nothing.
	await wait_seconds(0.6)
	assert_false(main.state.has_flag(&"late"))
	assert_false(main.is_talking())

func test_two_people_used_at_once_give_one_conversation_and_one_use() -> void:
	var other: Npc = NPC.instantiate()
	other.dialogue = TALK
	other.title = "again"
	main.room.add_child(other)
	other.global_position = main.player.global_position + Vector3(-3, 0, 0)
	await wait_physics_frames(2)
	watch_signals(smith)
	watch_signals(other)
	assert_true(smith.use(main.player))
	assert_false(other.use(main.player))
	assert_signal_emit_count(smith, "used", 1)
	assert_signal_not_emitted(other, "used")
	assert_signal_not_emitted(other, "talk_requested")
	await wait_physics_frames(2)
	assert_string_contains(_box().find_child("TextLabel").text, "The forge is cold tonight.")

func test_a_use_refused_by_a_fall_does_not_count() -> void:
	watch_signals(smith)
	main.player.take_hit(999)
	await wait_physics_frames(2)
	assert_false(smith.use(main.player))
	assert_signal_not_emitted(smith, "used")
	assert_false(main.is_talking())

func _click(control: Control) -> void:
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.position = control.get_global_rect().get_center()
	click.global_position = click.position
	click.pressed = true
	main.hud.get_viewport().push_input(click, true)
	var release: InputEventMouseButton = click.duplicate()
	release.pressed = false
	main.hud.get_viewport().push_input(release, true)
	await wait_physics_frames(2)

func test_party_panels_and_gift_buttons_do_nothing_while_talking() -> void:
	main.state.join(&"zahra")
	main.state.learn(&"alvar", &"iron_sinew")
	main.enter_room(&"haven")
	await wait_physics_frames(3)
	main.talk(TALK, "start")
	await wait_physics_frames(2)
	await _click(main.hud.panels()[1])
	await _click(main.hud.gift_buttons()[0])
	assert_eq(main.selected, main.player)
	assert_false(main.player.has_effect(&"iron_sinew"))
	assert_true(main.is_talking())

func test_someone_hidden_by_a_flag_has_no_collider_and_is_not_picked() -> void:
	var cam: Camera3D = main.rig.camera()
	var at: Vector2 = cam.unproject_position(smith.global_position + Vector3(0, 0.9, 0))
	assert_eq(Picker.interactable_at(cam, at), smith)
	smith.hidden_if = &"smith_gone"
	main.state.set_flag(&"smith_gone")
	await wait_physics_frames(2)
	assert_true((smith.find_child("CollisionShape3D") as CollisionShape3D).disabled)
	assert_null(Picker.interactable_at(cam, at))

func _gonzalo_joins() -> Unit:
	main.state.join(&"gonzalo")
	await wait_physics_frames(3)
	return main.party.filter(func(u: Unit) -> bool: return u.member_id == &"gonzalo")[0]

func _smith_on_screen() -> Vector2:
	var cam: Camera3D = main.rig.camera()
	var at: Vector2 = cam.unproject_position(smith.global_position + Vector3(0, 0.9, 0))
	assert_null(Picker.unit_at(cam, at))
	assert_eq(Picker.interactable_at(cam, at), smith)
	return at

func test_a_click_on_someone_with_a_companion_selected_sends_alvar_to_talk() -> void:
	var gonzalo: Unit = await _gonzalo_joins()
	main.select(gonzalo)
	main.rig.snap_to_target()
	await wait_physics_frames(2)
	main.input.click_at(_smith_on_screen())
	assert_eq(main.player.current_order(), Unit.Order.INTERACT)
	assert_eq(main.selected, gonzalo)
	await wait_for_signal(main.dialogue.line_shown, 5.0)
	assert_true(main.is_talking())
	assert_string_contains(_box().find_child("TextLabel").text, "The forge is cold tonight.")

func test_a_companion_cannot_be_sent_to_talk() -> void:
	var gonzalo: Unit = await _gonzalo_joins()
	watch_signals(smith)
	assert_false(smith.can_be_used_by(gonzalo))
	gonzalo.order_interact(smith)
	assert_ne(gonzalo.current_order(), Unit.Order.INTERACT)
	await wait_seconds(1.0)
	assert_signal_not_emitted(smith, "used")
	assert_false(main.is_talking())

func test_a_click_on_someone_while_alvar_is_in_the_fury_does_nothing() -> void:
	main.player.stats.spend_blood(main.player.stats.blood - 5)
	assert_true(main.player.is_in_fury())
	watch_signals(smith)
	main.input.click_at(_smith_on_screen())
	assert_ne(main.player.current_order(), Unit.Order.INTERACT)
	await wait_seconds(1.0)
	assert_signal_not_emitted(smith, "used")
	assert_false(main.is_talking())

func test_a_conversation_that_changes_conscience_and_then_fails_leaves_no_trace() -> void:
	main.talk(BROKEN, "changed_then_refused")
	await wait_physics_frames(2)
	await _tap(&"confirm")
	assert_push_error("Method \"get_tree\" not found")
	await wait_physics_frames(2)
	assert_false(main.is_talking())
	main.checkpoint()
	assert_eq(main.state.conscience, 7)
	assert_eq(main.store.load_state().conscience, 7)

func _hint() -> String:
	return (_box().find_child("HintLabel") as Label).text

func test_the_box_says_how_to_go_on() -> void:
	main.talk(TALK, "start")
	await wait_physics_frames(2)
	assert_eq(_hint(), "Enter or click")
	await _tap(&"confirm")
	assert_eq(_hint(), "1–4 or click")
	Language.apply("es")
	await wait_physics_frames(1)
	var spanish: String = _hint()
	TranslationServer.set_locale("en")
	await wait_physics_frames(2)  # the HUD rebuilt in English frees what it built in Spanish
	assert_eq(spanish, "1–4 o clic")

func test_space_advances_a_plain_line_and_does_not_take_a_choice() -> void:
	main.talk(TALK, "start")
	await wait_physics_frames(2)
	await _tap(&"pause")
	assert_string_contains(_box().find_child("TextLabel").text, "What will you do with the prisoner?")
	await _tap(&"pause")
	assert_string_contains(_box().find_child("TextLabel").text, "What will you do with the prisoner?")
	assert_eq(main.state.conscience, 7)
	assert_true(main.is_talking())
	assert_false(main.is_paused())

## Logs an error as a companion's figure enters the tree, as a figure that went wrong might.
func _noisy_figure(node: Node) -> void:
	if node is UnitVisual and node.get_parent() is Unit and (node.get_parent() as Unit).member_id == &"gonzalo":
		push_error("A noisy visual entered the tree")

func test_a_companion_joining_with_a_noisy_visual_does_not_end_the_conversation() -> void:
	get_tree().node_added.connect(_noisy_figure)
	main.talk(TALK, "joins")
	await wait_physics_frames(2)
	await _tap(&"confirm")
	get_tree().node_added.disconnect(_noisy_figure)
	assert_push_error("A noisy visual entered the tree")
	assert_true(main.state.has_joined(&"gonzalo"))
	assert_eq(main.party.size(), 2)
	assert_true(main.is_talking())
	assert_string_contains(_box().find_child("TextLabel").text, "Look after him.")
