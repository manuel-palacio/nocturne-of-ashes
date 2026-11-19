class_name MendFlesh
extends Gift
## A living ally in range, or the caster, regains health up to its maximum.

@export var amount: int = 0


func apply(_caster: Unit, target: Unit) -> void:
	target.stats.heal(amount)
