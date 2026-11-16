class_name MendFlesh
extends Gift
## A living ally in range, or the caster, regains health up to its maximum.

@export var amount: int = 40


func _init() -> void:
	id = &"mend_flesh"
	display_name = "Mend Flesh"
	blood_cost = 20
	cooldown = 6.0
	targeting = Targeting.ALLY
	cast_range = 8.0


func apply(_caster: Unit, target: Unit) -> void:
	target.stats.heal(amount)
