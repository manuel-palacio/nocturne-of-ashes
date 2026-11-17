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

## The room it leads to; empty for a door that never opens.
@export var to_room: StringName
## The entry of `to_room` the party arrives at.
@export var to_entry: StringName = &"start"
## The story flags that must all be set for it to open.
@export var needs_flags: Array[StringName] = []
## Shown when it is used while barred; translatable.
@export var locked_text: String = ""

## Asked, with no arguments, at each use; unless it is set and answers true, the use is refused and
## does not count.
var use_allowed: Callable = Callable()


func _init() -> void:
	leader_only = true


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
