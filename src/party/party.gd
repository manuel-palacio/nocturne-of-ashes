class_name Party
extends Node
## The party: its members (one to three), the leader Álvar, whose fall ends the round, and the selected
## member. The selected member's brain is off and the other living members follow it. Raises the
## fallen when asked. Builds members from a `GameState` (their Gifts and vitals), writes their vitals
## back, and keeps their vitals as a room was entered for a restart. It knows nothing of rooms or enemies.

## A living member became the selected one.
signal selection_changed(unit: Unit)
## A member fell.
signal member_fell(unit: Unit)
## A fallen member rose.
signal member_rose(unit: Unit)

## Each member's scene, by `Unit.member_id`.
const SCENES: Dictionary = {
	&"alvar": preload("res://scenes/units/alvar.tscn"),
	&"zahra": preload("res://scenes/units/zahra.tscn"),
	&"gonzalo": preload("res://scenes/units/gonzalo.tscn"),
}

## In the order they were added, the leader first.
var members: Array[Unit] = []
## Álvar: the member whose `member_id` is `GameState.LEADER`.
var leader: Unit
var selected: Unit

## Each member's vitals in the state as the room was entered, for a restart.
var _entry_vitals: Dictionary = {}  # StringName member -> Vector2i


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


## Adds the member `member_id` to the party under `parent`, at `marker`, with only the Gifts it knows
## in `state`, in its scene's order, and the vitals `state` holds for it: health above the maximum is
## clamped to it, a stored 0 arrives as `Unit.risen_health()`.
func spawn(member_id: StringName, marker: Node3D, state: GameState, parent: Node) -> Unit:
	var unit: Unit = (SCENES[member_id] as PackedScene).instantiate()
	var gift_user: GiftUser = unit.get_node(^"Gifts")
	var known: Array[StringName] = state.known_gifts(member_id)
	var gifts: Array[Gift] = []
	for gift: Gift in gift_user.gifts:
		if known.has(gift.id):
			gifts.append(gift)
	gift_user.gifts = gifts
	var vitals: Vector2i = state.vitals(member_id)
	if vitals.y >= 0:
		# Set as the starting Blood, so the unit begins with it and its Fury sees no fall into it.
		var stats: Stats = unit.stats.duplicate()
		stats.starting_blood = vitals.y
		unit.stats = stats
	parent.add_child(unit)
	unit.global_transform = marker.global_transform
	if vitals.x >= 0:
		var health: int = Unit.risen_health(unit.stats) if vitals.x == 0 else mini(vitals.x, unit.stats.max_health)
		unit.stats.take_damage(unit.stats.max_health - health)
	add(unit)
	return unit


## Stores each member's health and Blood in `state`; a fallen member's health as `Unit.risen_health()`.
func record(state: GameState) -> void:
	for member: Unit in members:
		var health: int = member.stats.health
		if not member.is_alive():
			health = Unit.risen_health(member.stats)
		state.set_vitals(member.member_id, health, member.stats.blood)


## Remembers the members' vitals in `state` as the room is entered.
func remember_entry_vitals(state: GameState) -> void:
	_entry_vitals.clear()
	for member: Unit in members:
		_entry_vitals[member.member_id] = state.vitals(member.member_id)


## Puts back into `state` the vitals remembered on entering the room.
func restore_entry_vitals(state: GameState) -> void:
	for member: StringName in _entry_vitals:
		var vitals: Vector2i = _entry_vitals[member]
		state.set_vitals(member, vitals.x, vitals.y)


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
