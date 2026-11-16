class_name CombatBrain
extends Node
## Fights and follows for its `Unit`, enemy or companion. Each think, a brain that `uses_gifts` first
## feeds or uses one Gift, unless the unit is carrying out the player's order or its own feed; if it
## did, the think ends. Then the first rule that applies wins: obey a taunt; leave an order the brain
## did not give alone; keep up its own feed; switch to a much nearer hostile; engage the nearest
## hostile within `aggro_radius`; walk after `leader`. A follow walk is the brain's own order, so
## taunts, switching and engaging interrupt it. Between thinks, a hit from a living hostile on an idle
## or following unit is answered with an attack at once. A hostile held by a feed is left alone: never
## chosen, counted or aimed at, and an attack of the brain's on it is dropped. The brain does nothing
## while its unit is drinking, stunned or in the Fury. All distances are flat on XZ.

## A follow walk is re-aimed once the leader has moved this far from where the walk was aimed.
const _FOLLOW_RETARGET: float = 1.0

@export var aggro_radius: float = 8.0
@export var think_interval: float = 0.25
## Another hostile must be this much nearer than the current target before the brain switches to it.
@export var switch_margin: float = 2.0
## How far short of the leader a follow walk ends.
@export var follow_distance: float = 3.0
## Whether the brain feeds and uses its unit's Gifts.
@export var uses_gifts: bool = false
## With `uses_gifts`, the unit feeds on a weakened hostile within `aggro_radius` while its Blood is below this.
@export var feeds_below: int = 30
## An ALLY Gift is used on the most hurt ally only below this fraction of its maximum health.
@export var mends_below: float = 0.5
## A SELF Gift is used when at least this many living hostiles are within `self_gift_radius`.
@export var self_gift_enemies: int = 2
@export var self_gift_radius: float = 4.0
## When false the brain does nothing. Turning it off stops a follow walk it started; a fight goes on.
## Any attack running when it is switched either way counts as the player's, left alone until it ends.
@export var enabled: bool = true:
	set(value):
		enabled = value
		_chosen_target = null
		_feeding = false
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
## Whether the unit's current feed order is one the brain gave.
var _feeding: bool = false
## Where the leader stood when the current follow walk was aimed.
var _leader_was_at: Vector3
## A hostile that hit the unit while the world was paused, answered once the brain runs again.
var _hit_while_paused: Unit

@onready var _unit: Unit = get_parent()


func _ready() -> void:
	_unit.was_hit.connect(_on_unit_hit)


func _physics_process(delta: float) -> void:
	if _hit_while_paused != null:
		var source: Unit = _hit_while_paused if is_instance_valid(_hit_while_paused) else null
		_hit_while_paused = null
		_on_unit_hit(0, source)
	_since_thought += delta
	if _since_thought < think_interval:
		return
	_since_thought = 0.0
	if enabled and _unit.can_act():
		_think()


## A living hostile that hits the unit while it is idle or on the brain's follow walk is attacked at
## once, at any distance. A player's order and an attack under way are left alone. A hit taken while
## the brain is not processing (the world is paused) is answered on its first frame back.
func _on_unit_hit(_amount: int, source: Unit) -> void:
	if not can_process():
		_hit_while_paused = source
		return
	if not enabled or not _unit.can_act() or not is_instance_valid(source) or not source.is_alive():
		return
	if not _unit.is_hostile_to(source) or Feeder.is_held(source):
		return
	var order: Unit.Order = _unit.current_order()
	if order == Unit.Order.NONE or (order == Unit.Order.MOVE and _following):
		_attack(source)


func _think() -> void:
	var order: Unit.Order = _unit.current_order()
	var attacking_own: bool = (
		order == Unit.Order.ATTACK and _chosen_target != null and _unit.attack_target() == _chosen_target
	)
	var following_own: bool = order == Unit.Order.MOVE and _following
	var feeding_own: bool = order == Unit.Order.FEED and _feeding
	if not attacking_own:
		_chosen_target = null
	if not following_own:
		_following = false
	if not feeding_own:
		_feeding = false
	var players_order: bool = order != Unit.Order.NONE and not attacking_own and not following_own and not feeding_own

	if attacking_own and Feeder.is_held(_chosen_target):
		# Someone is feeding on it; the meal is not the brain's to spoil.
		_chosen_target = null
		_unit.stop()
		return
	# While on its own feed the unit uses no Gift, which would most likely land on the meal.
	if uses_gifts and not players_order and not feeding_own:
		if _feed():
			return
		if _use_a_gift():
			return
	var taunter: Unit = _nearest_taunter()
	if taunter != null:
		if _unit.attack_target() != taunter:
			_attack(taunter)
		return
	if players_order or feeding_own:
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
	_feeding = false
	_chosen_target = target
	_unit.order_attack(target)


