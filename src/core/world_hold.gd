class_name WorldHold
extends Node
## Holds the world still for any number of reasons at once (the pause, a conversation, the title, the
## controls card): while any reason holds it the units do not process and the fight does not advance.
## Each reason is released on its own; the world moves again once none is left. Held units stay in the
## physics space (their scenes keep them active when disabled), so they can still be clicked and given
## orders.
##
## The room's air (its torches' flicker and embers: `Room.air()`) stops with the world too, but
## not for a conversation: the room stays alive while people talk. Held for a conversation alone, the
## units' figures stand at ease (`UnitVisual.at_ease`) rather than freezing mid-stride; for anything
## else, such as the pause, they freeze as they are.

## The reason that holds the units but leaves the air moving.
const TALK: StringName = &"talk"

var _units: Node
var _encounter: Encounter
var _air: Node
var _reasons: Dictionary = {}  # StringName -> true


## Called once, before anything is held: what to hold.
func setup(units: Node, encounter: Encounter) -> void:
	_units = units
	_encounter = encounter
	_units.child_entered_tree.connect(_put_at_ease)


## The room's air from now on (null for none), held as the world is now.
func set_air(air: Node) -> void:
	_air = air
	_apply()


## Holds the world for `reason` while `on`, or releases that reason.
func set_held(reason: StringName, on: bool) -> void:
	if on:
		_reasons[reason] = true
	else:
		_reasons.erase(reason)
	_apply()


func is_held() -> bool:
	return not _reasons.is_empty()


## Whether the air is held: the world is, for some reason other than a conversation.
func is_air_held() -> bool:
	return _reasons.keys().any(func(reason: StringName) -> bool: return reason != TALK)


func _apply() -> void:
	var held: bool = is_held()
	_units.process_mode = Node.PROCESS_MODE_DISABLED if held else Node.PROCESS_MODE_INHERIT
	_encounter.paused = held
	if is_instance_valid(_air):
		_air.process_mode = Node.PROCESS_MODE_DISABLED if is_air_held() else Node.PROCESS_MODE_INHERIT
	for unit: Node in _units.get_children():
		_put_at_ease(unit)


## Sets the figure of `unit` at ease while the world is held for a conversation alone.
func _put_at_ease(unit: Node) -> void:
	var visual := unit.get_node_or_null(^"Visual") as UnitVisual
	if visual != null:
		visual.at_ease = is_held() and not is_air_held()
