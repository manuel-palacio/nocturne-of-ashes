class_name Hud
extends CanvasLayer
## Shows a panel per party member, the selected member's Gifts, Conscience in a story, the conversation on show (in its
## `DialogueBox`), the prompts for a pause, a cleared room and Álvar's fall, and a passing notice.
## Clicks on panels and Gift buttons go out through its signals. Every control draws with
## `resources/ui/theme.tres`.
##
## Texts: every control whose text is set here or in a panel or button has automatic translation off
## in its scene and gets its text from `tr()` in code, so reading `text` gives what is shown. When the
## language changes the HUD sets its prompts again and rebuilds its panels and Gift buttons. The
## dialogue box shows conversations as written; its only text of its own is its hint.

## A member's panel was clicked.
signal member_pressed(unit: Unit)
## A Gift button was pressed.
signal gift_chosen(index: int)
## The fallen prompt was clicked: the player asks to rise, as with Enter.
signal fallen_pressed

const PANEL: PackedScene = preload("res://scenes/ui/party_member_panel.tscn")
const GIFT_BUTTON: PackedScene = preload("res://scenes/ui/gift_button.tscn")

## Seconds a notice stays on show, in real time: neither the pause nor a conversation holds the HUD.
@export var notice_time: float = 2.5

var _panels: Array[PartyMemberPanel] = []
var _gift_buttons: Array[GiftButton] = []
## What the panels and Gift buttons show, kept to rebuild them in another language.
var _party: Array[Unit] = []
var _selected: Unit
var _targeting_index: int = -1
## The story state whose Conscience is shown; null in a skirmish.
var _state: GameState
## The notice on show, as the untranslated source text; empty when none.
var _notice: String = ""
## Seconds until the notice goes.
var _notice_left: float = 0.0

@onready var _party_column: VBoxContainer = %PartyColumn
@onready var _gift_bar: HBoxContainer = %GiftBar
@onready var _fallen_label: Label = %FallenLabel
@onready var _paused_label: Label = %PausedLabel
@onready var _cleared_label: Label = %ClearedLabel
@onready var _conscience_label: Label = %ConscienceLabel
@onready var _notice_label: Label = %NoticeLabel
@onready var _dialogue_box: DialogueBox = %DialogueBox


func _ready() -> void:
	_fallen_label.gui_input.connect(_on_fallen_label_input)
	_show_texts()
	hide_fallen()
	hide_cleared()
	set_paused(false)
	hide_notice()


func _process(delta: float) -> void:
	if _notice.is_empty():
		return
	_notice_left -= delta
	if _notice_left <= 0.0:
		hide_notice()


## Replaces every panel with one per member of `party`, in order, and empties the Gift bar until a
## member is selected.
func bind_party(party: Array[Unit]) -> void:
	_party = party.duplicate()
	_selected = null
	_targeting_index = -1
	_clear(_panels)
	_clear(_gift_buttons)
	for member: Unit in party:
		var panel: PartyMemberPanel = PANEL.instantiate()
		_party_column.add_child(panel)
		panel.bind(member)
		panel.pressed.connect(member_pressed.emit)
		_panels.append(panel)


## Shows the Conscience of `state` and follows its changes, dropping the state shown before; hides it
## when `state` is null, as in a skirmish. Called at each room start, as `Main` may hold a new state then.
func bind_state(state: GameState) -> void:
	if _state != null and _state.conscience_changed.is_connected(_on_conscience_changed):
		_state.conscience_changed.disconnect(_on_conscience_changed)
	_state = state
	_conscience_label.visible = state != null
	if state != null:
		state.conscience_changed.connect(_on_conscience_changed)
	_show_conscience()


## Shows the conversations `runner` runs in the dialogue box.
func bind_dialogue(runner: DialogueRunner) -> void:
	_dialogue_box.bind(runner)


## Marks `unit`'s panel and fills the Gift bar with its Gifts.
func show_selected(unit: Unit) -> void:
	_selected = unit
	_targeting_index = -1
	for panel: PartyMemberPanel in _panels:
		panel.set_selected(panel.unit() == unit)
	_clear(_gift_buttons)
	var gifts := unit.get_node_or_null(^"Gifts") as GiftUser
	if gifts == null:
		return
	for index: int in gifts.count():
		var button: GiftButton = GIFT_BUTTON.instantiate()
		_gift_bar.add_child(button)
		button.bind(gifts, index)
		button.chosen.connect(gift_chosen.emit)
		_gift_buttons.append(button)


## Marks the button of the Gift at `index` as awaiting a target; −1 marks none.
func show_targeting(index: int) -> void:
	_targeting_index = index
	for i: int in _gift_buttons.size():
		_gift_buttons[i].set_targeting(i == index)


func panels() -> Array[PartyMemberPanel]:
	return _panels


func gift_buttons() -> Array[GiftButton]:
	return _gift_buttons


func show_fallen() -> void:
	_fallen_label.visible = true


func hide_fallen() -> void:
	_fallen_label.visible = false


func is_fallen_shown() -> bool:
	return _fallen_label.visible


func set_paused(on: bool) -> void:
	_paused_label.visible = on


func show_cleared() -> void:
	_cleared_label.visible = true


func hide_cleared() -> void:
	_cleared_label.visible = false


## Shows `text`, an English source text, in the middle of the screen for `notice_time` seconds, in
## place of any notice on show. An empty text hides the notice.
func show_notice(text: String) -> void:
	if text.is_empty():
		hide_notice()
		return
	_notice = text
	_notice_left = notice_time
	_notice_label.text = tr(text)
	_notice_label.visible = true


func hide_notice() -> void:
	_notice = ""
	_notice_label.visible = false


## The notice on show, as the source text it was given; empty when none.
func notice() -> String:
	return _notice


func _notification(what: int) -> void:
	# Also sent on entering the tree, before the nodes are ready.
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_show_texts()
		_rebuild()


func _show_texts() -> void:
	_fallen_label.text = tr("You have fallen — press Enter")
	_paused_label.text = tr("Paused — give your orders")
	_cleared_label.text = tr("The vault is quiet")
	# Never `tr("")`, which gives the translation's header.
	_notice_label.text = tr(_notice) if not _notice.is_empty() else ""
	_show_conscience()


func _show_conscience() -> void:
	if _state != null:
		_conscience_label.text = "%s %d/%d" % [tr("Conscience"), _state.conscience, GameState.CONSCIENCE_MAX]


## The prompt covers the screen while it shows and takes every mouse button; a left press is a click.
func _on_fallen_label_input(event: InputEvent) -> void:
	var button := event as InputEventMouseButton
	if button != null and button.pressed and button.button_index == MOUSE_BUTTON_LEFT:
		fallen_pressed.emit()


func _on_conscience_changed(_value: int) -> void:
	_show_conscience()


## Makes the panels and Gift buttons again, in the current language, in the state they were in.
func _rebuild() -> void:
	var selected: Unit = _selected
	var targeting_index: int = _targeting_index
	bind_party(_party)
	if is_instance_valid(selected):
		show_selected(selected)
		show_targeting(targeting_index)


## Takes the controls out of the tree at once, so none is found or drawn again, and frees them.
func _clear(controls: Array) -> void:
	for control: Control in controls:
		control.get_parent().remove_child(control)
		control.queue_free()
	controls.clear()
