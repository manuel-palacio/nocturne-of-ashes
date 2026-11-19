class_name BloodLance
extends Gift
## An enemy in range is wounded from afar.

@export var damage: int = 0


func apply(caster: Unit, target: Unit) -> void:
	target.take_hit(damage, caster)
