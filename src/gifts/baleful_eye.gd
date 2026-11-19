class_name BalefulEye
extends Gift
## An enemy in range is stunned for a while.

@export var duration: float = 0.0


func apply(_caster: Unit, target: Unit) -> void:
	var effect := StatusEffect.new()
	effect.id = id
	effect.duration = duration
	effect.stuns = true
	target.add_effect(effect)
