class_name DialogueBox
extends Control
## The conversation on show, at the bottom of the screen: who speaks, what they say, and the open
## choices numbered from 1, and at its lower right a hint saying how to go on. Visible exactly while
## its runner runs. A plain line goes on with the `confirm` or `pause` action (Enter or Space) or a
## left click on the box; a choice is taken by clicking it or pressing its number (`choice_1`…
## `choice_4`), read only while a conversation runs. No control takes keyboard focus, and the box stops
## the mouse over its whole area, so no click on it reaches the world. It grows upwards to fit its
## line and choices.
##
## Texts: the speaker, the line and the choices are shown as written (automatic translation is off in
## the scene); the hint, its only text, comes from `tr()` and follows a language change.

## The actions that take the first, second… open choice.
const CHOICE_ACTIONS: Array[StringName] = [&"choice_1", &"choice_2", &"choice_3", &"choice_4"]
## The hints on a plain line and on a line with choices.
const PLAIN_HINT: String = "Enter or click"
const CHOICE_HINT: String = "1–4 or click"

var _runner: DialogueRunner
## The process frame the conversation opened on: no key counts in it, so a press that opened a
## conversation does not also answer its first line.
var _opened_on: int = -1

@onready var _frame: Control = %Frame
@onready var _speaker: Label = %SpeakerLabel
@onready var _text: Label = %TextLabel
@onready var _choices: VBoxContainer = %Choices
@onready var _hint: Label = %HintLabel


func _ready() -> void:
	visible = false
	_frame.minimum_size_changed.connect(_fit)
	_fit()


## Shows the lines and choices `runner` gives, and closes when it finishes.
func bind(runner: DialogueRunner) -> void:
	_runner = runner
	runner.line_shown.connect(_show_line)
	runner.finished.connect(_close)


func _process(_delta: float) -> void:
	if _runner == null or not _runner.is_running() or Engine.get_process_frames() == _opened_on:
		return
	# Polled rather than read from events, so presses made with Input.action_press count too.
	# Pausing is impossible while talking, so Space goes on as Enter does.
	if Input.is_action_just_pressed(&"confirm") or Input.is_action_just_pressed(&"pause"):
		_runner.advance()
		return
	for index: int in CHOICE_ACTIONS.size():
		if Input.is_action_just_pressed(CHOICE_ACTIONS[index]):
			_runner.choose(index)
			return


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_show_hint()


func _gui_input(event: InputEvent) -> void:
	var button := event as InputEventMouseButton
	if button == null or not button.pressed or button.button_index != MOUSE_BUTTON_LEFT:
		return
	accept_event()
	if _runner != null and _choices.get_child_count() == 0:
		_runner.advance()


func _show_line(speaker: String, text: String, choices: Array[String]) -> void:
	if not visible:
		_opened_on = Engine.get_process_frames()
	visible = true
	_speaker.text = speaker
	_speaker.visible = not speaker.is_empty()
	_text.text = text
	_clear_choices()
	for index: int in choices.size():
		var choice := Button.new()
		choice.text = "%d. %s" % [index + 1, choices[index]]
		choice.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		choice.focus_mode = Control.FOCUS_NONE
		choice.alignment = HORIZONTAL_ALIGNMENT_LEFT
		choice.add_theme_font_size_override(&"font_size", 18)
		# Deferred, so the button is not taken away while it is still sending its press.
		choice.pressed.connect(_runner.choose.bind(index), CONNECT_DEFERRED)
		_choices.add_child(choice)
	_show_hint()


func _close() -> void:
	visible = false
	_clear_choices()


func _show_hint() -> void:
	_hint.text = tr(CHOICE_HINT if _choices.get_child_count() > 0 else PLAIN_HINT)


## Takes the choice buttons out of the tree at once, so none is found or drawn again, and frees them.
func _clear_choices() -> void:
	for choice: Node in _choices.get_children():
		_choices.remove_child(choice)
		choice.queue_free()


## Keeps the bottom edge where it is and makes the box as tall as its contents.
func _fit() -> void:
	offset_top = offset_bottom - _frame.get_combined_minimum_size().y
