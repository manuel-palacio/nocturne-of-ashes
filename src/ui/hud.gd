class_name Hud
extends CanvasLayer
## Shows a panel per party member, the selected member's Gifts, the conversation on show (in its
## `DialogueBox`), and the prompts for a pause, a cleared room and Álvar's fall. Clicks on panels and
## Gift buttons go out through its signals.
##
## Texts: every control whose text is set here or in a panel or button has automatic translation off
## in its scene and gets its text from `tr()` in code, so reading `text` gives what is shown. When the
## language changes the HUD sets its prompts again and rebuilds its panels and Gift buttons. The
## dialogue box shows conversations as written; it has no texts of its own.

## A member's panel was clicked.
signal member_pressed(unit: Unit)
## A Gift button was pressed.
signal gift_chosen(index: int)

const PANEL: PackedScene = preload("res://scenes/ui/party_member_panel.tscn")
const GIFT_BUTTON: PackedScene = preload("res://scenes/ui/gift_button.tscn")

var _panels: Array[PartyMemberPanel] = []
var _gift_buttons: Array[GiftButton] = []
## What the panels and Gift buttons show, kept to rebuild them in another language.
var _party: Array[Unit] = []
var _selected: Unit
var _targeting_index: int = -1

@onready var _party_column: VBoxContainer = %PartyColumn
@onready var _gift_bar: HBoxContainer = %GiftBar
@onready var _fallen_label: Label = %FallenLabel
@onready var _paused_label: Label = %PausedLabel
@onready var _cleared_label: Label = %ClearedLabel
@onready var _dialogue_box: DialogueBox = %DialogueBox


func _ready() -> void:
	_show_texts()
	hide_fallen()
	hide_cleared()
	set_paused(false)


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


func _notification(what: int) -> void:
	# Also sent on entering the tree, before the nodes are ready.
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_show_texts()
		_rebuild()


func _show_texts() -> void:
	_fallen_label.text = tr("You have fallen — press Enter")
	_paused_label.text = tr("Paused — give your orders")
	_cleared_label.text = tr("The vault is quiet")


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
