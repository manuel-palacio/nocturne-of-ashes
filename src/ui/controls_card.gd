class_name ControlsCard
extends Control
## A card over the whole screen listing the game's controls, a key and what it does on each row.
## Closed by `cancel` (Escape), by a click anywhere off the card, or by `close()`; a click on the card
## does nothing. While open it takes every mouse button and the wheel, so nothing reaches the world or
## the controls behind it. It takes no keyboard focus. Whoever shows it holds the world while it is
## open, through `toggled`.
##
## Texts: its labels have automatic translation off in the scene and get their text from `tr()` in
## code, set again when the language changes.

## The card opened (`open` true) or closed.
signal toggled(open: bool)

## Each row: the keys or clicks, and what they do. English source texts.
const ROWS: Array[Array] = [
	["Left click", "Move; on an enemy, attack it"],
	["Left click a weakened enemy", "Feed on them, when short of Blood"],
	["Tab, or click a companion or a panel", "Select a party member"],
	["1, 2, or click a Gift", "Use a Gift, then click its target if it needs one; Escape or a right click cancels"],
	["Space", "Pause and resume; orders given while paused begin on resume"],
	["Q and E, mouse wheel", "Turn the camera, zoom"],
	["Left click someone", "Walk up and talk; Enter or a click goes on, 1–4 choose"],
	["Left click a door", "Take the party through it"],
	["Enter or click, after a fall", "Begin again from the last checkpoint"],
]
const HEADING: String = "Controls"
const HINT: String = "Escape or click outside to close"

@onready var _heading: Label = %Heading
@onready var _grid: GridContainer = %Grid
@onready var _hint: Label = %Hint


func _ready() -> void:
	visible = false
	for row: Array in ROWS:
		var keys := Label.new()
		keys.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		keys.theme_type_variation = &"KeyLabel"
		keys.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var action := Label.new()
		action.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		action.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		action.custom_minimum_size.x = 400.0
		action.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		action.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_grid.add_child(keys)
		_grid.add_child(action)
	_show_texts()


func _process(_delta: float) -> void:
	# Polled rather than read from events, so presses made with Input.action_press count too.
	if visible and Input.is_action_just_pressed(&"cancel"):
		close()


func open() -> void:
	if visible:
		return
	visible = true
	toggled.emit(true)


func close() -> void:
	if not visible:
		return
	visible = false
	toggled.emit(false)


func toggle() -> void:
	if visible:
		close()
	else:
		open()


func is_open() -> bool:
	return visible


## How many rows of controls it lists.
func rows() -> int:
	return ROWS.size()


## Everything it shows, one text per line, as shown.
func text() -> String:
	var lines: PackedStringArray = [_heading.text]
	for label: Node in _grid.get_children():
		lines.append((label as Label).text)
	lines.append(_hint.text)
	return "\n".join(lines)


func _notification(what: int) -> void:
	# Also sent on entering the tree, before the nodes are ready.
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_show_texts()


## A left press off the card closes it; the card itself stops its own clicks.
func _gui_input(event: InputEvent) -> void:
	var button := event as InputEventMouseButton
	if button == null:
		return
	accept_event()
	if button.pressed and button.button_index == MOUSE_BUTTON_LEFT:
		close()


func _show_texts() -> void:
	_heading.text = tr(HEADING)
	_hint.text = tr(HINT)
	var labels: Array[Node] = _grid.get_children()
	for index: int in ROWS.size():
		(labels[index * 2] as Label).text = tr(ROWS[index][0])
		(labels[index * 2 + 1] as Label).text = tr(ROWS[index][1])
