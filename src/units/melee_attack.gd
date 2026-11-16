class_name MeleeAttack
extends Node
## A close-range weapon on a `Unit`: hits a target within reach, then waits out its cooldown.

signal hit(target: Unit, amount: int)

@export var damage: int = 12
@export var attack_range: float = 1.6
@export var cooldown: float = 1.0

var _cooldown_left: float = 0.0

@onready var _unit: Unit = get_parent()


func _physics_process(delta: float) -> void:
	_cooldown_left = maxf(_cooldown_left - delta, 0.0)


## True when `target` is within `attack_range`, measured flat on the ground plane.
func in_range(target: Unit) -> bool:
	var offset: Vector3 = target.global_position - _unit.global_position
	return Vector2(offset.x, offset.z).length() <= attack_range


func ready_to_swing() -> bool:
	return _cooldown_left <= 0.0


## Strikes `target` if both are alive, its own unit is not stunned, the target is in range and the
## cooldown has run out. Returns whether it hit; `hit` carries the damage dealt.
func try_hit(target: Unit) -> bool:
	if not _unit.is_alive() or _unit.is_stunned():
		return false
	if not is_instance_valid(target) or not target.is_alive():
		return false
	if not ready_to_swing() or not in_range(target):
		return false
	var dealt: int = target.take_hit(roundi(damage * _unit.damage_dealt_multiplier()), _unit)
	_cooldown_left = cooldown
	hit.emit(target, dealt)
	return true
