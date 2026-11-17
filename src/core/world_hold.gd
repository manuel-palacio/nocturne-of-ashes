class_name WorldHold
extends Node
## Holds the world still for any number of reasons at once (the pause, a conversation, the title):
## while any reason holds it the units do not process and the fight does not advance. Each reason is
## released on its own; the world moves again once none is left. Held units stay in the physics space
## (their scenes keep them active when disabled), so they can still be clicked and given orders.

var _units: Node
var _encounter: Encounter
var _reasons: Dictionary = {}  # StringName -> true


## Called once, before anything is held: what to hold.
func setup(units: Node, encounter: Encounter) -> void:
	_units = units
	_encounter = encounter


## Holds the world for `reason` while `on`, or releases that reason.
func set_held(reason: StringName, on: bool) -> void:
	if on:
		_reasons[reason] = true
	else:
		_reasons.erase(reason)
	var held: bool = is_held()
	_units.process_mode = Node.PROCESS_MODE_DISABLED if held else Node.PROCESS_MODE_INHERIT
	_encounter.paused = held


func is_held() -> bool:
	return not _reasons.is_empty()
