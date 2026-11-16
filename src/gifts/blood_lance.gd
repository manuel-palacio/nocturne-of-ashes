class_name BloodLance
extends Gift
## An enemy in range is wounded from afar.

@export var damage: int = 30


func _init() -> void:
	id = &"blood_lance"
	display_name = "Blood Lance"
	blood_cost = 15
	cooldown = 4.0
	targeting = Targeting.ENEMY
	cast_range = 10.0


func apply(caster: Unit, target: Unit) -> void:
	target.take_hit(damage, caster)
