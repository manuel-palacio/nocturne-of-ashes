class_name Feeder
extends Node
## Feeding for its `Unit`: holds the target and the drinking time. The unit walks into reach and calls
## `start_drinking()`; the feed then completes after the unit's `feed_time`, or is broken when the
## feeder is stunned or the target dies or leaves the tree. The unit breaks it on any new order.

## The feed completed: `target` died of it and the unit gained its Blood.
signal finished(target: Unit)
## A feed in progress was given up, with no Blood gained.
signal broken

## The stunning effect the target carries while it is drunk from.
const FED_ON: StringName = &"fed_on"
## The hold outlasts the drinking time by this much, so the two timers can never end it early.
const _HOLD_MARGIN: float = 0.5

var _target: Unit
var _active: bool = false
var _drinking: bool = false
var _time_left: float = 0.0

@onready var _unit: Unit = get_parent()


func _physics_process(delta: float) -> void:
	if not _active:
		return
	if not is_instance_valid(_target) or not _target.is_alive() or _unit.is_stunned():
		cancel()
		return
	if _drinking:
		_time_left -= delta
		if _time_left <= 0.0:
			_complete()


## Takes `target` as the one to feed on; drinking starts with `start_drinking()`.
func begin(target: Unit) -> void:
	cancel()
	_target = target
	_active = true
	_drinking = false


## The target of the feed in progress, or null.
func target() -> Unit:
	return _target if _active and is_instance_valid(_target) else null


func is_drinking() -> bool:
	return _active and _drinking


## Starts drinking from the target, which is held stunned until the feed ends.
func start_drinking() -> void:
	if target() == null or _drinking:
		return
	_drinking = true
	_time_left = _unit.feed_time
	var hold := StatusEffect.new()
	hold.id = FED_ON
	hold.stuns = true
	hold.duration = _unit.feed_time + _HOLD_MARGIN
	_target.add_effect(hold)


## Breaks the feed in progress, if any: the target is let go and `broken` is emitted.
func cancel() -> void:
	if not _active:
		return
	_release()
	broken.emit()


func _complete() -> void:
	var target: Unit = _target
	_release()
	_unit.stats.gain_blood(_unit.feed_gain)
	# Enough that the hit, scaled by the damage the target takes, removes all its remaining health.
	var multiplier: float = maxf(target.damage_taken_multiplier(), 0.01)
	target.take_hit(ceili(target.stats.health / multiplier), _unit)
	finished.emit(target)


func _release() -> void:
	if is_instance_valid(_target):
		_target.remove_effect(FED_ON)
	_target = null
	_active = false
	_drinking = false
