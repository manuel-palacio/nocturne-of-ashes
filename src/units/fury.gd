class_name Fury
extends Node
## The Fury of its `Unit`: starts when a blood-drinker's Blood is spent from at or above its
## `fury_threshold` to below it, and lasts `fury_time`, with the unit carrying the `fury` effect.
## The unit drives the attacks and asks this node for the nearest victim.

signal started
signal ended

const EFFECT_ID: StringName = &"fury"

var _active: bool = false
var _time_left: float = 0.0
## Blood as of the latest change seen, to tell a fall across the threshold from a start below it.
var _last_blood: int = 0

@onready var _unit: Unit = get_parent()


func _physics_process(delta: float) -> void:
	if not _active:
		return
	_time_left -= delta
	if _time_left <= 0.0:
		end()


## Follows the Blood in `stats` from its current value on. The unit calls this once its stats are set up.
func watch(stats: Stats) -> void:
	_last_blood = stats.blood
	stats.blood_changed.connect(_on_blood_changed)


func is_active() -> bool:
	return _active


## Ends the Fury in progress, if any, and emits `ended`.
func end() -> void:
	if not _active:
		return
	_active = false
	_unit.remove_effect(EFFECT_ID)
	ended.emit()


## The nearest living unit of any faction other than this one, flat on XZ, or null.
func nearest_victim() -> Unit:
	var nearest: Unit = null
	var best: float = INF
	var here: Vector3 = _unit.global_position
	for node: Node in get_tree().get_nodes_in_group(&"units"):
		var other: Unit = node as Unit
		if other == null or other == _unit or not other.is_alive():
			continue
		var distance: float = Vector2(other.global_position.x - here.x, other.global_position.z - here.z).length()
		if distance < best:
			best = distance
			nearest = other
	return nearest


func _on_blood_changed(current: int, _maximum: int) -> void:
	var before: int = _last_blood
	_last_blood = current
	if _active or not _unit.drinks_blood or not _unit.is_alive():
		return
	if before >= _unit.fury_threshold and current < _unit.fury_threshold:
		_begin()


func _begin() -> void:
	_active = true
	_time_left = _unit.fury_time
	var rage := StatusEffect.new()
	rage.id = EFFECT_ID
	rage.duration = _unit.fury_time
	rage.damage_dealt_multiplier = _unit.fury_damage
	_unit.add_effect(rage)
	started.emit()
