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
## Who gave an order: the player, the unit's brain, or the game itself, as the Fury does.
enum Issuer { NONE, PLAYER, BRAIN, SYSTEM }

var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _standing: Transform3D
var _fallen: Transform3D

@onready var _mover: Mover = $Mover
@onready var _orders: Orders = $Orders
@onready var _body: MeshInstance3D = $Body
@onready var _effects: Effects = $Effects
@onready var _feeder: Feeder = $Feeder
@onready var _fury: Fury = $Fury
@onready var _feed_mark: Node3D = $FeedMark


func _ready() -> void:
	add_to_group(&"units")
	# Each instance gets its own copy; reset() applies the scene's maximums, which _init cannot see.
	stats = stats.duplicate() if stats != null else Stats.new()
	stats.reset()
	stats.died.connect(_on_stats_died)
	_effects.changed.connect(effects_changed.emit)
	for relayed: StringName in [&"arrived", &"attack_ended", &"fed", &"feed_broken", &"fury_started", &"fury_ended"]:
		_orders.connect(relayed, Signal(self, relayed).emit)  # the unit emits what its orders report
	_fury.watch(stats)
	_standing = _body.transform
	# Lying on its side, lowered so its lowest point touches the floor at the unit's feet.
	var lying: Basis = Basis(Vector3.RIGHT, PI / 2.0)
	var lowest: float = (Transform3D(lying, Vector3.ZERO) * _body.get_aabb()).position.y
	_fallen = Transform3D(lying, Vector3(_standing.origin.x, -lowest, _standing.origin.z))


func _physics_process(delta: float) -> void:
	_orders.step()
	var was_on_floor: bool = is_on_floor()
	if not was_on_floor:
		velocity.y -= _gravity * delta
	move_and_slide()
	_mover.after_move(delta, was_on_floor)


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


## Shows or hides the mark that tells the player this unit is weak enough to feed on.
func set_feed_mark(on: bool) -> void:
	_feed_mark.visible = on


func has_feed_mark() -> bool:
	return _feed_mark.visible


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


## Walks this frame in the flat unit `direction` at `walk_speed()`; `Vector3.ZERO` stands still. Only
## the horizontal velocity is set, so a fall in progress carries on.
func walk(direction: Vector3) -> void:
	var step: Vector3 = direction * walk_speed()
	velocity.x = step.x
	velocity.z = step.z


## Turns to face `point`, flat on XZ; a point at the unit's feet leaves the facing as it is.
func face(point: Vector3) -> void:
	var facing: Vector3 = point - global_position
	if Vector2(facing.x, facing.z).length() > 0.01:
		rotation.y = atan2(-facing.x, -facing.z)


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
	_orders.clear()
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
	_orders.clear()
	clear_effects()
	# Off every layer, so clicks and rays pass through the body, which still rests on the floor.
	set_deferred(&"collision_layer", 0)
	_body.transform = _fallen
	died.emit(self)
