class_name PartyMemberPanel
extends PanelContainer
## One party member in the HUD: a swatch in the colour of the member's tunic, the name, health and
## Blood bars, and whether the member is fallen, in the Fury or feeding. A left click asks to select
## the member. The left button is consumed; the right button and the wheel pass through to the world.

## The panel was clicked; the click is consumed, so it gives no order in the world.
signal pressed(unit: Unit)

## The look while not selected, and while selected.
@export var normal_style: StyleBox
@export var selected_style: StyleBox

var _unit: Unit
var _selected: bool = false

@onready var _swatch: ColorRect = %Swatch
@onready var _name_label: Label = %NameLabel
@onready var _health_bar: ProgressBar = %HealthBar
@onready var _blood_bar: ProgressBar = %BloodBar
@onready var _state_label: Label = %StateLabel


func _ready() -> void:
	set_selected(false)


func _process(_delta: float) -> void:
	# Polled as well, since a feed's drinking starts with no signal.
	_show_state()


func _gui_input(event: InputEvent) -> void:
	var button := event as InputEventMouseButton
	if button == null or button.button_index != MOUSE_BUTTON_LEFT:
		return
	accept_event()
	if button.pressed and is_instance_valid(_unit):
		pressed.emit(_unit)


## Follows `unit` from now on. A panel is bound once; the HUD makes new panels for a new party.
func bind(unit: Unit) -> void:
	_unit = unit
	_name_label.text = tr(unit.display_name)
	_swatch.color = _tunic_colour(unit)
	unit.stats.health_changed.connect(_on_health_changed)
	unit.stats.blood_changed.connect(_on_blood_changed)
	for changed: Signal in [unit.died, unit.revived]:
		changed.connect(_show_state.unbind(1))
	for changed: Signal in [unit.fury_started, unit.fury_ended, unit.feed_broken]:
		changed.connect(_show_state)
	unit.fed.connect(_show_state.unbind(1))
	_on_health_changed(unit.stats.health, unit.stats.max_health)
	_on_blood_changed(unit.stats.blood, unit.stats.max_blood)
	_show_state()


func unit() -> Unit:
	return _unit


func set_selected(on: bool) -> void:
	_selected = on
	add_theme_stylebox_override(&"panel", selected_style if on else normal_style)


func is_selected() -> bool:
	return _selected


## Fallen, then The Fury, then Feeding, else empty.
func _show_state() -> void:
	var state: String = ""
	if not is_instance_valid(_unit):
		pass
	elif not _unit.is_alive():
		state = tr("Fallen")
	elif _unit.is_in_fury():
		state = tr("The Fury")
	elif _unit.is_feeding():
		state = tr("Feeding")
	_state_label.text = state


func _on_health_changed(current: int, maximum: int) -> void:
	_health_bar.max_value = maximum
	_health_bar.value = current


func _on_blood_changed(current: int, maximum: int) -> void:
	_blood_bar.max_value = maximum
	_blood_bar.value = current


func _tunic_colour(unit: Unit) -> Color:
	var visual := unit.get_node_or_null(^"Visual") as UnitVisual
	if visual == null or visual.dress == null:
		return Color.GRAY
	return visual.dress.colour(Dress.Region.TUNIC)
