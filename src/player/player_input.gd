class_name PlayerInput
extends Node
## Turns mouse clicks and keys into orders for the controlled unit, Gift uses, selection requests, and
## moves for the camera rig. It never calls `Main`; selection goes out through its signals.

## A click landed on a living friend of the controlled unit, or a party member was pressed.
signal select_requested(unit: Unit)
## The `select_next` action was pressed.
signal select_next_requested
## Targeting opened for the Gift at `index`, or closed when `index` is −1.
signal targeting_changed(index: int)

## The controlled unit. Changing it closes targeting.
var unit: Unit:
	set(value):
		unit = value
		cancel_targeting()
var rig: CameraRig
## When false, clicks and keys give no orders and targeting closes.
var enabled: bool = true:
	set(value):
		enabled = value
		if not enabled:
			cancel_targeting()

## The index of the Gift waiting for a click on its target, or −1.
var _targeting: int = -1


func _unhandled_input(event: InputEvent) -> void:
	var button := event as InputEventMouseButton
	if button == null or not button.pressed:
		return
	match button.button_index:
		MOUSE_BUTTON_LEFT:
			click_at(button.position)
		MOUSE_BUTTON_RIGHT:
			cancel_targeting()
		MOUSE_BUTTON_WHEEL_UP:
			rig.zoom_by(-1)
		MOUSE_BUTTON_WHEEL_DOWN:
			rig.zoom_by(1)


func _process(delta: float) -> void:
	# Polled rather than read from events, so presses made with Input.action_press count too.
	if enabled and Input.is_action_just_pressed(&"select_next"):
		select_next_requested.emit()
	if Input.is_action_just_pressed(&"gift_1"):
		press_gift(0)
	if Input.is_action_just_pressed(&"gift_2"):
		press_gift(1)
	if Input.is_action_just_pressed(&"cancel"):
		cancel_targeting()
	_close_stale_targeting()
	if rig == null:
		return
	var turn: float = Input.get_action_strength(&"camera_right") - Input.get_action_strength(&"camera_left")
	if turn != 0.0:
		rig.rotate_by(turn * rig.rotate_speed * delta)


## The index of the Gift waiting for a click on its target, or −1.
func targeting_gift() -> int:
	return _targeting


## Uses the controlled unit's SELF Gift at `index` at once; opens targeting for a targeted Gift that is
## ready apart from its target. Pressing the Gift being targeted closes targeting. A Gift that is not
## ready is ignored.
func press_gift(index: int) -> void:
	if not enabled or unit == null:
		return
	if index == _targeting:
		cancel_targeting()
		return
	var gifts: GiftUser = _gifts()
	if gifts == null or not gifts.is_ready(index):
		return
	if gifts.gift(index).targeting == Gift.Targeting.SELF:
		cancel_targeting()
		gifts.use(index)
	else:
		_set_targeting(index)


func cancel_targeting() -> void:
	_set_targeting(-1)


## While targeting, uses the Gift on a unit under the point that it can target, else does nothing;
## targeting whose Gift is no longer ready is closed first, and the click counts as a plain one.
## Otherwise asks to select a living friend under the point; feeds on a living hostile there when the
## unit can and is short of Blood, else attacks it; else walks to the ground under it. A click on the
## controlled unit itself does nothing.
func click_at(screen_position: Vector2) -> void:
	if not enabled or unit == null or not unit.is_alive():
		return
	var cam: Camera3D = rig.camera()
	var other: Unit = Picker.unit_at(cam, screen_position)
	_close_stale_targeting()
	if _targeting >= 0:
		_use_targeted_on(other)
		return
	if other == unit:
		return
	if other != null and other.is_alive():
		if unit.can_feed_on(other) and unit.stats.blood < unit.stats.max_blood:
			unit.order_feed(other)
		elif unit.is_hostile_to(other):
			unit.order_attack(other)
		else:
			select_requested.emit(other)
		return
	var on_ground: Variant = Picker.ground_at(cam, screen_position)
	if on_ground != null:
		unit.order_move(on_ground)


## A party member was pressed outside the world, as on its HUD panel: while targeting a Gift that can
## be used on `member`, uses it on them and keeps the selection; otherwise asks to select them.
func press_member(member: Unit) -> void:
	_close_stale_targeting()
	if enabled and _targeting >= 0 and _use_targeted_on(member):
		return
	select_requested.emit(member)


## Uses the Gift being targeted on `target` and closes targeting, if the Gift can be used on it.
## Returns whether it was used.
func _use_targeted_on(target: Unit) -> bool:
	var gifts: GiftUser = _gifts()
	if target != null and gifts != null and gifts.use(_targeting, target):
		cancel_targeting()
		return true
	return false


## Closes targeting once its Gift is no longer ready: the unit was stunned, fell, entered the Fury or
## lost the Blood.
func _close_stale_targeting() -> void:
	var gifts: GiftUser = _gifts()
	if _targeting >= 0 and (gifts == null or not gifts.is_ready(_targeting)):
		cancel_targeting()


func _gifts() -> GiftUser:
	return unit.get_node_or_null(^"Gifts") as GiftUser if unit != null else null


func _set_targeting(index: int) -> void:
	if index == _targeting:
		return
	_targeting = index
	targeting_changed.emit(index)
