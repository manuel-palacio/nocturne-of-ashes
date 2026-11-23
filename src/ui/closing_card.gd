class_name ClosingCard
extends Control
## A card over the whole screen saying the story rests here for now: a title, what has been reached
## and kept (the Alma carried, given to `open()`), and how to go on. Closed by `confirm` (Enter), by
## `pause` (Space), by `cancel` (Escape), by a left click anywhere, or by `close()`. While open it takes every mouse button
## and the wheel, so nothing reaches the world or the controls behind it. It takes no keyboard focus.
## Whoever shows it holds the world while it is open, through `toggled`, as for the `ControlsCard`.
## For `ANSWER_DELAY` seconds after it opens no key or click closes it (they are still taken), so a key
## mashed in the fight's last moment or clicks still meant for the last enemy cannot close it unread; its
## hint, saying how to close it, shows only once it answers (made see-through, so the card keeps its size).
##
## Texts: its labels have automatic translation off in the scene and get their text from `tr()` in
## code, set again when the language changes.

## The card opened (`open` true) or closed.
signal toggled(open: bool)

const HEADING: String = "Here the descent rests"
## Formatted with the Alma carried.
const BODY: String = "The last lock of Toledo's vaults is still shut, and what waits behind it is not yet written. Your game is saved: when the story goes on, it goes on from here, with the Alma you carry (%d of 10)."
## In place of `BODY` when the game is not saved (the browser keeps no saves, or the write failed).
## Formatted with the Alma carried.
const BODY_UNSAVED: String = "The last lock of Toledo's vaults is still shut, and what waits behind it is not yet written. This browser is not keeping saves: your progress, and the Alma you carry (%d of 10), last until the page is closed."
const HINT: String = "Enter or click to stay in the vault"
## Seconds after it opens before a key or a click closes it.
const ANSWER_DELAY: float = 2.5

## The Alma shown in the body.
var _alma: int = 0
## Whether the body says the game is saved.
var _saved: bool = true
## Seconds until a key or a click closes it.
var _answer_wait: float = 0.0

@onready var _heading: Label = %Heading
@onready var _body: Label = %Body
@onready var _hint: Label = %Hint


func _ready() -> void:
	visible = false
	focus_mode = Control.FOCUS_NONE
	_show_texts()


func _process(delta: float) -> void:
	if not visible:
		return
	if _answer_wait > 0.0:
		_answer_wait -= delta
		if _answer_wait <= 0.0:
			_show_hint(true)
		return
	# Polled rather than read from events, so presses made with Input.action_press count too.
	if (Input.is_action_just_pressed(&"confirm") or Input.is_action_just_pressed(&"pause")
			or Input.is_action_just_pressed(&"cancel")):
		close()


## Shows the card with `alma`, the Alma carried, in its body, which says the game is saved when `saved`
## is true and, when false, that this browser is not keeping saves.
func open(alma: int, saved: bool = true) -> void:
	_alma = alma
	_saved = saved
	_show_texts()
	if visible:
		return
	_answer_wait = ANSWER_DELAY
	_show_hint(false)
	visible = true
	toggled.emit(true)


func close() -> void:
	if not visible:
		return
	visible = false
	toggled.emit(false)


func is_open() -> bool:
	return visible


## Whether it is open and a key or a click would now close it.
func accepts_answer() -> bool:
	return visible and _answer_wait <= 0.0


## Whether the hint saying how to close it shows: only once it answers.
func is_hint_shown() -> bool:
	return _hint.modulate.a > 0.0


## Everything it shows, one text per line, as shown; the hint even while it is see-through.
func text() -> String:
	return "\n".join([_heading.text, _body.text, _hint.text])


func _notification(what: int) -> void:
	# Also sent on entering the tree, before the nodes are ready.
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_show_texts()


## Any left press closes it once `ANSWER_DELAY` is over; it stops every mouse button itself.
func _gui_input(event: InputEvent) -> void:
	var button := event as InputEventMouseButton
	if button == null:
		return
	accept_event()
	if button.pressed and button.button_index == MOUSE_BUTTON_LEFT and _answer_wait <= 0.0:
		close()


func _show_hint(shown: bool) -> void:
	_hint.modulate.a = 1.0 if shown else 0.0


func _show_texts() -> void:
	_heading.text = tr(HEADING)
	_body.text = tr(BODY if _saved else BODY_UNSAVED) % _alma
	_hint.text = tr(HINT)
