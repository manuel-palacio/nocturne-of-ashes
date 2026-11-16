class_name Unit
extends CharacterBody3D
## The body every character uses: carries out its orders, walking through its `Mover`, takes hits,
## carries timed status effects, dies with its stats and can be revived. A blood-drinking unit feeds
## on weakened enemies through its `Feeder`, and its `Fury` takes it over when Blood is spent too low.

signal died(unit: Unit)
signal arrived
signal attack_ended
signal was_hit(amount: int, source: Unit)
signal effects_changed
signal revived(unit: Unit)
## A feed completed: `target` died of it and this unit gained Blood.
signal fed(target: Unit)
## A feed in progress was given up, with no Blood gained.
signal feed_broken
signal fury_started
signal fury_ended

@export var stats: Stats
@export var faction: StringName = &"player"
@export var move_speed: float = 4.0
@export var display_name: String = ""
## Whether the unit can feed on enemies for Blood.
@export var drinks_blood: bool = false
## A target can be fed on at or below this fraction of its maximum health.
@export var feed_threshold: float = 0.35
@export var feed_time: float = 2.0
@export var feed_gain: int = 40
## Spending Blood from at or above this to below it starts the Fury.
@export var fury_threshold: int = 10
@export var fury_time: float = 5.0
## Damage dealt is multiplied by this during the Fury.
@export var fury_damage: float = 1.5

## What the unit was last told to do; NONE once it is done, stopped or dead.
enum Order { NONE, MOVE, ATTACK, FEED }

## While chasing, the walk is re-aimed once the target has moved this far from where it was headed.
const _CHASE_RETARGET: float = 0.5

var _order: Order = Order.NONE
var _attack_target: Unit
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _standing: Transform3D
var _fallen: Transform3D

@onready var _mover: Mover = $Mover
@onready var _body: MeshInstance3D = $Body
@onready var _melee: MeleeAttack = get_node_or_null(^"Melee")
@onready var _effects: Effects = $Effects
@onready var _feeder: Feeder = $Feeder
@onready var _fury: Fury = $Fury


func _ready() -> void:
	add_to_group(&"units")
	# Each instance gets its own copy; reset() applies the scene's maximums, which _init cannot see.
	stats = stats.duplicate() if stats != null else Stats.new()
	stats.reset()
	stats.died.connect(_on_stats_died)
	_mover.arrived.connect(_on_mover_arrived)
	_mover.stalled.connect(stop)
	_effects.changed.connect(effects_changed.emit)
	_feeder.finished.connect(_on_feed_finished)
	_feeder.broken.connect(_on_feed_broken)
	_fury.watch(stats)
	_fury.started.connect(_on_fury_started)
	_fury.ended.connect(_on_fury_ended)
	_standing = _body.transform
	# Lying on its side, lowered so its lowest point touches the floor at the unit's feet.
	var lying: Basis = Basis(Vector3.RIGHT, PI / 2.0)
	var lowest: float = (Transform3D(lying, Vector3.ZERO) * _body.get_aabb()).position.y
	_fallen = Transform3D(lying, Vector3(_standing.origin.x, -lowest, _standing.origin.z))


func _physics_process(delta: float) -> void:
	# A stunned unit keeps its order but neither chases, strikes nor walks; its Mover skips the frame.
	if is_stunned():
		_stand_still()
	else:
		if is_in_fury():
			_rage()
		if _order == Order.ATTACK:
			_pursue()
		elif _order == Order.FEED:
			_approach_feed()
		if _mover.steer():
			var step: Vector3 = _mover.heading() * walk_speed()
			velocity.x = step.x
			velocity.z = step.z
	var was_on_floor: bool = is_on_floor()
	if not was_on_floor:
		velocity.y -= _gravity * delta
	move_and_slide()
	_mover.after_move(delta, was_on_floor)


func current_order() -> Order:
	return _order


## Walks to the reachable navmesh point nearest to `target`. Ignored once dead and in the Fury.
## An order given before the navigation map has synced is held until it has.
func order_move(target: Vector3) -> void:
	if not is_alive() or is_in_fury():
		return
	_feeder.cancel()
	_attack_target = null
	_order = Order.MOVE
	# A plain walk that makes no progress is dropped with a warning.
	_mover.stall_check = true
	_mover.walk_to(target)


## Chases `target` into melee range and strikes it until it dies. Ignored for friends and the dead,
## and in the Fury.
func order_attack(target: Unit) -> void:
	if not is_alive() or is_in_fury() or target == null or not target.is_alive() or not is_hostile_to(target):
		return
	_chase(target)


func attack_target() -> Unit:
	return _attack_target if is_instance_valid(_attack_target) else null


## Closes to melee range of `target`, then feeds on it for `feed_time`, holding it stunned. Ignored
## unless `can_feed_on(target)`, which is never the case in the Fury.
func order_feed(target: Unit) -> void:
	if _melee == null or not can_feed_on(target):
		return
	_feeder.begin(target)
	_attack_target = null
	_order = Order.FEED
	_close_in(target)


