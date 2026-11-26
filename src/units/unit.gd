class_name Unit
extends CharacterBody3D
## The body every character uses: carries out its orders through its `Orders`, takes hits, carries
## timed status effects, dies with its stats and can be revived. A blood-drinking unit feeds on
## weakened enemies through its `Feeder`, and its `Fury` takes it over when Blood is spent too low.

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
## The unit walked up to `target` and used it.
signal interacted(target: Interactable)
signal fury_started
signal fury_ended

@export var stats: Stats
@export var faction: StringName = &"player"
@export var move_speed: float = 4.0
@export var display_name: String = ""
## Which party member this is (`&"alvar"`, `&"zahra"`, `&"gonzalo"`); empty for everyone else.
@export var member_id: StringName = &""
## Whether the unit can feed on enemies for Blood.
@export var drinks_blood: bool = false
## A target can be fed on at or below this fraction of its maximum health.
@export var feed_threshold: float = 0.2
@export var feed_time: float = 2.5
@export var feed_gain: int = 40
## Health a completed feed gives back when it restores the whole `feed_gain` of Blood; a feed that
## restores less (the Blood nearly full) gives the same share of it.
@export var feed_heal: int = 55
## Spending Blood from at or above this to below it starts the Fury.
@export var fury_threshold: int = 10
@export var fury_time: float = 5.0
## Damage dealt is multiplied by this during the Fury.
@export var fury_damage: float = 1.5

## What the unit was last told to do; NONE once it is done, stopped or dead.
enum Order { NONE, MOVE, ATTACK, FEED, INTERACT }
## Who gave an order: the player, the unit's brain, or the game itself, as the Fury does.
enum Issuer { NONE, PLAYER, BRAIN, SYSTEM }

## The share of its maximum health a fallen unit rises with, wherever it rises.
const RISEN_HEALTH: float = 0.3
## How fast a walking unit turns to face where it goes, in radians per second.
const TURN_SPEED: float = 10.0

var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
## True while `take_hit()` deals its damage.
var _taking_hit: bool = false
## The marks asked for; the visual shows them while the unit stands.
var _selected_mark: bool = false
var _feed_mark: bool = false

@onready var _mover: Mover = $Mover
@onready var _orders: Orders = $Orders
@onready var _effects: Effects = $Effects
@onready var _feeder: Feeder = $Feeder
@onready var _fury: Fury = $Fury
@onready var _separation: Separation = $Separation
@onready var _visual: UnitVisual = get_node_or_null(^"Visual") as UnitVisual


func _ready() -> void:
	add_to_group(&"units")
	# Each instance gets its own copy; reset() applies the scene's maximums, which _init cannot see.
	stats = stats.duplicate() if stats != null else Stats.new()
	stats.reset()
	stats.died.connect(_on_stats_died)
	_effects.changed.connect(effects_changed.emit)
	# The unit emits what its orders report.
	_orders.arrived.connect(arrived.emit)
	_orders.attack_ended.connect(attack_ended.emit)
	_orders.fed.connect(fed.emit)
	_orders.feed_broken.connect(feed_broken.emit)
	_orders.interacted.connect(interacted.emit)
	_orders.fury_started.connect(fury_started.emit)
	_orders.fury_ended.connect(fury_ended.emit)
	_fury.watch(stats)
	# Marks asked for before the unit was ready reach the visual now.
	if _visual != null:
		_visual.show_selected_mark(_selected_mark)
		_visual.show_feed_mark(_feed_mark)


func _physics_process(delta: float) -> void:
	_orders.step()
	var was_on_floor: bool = is_on_floor()
	if not was_on_floor:
		velocity.y -= _gravity * delta
	_move_body(_separation.push())
	_mover.after_move(delta, was_on_floor)


## Moves the body with its velocity plus `push`, the `Separation`'s for this frame. The push lasts this
## one move: the unit's own horizontal velocity is kept as it was, so nothing else sees it walk.
func _move_body(push: Vector3) -> void:
	if push == Vector3.ZERO:
		move_and_slide()
		return
	var own: Vector3 = velocity
	velocity.x += push.x
	velocity.z += push.z
	move_and_slide()
	velocity.x = own.x
	velocity.z = own.z


func current_order() -> Order:
	return _orders.current()


## Who gave the current order; NONE when there is none, SYSTEM for what the Fury makes the unit do.
func order_issuer() -> Issuer:
	return _orders.issuer()


## Walks to the reachable navmesh point nearest to `target`. Ignored once dead and in the Fury.
## An order given before the navigation map has synced is held until it has.
func order_move(target: Vector3, issuer: Issuer = Issuer.PLAYER) -> void:
	_orders.move(target, issuer)


## Chases `target` into melee range and strikes it until it dies. Ignored for friends and the dead,
## and in the Fury.
func order_attack(target: Unit, issuer: Issuer = Issuer.PLAYER) -> void:
	if target != null and target.is_alive() and is_hostile_to(target):
		_orders.attack(target, issuer)


func attack_target() -> Unit:
	return _orders.attack_target()


