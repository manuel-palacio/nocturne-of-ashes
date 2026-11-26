class_name PlayerInput
extends Node
## Turns mouse clicks and keys into orders for the controlled unit, Gift uses, selection requests, and
## moves for the camera rig. It never calls `Main`; selection goes out through its signals.
## It also marks what the leader can use, one use ring at a time: the usable interactable under the
## mouse if there is one, else the nearest usable one within `NEAR_USE` of the leader. None shows while
## input is off, as it is on the title, in a conversation and while the leader is down, nor while the
## mouse is outside the window or over the HUD.

## A click landed on a living friend of the controlled unit, or a party member was pressed.
signal select_requested(unit: Unit)
## The `select_next` action was pressed.
signal select_next_requested
## Targeting opened for the Gift at `index`, or closed when `index` is −1.
signal targeting_changed(index: int)
## Something the player asked for went otherwise, and should be said: `text`, a source text, with its
## `%s` places filled by `args`, as `Hud.show_notice()` takes them.
signal notice_requested(text: String, args: Array)

## Said when a click to feed finds the controlled unit's Blood full, and it attacks instead.
const FULL_BLOOD_TEXT: String = "%s's Blood is full"

## A usable interactable this near the leader, flat, in metres, shows its ring when the mouse is on
## nothing usable.
const NEAR_USE: float = 4.0
## The nearest keeps its ring until another is this much nearer, so two at about the same distance do
## not swap it while the leader walks.
const NEAR_MARGIN: float = 0.5

## The controlled unit. Changing it closes targeting.
var unit: Unit:
	set(value):
		unit = value
		cancel_targeting()
var rig: CameraRig
## The party's leader, who uses whatever is `Interactable.leader_only`, whoever is controlled. Set by
## the party's owner whenever the party or the selection changes.
var leader: Unit
## When false, clicks and keys give no orders and targeting closes.
var enabled: bool = true:
	set(value):
		enabled = value
		_marks_stale = true
		if not enabled:
			cancel_targeting()
			_pointing = false

## While true no key or click gives an order or changes targeting, and targeting stays as it is: a
## card covers the game (the controls card). Unlike `enabled` it leaves the use ring as it was.
var suspended: bool = false

## The index of the Gift waiting for a click on its target, or −1.
var _targeting: int = -1
## Where the mouse is over the world, while it is.
var _pointer: Vector2 = Vector2.ZERO
var _pointing: bool = false
## The interactable whose ring is lit, and the one that was nearest the leader.
var _lit: Interactable
var _nearest: Interactable
## What the ring was last chosen from: pointer, leader's place, camera; and whether to choose again.
var _marked_pointer: Vector2 = Vector2.ZERO
var _marked_pointing: bool = false
var _marked_leader_at: Vector3 = Vector3.INF
var _marked_camera: Transform3D = Transform3D()
var _marks_stale: bool = true


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_MOUSE_EXIT:
		_pointing = false


# Every motion first counts as off the world; it comes back in `_unhandled_input` unless the HUD took it.
func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_pointing = false


func _unhandled_input(event: InputEvent) -> void:
	if suspended:
		return
	var motion := event as InputEventMouseMotion
	if motion != null:
		point_at(motion.position)
		return
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
	if suspended:
		return
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
	_show_use_marks()
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
	if not enabled or suspended or unit == null:
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
## unit can and is short of Blood, else attacks it, saying the Blood is full when that was why, and
## leaves an attack already on that very enemy going as it is (no new chase); else has an interactable
## under it used, by the leader when it is leader-only, which leaves the selection as it is, else by
## the unit, and does nothing when that one may not use it; else walks to the ground under it. A click
## on the controlled unit itself does nothing.
func click_at(screen_position: Vector2) -> void:
	if not enabled or suspended or unit == null or not unit.is_alive():
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
			if unit.can_feed_on(other):
				notice_requested.emit(FULL_BLOOD_TEXT, [unit.display_name])
			if unit.current_order() != Unit.Order.ATTACK or unit.attack_target() != other:
				unit.order_attack(other)
		else:
			select_requested.emit(other)
		return
	var thing: Interactable = Picker.interactable_at(cam, screen_position)
	if thing != null:
		var user: Unit = leader if thing.leader_only else unit
		if user != null and user.is_alive() and thing.can_be_used_by(user):
			user.order_interact(thing)
		return
	var on_ground: Variant = Picker.ground_at(cam, screen_position)
	if on_ground != null:
		unit.order_move(on_ground)


## The mouse is over `screen_position`: what lies under it there is marked if usable, from now on
## as the camera moves.
func point_at(screen_position: Vector2) -> void:
	_pointer = screen_position
	_pointing = true


## A party member was pressed outside the world, as on its HUD panel: while targeting a Gift that can
## be used on `member`, uses it on them and keeps the selection; otherwise asks to select them.
## Does nothing while input is off.
func press_member(member: Unit) -> void:
	if not enabled or suspended:
		return
	_close_stale_targeting()
	if _targeting >= 0 and _use_targeted_on(member):
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


## Has the use ring chosen again on the next frame, though nothing has moved: what can be used has
## changed, as when a story flag shows or hides someone.
func refresh_use_marks() -> void:
	_marks_stale = true


## Lights one use ring: the usable interactable's under the mouse, else the nearest usable one's within
## `NEAR_USE` of the leader. Chosen again only when the pointer, the leader or the camera has moved,
## input was turned on or off, or `refresh_use_marks()` asked; only the ring that changes is touched.
func _show_use_marks() -> void:
	var leader_at: Vector3 = leader.global_position if is_instance_valid(leader) else Vector3.INF
	var camera: Transform3D = rig.camera().global_transform if rig != null else Transform3D()
	if (not _marks_stale and _pointing == _marked_pointing and _pointer == _marked_pointer
			and leader_at == _marked_leader_at and camera == _marked_camera):
		return
	_marks_stale = false
	_marked_pointing = _pointing
	_marked_pointer = _pointer
	_marked_leader_at = leader_at
	_marked_camera = camera
	var chosen: Interactable = null
	if enabled and rig != null and is_instance_valid(leader) and leader.is_alive():
		if _pointing:
			chosen = Picker.interactable_at(rig.camera(), _pointer)
			if chosen != null and not _usable(chosen):
				chosen = null
		_nearest = _nearest_usable()
		if chosen == null:
			chosen = _nearest
	if chosen != _lit:
		if is_instance_valid(_lit):
			_lit.set_use_mark(false)
		if chosen != null:
			chosen.set_use_mark(true)
		_lit = chosen


## The usable interactable nearest the leader within `NEAR_USE`; the one nearest before keeps that
## place unless another is `NEAR_MARGIN` nearer.
func _nearest_usable() -> Interactable:
	var best: Interactable = null
	var best_distance: float = NEAR_USE
	var kept_distance: float = INF
	for node: Node in get_tree().get_nodes_in_group(&"interactables"):
		var thing := node as Interactable
		if not _usable(thing):
			continue
		var distance: float = _flat_distance(thing)
		if thing == _nearest:
			kept_distance = distance
		if distance <= best_distance:
			best_distance = distance
			best = thing
	if kept_distance <= NEAR_USE and best != _nearest and best_distance > kept_distance - NEAR_MARGIN:
		return _nearest
	return best


func _flat_distance(thing: Interactable) -> float:
	var gap: Vector3 = thing.global_position - leader.global_position
	return Vector2(gap.x, gap.z).length()


## Whether the leader may use `thing` now and its ring may show: it is shown and offers him its use.
func _usable(thing: Interactable) -> bool:
	return thing != null and thing.is_visible_in_tree() and thing.offers_use_to(leader)
