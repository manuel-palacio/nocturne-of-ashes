class_name CombatBrain
extends Node
## Fights and follows for its `Unit`, enemy or companion. Each think, a brain that `uses_gifts` first
## feeds or uses one Gift, unless the unit is carrying out the player's order or its own feed; if it
## did, the think ends. Then the first rule that applies wins: obey a taunt; leave an order the brain
## did not give alone; keep up its own feed; switch to a much nearer hostile; engage the nearest
## hostile within `aggro_radius`, or at any distance once `alerted`; walk after `leader`. Every order the brain gives carries
## `Unit.Issuer.BRAIN`, which is how it tells its own orders from the player's; a follow walk is its
## own order, so taunts, switching and engaging interrupt it. Between thinks, a hit from a living hostile on an idle
## or following unit is answered with an attack at once. A hostile taken as a meal is left alone: never
## chosen, counted or aimed at, and an attack of the brain's on it is dropped. A hostile is taken from
## the moment another living unit has a feed order on it, through the walk in and the drinking. The brain does nothing
## while its unit is drinking, stunned or in the Fury. All distances are flat on XZ.

## A follow walk is re-aimed once the leader has moved this far from where the walk was aimed.
const _FOLLOW_RETARGET: float = 1.0

@export var aggro_radius: float = 8.0
@export var think_interval: float = 0.25
## Another hostile must be this much nearer than the current target before the brain switches to it.
@export var switch_margin: float = 2.0
## How far short of the leader a follow walk ends.
@export var follow_distance: float = 3.0
## An idle follower starts a follow walk only once farther than `follow_distance` plus this from a
## leader standing still, so followers spaced apart around it, a little beyond `follow_distance`, stay
## at rest when nudged.
@export var follow_slack: float = 2.0
## As `follow_slack`, while the leader walks (`is_moving()`) and for `follow_recent` seconds after it
## stops, so a leader walking away is followed even when its walk ends between two thinks. A follow
## walk under way is carried out whichever band applies.
@export var follow_slack_moving: float = 1.0
## Seconds after the leader stops walking during which `follow_slack_moving` still applies; longer
## than `think_interval`, so at least one think falls in it.
@export var follow_recent: float = 0.6
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
## An order stays the brain's, or the player's, however often the brain is switched.
@export var enabled: bool = true:
	set(value):
		enabled = value
		if not enabled and _unit != null and _is_following():
			_unit.stop()

## Once set, the brain engages the nearest hostile at any distance, not only within `aggro_radius`:
## its side has been roused, as when the room's fight has begun (`Encounter`).
var alerted: bool = false

## Whom the unit follows. A new leader starts with no memory of walking: what the last one did says
## nothing about it.
var leader: Unit:
	set(value):
		if value != leader:
			_leader_still_for = INF
		leader = value

var _since_thought: float = 0.0
## Where the leader stood when the current follow walk was aimed.
var _leader_was_at: Vector3
## Seconds since the leader was last seen walking, watched every physics frame.
var _leader_still_for: float = INF
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
	if leader != null and is_instance_valid(leader) and leader.is_moving():
		_leader_still_for = 0.0
	else:
		_leader_still_for += delta
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
	if not _unit.is_hostile_to(source) or _is_taken(source):
		return
	if _unit.current_order() == Unit.Order.NONE or _is_following():
		_attack(source)


func _think() -> void:
	var order: Unit.Order = _unit.current_order()
	var own: bool = _unit.order_issuer() == Unit.Issuer.BRAIN
	var attacking_own: bool = own and order == Unit.Order.ATTACK and _unit.attack_target() != null
	var feeding_own: bool = own and order == Unit.Order.FEED
	var players_order: bool = order != Unit.Order.NONE and not own

	if attacking_own and _is_taken(_unit.attack_target()):
		# Someone has claimed it as a meal; the meal is not the brain's to spoil.
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
	if nearest != null and (alerted or _flat_to(nearest) <= aggro_radius):
		_attack(nearest)
		return
	_follow()


