class_name CombatBrain
extends Node
## Fights and follows for its `Unit`, enemy or companion. Each think, the first rule that applies wins:
## obey a taunt; leave an order the brain did not give alone; switch to a much nearer hostile; engage
## the nearest hostile within `aggro_radius`; walk after `leader`. A follow walk is the brain's own
## order, so taunts, switching and engaging interrupt it. It does nothing while its unit is feeding.
## All distances are flat on XZ.

## A follow walk is re-aimed once the leader has moved this far from where the walk was aimed.
const _FOLLOW_RETARGET: float = 1.0

@export var aggro_radius: float = 8.0
@export var think_interval: float = 0.25
## Another hostile must be this much nearer than the current target before the brain switches to it.
@export var switch_margin: float = 2.0
## How far short of the leader a follow walk ends.
@export var follow_distance: float = 3.0
## When false the brain does nothing. Turning it off stops a follow walk it started; a fight goes on.
## Any attack running when it is switched either way counts as the player's, left alone until it ends.
@export var enabled: bool = true:
	set(value):
		enabled = value
		_chosen_target = null
		if not enabled:
			if _following and _unit != null and _unit.current_order() == Unit.Order.MOVE:
				_unit.stop()
			_following = false

var leader: Unit

var _since_thought: float = 0.0
## The attack target the brain last chose, to tell its own attack orders from the player's.
var _chosen_target: Unit
## Whether the unit's current move order is a follow walk the brain started.
var _following: bool = false
## Where the leader stood when the current follow walk was aimed.
var _leader_was_at: Vector3

@onready var _unit: Unit = get_parent()


func _physics_process(delta: float) -> void:
	_since_thought += delta
	if _since_thought < think_interval:
		return
	_since_thought = 0.0
	if enabled and _unit.is_alive() and not _unit.is_stunned() and not _unit.is_feeding():
		_think()


func _think() -> void:
	var order: Unit.Order = _unit.current_order()
	var attacking_own: bool = (
		order == Unit.Order.ATTACK and _chosen_target != null and _unit.attack_target() == _chosen_target
	)
	var following_own: bool = order == Unit.Order.MOVE and _following
	if not attacking_own:
		_chosen_target = null
	if not following_own:
		_following = false

	var taunter: Unit = _nearest_taunter()
	if taunter != null:
		if _unit.attack_target() != taunter:
			_attack(taunter)
		return
	if order != Unit.Order.NONE and not attacking_own and not following_own:
		return
	if attacking_own:
		_reconsider()
		return
	var nearest: Unit = _nearest_hostile()
	if nearest != null and _flat_to(nearest) <= aggro_radius:
		_attack(nearest)
		return
	_follow()


## Switches to the nearest hostile when it is nearer than the current target by more than `switch_margin`.
func _reconsider() -> void:
	var nearest: Unit = _nearest_hostile()
	if nearest != null and nearest != _chosen_target and _flat_to(nearest) + switch_margin < _flat_to(_chosen_target):
		_attack(nearest)


func _follow() -> void:
	if leader == null or not is_instance_valid(leader) or not leader.is_alive():
		return
	if _following and _flat(leader.global_position, _leader_was_at) <= _FOLLOW_RETARGET:
		return
	if not _following and _flat_to(leader) <= follow_distance + 1.0:
		return
	var away: Vector3 = _unit.global_position - leader.global_position
	away.y = 0.0
	_leader_was_at = leader.global_position
	_unit.order_move(leader.global_position + away.normalized() * follow_distance)
	_following = true


func _attack(target: Unit) -> void:
	_following = false
	_chosen_target = target
	_unit.order_attack(target)


## The nearest living hostile whose taunt reaches this unit, or null.
func _nearest_taunter() -> Unit:
	var nearest: Unit = null
	var best: float = INF
	for other: Unit in _living_hostiles():
		var distance: float = _flat_to(other)
		var reach: float = other.taunt_radius()
		if reach > 0.0 and distance <= reach and distance < best:
			best = distance
			nearest = other
	return nearest


## The nearest living hostile at any distance, or null.
func _nearest_hostile() -> Unit:
	var nearest: Unit = null
	var best: float = INF
	for other: Unit in _living_hostiles():
		var distance: float = _flat_to(other)
		if distance < best:
			best = distance
			nearest = other
	return nearest


func _living_hostiles() -> Array[Unit]:
	var hostiles: Array[Unit] = []
	for node: Node in get_tree().get_nodes_in_group(&"units"):
		var other: Unit = node as Unit
		if other != null and other != _unit and other.is_alive() and _unit.is_hostile_to(other):
			hostiles.append(other)
	return hostiles


func _flat_to(other: Unit) -> float:
	return _flat(_unit.global_position, other.global_position)


static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
