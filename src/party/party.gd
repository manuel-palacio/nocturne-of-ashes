class_name Party
extends Node
## The party: its members (one to three), the leader Álvar, whose fall ends the round, and the selected
## member. The selected member's brain is off and the other living members follow it. Raises the
## fallen when asked. It knows nothing of rooms or enemies.

## A living member became the selected one.
signal selection_changed(unit: Unit)
## A member fell.
signal member_fell(unit: Unit)
## A fallen member rose.
signal member_rose(unit: Unit)

## In the order they were added, the leader first.
var members: Array[Unit] = []
## Álvar: the member whose `member_id` is `GameState.LEADER`.
var leader: Unit
var selected: Unit


## Forgets every member; the caller frees their nodes.
func clear() -> void:
	for member: Unit in members:
		if is_instance_valid(member):
			member.died.disconnect(_on_member_died)
			member.revived.disconnect(_on_member_revived)
	members.clear()
	leader = null
	selected = null


func add(member: Unit) -> void:
	members.append(member)
	if member.member_id == GameState.LEADER:
		leader = member
	member.died.connect(_on_member_died)
	member.revived.connect(_on_member_revived)


## Makes `unit` the selected member and sets the other living members following it.
## Ignored unless `unit` is a living member, and while the leader is down.
func select(unit: Unit) -> void:
	if not _leader_alive() or unit == null or not members.has(unit) or not unit.is_alive():
		return
	selected = unit
	for member: Unit in members:
		if member.is_alive():
			_steer_brain(member)
	selection_changed.emit(unit)


## Selects the next living member after the selected one, wrapping round. Ignored while the leader is down.
func select_next() -> void:
	if not _leader_alive():
		return
	var at: int = members.find(selected)
	for step: int in range(1, members.size() + 1):
		var candidate: Unit = members[(at + step) % members.size()]
		if candidate.is_alive():
			select(candidate)
			return


func revive_fallen() -> void:
	for member: Unit in members:
		if not member.is_alive():
			member.revive()


func _leader_alive() -> bool:
	return leader != null and leader.is_alive()


## The selected member's brain is off; every other member's follows the selected one.
## The setter forgets the brain's chosen target, so `enabled` is only written when it changes.
func _steer_brain(member: Unit) -> void:
	var brain: CombatBrain = member.get_node(^"Brain")
	brain.leader = selected
	var wanted: bool = member != selected
	if brain.enabled != wanted:
		brain.enabled = wanted


## Selection goes back to the leader when the selected companion falls.
func _on_member_died(unit: Unit) -> void:
	member_fell.emit(unit)
	if unit != leader and unit == selected:
		select(leader)


func _on_member_revived(unit: Unit) -> void:
	_steer_brain(unit)
	member_rose.emit(unit)
