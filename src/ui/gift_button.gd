class_name GiftButton
extends Button
## One Gift of the selected member: key, name and Blood cost, the cooldown left, and a mark while the
## Gift waits for a target. Disabled whenever the Gift is not ready apart from its target. The left
## button is consumed, enabled or not; the right button and the wheel pass through to the world.

## The button was pressed.
signal chosen(index: int)

## The look while its Gift waits for a target.
@export var targeting_style: StyleBox

var _user: GiftUser
var _unit: Unit
var _index: int = -1
var _targeting: bool = false

@onready var _cooldown_label: Label = %CooldownLabel


func _ready() -> void:
	pressed.connect(func() -> void: chosen.emit(_index))
	# The button lets mouse events through; it takes the left button once it has handled it. Taken
	# here, before the button sees it, the press would never reach it.
	button_down.connect(accept_event)
	button_up.connect(accept_event)


func _gui_input(event: InputEvent) -> void:
	# A disabled button does not handle the left button, so it is taken here.
	var button := event as InputEventMouseButton
	if disabled and button != null and button.button_index == MOUSE_BUTTON_LEFT:
		accept_event()


func _process(_delta: float) -> void:
	# The countdown has no signal per second, and a feed's drinking starts with none either.
	_refresh()


## Shows the Gift at `index` of `user`. A button is bound once; the HUD makes new buttons for a new selection.
func bind(user: GiftUser, index: int) -> void:
	_user = user
	_unit = user.get_parent() as Unit
	_index = index
	var gift: Gift = user.gift(index)
	text = "%d %s (%d)" % [index + 1, tr(gift.display_name), gift.blood_cost]
	user.cooldowns_changed.connect(_refresh)
	_unit.stats.blood_changed.connect(_refresh.unbind(2))
	for changed: Signal in [_unit.effects_changed, _unit.fury_started, _unit.fury_ended, _unit.feed_broken]:
		changed.connect(_refresh)
	for changed: Signal in [_unit.fed, _unit.died, _unit.revived]:
		changed.connect(_refresh.unbind(1))
	_refresh()


func set_targeting(on: bool) -> void:
	_targeting = on
	if on:
		add_theme_stylebox_override(&"normal", targeting_style)
		add_theme_stylebox_override(&"hover", targeting_style)
	else:
		remove_theme_stylebox_override(&"normal")
		remove_theme_stylebox_override(&"hover")


func is_targeting() -> bool:
	return _targeting


func _refresh() -> void:
	if not is_instance_valid(_user):
		disabled = true
		_cooldown_label.text = ""
		return
	disabled = not _user.is_ready(_index)
	var left: float = _user.cooldown_left(_index)
	_cooldown_label.text = str(ceili(left)) if left > 0.0 else ""
