class_name ClosingCard
extends Control
## A card over the whole screen saying the story rests here for now: a title, what has been reached
## and kept (the Alma carried, given to `open()`), and how to go on. Closed by `confirm` (Enter), by
## `pause` (Space), by a left click anywhere, or by `close()`. While open it takes every mouse button
## and the wheel, so nothing reaches the world or the controls behind it. It takes no keyboard focus.
## Whoever shows it holds the world while it is open, through `toggled`, as for the `ControlsCard`.
##
## Texts: its labels have automatic translation off in the scene and get their text from `tr()` in
## code, set again when the language changes.

## The card opened (`open` true) or closed.
signal toggled(open: bool)

const HEADING: String = "Here the descent rests"
## Formatted with the Alma carried.
const BODY: String = "The last lock of Toledo's vaults is still shut, and what waits behind it is not yet written. Your game is saved: when the story goes on, it goes on from here, with the Alma you carry (%d of 10)."
const HINT: String = "Enter or click to stay in the vault"

## The Alma shown in the body.
var _alma: int = 0

@onready var _heading: Label = %Heading
@onready var _body: Label = %Body
@onready var _hint: Label = %Hint


func _ready() -> void:
	visible = false
	focus_mode = Control.FOCUS_NONE
	_show_texts()


func _process(_delta: float) -> void:
	# Polled rather than read from events, so presses made with Input.action_press count too.
	if visible and (Input.is_action_just_pressed(&"confirm") or Input.is_action_just_pressed(&"pause")):
		close()


## Shows the card with `alma`, the Alma carried, in its body.
func open(alma: int) -> void:
	_alma = alma
	_show_texts()
	if visible:
		return
	visible = true
	toggled.emit(true)


func close() -> void:
	if not visible:
		return
	visible = false
	toggled.emit(false)


func is_open() -> bool:
	return visible


## Everything it shows, one text per line, as shown.
func text() -> String:
	return "\n".join([_heading.text, _body.text, _hint.text])


func _notification(what: int) -> void:
	# Also sent on entering the tree, before the nodes are ready.
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_show_texts()


## Any left press closes it; it stops every mouse button itself.
func _gui_input(event: InputEvent) -> void:
	var button := event as InputEventMouseButton
	if button == null:
		return
	accept_event()
	if button.pressed and button.button_index == MOUSE_BUTTON_LEFT:
		close()


func _show_texts() -> void:
	_heading.text = tr(HEADING)
	_body.text = tr(BODY) % _alma
	_hint.text = tr(HINT)
