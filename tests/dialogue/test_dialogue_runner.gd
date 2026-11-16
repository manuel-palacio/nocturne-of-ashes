# tests/dialogue/test_dialogue_runner.gd
extends GutTest

const TALK := preload("res://tests/fixtures/test_talk.dialogue")
const SLOW := preload("res://tests/fixtures/test_slow_talk.dialogue")

var runner: DialogueRunner
var state: GameState
var hooks: StoryHooks
var lines: Array = []

func before_each() -> void:
	lines = []
	state = GameState.new_game()
	hooks = StoryHooks.new(state, func() -> Unit: return null)
	runner = add_child_autofree(DialogueRunner.new())
	runner.line_shown.connect(func(speaker: String, text: String, choices: Array[String]) -> void:
		lines.append([speaker, text, choices]))

func _last() -> Array:
	return lines[-1]

func test_start_shows_the_first_line() -> void:
	runner.start(TALK, "start", hooks)
	await wait_physics_frames(2)
	assert_true(runner.is_running())
	assert_eq(_last(), ["Smith", "The forge is cold tonight.", []])

func test_advance_reaches_the_choices_and_hides_those_not_allowed() -> void:
	runner.start(TALK, "start", hooks)
	await wait_physics_frames(2)
	runner.advance()
	await wait_physics_frames(2)
	assert_eq(_last()[1], "What will you do with the prisoner?")
	assert_eq(_last()[2], ["Spare him", "Drain him"])

func test_a_choice_runs_its_effects_and_its_reply() -> void:
	runner.start(TALK, "start", hooks)
	await wait_physics_frames(2)
	runner.advance()
	await wait_physics_frames(2)
	runner.choose(0)
	await wait_physics_frames(2)
	assert_eq(state.conscience, 8)
	assert_true(state.has_flag(&"spared"))
	assert_eq(_last()[1], "Mercy. Rare here.")

func test_the_other_choice_has_its_own_effects() -> void:
	runner.start(TALK, "start", hooks)
	await wait_physics_frames(2)
	runner.advance()
	await wait_physics_frames(2)
	runner.choose(1)
	await wait_physics_frames(2)
	assert_eq(state.conscience, 5)
	assert_false(state.has_flag(&"spared"))

func test_a_condition_can_open_a_choice() -> void:
	state.set_flag(&"knows_word")
	runner.start(TALK, "start", hooks)
	await wait_physics_frames(2)
	runner.advance()
	await wait_physics_frames(2)
	assert_eq(_last()[2].size(), 3)

func test_it_finishes_after_the_last_line() -> void:
	watch_signals(runner)
	runner.start(TALK, "start", hooks)
	await wait_physics_frames(2)
	runner.advance()
	await wait_physics_frames(2)
	runner.choose(0)
	await wait_physics_frames(2)
	runner.advance()
	await wait_physics_frames(2)
	assert_false(runner.is_running())
	assert_signal_emit_count(runner, "finished", 1)

func test_lines_can_depend_on_conscience() -> void:
	runner.start(TALK, "again", hooks)
	await wait_physics_frames(2)
	assert_eq(_last()[1], "I have seen that look before.")
	runner.stop()
	state.change_conscience(2)
	runner.start(TALK, "again", hooks)
	await wait_physics_frames(2)
	assert_eq(_last()[1], "You walk lightly, friend.")

func test_wrong_inputs_do_nothing() -> void:
	runner.advance()
	runner.choose(0)
	runner.start(TALK, "start", hooks)
	await wait_physics_frames(2)
	runner.choose(0)   # no choices on this line
	await wait_physics_frames(2)
	assert_eq(_last()[1], "The forge is cold tonight.")
	runner.advance()
	await wait_physics_frames(2)
	runner.advance()   # choices are up
	runner.choose(7)
	await wait_physics_frames(2)
	assert_eq(_last()[1], "What will you do with the prisoner?")

func test_stop_ends_without_running_more() -> void:
	watch_signals(runner)
	runner.start(TALK, "start", hooks)
	await wait_physics_frames(2)
	runner.stop()
	assert_false(runner.is_running())
	assert_signal_emit_count(runner, "finished", 1)
	assert_eq(state.conscience, 7)

func test_revoked_hooks_change_nothing() -> void:
	hooks.revoke()
	hooks.change_conscience(-3)
	hooks.set_flag("late")
	hooks.join("zahra")
	hooks.learn("alvar", "iron_sinew")
	assert_eq(state.conscience, 7)
	assert_false(state.has_flag(&"late"))
	assert_false(state.has_joined(&"zahra"))
	assert_false(state.knows(&"alvar", &"iron_sinew"))
	assert_eq(hooks.conscience(), 0)
	assert_false(hooks.has_joined("alvar"))

func test_what_a_stopped_conversation_still_runs_changes_nothing() -> void:
	runner.start(SLOW, "start", hooks)
	await wait_physics_frames(2)
	runner.advance()   # the add-on now waits before setting a flag
	await wait_physics_frames(2)
	runner.stop()
	await wait_seconds(0.5)
	assert_false(state.has_flag(&"late"))
	assert_eq(lines.size(), 1)