## Whether this living blood-drinker can feed on `target`: a living hostile at or below this unit's
## `feed_threshold` of its maximum health, not already held by another feed.
func can_feed_on(target: Unit) -> bool:
	if not is_alive() or not drinks_blood or is_in_fury() or not is_instance_valid(target) or not target.is_alive():
		return false
	if not is_hostile_to(target) or Feeder.is_held(target):
		return false
	return float(target.stats.health) / target.stats.max_health <= feed_threshold


## True while drinking from the target, after the walk there: the unit neither walks nor strikes.
func is_feeding() -> bool:
	return _feeder.is_drinking()


func is_in_fury() -> bool:
	return _fury.is_active()


## Whether the unit is free to act on its own choices: alive, not stunned, not feeding, not in the Fury.
func can_act() -> bool:
	return is_alive() and not is_stunned() and not is_feeding() and not is_in_fury()


## Halts and drops any order; a feed in progress is broken. Ignored in the Fury.
func stop() -> void:
	if is_in_fury():
		return
	_feeder.cancel()
	_drop_order()


func _drop_order() -> void:
	_attack_target = null
	_order = Order.NONE
	_halt()


## Stops walking and stands still.
func _halt() -> void:
	_mover.halt()
	_stand_still()


## Drops the horizontal velocity; a fall in progress carries on.
func _stand_still() -> void:
	velocity.x = 0.0
	velocity.z = 0.0


## A finished path ends a move order. A chase path can end short of the target; the chase goes on.
func _on_mover_arrived() -> void:
	_stand_still()
	if _order == Order.MOVE:
		_order = Order.NONE
		arrived.emit()


func _pursue() -> void:
	if not is_instance_valid(_attack_target) or not _attack_target.is_alive():
		stop()
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


## Attacks `target` whatever its faction: the checks are the caller's. Breaks a feed in progress.
func _chase(target: Unit) -> void:
	if _melee == null:
		return
	_feeder.cancel()
	_attack_target = target
	_order = Order.ATTACK
	_close_in(target)


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
	var facing: Vector3 = target_at - global_position
	if Vector2(facing.x, facing.z).length() > 0.01:
		rotation.y = atan2(-facing.x, -facing.z)
	return true


func _on_feed_finished(target: Unit) -> void:
	_order = Order.NONE
	fed.emit(target)


## A broken feed leaves the unit idle; a new order that broke it is set right after.
func _on_feed_broken() -> void:
	_order = Order.NONE
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
		_drop_order()
	else:
		_chase(victim)


func _on_fury_started() -> void:
	_feeder.cancel()
	_drop_order()
	fury_started.emit()
	_rage()


func _on_fury_ended() -> void:
	_drop_order()
	fury_ended.emit()


## Metres per second while walking, with the effects applied.
func walk_speed() -> float:
	return move_speed * speed_multiplier()


## Deals `amount`, scaled by the damage this unit takes, and never less than 1. Returns the health
## removed, which `was_hit` also carries; 0 for amounts of 0 or less and for the dead.
func take_hit(amount: int, source: Unit = null) -> int:
	if amount <= 0 or not is_alive():
		return 0
	var health_before: int = stats.health
	stats.take_damage(maxi(roundi(amount * damage_taken_multiplier()), 1))
	var removed: int = health_before - stats.health
	was_hit.emit(removed, source)
	return removed


## Brings a dead unit back with `health_fraction` of its maximum health, standing and with no order.
func revive(health_fraction: float = 0.3) -> void:
	if is_alive():
		return
	stats.revive(maxi(roundi(stats.max_health * health_fraction), 1))
	_body.transform = _standing
	# Deferred like the change on death, so a death and revival in one frame end on layer 2.
	set_deferred(&"collision_layer", 2)
	clear_effects()
	stop()
	revived.emit(self)


## Adds a copy of `effect`; one with the same id is replaced, which restarts its time.
func add_effect(effect: StatusEffect) -> void:
	_effects.add(effect)


func remove_effect(id: StringName) -> void:
	_effects.remove(id)


func has_effect(id: StringName) -> bool:
	return _effects.has(id)


## The ids of the active effects, oldest first.
func effect_ids() -> Array[StringName]:
	return _effects.ids()


func clear_effects() -> void:
	_effects.clear()


func is_stunned() -> bool:
	return _effects.stuns()


func speed_multiplier() -> float:
	return _effects.speed_multiplier()


func damage_dealt_multiplier() -> float:
	return _effects.damage_dealt_multiplier()


func damage_taken_multiplier() -> float:
	return _effects.damage_taken_multiplier()


## The largest taunt radius among the active effects; 0 when none taunts.
func taunt_radius() -> float:
	return _effects.taunt_radius()


func is_moving() -> bool:
	return _mover.is_walking()


func is_alive() -> bool:
	return not stats.is_dead()


func is_hostile_to(other: Unit) -> bool:
	return faction != other.faction


func _on_stats_died() -> void:
	_fury.end()
	stop()
	clear_effects()
	# Off every layer, so clicks and rays pass through the body, which still rests on the floor.
	set_deferred(&"collision_layer", 0)
	_body.transform = _fallen
	died.emit(self)
