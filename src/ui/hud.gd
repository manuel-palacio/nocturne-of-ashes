class_name Hud
extends CanvasLayer
## Shows a panel per party member, the selected member's Gifts, and the prompts for a pause, a cleared
## room and Álvar's fall. Clicks on panels and Gift buttons go out through its signals.

## A member's panel was clicked.
signal member_pressed(unit: Unit)
## A Gift button was pressed.
signal gift_chosen(index: int)

const PANEL: PackedScene = preload("res://scenes/ui/party_member_panel.tscn")
const GIFT_BUTTON: PackedScene = preload("res://scenes/ui/gift_button.tscn")

var _panels: Array[PartyMemberPanel] = []
var _gift_buttons: Array[GiftButton] = []

@onready var _party_column: VBoxContainer = %PartyColumn
@onready var _gift_bar: HBoxContainer = %GiftBar
@onready var _fallen_label: Label = %FallenLabel
@onready var _paused_label: Label = %PausedLabel
@onready var _cleared_label: Label = %ClearedLabel


func _ready() -> void:
	hide_fallen()
	hide_cleared()
	set_paused(false)


## Replaces every panel with one per member of `party`, in order, and empties the Gift bar until a
## member is selected.
func bind_party(party: Array[Unit]) -> void:
	_clear(_panels)
	_clear(_gift_buttons)
	for member: Unit in party:
		var panel: PartyMemberPanel = PANEL.instantiate()
		_party_column.add_child(panel)
		panel.bind(member)
		panel.pressed.connect(member_pressed.emit)
		_panels.append(panel)


## Marks `unit`'s panel and fills the Gift bar with its Gifts.
func show_selected(unit: Unit) -> void:
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


## Takes the controls out of the tree at once, so none is found or drawn again, and frees them.
func _clear(controls: Array) -> void:
	for control: Control in controls:
		control.get_parent().remove_child(control)
		control.queue_free()
	controls.clear()
