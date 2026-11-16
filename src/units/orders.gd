class_name Orders
extends Node
## The orders of its `Unit`: what it was last told to do and by whom, and how it carries that out each
## frame, walking through the `Mover`, chasing and striking with its melee, closing in on a feed
## through the `Feeder`, and raging while its `Fury` holds it. Every order passes one gate, `accepts`,
## and replaces the one before it in one place, which breaks off whatever the unit was doing. Only the
## unit talks to this node.

signal arrived
signal attack_ended
signal fed(target: Unit)
signal feed_broken
signal fury_started
signal fury_ended

## While chasing, the walk is re-aimed once the target has moved this far from where it was headed.
const _CHASE_RETARGET: float = 0.5

var _order: Unit.Order = Unit.Order.NONE
var _issuer: Unit.Issuer = Unit.Issuer.NONE
var _attack_target: Unit

@onready var _unit: Unit = get_parent()
@onready var _mover: Mover = $"../Mover"
@onready var _melee: MeleeAttack = get_node_or_null(^"../Melee")
@onready var _feeder: Feeder = $"../Feeder"
@onready var _fury: Fury = $"../Fury"


func _ready() -> void:
	_mover.arrived.connect(_on_mover_arrived)
	_mover.stalled.connect(_break_off)
	_feeder.finished.connect(_on_feed_finished)
	_feeder.broken.connect(_on_feed_broken)
	_fury.started.connect(_on_fury_started)
	_fury.ended.connect(_on_fury_ended)


## One frame of the current order, run by the unit before it moves its body.
func step() -> void:
	# A stunned unit keeps its order but neither chases, strikes nor walks; its Mover skips the frame.
	if _unit.is_stunned():
		_unit.walk(Vector3.ZERO)
		return
	if _unit.is_in_fury():
		_rage()
	match _order:
		Unit.Order.ATTACK:
			_pursue()
		Unit.Order.FEED:
			_approach_feed()
	if _mover.steer():
		_unit.walk(_mover.heading())


func current() -> Unit.Order:
	return _order


## Who gave the current order; NONE when there is none.
func issuer() -> Unit.Issuer:
	return _issuer if _order != Unit.Order.NONE else Unit.Issuer.NONE


func attack_target() -> Unit:
	return _attack_target if is_instance_valid(_attack_target) else null


func feed_target() -> Unit:
	return _feeder.target() if _order == Unit.Order.FEED else null


## Whether `issuer` may give the unit an order now: never once it is dead, and in the Fury only the
## Fury itself, as `SYSTEM`.
func accepts(issuer: Unit.Issuer) -> bool:
	return _unit.is_alive() and (issuer == Unit.Issuer.SYSTEM or not _unit.is_in_fury())


func move(target: Vector3, issuer: Unit.Issuer) -> void:
	if not _take(Unit.Order.MOVE, issuer):
		return
	# A plain walk that makes no progress is dropped with a warning.
	_mover.stall_check = true
	_mover.walk_to(target)


## Attacks `target` whatever its faction: the checks on the target are the caller's.
func attack(target: Unit, issuer: Unit.Issuer) -> void:
	if _melee == null or not _take(Unit.Order.ATTACK, issuer):
		return
	_attack_target = target
	_close_in(target)


## Whether the unit, free to take the player's orders, can feed on `target`: it drinks blood, and
## `target` is a living hostile at or below the unit's `feed_threshold` of its maximum health, not
## already held by another feed.
func can_feed_on(target: Unit) -> bool:
	if not _unit.drinks_blood or not accepts(Unit.Issuer.PLAYER) or not is_instance_valid(target):
		return false
	if not target.is_alive() or not _unit.is_hostile_to(target) or Feeder.is_held(target):
		return false
	return float(target.stats.health) / target.stats.max_health <= _unit.feed_threshold


func feed(target: Unit, issuer: Unit.Issuer) -> void:
	if _melee == null or not can_feed_on(target) or not _take(Unit.Order.FEED, issuer):
		return
	_feeder.begin(target)
	_close_in(target)


func stop(issuer: Unit.Issuer) -> void:
	if accepts(issuer):
		_break_off()


## Drops any order without asking the gate, as death does.
func clear() -> void:
	_break_off()


## Passes `issuer` through the gate and, if it may, replaces the current order with `order`.
func _take(order: Unit.Order, issuer: Unit.Issuer) -> bool:
	if not accepts(issuer):
		return false
	_break_off()
	_order = order
	_issuer = issuer
	return true


## Ends whatever the unit was doing: a feed in progress is broken, and it stands still with no order.
func _break_off() -> void:
	_feeder.cancel()
	_attack_target = null
	_order = Unit.Order.NONE
	_halt()


## Stops walking and stands still.
func _halt() -> void:
	_mover.halt()
	_unit.walk(Vector3.ZERO)


## A finished path ends a move order. A chase path can end short of the target; the chase goes on.
func _on_mover_arrived() -> void:
	_unit.walk(Vector3.ZERO)
	if _order == Unit.Order.MOVE:
		_order = Unit.Order.NONE
		arrived.emit()


func _pursue() -> void:
	if not is_instance_valid(_attack_target) or not _attack_target.is_alive():
		_break_off()
		attack_ended.emit()
		return
	if not _reach(_attack_target):
		return
	if _melee.ready_to_swing():
		_melee.try_hit(_attack_target)


## Walks to the feed's target and starts drinking once in reach. A lost target is the Feeder's to handle.
func _approach_feed() -> void:
	var target: Unit = _feeder.target()
	if target == null or _feeder.is_drinking():
		return
	if _reach(target):
		_feeder.start_drinking()


## Starts a chase towards `target`. A chase re-aims on its own, and a blocked chaser keeps trying.
func _close_in(target: Unit) -> void:
	_mover.stall_check = false
	_mover.walk_to(target.global_position)


## One frame of a chase: re-aims while `target` is out of melee range and returns false; in range,
## halts facing it and returns true.
func _reach(target: Unit) -> bool:
	var target_at: Vector3 = target.global_position
	if not _melee.in_range(target):
		var drift: Vector3 = target_at - _mover.destination()
		# Re-aim only when the target has moved, so a path ending short of it does not re-path each frame.
		if Vector2(drift.x, drift.z).length() > _CHASE_RETARGET:
			_mover.walk_to(target_at)
		return false
	_halt()
	_unit.face(target_at)
	return true


func _on_feed_finished(target: Unit) -> void:
	_order = Unit.Order.NONE
	fed.emit(target)


## A broken feed leaves the unit idle; a new order that broke it is set right after.
func _on_feed_broken() -> void:
	_order = Unit.Order.NONE
	_halt()
	feed_broken.emit()


## In the Fury the unit keeps after its victim while it lives, then turns on the nearest unit of any
## faction; with no one left it stands idle.
func _rage() -> void:
	var victim: Unit = attack_target()
	if victim != null and victim.is_alive():
		return
	victim = _fury.nearest_victim()
	if victim == null:
		_break_off()
	else:
		attack(victim, Unit.Issuer.SYSTEM)


func _on_fury_started() -> void:
	_break_off()
	fury_started.emit()
	_rage()


func _on_fury_ended() -> void:
	_break_off()
	fury_ended.emit()
