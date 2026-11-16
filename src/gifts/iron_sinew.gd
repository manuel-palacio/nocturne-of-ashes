class_name IronSinew
extends Gift
## The caster walks faster and hits harder for a while.

@export var duration: float = 8.0
@export var speed_multiplier: float = 1.4
@export var damage_dealt_multiplier: float = 1.5


func _init() -> void:
	id = &"iron_sinew"
	display_name = "Iron Sinew"
	blood_cost = 20
	cooldown = 12.0
	targeting = Targeting.SELF


func apply(caster: Unit, _target: Unit) -> void:
	var effect := StatusEffect.new()
	effect.id = id
	effect.duration = duration
	effect.speed_multiplier = speed_multiplier
	effect.damage_dealt_multiplier = damage_dealt_multiplier
	caster.add_effect(effect)
