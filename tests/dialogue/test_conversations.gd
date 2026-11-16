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
	assert_signal_not_emitted(main, "checkpoint_saved")

func test_a_hook_called_with_the_wrong_arguments_ends_the_conversation_unsaved() -> void:
	watch_signals(main)
	main.talk(BROKEN, "wrong_args")
	await wait_physics_frames(2)
	await _tap(&"confirm")
	assert_engine_error("expected 1 argument(s), but called with 0")
	assert_eq(main.state.conscience, 7)
	await _assert_play_goes_on()
	assert_signal_not_emitted(main, "checkpoint_saved")

func test_a_missing_cue_ends_the_conversation_unsaved() -> void:
	watch_signals(main)
	main.talk(TALK, "no_such_cue")
	await wait_physics_frames(2)
	assert_push_error("has no cue no_such_cue")
	await _assert_play_goes_on()
	assert_signal_not_emitted(main, "checkpoint_saved")
