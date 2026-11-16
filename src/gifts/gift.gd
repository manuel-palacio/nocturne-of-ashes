class_name Gift
extends Resource
## A power a unit uses for Blood, then waits out its cooldown. One resource is shared by every unit
## that carries it: it holds the numbers and the rules only, and the `GiftUser` keeps the cooldowns.

enum Targeting { SELF, ENEMY, ALLY }

@export var id: StringName
@export var display_name: String
@export var blood_cost: int = 0
## Seconds before the Gift can be used again.
@export var cooldown: float = 0.0
@export var targeting: Targeting = Targeting.SELF
## How far the target may be from the caster, flat on XZ. Unused for SELF.
@export var cast_range: float = 0.0


## Whether `target` suits this Gift. SELF needs none and ignores it; ENEMY takes a living hostile in
## range; ALLY a living friend in range, the caster included.
func can_target(caster: Unit, target: Unit) -> bool:
	if targeting == Targeting.SELF:
		return true
	if not is_instance_valid(target) or not target.is_alive():
		return false
	if caster.is_hostile_to(target) != (targeting == Targeting.ENEMY):
		return false
	var offset: Vector3 = target.global_position - caster.global_position
	return Vector2(offset.x, offset.z).length() <= cast_range


## Carries out the Gift. Each Gift overrides this.
func apply(_caster: Unit, _target: Unit) -> void:
	push_error("Gift %s does not override apply()" % id)
