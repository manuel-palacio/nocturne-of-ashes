class_name Interactable
extends StaticBody3D
## Something in a room that is clicked but is not a combatant. A unit ordered to it walks within
## `reach` and uses it. It needs a collision shape as a child to be clicked, sits on the "interact"
## layer (4) only and is not in the `&"units"` group, so brains and the Fury never see it.

signal used(by: Unit)

## What it is, shown to the player; translatable.
@export var label: String = ""
## A unit uses it from this flat distance or nearer, in metres.
@export var reach: float = 2.0


## Subclasses that define `_init` call `super()`, which puts the body on its layer.
func _init() -> void:
	collision_layer = 0b1000
	collision_mask = 0


## Whether `unit` may use it; always true here, narrowed by subclasses.
func can_be_used_by(_unit: Unit) -> bool:
	return true


## Emits `used` if `by` may use it; subclasses add what happens. Returns whether it was used.
func use(by: Unit) -> bool:
	if not can_be_used_by(by):
		return false
	used.emit(by)
	return true
