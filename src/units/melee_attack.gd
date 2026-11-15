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


## Strikes `target` if it is alive, in range and the cooldown has run out. Returns whether it hit.
func try_hit(target: Unit) -> bool:
	if not is_instance_valid(target) or not target.is_alive():
		return false
	if not ready_to_swing() or not in_range(target):
		return false
	target.stats.take_damage(damage)
	_cooldown_left = cooldown
	hit.emit(target, damage)
	return true
