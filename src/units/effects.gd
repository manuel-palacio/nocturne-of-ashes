class_name Effects
extends Node
## The timed status effects on one `Unit`: keeps its own copy of each, counts them down each physics
## frame and answers what they add up to.

signal changed

var _active: Array[StatusEffect] = []


func _physics_process(delta: float) -> void:
	if _active.is_empty():
		return
	for effect: StatusEffect in _active:
		effect.duration -= delta
	_keep(func(e: StatusEffect) -> bool: return e.duration > 0.0)


## Adds a copy of `effect`; one with the same id is replaced, which restarts its time.
func add(effect: StatusEffect) -> void:
	_active = _active.filter(func(e: StatusEffect) -> bool: return e.id != effect.id)
	_active.append(effect.duplicate())
	changed.emit()


func remove(id: StringName) -> void:
	_keep(func(e: StatusEffect) -> bool: return e.id != id)


func has(id: StringName) -> bool:
	return _active.any(func(e: StatusEffect) -> bool: return e.id == id)


func clear() -> void:
	if _active.is_empty():
		return
	_active.clear()
	changed.emit()


func stuns() -> bool:
	return _active.any(func(e: StatusEffect) -> bool: return e.stuns)


func speed_multiplier() -> float:
	return _product(func(e: StatusEffect) -> float: return e.speed_multiplier)


func damage_dealt_multiplier() -> float:
	return _product(func(e: StatusEffect) -> float: return e.damage_dealt_multiplier)


func damage_taken_multiplier() -> float:
	return _product(func(e: StatusEffect) -> float: return e.damage_taken_multiplier)


## The largest taunt radius among the active effects; 0 when none taunts.
func taunt_radius() -> float:
	var largest: float = 0.0
	for effect: StatusEffect in _active:
		largest = maxf(largest, effect.taunt_radius)
	return largest


func _product(factor: Callable) -> float:
	var product: float = 1.0
	for effect: StatusEffect in _active:
		product *= factor.call(effect)
	return product


## Keeps the effects for which `predicate` holds; emits `changed` if any were dropped.
func _keep(predicate: Callable) -> void:
	var before: int = _active.size()
	_active = _active.filter(predicate)
	if _active.size() != before:
		changed.emit()
