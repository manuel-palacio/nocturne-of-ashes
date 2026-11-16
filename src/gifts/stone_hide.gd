class_name StoneHide
extends Gift
## The caster takes much less damage for a while and draws the enemies around it.

@export var duration: float = 8.0
@export var damage_taken_multiplier: float = 0.4
@export var taunt_radius: float = 8.0


func _init() -> void:
	id = &"stone_hide"
	display_name = "Stone Hide"
	blood_cost = 20
	cooldown = 15.0
	targeting = Targeting.SELF


func apply(caster: Unit, _target: Unit) -> void:
	var effect := StatusEffect.new()
	effect.id = id
	effect.duration = duration
	effect.damage_taken_multiplier = damage_taken_multiplier
	effect.taunt_radius = taunt_radius
	caster.add_effect(effect)