## Below `feeds_below` Blood, feeds on the nearest hostile within `aggro_radius` the unit can feed on.
## Never while a hostile's taunt reaches the unit, so taunt and meal cannot take turns. Returns whether
## the unit took the feed order.
func _feed() -> bool:
	if _unit.stats.blood >= feeds_below or _nearest_taunter() != null:
		return false
	var nearest: Unit = null
	var best: float = INF
	for other: Unit in _open_hostiles():
		var distance: float = _flat_to(other)
		if distance <= aggro_radius and distance < best and _unit.can_feed_on(other):
			best = distance
			nearest = other
	if nearest == null:
		return false
	_unit.order_feed(nearest)
	if _unit.current_order() != Unit.Order.FEED:
		return false
	_following = false
	_chosen_target = null
	_feeding = true
	return true


## Uses the first Gift, in slot order, that is ready, leaves the unit's Blood at or above its
## `fury_threshold`, and has a use now. Returns whether one was used.
func _use_a_gift() -> bool:
	var gifts: GiftUser = _unit.get_node_or_null(^"Gifts")
	if gifts == null:
		return false
	for index: int in gifts.count():
		var gift: Gift = gifts.gift(index)
		if not gifts.is_ready(index) or _unit.stats.blood - gift.blood_cost < _unit.fury_threshold:
			continue
		match gift.targeting:
			Gift.Targeting.ALLY:
				var hurt: Unit = _most_hurt_ally()
				if hurt != null and _health_fraction(hurt) < mends_below and gifts.use(index, hurt):
					return true
			Gift.Targeting.SELF:
				if _hostiles_within(self_gift_radius) >= self_gift_enemies and gifts.use(index):
					return true
			Gift.Targeting.ENEMY:
				var target: Unit = _gift_enemy(gift)
				if target != null and gifts.use(index, target):
					return true
	return false


## The unit's attack target if `gift` can reach it, else the nearest hostile within `aggro_radius`
## that it can reach, or null.
func _gift_enemy(gift: Gift) -> Unit:
	var current: Unit = _unit.attack_target()
	if current != null and not Feeder.is_held(current) and gift.can_target(_unit, current):
		return current
	var nearest: Unit = null
	var best: float = INF
	for other: Unit in _open_hostiles():
		var distance: float = _flat_to(other)
		if distance <= aggro_radius and distance < best and gift.can_target(_unit, other):
			best = distance
			nearest = other
	return nearest


## The living friend, the unit included, with the lowest fraction of its maximum health.
func _most_hurt_ally() -> Unit:
	var hurt: Unit = null
	var lowest: float = INF
	for node: Node in get_tree().get_nodes_in_group(&"units"):
		var other: Unit = node as Unit
		if other != null and other.is_alive() and not _unit.is_hostile_to(other) and _health_fraction(other) < lowest:
			lowest = _health_fraction(other)
			hurt = other
	return hurt


func _hostiles_within(radius: float) -> int:
	var near: int = 0
	for other: Unit in _open_hostiles():
		if _flat_to(other) <= radius:
			near += 1
	return near


static func _health_fraction(unit: Unit) -> float:
	return float(unit.stats.health) / unit.stats.max_health


## The nearest living hostile whose taunt reaches this unit, or null.
func _nearest_taunter() -> Unit:
	var nearest: Unit = null
	var best: float = INF
	for other: Unit in _open_hostiles():
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
	for other: Unit in _open_hostiles():
		var distance: float = _flat_to(other)
		if distance < best:
			best = distance
			nearest = other
	return nearest


## The living hostiles not held by a feed: a meal in progress is never chosen, counted or aimed at.
func _open_hostiles() -> Array[Unit]:
	var hostiles: Array[Unit] = []
	for node: Node in get_tree().get_nodes_in_group(&"units"):
		var other: Unit = node as Unit
		if other == null or other == _unit or not other.is_alive() or Feeder.is_held(other):
			continue
		if _unit.is_hostile_to(other):
			hostiles.append(other)
	return hostiles


func _flat_to(other: Unit) -> float:
	return _flat(_unit.global_position, other.global_position)


static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