## Closes to melee range of `target`, then feeds on it for `feed_time`, holding it stunned. Ignored
## unless `can_feed_on(target)`, which is never the case in the Fury.
func order_feed(target: Unit, issuer: Issuer = Issuer.PLAYER) -> void:
	_orders.feed(target, issuer)


## The unit this one has a feed order on, walking there or drinking; null when none.
func feed_target() -> Unit:
	return _orders.feed_target()


## Whether this blood-drinker, free to take the player's orders, can feed on `target`: a living hostile
## at or below this unit's `feed_threshold` of its maximum health, not already held by another feed.
func can_feed_on(target: Unit) -> bool:
	return _orders.can_feed_on(target)


## Walks within `target.reach` of `target`, flat, uses it once and ends the order. Ignored for a freed
## target, for one that refuses this unit, once dead and in the Fury. A path that ends out of reach,
## or a target freed or refusing on the way, ends the order with the target unused.
func order_interact(target: Interactable, issuer: Issuer = Issuer.PLAYER) -> void:
	_orders.interact(target, issuer)


## Shows or hides the mark that tells the player this unit is weak enough to feed on.
func set_feed_mark(on: bool) -> void:
	_feed_mark = on
	if _visual != null:
		_visual.show_feed_mark(on)


## Whether the feed mark shows: asked for, and the unit standing.
func has_feed_mark() -> bool:
	return _feed_mark and is_alive()


## Shows or hides the ring that marks the party's selected member.
func set_selected_mark(on: bool) -> void:
	_selected_mark = on
	if _visual != null:
		_visual.show_selected_mark(on)


## Whether the selected ring shows: asked for, and the unit standing.
func has_selected_mark() -> bool:
	return _selected_mark and is_alive()


## True while drinking from the target, after the walk there: the unit neither walks nor strikes.
func is_feeding() -> bool:
	return _feeder.is_drinking()


func is_in_fury() -> bool:
	return _fury.is_active()


## Whether the unit is free to act on its own choices: alive, not stunned, not feeding, not in the Fury.
func can_act() -> bool:
	return is_alive() and not is_stunned() and not is_feeding() and not is_in_fury()


## Halts and drops any order; a feed in progress is broken. The player's: ignored in the Fury.
func stop() -> void:
	_orders.stop(Issuer.PLAYER)


## For `Orders` only: walks this frame in the flat unit `direction` at `walk_speed()`, turning towards
## it by at most `TURN_SPEED`; `Vector3.ZERO` stands still. Only the horizontal velocity is set, so a
## fall in progress carries on.
func drive(direction: Vector3) -> void:
	var step: Vector3 = direction * walk_speed()
	velocity.x = step.x
	velocity.z = step.z
	if Vector2(step.x, step.z).length() > 0.01:
		var heading: float = atan2(-step.x, -step.z)
		rotation.y = rotate_toward(rotation.y, heading, TURN_SPEED * get_physics_process_delta_time())


## For `Orders` only: turns to face `point`, flat on XZ; a point at the unit's feet leaves the facing as it is.
func face(point: Vector3) -> void:
	var facing: Vector3 = point - global_position
	if Vector2(facing.x, facing.z).length() > 0.01:
		rotation.y = atan2(-facing.x, -facing.z)


## Metres per second while walking, with the effects applied.
func walk_speed() -> float:
	return move_speed * speed_multiplier()


## Deals `amount`, scaled by the damage this unit takes, and never less than 1. Returns the health
## removed, which `was_hit` also carries; 0 for amounts of 0 or less and for the dead. A killing blow
## is announced as a hit before the death.
func take_hit(amount: int, source: Unit = null) -> int:
	if amount <= 0 or not is_alive():
		return 0
	var health_before: int = stats.health
	_taking_hit = true
	stats.take_damage(maxi(roundi(amount * damage_taken_multiplier()), 1))
	_taking_hit = false
	var removed: int = health_before - stats.health
	was_hit.emit(removed, source)
	if not is_alive():
		_fall()
	return removed


## The health a fallen unit with `stats` rises with: `RISEN_HEALTH` of its maximum, at least 1.
static func risen_health(stats: Stats) -> int:
	return maxi(roundi(stats.max_health * RISEN_HEALTH), 1)


## Brings a dead unit back with `risen_health()`, standing and with no order.
func revive() -> void:
	if is_alive():
		return
	stats.revive(risen_health(stats))
	# Deferred like the change on death, so a death and revival in one frame end on layer 2.
	set_deferred(&"collision_layer", 2)
	clear_effects()
	_orders.clear()
	revived.emit(self)


## Adds a copy of `effect`; one with the same id is replaced, which restarts its time. Ignored once dead.
func add_effect(effect: StatusEffect) -> void:
	if not is_alive():
		return
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
	# A hit in progress announces the fall once it has announced the hit.
	if not _taking_hit:
		_fall()


func _fall() -> void:
	_fury.end()
	_orders.clear()
	clear_effects()
	# Off every layer, so clicks and rays pass through the body, which still rests on the floor.
	set_deferred(&"collision_layer", 0)
	died.emit(self)
