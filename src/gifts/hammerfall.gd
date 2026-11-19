class_name Hammerfall
extends Gift
## Every living hostile within `radius` of the caster, flat on XZ, is hit and stunned for a while.

@export var radius: float = 0.0
@export var damage: int = 0
@export var stun_time: float = 0.0


func apply(caster: Unit, _target: Unit) -> void:
	var here: Vector3 = caster.global_position
	for node: Node in caster.get_tree().get_nodes_in_group(&"units"):
		var other: Unit = node as Unit
		if other == null or other == caster or not other.is_alive() or not caster.is_hostile_to(other):
			continue
		var offset: Vector3 = other.global_position - here
		if Vector2(offset.x, offset.z).length() > radius:
			continue
		other.take_hit(damage, caster)
		if other.is_alive():
			var stun := StatusEffect.new()
			stun.id = id
			stun.duration = stun_time
			stun.stuns = true
			other.add_effect(stun)