## Switches to the nearest hostile when it is nearer than the current target by more than `switch_margin`.
func _reconsider() -> void:
	var current: Unit = _unit.attack_target()
	var nearest: Unit = _nearest_hostile()
	if nearest != null and nearest != current and _flat_to(nearest) + switch_margin < _flat_to(current):
		_attack(nearest)


func _follow() -> void:
	if leader == null or not is_instance_valid(leader) or not leader.is_alive():
		return
	var following: bool = _is_following()
	if following and _flat(leader.global_position, _leader_was_at) <= _FOLLOW_RETARGET:
		return
	var slack: float = follow_slack_moving if _leader_still_for < follow_recent else follow_slack
	if not following and _flat_to(leader) <= follow_distance + slack:
		return
	var away: Vector3 = _unit.global_position - leader.global_position
	away.y = 0.0
	_leader_was_at = leader.global_position
	_unit.order_move(leader.global_position + away.normalized() * follow_distance, Unit.Issuer.BRAIN)


## Whether the unit is on a follow walk: the only walk the brain orders.
func _is_following() -> bool:
	return _unit.current_order() == Unit.Order.MOVE and _unit.order_issuer() == Unit.Issuer.BRAIN


func _attack(target: Unit) -> void:
	_unit.order_attack(target, Unit.Issuer.BRAIN)


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
	_unit.order_feed(nearest, Unit.Issuer.BRAIN)
	return _unit.current_order() == Unit.Order.FEED


## Uses the first Gift, in slot order, that is ready, leaves the unit's Blood at or above its
## `fury_threshold`, and has a use now. An ENEMY or SELF Gift must also leave the Blood for the unit's
## ALLY Gift, if it carries one, so a mender always keeps the means to mend. Returns whether one was used.
func _use_a_gift() -> bool:
	var gifts: GiftUser = _unit.get_node_or_null(^"Gifts")
	if gifts == null:
		return false
	var mend_reserve: int = _ally_gift_cost(gifts)
	for index: int in gifts.count():
		var gift: Gift = gifts.gift(index)
		var keep: int = _unit.fury_threshold
		if gift.targeting != Gift.Targeting.ALLY:
			keep += mend_reserve
		if not gifts.is_ready(index) or _unit.stats.blood - gift.blood_cost < keep:
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


## The highest Blood cost among the unit's ALLY Gifts; 0 when it carries none.
static func _ally_gift_cost(gifts: GiftUser) -> int:
	var cost: int = 0
	for index: int in gifts.count():
		var gift: Gift = gifts.gift(index)
		if gift.targeting == Gift.Targeting.ALLY:
			cost = maxi(cost, gift.blood_cost)
	return cost


## The unit's attack target if `gift` can reach it, else the nearest hostile within `aggro_radius`
## that it can reach, or null.
func _gift_enemy(gift: Gift) -> Unit:
	var current: Unit = _unit.attack_target()
	if current != null and not _is_taken(current) and gift.can_target(_unit, current):
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


## The living hostiles not taken as a meal: a meal is never chosen, counted or aimed at.
func _open_hostiles() -> Array[Unit]:
	var taken: Array[Unit] = _others_feed_targets()
	var hostiles: Array[Unit] = []
	for node: Node in get_tree().get_nodes_in_group(&"units"):
		var other: Unit = node as Unit
		if other == null or other == _unit or not other.is_alive() or Feeder.is_held(other):
			continue
		if _unit.is_hostile_to(other) and not taken.has(other):
			hostiles.append(other)
	return hostiles


## Whether `other` is held by a feed or another living unit has a feed order on it.
func _is_taken(other: Unit) -> bool:
	return Feeder.is_held(other) or _others_feed_targets().has(other)


## The feed targets of every living unit but this brain's own.
func _others_feed_targets() -> Array[Unit]:
	var targets: Array[Unit] = []
	for node: Node in get_tree().get_nodes_in_group(&"units"):
		var other: Unit = node as Unit
		if other == null or other == _unit or not other.is_alive():
			continue
		var meal: Unit = other.feed_target()
		if meal != null:
			targets.append(meal)
	return targets


func _flat_to(other: Unit) -> float:
	return _flat(_unit.global_position, other.global_position)


static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
