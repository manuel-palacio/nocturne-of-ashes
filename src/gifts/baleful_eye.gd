class_name BalefulEye
extends Gift
## An enemy in range is stunned for a while.

@export var duration: float = 4.0


func _init() -> void:
	id = &"baleful_eye"
	display_name = "Baleful Eye"
	blood_cost = 15
	cooldown = 10.0
	targeting = Targeting.ENEMY
	cast_range = 8.0


func apply(_caster: Unit, target: Unit) -> void:
	var effect := StatusEffect.new()
	effect.id = id
	effect.duration = duration
	effect.stuns = true
	target.add_effect(effect)
