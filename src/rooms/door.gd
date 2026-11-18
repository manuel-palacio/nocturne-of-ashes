class_name Door
extends Interactable
## A way out of a room: Álvar walks up to it and uses it, and the party goes to the room `to_room`,
## arriving at its entry `to_entry`. It may be barred until story flags are set. A door decides nothing
## else: a use asks for the travel, or, with no room behind it, is refused with `locked_text`; whoever
## answers the signals decides what happens. Until that one sets `use_allowed` the door is inert: no
## use counts and nothing is emitted.

## Álvar used the door, which leads somewhere: the party should go through, if it may.
signal travel_requested(door: Door)
## Álvar used a door that leads nowhere: `text` should be shown.
signal refused(text: String)

## Its use ring lies this far in front of it, on the side facing the middle of its room.
const USE_MARK_AHEAD: float = 0.9

## The room it leads to; empty for a door that never opens.
@export var to_room: StringName
## The entry of `to_room` the party arrives at.
@export var to_entry: StringName = &"start"
## The story flags that must all be set for it to open.
@export var needs_flags: Array[StringName] = []
## Shown when it is used while barred; translatable.
@export var locked_text: String = ""
## When set, the door's leaf is drawn exactly while this node is drawn, so a door set in a wall that the
## camera cuts (its frame) goes and comes back with it; unset, the leaf is always drawn. Only the leaf:
## the door's body, its ring and its use never depend on it.
@export var drawn_with: Node3D

## Asked, with no arguments, at each use; unless it is set and answers true, the use is refused and
## does not count.
var use_allowed: Callable = Callable()


func _init() -> void:
	leader_only = true


func _ready() -> void:
	if drawn_with != null:
		# A Node3D's `visibility_changed` also fires when an ancestor (a cut wall) is shown or hidden.
		drawn_with.visibility_changed.connect(_draw_leaf)
		_draw_leaf()


func _draw_leaf() -> void:
	var leaf := get_node_or_null(^"Leaf") as Node3D
	if leaf != null:
		leaf.visible = drawn_with.is_visible_in_tree()


## In front of it, on the floor: on whichever side of it the room's origin lies.
func use_mark_position() -> Vector3:
	var room: Node3D = get_parent_node_3d()
	var side: float = 1.0
	if room != null and to_local(room.global_position).z < 0.0:
		side = -1.0
	return Vector3(0.0, 0.0, USE_MARK_AHEAD * side)


## Its ring shows for Álvar once the door is wired to the travel, barred or not: a barred door still
## says why when used. A door nothing answers (as in the skirmish) shows none.
func offers_use_to(unit: Unit) -> bool:
	return can_be_used_by(unit) and use_allowed.is_valid()


## Only Álvar opens doors.
func can_be_used_by(unit: Unit) -> bool:
	return unit != null and unit.member_id == GameState.LEADER


func use(by: Unit) -> bool:
	if not use_allowed.is_valid() or not use_allowed.call():
		return false
	if not super(by):
		return false
	if to_room.is_empty():
		refused.emit(locked_text)
	else:
		travel_requested.emit(self)
	return true


## Whether it stays shut with the flags of `state`: it leads nowhere, or one of `needs_flags` is unset.
func is_locked(state: GameState) -> bool:
	if to_room.is_empty():
		return true
	for flag: StringName in needs_flags:
		if not state.has_flag(flag):
			return true
	return false
