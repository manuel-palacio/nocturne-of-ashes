class_name GiftUser
extends Node
## The Gifts of its parent `Unit` and their cooldowns. A unit uses a Gift when it is free to act, the
## cooldown is over, it has the Blood and the target suits the Gift.

signal gift_used(index: int, target: Unit)
signal cooldowns_changed

@export var gifts: Array[Gift] = []:
	set(value):
		gifts = value
		_cooldowns.resize(gifts.size())
		_cooldowns.fill(0.0)

## Seconds left on each Gift's cooldown, by index.
var _cooldowns: PackedFloat32Array = PackedFloat32Array()

@onready var _unit: Unit = get_parent()


func _physics_process(delta: float) -> void:
	var ticked: bool = false
	for i: int in _cooldowns.size():
		if _cooldowns[i] > 0.0:
			_cooldowns[i] = maxf(_cooldowns[i] - delta, 0.0)
			ticked = true
	if ticked:
		cooldowns_changed.emit()


func count() -> int:
	return gifts.size()


## The Gift at `index`, or null when out of range.
func gift(index: int) -> Gift:
	return gifts[index] if index >= 0 and index < gifts.size() else null


func cooldown_left(index: int) -> float:
	return _cooldowns[index] if index >= 0 and index < _cooldowns.size() else 0.0


func can_use(index: int, target: Unit = null) -> bool:
	var used: Gift = gift(index)
	if used == null or not _unit.can_act() or _cooldowns[index] > 0.0:
		return false
	return _unit.stats.blood >= used.blood_cost and used.can_target(_unit, target)


## Uses the Gift at `index` on `target` if `can_use`; returns whether it was used. The Blood is spent
## first, so a Gift that takes Blood under the Fury threshold takes effect, then the Fury begins.
func use(index: int, target: Unit = null) -> bool:
	if not can_use(index, target):
		return false
	var used: Gift = gifts[index]
	_unit.stats.spend_blood(used.blood_cost)
	_cooldowns[index] = used.cooldown
	cooldowns_changed.emit()
	used.apply(_unit, target)
	gift_used.emit(index, target)
	return true


func reset_cooldowns() -> void:
	_cooldowns.fill(0.0)
	cooldowns_changed.emit()
